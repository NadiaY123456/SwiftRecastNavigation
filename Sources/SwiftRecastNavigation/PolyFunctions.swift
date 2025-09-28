// SPDX-License-Identifier: MIT
//
//  PolyFunctions.swift
//  SwiftRecastNavigation
//

import CRecast
import simd

// Add these methods to the NavMeshQuery class in NavMeshQuery.swift

public extension NavMeshQuery {
    /// Represents a wall segment with start and end points
    struct WallSegment {
        /// Start point of the wall segment
        public let start: SIMD3<Float>
        /// End point of the wall segment
        public let end: SIMD3<Float>
        
        /// Length of the wall segment
        public var length: Float {
            return simd_distance(start, end)
        }
        
        /// Direction vector from start to end (normalized)
        public var direction: SIMD3<Float> {
            let diff = end - start
            let len = simd_length(diff)
            return len > 0 ? diff / len : SIMD3<Float>(0, 0, 0)
        }
    }
    
    /// Finds all polygons within a circular range from a center point.
    ///
    /// The search is constrained by the navigation mesh and the provided filter.
    /// This is useful for spatial queries like finding all navigable areas within
    /// a certain distance of a character or explosion.
    ///
    /// - Parameters:
    ///   - center: The center point of the search circle
    ///   - radius: The radius of the search circle
    ///   - filter: Optional filter to constrain which polygons are included
    ///   - maxPolys: Maximum number of polygons to return (default: 256)
    /// - Returns: On success, returns an array of polygon references within range.
    ///           On failure, returns a NavMeshError.
    func findPolysWithinRange(
        center: PointInPoly,
        radius: Float,
        filter custom: NavQueryFilter? = nil,
        maxPolys: Int = 256
    ) -> Result<[dtPolyRef], NavMesh.NavMeshError> {
        var centerPoint = center.point
        var resultRefs = [dtPolyRef](repeating: 0, count: maxPolys)
        var resultParents = [dtPolyRef](repeating: 0, count: maxPolys)
        var resultCount: Int32 = 0
        
        let status = query.findPolysAroundCircle(
            center.polyRef,
            &centerPoint,
            radius,
            (custom ?? filter).query,
            &resultRefs,
            &resultParents,
            nil, // costs - not needed for basic query
            &resultCount,
            Int32(maxPolys)
        )
        
        if dtStatusSucceed(status) {
            // Trim the array to actual size
            resultRefs.removeSubrange(Int(resultCount)..<maxPolys)
            return .success(resultRefs)
        }
        
        return .failure(NavMesh.statusToError(status))
    }
    
    /// Finds all polygons within a circular range, including traversal costs.
    ///
    /// This variant also returns the cost to reach each polygon from the center point,
    /// which can be useful for AI decision-making or heat map generation.
    ///
    /// - Parameters:
    ///   - center: The center point of the search circle
    ///   - radius: The radius of the search circle
    ///   - filter: Optional filter to constrain which polygons are included
    ///   - maxPolys: Maximum number of polygons to return (default: 256)
    /// - Returns: On success, returns a tuple containing arrays of polygon references,
    ///           their parent references in the search graph, and the costs to reach them.
    ///           On failure, returns a NavMeshError.
    func findPolysWithinRangeWithCosts(
        center: PointInPoly,
        radius: Float,
        filter custom: NavQueryFilter? = nil,
        maxPolys: Int = 256
    ) -> Result<(polyRefs: [dtPolyRef], parentRefs: [dtPolyRef], costs: [Float]), NavMesh.NavMeshError> {
        var centerPoint = center.point
        var resultRefs = [dtPolyRef](repeating: 0, count: maxPolys)
        var resultParents = [dtPolyRef](repeating: 0, count: maxPolys)
        var resultCosts = [Float](repeating: 0, count: maxPolys)
        var resultCount: Int32 = 0
        
        let status = query.findPolysAroundCircle(
            center.polyRef,
            &centerPoint,
            radius,
            (custom ?? filter).query,
            &resultRefs,
            &resultParents,
            &resultCosts,
            &resultCount,
            Int32(maxPolys)
        )
        
        if dtStatusSucceed(status) {
            // Trim arrays to actual size
            let count = Int(resultCount)
            resultRefs.removeSubrange(count..<maxPolys)
            resultParents.removeSubrange(count..<maxPolys)
            resultCosts.removeSubrange(count..<maxPolys)
            
            return .success((
                polyRefs: resultRefs,
                parentRefs: resultParents,
                costs: resultCosts
            ))
        }
        
        return .failure(NavMesh.statusToError(status))
    }
    
