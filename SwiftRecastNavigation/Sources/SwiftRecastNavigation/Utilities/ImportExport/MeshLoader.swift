// SPDX-License-Identifier: MIT
//
//  MeshLoader.swift
//  SwiftRecastNavigation
//
//  Created by Nadia Yilmaz on 6/22/25.
//

import Foundation
import RealityKit
import simd



/// Mesh loader supporting multiple creation paths for navigation mesh generation
public final class MeshLoader {
    // MARK: - Properties
    
    /// Scale factor for the mesh
    public var scale: Float = 1.0
    /// 3D vertex positions
    public var vertices: [SIMD3<Float>] = []
    /// Per-triangle normals
    public var normals: [SIMD3<Float>] = []
    /// Triangle indices (3 per triangle)
    public var triangles: [Int32] = []
    
    // MARK: - Initialization
    
    /// Creates an empty mesh loader
    init() { /* intentionally blank */ }
    
    // MARK: - Path A: Load from OBJ File
    
    /// Loads mesh data from an OBJ file on disk
    public convenience init(file: String) throws {
        self.init()
        let result = try OBJParser.load(from: file)
        self.vertices = result.vertices
        self.triangles = result.triangles
        self.normals = result.normals
    }
    
    // MARK: - Path B: Build from 2D Vertices + RealityKit Model
    
    /// Creates a 3D mesh by projecting 2D splat vertices onto a RealityKit terrain model
    public convenience init(splatMesh2D: MeshResult2D, terrainModel: ModelEntity, debugPrint: Bool = false) {
        self.init()
        
        if debugPrint {
            print("\n=== Building Splat Mesh Overlay ===")
            print("Splat vertices count: \(splatMesh2D.vertices.count)")
            print("Splat image size: \(splatMesh2D.imageSize.width) x \(splatMesh2D.imageSize.height)")
        }
        
        // Map splat pixels to terrain space
        let terrainSpaceXZ = CoordinateMapper.mapSplatPixelsToTerrainSpace(
            splatMesh2D.vertices,
            imageSize: splatMesh2D.imageSize,
            onto: terrainModel
        )
        
        if debugPrint {
            print("\nMapped splat vertices to terrain space")
            if terrainSpaceXZ.count > 0 {
                print("First mapped vertex: \(terrainSpaceXZ[0])")
                print("Last mapped vertex: \(terrainSpaceXZ[terrainSpaceXZ.count - 1])")
            }
            print("\nSampling terrain heights at \(terrainSpaceXZ.count) positions...")
        }
        
        // Sample terrain heights
        let heightSamples = TerrainSampler.sampleHeights(
            at: terrainSpaceXZ,
            on: terrainModel
        )
        
        // Convert optional heights to default value of 0
        let heights = heightSamples.map { $0 ?? 0.0 }
        
        if debugPrint {
            // Count valid heights
            let validHeightCount = heightSamples.compactMap { $0 }.count
            print("Valid heights sampled: \(validHeightCount) out of \(heightSamples.count)")
            
            if let minHeight = heights.min(), let maxHeight = heights.max() {
                print("Height range: \(minHeight) to \(maxHeight)")
            }
        }
        
        // Build 3D vertices
        self.vertices = zip(terrainSpaceXZ, heights).map { xz, y in
            [xz.x, y, xz.y]
        }
        
        if debugPrint {
            print("\nBuilt \(vertices.count) 3D vertices for splat overlay")
        }
        
        // Copy triangle indices
        self.triangles = splatMesh2D.indices.map(Int32.init)
        
        if debugPrint {
            print("Triangle indices count: \(triangles.count)")
            print("Triangle count: \(triangles.count / 3)")
        }
        
        // Generate normals
        rebuildNormals()
        
        if debugPrint {
            print("=== Splat Mesh Overlay Complete ===\n")
        }
    }
    
    // MARK: - Path C: Build from 3D Vertices
    
    /// Creates mesh from pre-existing 3D vertex and index buffers
    public convenience init(vertices3D: [SIMD3<Float>], indices: [UInt32]) {
        self.init()
        self.vertices = vertices3D
        self.triangles = indices.map { Int32($0) }
        rebuildNormals()
    }
    
    // MARK: - Path D: Build from 2D Vertices + OBJ Terrain
    
