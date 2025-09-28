// SPDX-License-Identifier: MIT
//
//  NavMeshConfig.swift
//  SwiftRecastNavigation
//  Configuration for navigation mesh building
//

import Foundation
import CRecast

/// Area code constants for navigation mesh
public enum NavMeshAreaCode {
    public static let ground: UInt8 = 1
    public static let road: UInt8 = 2
    public static let water: UInt8 = 3
    public static let grass: UInt8 = 4
    public static let door: UInt8 = 5
    public static let jump: UInt8 = 6
    public static let defaultWalkable: UInt8 = 63
}

/// The possible styles for partitioning the heightfield
public enum PartitionStyle: Int32 {
    case watershed
    case monotone
    case layer
}

/// The configuration parameters that drive the creation of your navigation mesh.
public struct NavMeshConfig {
    /// The size of tiles in voxels. Set to 0 for single-tile (solo) mesh
    public var tileSize: Int32 = 0
    
    /// The xz-plane cell size to use for fields. [Limit: > 0] [Units: wu]
    public var cellSize: Float = 0.3
    
    /// The y-axis cell size to use for fields. [Limit: > 0] [Units: wu]
    public var cellHeight: Float = 0.2
    
    /// Agent parameters
    public var agentHeight: Float = 2.0
    public var agentRadius: Float = 0.6
    public var agentMaxClimb: Float = 0.9
    public var agentMaxSlope: Float = 45.0
    
    /// The kind of partitioning to use
    public var partitionStyle: PartitionStyle = .watershed
    
    /// The distance to erode/shrink the walkable area of the heightfield away from obstructions
    public var walkableRadius: Int32 = 2
    
    /// Minimum floor to 'ceiling' height that will still allow the floor area to be considered walkable
    public var walkableHeight: Int32 = 10
    
    /// Maximum ledge height that is considered to still be traversable
    public var walkableClimb: Int32 = 4
    
    /// The maximum allowed length for contour edges along the border of the mesh
    public var maxEdgeLen: Int32 = 12
    
    /// The maximum distance a simplified contour's border edges should deviate the original raw contour
    public var maxSimplificationError: Float = 1.3
    
    /// The minimum number of cells allowed to form isolated island areas
    public var minRegionArea: Int32 = 64
    
    /// Any regions with a span count smaller than this value will, if possible, be merged with larger regions
    public var mergeRegionArea: Int32 = 400
    
    /// The maximum number of vertices allowed for polygons generated during the contour to polygon conversion process
    public var maxVertsPerPoly: Int32 = 6
    
    /// Sets the sampling distance to use when generating the detail mesh
    public var detailSampleDist: Float = 6
    
    /// The maximum distance the detail mesh surface should deviate from heightfield data
    public var detailSampleMaxError: Float = 1
    
    /// Filtering options
    public var filterLowHangingObstacles: Bool = false
    public var filterLedgeSpans: Bool = false
    public var filterWalkableLowHeightSpans: Bool = false
    
    /// Custom bounds (optional - computed from geometry if not set)
    public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
    
    public init() {}
}

/// Represents an area mesh with its corresponding area code
public struct AreaDefinition {
    public let vertices: [SIMD3<Float>]
    public let triangles: [Int32]
    public let areaCode: UInt8
    
    public init(vertices: [SIMD3<Float>], triangles: [Int32], areaCode: UInt8) {
        self.vertices = vertices
        self.triangles = triangles
        self.areaCode = areaCode
    }
    
    public init(vertices: [Float], triangles: [Int32], areaCode: UInt8) {
        var verts: [SIMD3<Float>] = []
        for i in stride(from: 0, to: vertices.count, by: 3) {
            verts.append(SIMD3<Float>(vertices[i], vertices[i + 1], vertices[i + 2]))
        }
        self.vertices = verts
        self.triangles = triangles
        self.areaCode = areaCode
    }
}
