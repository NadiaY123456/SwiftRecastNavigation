// SPDX-License-Identifier: MIT
//
//  NavMeshBuilder+RealityKit.swift
//  SwiftRecastNavigation
//
//  RealityKit integration for NavMeshBuilder
//

#if canImport(RealityKit)
import RealityKit
import CRecast

extension NavMeshBuilder {
    /// Creates a NavMeshBuilder from a RealityKit ModelComponent
    public convenience init(model: ModelComponent, config: NavMeshConfig = NavMeshConfig()) throws {
        var floatArray: [Float] = []
        var triangles: [Int32] = []
        
        for model in model.mesh.contents.models {
            for part in model.parts {
                if let vertices = part.buffers[.positions]?.get(SIMD3<Float>.self) {
                    floatArray = Array(repeating: 0, count: vertices.count * 3)
                    var i = 0
                    for vertex in vertices {
                        floatArray[i] = vertex.x
                        floatArray[i + 1] = vertex.y
                        floatArray[i + 2] = vertex.z
                        i += 3
                    }
                }
                
                if let triangleBuffer = part.buffers[.triangleIndices]?.get(UInt16.self) {
                    triangles = Array(repeating: 0, count: triangleBuffer.count)
                    let telem = triangleBuffer.elements
                    for x in 0..<triangleBuffer.count {
                        triangles[x] = Int32(telem[x])
                    }
                } else if let triangleBuffer = part.buffers[.triangleIndices]?.get(UInt32.self) {
                    triangles = Array(repeating: 0, count: triangleBuffer.count)
                    let telem = triangleBuffer.elements
                    for x in 0..<triangleBuffer.count {
                        triangles[x] = Int32(telem[x])
                    }
                }
            }
        }
        
        try self.init(vertices: floatArray, triangles: triangles, config: config)
    }
    
    /// Returns a MeshResource for visualization of a specific tile
    public func getTileMeshResource(tileX: Int, tileY: Int) throws -> MeshResource? {
        guard let result = tiledResult,
              let navMesh = result.pointee.navMesh else {
            return nil
        }
        
        guard let geom = bindingExtractTileGeometry(navMesh, Int32(tileX), Int32(tileY)) else {
            return nil
        }
        defer { freeVertsAndTriangles(geom) }
        
        let vat = geom.pointee
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        
        vat.verts.withMemoryRebound(to: SIMD4<Float>.self, capacity: Int(vat.nverts)) { vertPtr in
            for i in 0..<Int(vat.nverts) {
                let vec = SIMD3<Float>(vertPtr[i].x, vertPtr[i].y, vertPtr[i].z)
                positions.append(vec)
                // Defer normals: we'll accumulate per-vertex
                normals.append(SIMD3<Float>(repeating: 0))
            }
        }
        
        var triangles: [UInt32] = []
        vat.triangles.withMemoryRebound(to: UInt32.self, capacity: Int(vat.ntris)) { tPtr in
            for i in 0..<Int(vat.ntris) {
                triangles.append(tPtr[i])
            }
        }
        
        // --- Recompute vertex normals from triangles ---
        for t in stride(from: 0, to: triangles.count, by: 3) {
            let i0 = Int(triangles[t + 0])
            let i1 = Int(triangles[t + 1])
            let i2 = Int(triangles[t + 2])
            let e1 = positions[i1] - positions[i0]
            let e2 = positions[i2] - positions[i0]
            let n  = simd_normalize(simd_cross(e1, e2))
            normals[i0] += n
            normals[i1] += n
            normals[i2] += n
        }
        for i in 0..<normals.count {
            let len = simd_length(normals[i])
            normals[i] = len > 0 ? normals[i] / len : SIMD3<Float>(0, 1, 0)
        }

        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(triangles)
        
        return try MeshResource.generate(from: [descriptor])
    }
    
    /// Returns a combined MeshResource for all tiles
    public func getAllTilesMeshResource() throws -> MeshResource? {
        guard let result = tiledResult,
              let navMesh = result.pointee.navMesh else {
            return nil
        }
        
        var allPositions: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allTriangles: [UInt32] = []
        var vertexOffset: UInt32 = 0
        
        // Get grid dimensions
        let maxTiles = dtNavMeshGetMaxTiles(navMesh)
        
        for i in 0..<maxTiles {
            let tile = dtNavMeshGetTile(navMesh, i)
            guard let tile = tile,
                  let header = dtMeshTileGetHeader(tile),
                  dtMeshHeaderGetPolyCount(header) > 0 else {
                continue
            }
            
            // Extract this tile's geometry
            // Note: We'd need to add a function to get tile X,Y from index
            // For now, this is a simplified version
            
            let vertCount = dtMeshHeaderGetVertCount(header)
            let verts = dtMeshTileGetVerts(tile)
            
            // Add vertices
            for j in 0..<Int(vertCount) {
                let idx = j * 3
                let pos = SIMD3<Float>(verts![idx], verts![idx + 1], verts![idx + 2])
                allPositions.append(pos)
                allNormals.append(.zero) // will accumulate after triangles
            }
            
            // Add triangles with offset
            let polys = dtMeshTileGetPolys(tile)
            for j in 0..<Int(dtMeshHeaderGetPolyCount(header)) {
                let p = polys!.advanced(by: j)
                let vertCount = dtPolyGetVertCount(p)
                
                // Compare with raw value of DT_POLYTYPE_OFFMESH_CONNECTION
                if dtPolyGetType(p) == UInt8(DT_POLYTYPE_OFFMESH_CONNECTION.rawValue) {
                    continue
                }
                
                for k in 2..<Int(vertCount) {
                    allTriangles.append(vertexOffset + UInt32(dtPolyGetVert(p, 0)))
                    allTriangles.append(vertexOffset + UInt32(dtPolyGetVert(p, Int32(k - 1))))
                    allTriangles.append(vertexOffset + UInt32(dtPolyGetVert(p, Int32(k))))
                }
            }
            
            vertexOffset += UInt32(vertCount)
        }
        
        // --- Recompute vertex normals from triangles ---
        for t in stride(from: 0, to: allTriangles.count, by: 3) {
            let i0 = Int(allTriangles[t + 0])
            let i1 = Int(allTriangles[t + 1])
            let i2 = Int(allTriangles[t + 2])
            let e1 = allPositions[i1] - allPositions[i0]
            let e2 = allPositions[i2] - allPositions[i0]
            let n  = simd_normalize(simd_cross(e1, e2))
            allNormals[i0] += n
            allNormals[i1] += n
            allNormals[i2] += n
        }
        for i in 0..<allNormals.count {
            let len = simd_length(allNormals[i])
            allNormals[i] = len > 0 ? allNormals[i] / len : SIMD3<Float>(0, 1, 0)
        }

        if allPositions.isEmpty {
            return nil
        }
        
        var descriptor = MeshDescriptor()
        descriptor.positions = MeshBuffer(allPositions)
        descriptor.normals = MeshBuffer(allNormals)
        descriptor.primitives = .triangles(allTriangles)
        
        return try MeshResource.generate(from: [descriptor])
    }
}
#endif