    /// Finds all polygons within a tile's bounds.
    ///
    /// This method retrieves all polygon references that belong to a specific tile
    /// in the navigation mesh. This is useful for debugging, visualization, or
    /// tile-based processing.
    ///
    /// - Parameters:
    ///   - tileX: The X coordinate of the tile
    ///   - tileY: The Y coordinate of the tile
    ///   - layer: The layer of the tile (default: 0)
    /// - Returns: On success, returns an array of all polygon references in the tile.
    ///           Returns an empty array if the tile doesn't exist.
    ///
    /// - Note: This method iterates through all tiles to find the matching coordinates.
    ///         For better performance with frequent queries, consider caching tile references.
    func findPolysInTile(
        tileX: Int,
        tileY: Int,
        layer: Int = 0
    ) -> [dtPolyRef] {
        // Access the underlying navmesh through the query
        guard let navMesh = query.getAttachedNavMesh() else {
            return []
        }
        
        // Find the tile with matching coordinates
        // We need to iterate through tiles to find the one with the right x,y coordinates
        let maxTiles = dtNavMeshGetMaxTiles(navMesh)
        var targetTile: OpaquePointer?
        
        for i in 0..<maxTiles {
            guard let tile = dtNavMeshGetTile(navMesh, i) else { continue }
            
            var tx: Int32 = 0
            var ty: Int32 = 0
            var tlayer: Int32 = 0
            dtNavMeshGetTileStateAt(navMesh, i, &tx, &ty, &tlayer)
            
            if tx == Int32(tileX), ty == Int32(tileY), tlayer == Int32(layer) {
                targetTile = tile
                break
            }
        }
        
        guard let tile = targetTile,
              let header = dtMeshTileGetHeader(tile)
        else {
            return []
        }
        
        let polyCount = Int(dtMeshHeaderGetPolyCount(header))
        var polyRefs: [dtPolyRef] = []
        polyRefs.reserveCapacity(polyCount)
        
        // Get the base reference for this tile
        let base = dtNavMeshGetPolyRefBase(navMesh, tile)
        
        // Get all polygons in this tile
        if let polys = dtMeshTileGetPolys(tile) {
            for i in 0..<polyCount {
                // Calculate the polygon reference
                // Skip null polygons (those without vertices)
                var poly = polys.advanced(by: i).pointee
                if dtPolyGetVertCount(&poly) > 0 {
                    let ref = base | dtPolyRef(i)
                    polyRefs.append(ref)
                }
            }
        }
        
        return polyRefs
    }
    
    /// Finds all polygons within a tile by tile index.
    ///
    /// This is more efficient than `findPolysInTile` if you already know the tile index.
    ///
    /// - Parameter tileIndex: The index of the tile (0 to maxTiles-1)
    /// - Returns: On success, returns an array of all polygon references in the tile.
    ///           Returns an empty array if the tile doesn't exist.
    func findPolysInTileByIndex(tileIndex: Int) -> [dtPolyRef] {
        // Access the underlying navmesh through the query
        guard let navMesh = query.getAttachedNavMesh() else {
            return []
        }
        
        guard tileIndex >= 0, tileIndex < dtNavMeshGetMaxTiles(navMesh),
              let tile = dtNavMeshGetTile(navMesh, Int32(tileIndex)),
              let header = dtMeshTileGetHeader(tile)
        else {
            return []
        }
        
        let polyCount = Int(dtMeshHeaderGetPolyCount(header))
        var polyRefs: [dtPolyRef] = []
        polyRefs.reserveCapacity(polyCount)
        
        // Get the base reference for this tile
        let base = dtNavMeshGetPolyRefBase(navMesh, tile)
        
        // Get all polygons in this tile
        if let polys = dtMeshTileGetPolys(tile) {
            for i in 0..<polyCount {
                // Calculate the polygon reference
                // Skip null polygons (those without vertices)
                var poly = polys.advanced(by: i).pointee
                if dtPolyGetVertCount(&poly) > 0 {
                    let ref = base | dtPolyRef(i)
                    polyRefs.append(ref)
                }
            }
        }
        
        return polyRefs
    }
    