    /// Creates a 3D mesh by projecting 2D splat vertices onto terrain loaded from an OBJ file
    public convenience init(splatMesh2D: MeshResult2D, terrainOBJPath: String, terrainScale: Float = 1.0, debugPrint: Bool = false) throws {
        self.init()
        
        if debugPrint {
            print("\n=== Building Splat Mesh Overlay from OBJ Terrain ===")
            print("Splat vertices count: \(splatMesh2D.vertices.count)")
            print("Splat image size: \(splatMesh2D.imageSize.width) x \(splatMesh2D.imageSize.height)")
            print("Loading terrain from: \(terrainOBJPath)")
        }
        
        // Load terrain mesh
        let terrainResult = try OBJParser.load(from: terrainOBJPath)
        
        if debugPrint {
            print("Terrain vertices: \(terrainResult.vertices.count)")
        }
        
        // Get terrain bounds
        let bounds = MeshBounds.compute(from: terrainResult.vertices)
        
        if debugPrint {
            print("\nTerrain bounds - X: [\(bounds.minX), \(bounds.maxX)]")
            print("Terrain bounds - Z: [\(bounds.minZ), \(bounds.maxZ)]")
        }
        
        // Map splat pixels to terrain space
        let terrainSpaceXZ = CoordinateMapper.mapSplatPixelsToOBJTerrainSpace(
            splatMesh2D.vertices,
            imageSize: splatMesh2D.imageSize,
            terrainBounds: bounds,
            scale: terrainScale
        )
        
        if debugPrint {
            print("\nMapped splat vertices to terrain space")
            if terrainSpaceXZ.count > 0 {
                print("First mapped vertex: \(terrainSpaceXZ[0])")
                print("Last mapped vertex: \(terrainSpaceXZ[terrainSpaceXZ.count - 1])")
            }
            print("\nSampling terrain heights at \(terrainSpaceXZ.count) positions...")
        }
        
        // Sample terrain heights
        let heights = TerrainSampler.sampleOBJHeights(
            at: terrainSpaceXZ,
            terrainVertices: terrainResult.vertices,
            scale: terrainScale
        )
        
        if debugPrint {
            // Count valid heights
            if let minHeight = heights.min(), let maxHeight = heights.max() {
                print("Height range: \(minHeight) to \(maxHeight)")
            }
        }
        
        // Build 3D vertices
        self.vertices = zip(terrainSpaceXZ, heights).map { xz, y in
            [xz.x, y, xz.y]
        }
        
        if debugPrint {
            print("\nBuilt \(vertices.count) 3D vertices for splat overlay")
        }
        
        // Copy triangle indices
        self.triangles = splatMesh2D.indices.map(Int32.init)
        
        if debugPrint {
            print("Triangle indices count: \(triangles.count)")
            print("Triangle count: \(triangles.count / 3)")
        }
        
        // Generate normals
        rebuildNormals()
        
        if debugPrint {
            print("=== Splat Mesh Overlay Complete ===\n")
        }
    }
    
    // MARK: - Public Methods
    
    /// Writes mesh data to an OBJ file
    public func writeOBJ(to url: URL) throws {
        try OBJParser.write(vertices: vertices, triangles: triangles, to: url)
    }
    
    /// Computes the X-Z bounds of the current mesh
    func computeBounds() -> MeshBounds {
        return MeshBounds.compute(from: vertices)
    }
    
    // MARK: - Private Methods
    
    /// Rebuilds per-triangle normals from vertices and triangles
    private func rebuildNormals() {
        normals.removeAll(keepingCapacity: true)
        
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let v0 = triangles[i]
            let v1 = triangles[i + 1]
            let v2 = triangles[i + 2]
            
            // Validate indices
            guard v0 >= 0 && v0 < vertices.count &&
                  v1 >= 0 && v1 < vertices.count &&
                  v2 >= 0 && v2 < vertices.count else {
                normals.append([0, 1, 0]) // Default up normal
                continue
            }
            
            // Calculate normal using cross product
            let e0 = vertices[Int(v1)] - vertices[Int(v0)]
            let e1 = vertices[Int(v2)] - vertices[Int(v0)]
            let n = cross(e0, e1)
            let len = simd_length(n)
            normals.append(len > 0 ? n / len : [0, 1, 0])
        }
    }
}
