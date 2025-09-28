// SPDX-License-Identifier: MIT
//
//  TerrainSampler.swift
//  SwiftRecastDemo
//
//  Handles terrain height sampling from various sources
//

import Accelerate
import RealityKit
import simd

/// Handles terrain height sampling from RealityKit models and OBJ meshes
struct TerrainSampler {
    
    // MARK: - RealityKit Terrain Sampling
    
    /// Cached terrain mesh data for efficient height sampling
    struct TerrainMeshData {
        let vertices: [SIMD3<Float>]
        let xCoords: [Float]
        let yCoords: [Float]
        let zCoords: [Float]
        
        /// Extracts and caches terrain vertex data from a ModelEntity
        init(from terrainModel: ModelEntity, rotation: simd_quatf? = nil) {
            guard let mesh = terrainModel.model?.mesh else {
                self.vertices = []
                self.xCoords = []
                self.yCoords = []
                self.zCoords = []
                return
            }
            
            // Gather vertices in local space
            let localVertices: [SIMD3<Float>] = mesh.contents.models.flatMap { meshModel in
                meshModel.parts.flatMap { part in
                    part.positions.elements
                }
            }
            
            guard !localVertices.isEmpty else {
                self.vertices = []
                self.xCoords = []
                self.yCoords = []
                self.zCoords = []
                return
            }
            
            // Apply rotation if provided
            let transformedVertices: [SIMD3<Float>]
            if let rotation = rotation {
                transformedVertices = localVertices.map { vertex in
                    rotation.act(vertex)
                }
            } else {
                transformedVertices = localVertices
            }
            
            // Extract coordinates for Accelerate
            let vertexCount = transformedVertices.count
            var xCoordsLocal = [Float](repeating: 0, count: vertexCount)
            var yCoordsLocal = [Float](repeating: 0, count: vertexCount)
            var zCoordsLocal = [Float](repeating: 0, count: vertexCount)
            
            for (i, v) in transformedVertices.enumerated() {
                xCoordsLocal[i] = v.x
                yCoordsLocal[i] = v.y
                zCoordsLocal[i] = v.z
            }
            
            self.vertices = transformedVertices
            self.xCoords = xCoordsLocal
            self.yCoords = yCoordsLocal
            self.zCoords = zCoordsLocal
        }
    }
    
    /// Samples a single terrain height at given X-Z position from a RealityKit model
    static func sampleHeight(at localXZ: SIMD2<Float>, 
                           on terrainModel: ModelEntity, 
                           rotation: simd_quatf? = nil) -> Float? {
        let meshData = TerrainMeshData(from: terrainModel, rotation: rotation)
        
        guard !meshData.vertices.isEmpty else {
            return nil
        }
        
        let nearestIndex = findNearestVertexIndex(
            to: localXZ,
            in: meshData.xCoords,
            and: meshData.zCoords
        )
        
        return meshData.yCoords[nearestIndex]
    }
    
    /// Batch samples multiple terrain heights from a RealityKit model
    static func sampleHeights(at localXZPositions: [SIMD2<Float>], 
                            on terrainModel: ModelEntity, 
                            rotation: simd_quatf? = nil) -> [Float?] {
        let meshData = TerrainMeshData(from: terrainModel, rotation: rotation)
        
        guard !meshData.vertices.isEmpty else {
            return Array(repeating: nil, count: localXZPositions.count)
        }
        
        return localXZPositions.map { xz in
            let nearestIndex = findNearestVertexIndex(
                to: xz,
                in: meshData.xCoords,
                and: meshData.zCoords
            )
            return meshData.yCoords[nearestIndex]
        }
    }
    
    // MARK: - OBJ Terrain Sampling
    
    /// Samples terrain heights from OBJ vertices using nearest neighbor
    static func sampleOBJHeights(at localXZPositions: [SIMD2<Float>],
                               terrainVertices: [SIMD3<Float>],
                               scale: Float = 1.0) -> [Float] {
        guard !terrainVertices.isEmpty else {
            return Array(repeating: 0, count: localXZPositions.count)
        }
        
        // Scale terrain vertices
        let scaledVertices = terrainVertices.map { $0 * scale }
        
        // Extract coordinates for Accelerate
        let xCoords = scaledVertices.map { $0.x }
        let yCoords = scaledVertices.map { $0.y }
        let zCoords = scaledVertices.map { $0.z }
        
        return localXZPositions.map { xz in
            let nearestIndex = findNearestVertexIndex(
                to: xz,
                in: xCoords,
                and: zCoords
            )
            return yCoords[nearestIndex]
        }
    }
    
    // MARK: - Private Helpers
    
    /// Finds the index of the nearest vertex to a given X-Z position using Accelerate
    private static func findNearestVertexIndex(to queryXZ: SIMD2<Float>,
                                             in xCoords: [Float],
                                             and zCoords: [Float]) -> Int {
        let vertexCount = xCoords.count
        var distances = [Float](repeating: 0, count: vertexCount)
        
        // Batch calculate squared distances
        var diffX = [Float](repeating: 0, count: vertexCount)
        var diffZ = [Float](repeating: 0, count: vertexCount)
        
        // X differences
        vDSP_vfill([queryXZ.x], &diffX, 1, vDSP_Length(vertexCount))
        vDSP_vsub(xCoords, 1, diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
        vDSP_vsq(diffX, 1, &diffX, 1, vDSP_Length(vertexCount))
        
        // Z differences
        vDSP_vfill([queryXZ.y], &diffZ, 1, vDSP_Length(vertexCount))
        vDSP_vsub(zCoords, 1, diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
        vDSP_vsq(diffZ, 1, &diffZ, 1, vDSP_Length(vertexCount))
        
        // Sum for total squared distance
        vDSP_vadd(diffX, 1, diffZ, 1, &distances, 1, vDSP_Length(vertexCount))
        
        // Find nearest
        var minDistance: Float = 0
        var minIndex: vDSP_Length = 0
        vDSP_minvi(distances, 1, &minDistance, &minIndex, vDSP_Length(vertexCount))
        
        return Int(minIndex)
    }
}