    /// Finds all polygons overlapping a bounding box.
    ///
    /// This method uses the spatial query capabilities to find all polygons
    /// that overlap with the specified axis-aligned bounding box.
    ///
    /// - Parameters:
    ///   - minBounds: Minimum bounds of the query box (x, y, z)
    ///   - maxBounds: Maximum bounds of the query box (x, y, z)
    ///   - filter: Optional filter to constrain which polygons are included
    ///   - maxPolys: Maximum number of polygons to return (default: 256)
    /// - Returns: On success, returns an array of polygon references within the bounds.
    ///           On failure, returns a NavMeshError.
    func findPolysInBounds(
        minBounds: SIMD3<Float>,
        maxBounds: SIMD3<Float>,
        filter custom: NavQueryFilter? = nil,
        maxPolys: Int = 256
    ) -> Result<[dtPolyRef], NavMesh.NavMeshError> {
        var min: [Float] = [minBounds.x, minBounds.y, minBounds.z]
        var max: [Float] = [maxBounds.x, maxBounds.y, maxBounds.z]
        var polyRefs = [dtPolyRef](repeating: 0, count: maxPolys)
        var polyCount: Int32 = 0
        
        let status = query.queryPolygons(
            &min,
            &max,
            (custom ?? filter).query,
            &polyRefs,
            &polyCount,
            Int32(maxPolys)
        )
        
        if dtStatusSucceed(status) {
            // Trim to actual count
            polyRefs.removeSubrange(Int(polyCount)..<maxPolys)
            return .success(polyRefs)
        }
        
        return .failure(NavMesh.statusToError(status))
    }
    
    /// Gets the wall segments around a polygon.
    ///
    /// Wall segments represent the edges of a polygon that are not connected to
    /// other polygons (i.e., boundaries of the walkable area). This is useful for
    /// collision detection, visualization, or determining where a character can't pass.
    ///
    /// - Parameters:
    ///   - polyRef: The polygon reference to query
    ///   - filter: Optional filter to determine which neighboring polygons are considered passable
    ///   - maxSegments: Maximum number of wall segments to return (default: 32)
    /// - Returns: On success, returns an array of wall segments.
    ///           On failure, returns a NavMeshError.
    func getPolyWallSegments(
        polyRef: dtPolyRef,
        filter custom: NavQueryFilter? = nil,
        maxSegments: Int = 32
    ) -> Result<[WallSegment], NavMesh.NavMeshError> {
        // Allocate buffers for the segments
        // Each segment needs 6 floats (3 for start, 3 for end)
        var segmentVerts = [Float](repeating: 0, count: 6 * maxSegments)
        var segmentRefs = [dtPolyRef](repeating: 0, count: maxSegments)
        var segmentCount: Int32 = 0
        
        let status = query.getPolyWallSegments(
            polyRef,
            (custom ?? filter).query,
            &segmentVerts,
            &segmentRefs,
            &segmentCount,
            Int32(maxSegments)
        )
        
        if dtStatusSucceed(status) {
            var segments: [WallSegment] = []
            segments.reserveCapacity(Int(segmentCount))
            
            // Convert the flat array to WallSegment structs
            for i in 0..<Int(segmentCount) {
                let baseIdx = i * 6
                let start = SIMD3<Float>(
                    segmentVerts[baseIdx],
                    segmentVerts[baseIdx + 1],
                    segmentVerts[baseIdx + 2]
                )
                let end = SIMD3<Float>(
                    segmentVerts[baseIdx + 3],
                    segmentVerts[baseIdx + 4],
                    segmentVerts[baseIdx + 5]
                )
                
                segments.append(WallSegment(start: start, end: end))
            }
            
            return .success(segments)
        }
        
        return .failure(NavMesh.statusToError(status))
    }
    
