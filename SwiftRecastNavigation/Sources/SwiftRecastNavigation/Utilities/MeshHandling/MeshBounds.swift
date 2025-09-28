// SPDX-License-Identifier: MIT
//
//  MeshBounds.swift
//  SwiftRecastNavigation
//
//  Represents and computes axis-aligned bounds for mesh data
//

import Foundation
import simd

/// Represents axis-aligned bounds in X-Z plane
struct MeshBounds {
    let minX: Float
    let maxX: Float
    let minZ: Float
    let maxZ: Float
    
    /// Width of the bounds (X dimension)
    var width: Float { maxX - minX }
    
    /// Depth of the bounds (Z dimension)
    var depth: Float { maxZ - minZ }
    
    /// Center point in X-Z plane
    var center: SIMD2<Float> { 
        SIMD2<Float>((minX + maxX) / 2, (minZ + maxZ) / 2) 
    }
    
    /// Creates empty bounds at origin
    static var zero: MeshBounds {
        MeshBounds(minX: 0, maxX: 0, minZ: 0, maxZ: 0)
    }
    
    /// Computes bounds from an array of 3D vertices
    static func compute(from vertices: [SIMD3<Float>]) -> MeshBounds {
        guard !vertices.isEmpty else {
            return .zero
        }
        
        var minX = Float.infinity
        var maxX = -Float.infinity
        var minZ = Float.infinity
        var maxZ = -Float.infinity
        
        for v in vertices {
            minX = min(minX, v.x)
            maxX = max(maxX, v.x)
            minZ = min(minZ, v.z)
            maxZ = max(maxZ, v.z)
        }
        
        return MeshBounds(minX: minX, maxX: maxX, minZ: minZ, maxZ: maxZ)
    }
    
    /// Applies scale factor to bounds
    func scaled(by scale: Float) -> MeshBounds {
        MeshBounds(
            minX: minX * scale,
            maxX: maxX * scale,
            minZ: minZ * scale,
            maxZ: maxZ * scale
        )
    }
}
