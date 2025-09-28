// SPDX-License-Identifier: MIT
//
//  EntityExtensions.swift
//  SwiftRecastNavigation
//
//  RealityKit Entity extensions for traversal and bounds calculation
//

#if canImport(RealityKit)
import RealityKit
import simd



// MARK: - Entity Traversal

extension Entity {
    /// Performs depth-first traversal, executing closure on each entity
    func visit(_ body: (Entity) -> Void) {
        body(self)
        children.forEach { $0.visit(body) }
    }
}

// MARK: - ModelEntity Bounds

extension ModelEntity {
    /// Computes precise X-Z bounds from all vertex data in local space
    func exactLocalXZBounds() -> (min: SIMD2<Float>, max: SIMD2<Float>) {
        var minX = Float.infinity, maxX = -Float.infinity
        var minZ = Float.infinity, maxZ = -Float.infinity
        
        visit { entity in
            guard let modelComp = entity.components[ModelComponent.self] else { return }
            
            let bbox = modelComp.mesh.bounds
            minX = min(minX, bbox.min.x)
            maxX = max(maxX, bbox.max.x)
            minZ = min(minZ, bbox.min.z)
            maxZ = max(maxZ, bbox.max.z)
        }
        return (SIMD2<Float>(minX, minZ), SIMD2<Float>(maxX, maxZ))
    }
}
#endif