    /// Gets information about a specific polygon.
    ///
    /// This is a convenience method that retrieves detailed information about
    /// a polygon including its vertices and neighbor connections.
    ///
    /// - Parameter polyRef: The polygon reference to query
    /// - Returns: On success, returns detailed polygon information.
    ///           Returns nil if the polygon doesn't exist.
    func getPolyInfo(polyRef: dtPolyRef) -> PolyInfo? {
        guard let navMesh = query.getAttachedNavMesh() else {
            return nil
        }
        
        // Find the tile containing this polygon
        // We need to iterate through tiles to find the one containing this polyRef
        let maxTiles = dtNavMeshGetMaxTiles(navMesh)
        var targetTile: OpaquePointer?
        var polyIndex: Int = -1
        
        for i in 0..<maxTiles {
            guard let tile = dtNavMeshGetTile(navMesh, i),
                  let header = dtMeshTileGetHeader(tile) else { continue }
            
            let base = dtNavMeshGetPolyRefBase(navMesh, tile)
            let polyCount = Int(dtMeshHeaderGetPolyCount(header))
            
            // Check if this polyRef belongs to this tile
            for j in 0..<polyCount {
                if (base | dtPolyRef(j)) == polyRef {
                    targetTile = tile
                    polyIndex = j
                    break
                }
            }
            
            if targetTile != nil { break }
        }
        
        guard let tile = targetTile,
              let header = dtMeshTileGetHeader(tile),
              let polys = dtMeshTileGetPolys(tile),
              let verts = dtMeshTileGetVerts(tile),
              polyIndex >= 0
        else {
            return nil
        }
        
        // Get the polygon
        var poly = polys.advanced(by: polyIndex).pointee
        let vertCount = Int(dtPolyGetVertCount(&poly))
        
        // Extract vertices
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(vertCount)
        
        for i in 0..<vertCount {
            let vertIndex = Int(dtPolyGetVert(&poly, Int32(i)))
            let baseIdx = vertIndex * 3
            vertices.append(SIMD3<Float>(
                verts[baseIdx],
                verts[baseIdx + 1],
                verts[baseIdx + 2]
            ))
        }
        
        // Extract neighbor info
        var neighbors: [dtPolyRef] = []
        neighbors.reserveCapacity(vertCount)
        
        for i in 0..<vertCount {
            let nei = dtPolyGetNeighbor(&poly, Int32(i))
            if nei != 0 {
                // Convert local index to full reference
                let neiRef = dtNavMeshGetPolyRefBase(navMesh, tile) | dtPolyRef(nei - 1)
                neighbors.append(neiRef)
            } else {
                neighbors.append(0) // No neighbor on this edge
            }
        }
        
        return PolyInfo(
            polyRef: polyRef,
            vertices: vertices,
            neighbors: neighbors,
            flags: dtPolyGetFlags(&poly),
            area: dtPolyGetArea(&poly)
        )
    }
    
    /// Information about a polygon
    struct PolyInfo {
        /// The polygon reference
        public let polyRef: dtPolyRef
        /// Vertices of the polygon in world coordinates
        public let vertices: [SIMD3<Float>]
        /// Neighbor polygon references for each edge (0 if no neighbor)
        public let neighbors: [dtPolyRef]
        /// Polygon flags
        public let flags: UInt16
        /// Area type of the polygon
        public let area: UInt8
        
        /// Center point of the polygon
        public var center: SIMD3<Float> {
            guard !vertices.isEmpty else { return SIMD3<Float>(0, 0, 0) }
            return vertices.reduce(SIMD3<Float>(0, 0, 0), +) / Float(vertices.count)
        }
    }
}
