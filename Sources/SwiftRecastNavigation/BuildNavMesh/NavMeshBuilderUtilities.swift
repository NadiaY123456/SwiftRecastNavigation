// SPDX-License-Identifier: MIT
//
//  NavMeshBuilder+Utilities.swift
//  SwiftRecastNavigation
//
//  Utility functions for NavMeshBuilder
//

import Foundation
import CRecast

extension NavMeshBuilder {
    /// Gets the tile coordinates for a given world position
    public func getTilePosition(for worldPos: SIMD3<Float>) -> (x: Int, y: Int)? {
        guard let result = tiledResult,
              result.pointee.navMesh != nil else {
            return nil
        }
        
        var tx: Int32 = 0
        var ty: Int32 = 0
        
        withUnsafePointer(to: worldPos) { posPtr in
            posPtr.withMemoryRebound(to: Float.self, capacity: 3) { posFloatPtr in
                withUnsafePointer(to: boundaryMin) { bminPtr in
                    bminPtr.withMemoryRebound(to: Float.self, capacity: 3) { bminFloatPtr in
                        bindingGetTilePos(
                            posFloatPtr,
                            &tx,
                            &ty,
                            bminFloatPtr,
                            Float(config.tileSize),
                            config.cellSize
                        )
                    }
                }
            }
        }
        
        return (Int(tx), Int(ty))
    }
    
    /// Gets the bounds for a specific tile
    public func getTileBounds(tileX: Int, tileY: Int) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard let result = tiledResult,
              result.pointee.navMesh != nil else {
            return nil
        }
        
        var tileBmin = [Float](repeating: 0, count: 3)
        var tileBmax = [Float](repeating: 0, count: 3)
        
        withUnsafePointer(to: boundaryMin) { bminPtr in
            bminPtr.withMemoryRebound(to: Float.self, capacity: 3) { bminFloatPtr in
                withUnsafePointer(to: boundaryMax) { bmaxPtr in
                    bmaxPtr.withMemoryRebound(to: Float.self, capacity: 3) { bmaxFloatPtr in
                        tileBmin.withUnsafeMutableBufferPointer { tbminBuffer in
                            tileBmax.withUnsafeMutableBufferPointer { tbmaxBuffer in
                                bindingCalcTileBounds(
                                    bminFloatPtr,
                                    bmaxFloatPtr,
                                    Int32(tileX),
                                    Int32(tileY),
                                    Float(config.tileSize),
                                    config.cellSize,
                                    tbminBuffer.baseAddress,
                                    tbmaxBuffer.baseAddress
                                )
                            }
                        }
                    }
                }
            }
        }
        
        return (
            SIMD3<Float>(tileBmin[0], tileBmin[1], tileBmin[2]),
            SIMD3<Float>(tileBmax[0], tileBmax[1], tileBmax[2])
        )
    }
    
    /// Debug information about the built navigation mesh
    public var debugInfo: String {
        guard let result = tiledResult else {
            return "No navigation mesh built"
        }
        
        return """
        Navigation Mesh Info:
        - Tiles Built: \(result.pointee.tilesBuilt) / \(result.pointee.totalTiles)
        - Tile Size: \(config.tileSize) voxels
        - Cell Size: \(config.cellSize)
        - Bounds: [\(boundaryMin.x), \(boundaryMin.y), \(boundaryMin.z)] to [\(boundaryMax.x), \(boundaryMax.y), \(boundaryMax.z)]
        - Status: \(result.pointee.code == BCODE_OK ? "Success" : "Error")
        """
    }
    
    /// Rebuilds a specific tile at the given coordinates
    public func rebuildTile(at worldPos: SIMD3<Float>) -> Bool {
        // TODO: Implement tile rebuilding
        return false
    }
    
    /// Removes a tile at the given coordinates
    public func removeTile(at worldPos: SIMD3<Float>) -> Bool {
        // TODO: Implement tile removal
        return false
    }
}

// Add this extension to help debug area mesh building

extension NavMeshBuilder {
    
    /// Debug function to verify area definitions before building
    public func debugAreaDefinitions(_ areas: [AreaDefinition]) {
        print("\n🔍 Debugging Area Definitions:")
        print("  Total area definitions: \(areas.count)")
        
        for (index, area) in areas.enumerated() {
            print("\n  Area Definition \(index):")
            print("    Area Code: \(area.areaCode)")
            print("    Vertices: \(area.vertices.count)")
            print("    Triangles: \(area.triangles.count / 3) triangles")
            
            // Calculate bounds
            var minBounds = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
            var maxBounds = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
            
            for vertex in area.vertices {
                minBounds.x = min(minBounds.x, vertex.x)
                minBounds.y = min(minBounds.y, vertex.y)
                minBounds.z = min(minBounds.z, vertex.z)
                maxBounds.x = max(maxBounds.x, vertex.x)
                maxBounds.y = max(maxBounds.y, vertex.y)
                maxBounds.z = max(maxBounds.z, vertex.z)
            }
            
            print("    Bounds:")
            print("      Min: \(minBounds)")
            print("      Max: \(maxBounds)")
            print("      Size: \(maxBounds - minBounds)")
            
            // Check if bounds overlap with main mesh bounds
            let overlapsX = !(maxBounds.x < boundaryMin.x || minBounds.x > boundaryMax.x)
            let overlapsY = !(maxBounds.y < boundaryMin.y - 20 || minBounds.y > boundaryMax.y + 20) // Allow some Y tolerance
            let overlapsZ = !(maxBounds.z < boundaryMin.z || minBounds.z > boundaryMax.z)
            
            if overlapsX && overlapsY && overlapsZ {
                print("    ✅ Overlaps with main mesh")
            } else {
                print("    ❌ Does NOT overlap with main mesh!")
                if !overlapsX { print("      - No X overlap") }
                if !overlapsY { print("      - No Y overlap") }
                if !overlapsZ { print("      - No Z overlap") }
            }
        }
        
        print("\n  Main mesh bounds:")
        print("    Min: \(boundaryMin)")
        print("    Max: \(boundaryMax)")
    }
}

// Usage example:
// In your build code, before creating the NavMeshBuilder:
/*
let roadAreaDefinition = AreaDefinition(
    vertices: roadVertices,
    triangles: roadTriangles,
    areaCode: NavMeshAreaCode.road
)

// Debug the area definitions
let testBuilder = try NavMeshBuilder(
    vertices: mainVertices,
    triangles: mainTriangles,
    config: config,
    areas: []  // Empty for bounds calculation
)
testBuilder.debugAreaDefinitions([roadAreaDefinition])
*/
