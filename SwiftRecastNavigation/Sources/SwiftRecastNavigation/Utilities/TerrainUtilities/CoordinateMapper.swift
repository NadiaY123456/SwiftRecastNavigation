// SPDX-License-Identifier: MIT
//
//  CoordinateMapper.swift
//  SwiftRecastDemo
//
//  Handles coordinate space transformations for mesh generation
//

import CoreGraphics
import RealityKit
import simd

/// Handles coordinate space transformations between different mesh representations
struct CoordinateMapper {
    
    /// Maps pixel coordinates from splat map to RealityKit terrain's local space
    static func mapSplatPixelsToTerrainSpace(_ pixelVerts: [SIMD2<Float>],
                                             imageSize: CGSize,
                                             onto terrainModel: ModelEntity,
                                             rotation: simd_quatf? = nil) -> [SIMD2<Float>] {
        // Get visual bounds
        let visualBounds = terrainModel.visualBounds(relativeTo: terrainModel)
        var visualMin = visualBounds.min
        var visualExtents = visualBounds.extents
        
        // Apply rotation to bounds if needed
        if let rotation = rotation {
            let transformedBounds = applyRotationToBounds(
                boundsMin: visualMin,
                extents: visualExtents,
                rotation: rotation
            )
            visualMin = transformedBounds.min
            visualExtents = transformedBounds.extents
        }
        
        #if DEBUG
        print("\nTerrain bounds - X: [\(visualMin.x), \(visualMin.x + visualExtents.x)]")
        print("Terrain bounds - Z: [\(visualMin.z), \(visualMin.z + visualExtents.z)]")
        #endif
        
        // Scale factors to stretch splat image to terrain dimensions
        let scaleX = visualExtents.x / Float(imageSize.width)
        let scaleZ = visualExtents.z / Float(imageSize.height)
        
        #if DEBUG
        print("Scale factors - X: \(scaleX), Z: \(scaleZ)")
        #endif
        
        return pixelVerts.map { pixelCoord in
            // Map pixel coordinates to terrain's local space
            // Note: Y coordinate in splat is already flipped to match RealityKit
            SIMD2<Float>(
                visualMin.x + pixelCoord.x * scaleX,
                visualMin.z + pixelCoord.y * scaleZ
            )
        }
    }
    
    /// Maps pixel coordinates from splat map to OBJ terrain space
    static func mapSplatPixelsToOBJTerrainSpace(_ pixelVerts: [SIMD2<Float>],
                                                imageSize: CGSize,
                                                terrainBounds: MeshBounds,
                                                scale: Float = 1.0) -> [SIMD2<Float>] {
        // Apply scale to bounds
        let scaledBounds = terrainBounds.scaled(by: scale)
        
        // Calculate terrain dimensions
        let terrainWidth = scaledBounds.width
        let terrainDepth = scaledBounds.depth
        
        // Scale factors
        let scaleX = terrainWidth / Float(imageSize.width)
        let scaleZ = terrainDepth / Float(imageSize.height)
        
        #if DEBUG
        print("Scale factors - X: \(scaleX), Z: \(scaleZ)")
        #endif
        
        return pixelVerts.map { pixelCoord in
            SIMD2<Float>(
                scaledBounds.minX + pixelCoord.x * scaleX,
                scaledBounds.minZ + pixelCoord.y * scaleZ
            )
        }
    }
    
    // MARK: - Private Helpers
    
    /// Applies rotation to bounding box and returns new axis-aligned bounds
    private static func applyRotationToBounds(boundsMin: SIMD3<Float>,
                                              extents: SIMD3<Float>,
                                              rotation: simd_quatf) -> (min: SIMD3<Float>, extents: SIMD3<Float>) {
        // Get all 8 corners of the bounding box
        let corners = [
            SIMD3<Float>(boundsMin.x, boundsMin.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x + extents.x, boundsMin.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x, boundsMin.y + extents.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x + extents.x, boundsMin.y + extents.y, boundsMin.z),
            SIMD3<Float>(boundsMin.x, boundsMin.y, boundsMin.z + extents.z),
            SIMD3<Float>(boundsMin.x + extents.x, boundsMin.y, boundsMin.z + extents.z),
            SIMD3<Float>(boundsMin.x, boundsMin.y + extents.y, boundsMin.z + extents.z),
            SIMD3<Float>(boundsMin.x + extents.x, boundsMin.y + extents.y, boundsMin.z + extents.z)
        ]
        
        // Rotate all corners
        let rotatedCorners = corners.map { rotation.act($0) }
        
        // Find new axis-aligned bounds
        var newMin = rotatedCorners[0]
        var newMax = rotatedCorners[0]
        
        for corner in rotatedCorners {
            newMin.x = Swift.min(newMin.x, corner.x)
            newMin.y = Swift.min(newMin.y, corner.y)
            newMin.z = Swift.min(newMin.z, corner.z)
            newMax.x = Swift.max(newMax.x, corner.x)
            newMax.y = Swift.max(newMax.y, corner.y)
            newMax.z = Swift.max(newMax.z, corner.z)
        }
        
        return (newMin, newMax - newMin)
    }
}
