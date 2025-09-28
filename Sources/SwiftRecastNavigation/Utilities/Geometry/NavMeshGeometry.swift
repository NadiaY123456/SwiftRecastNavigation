// SPDX-License-Identifier: MIT
//
//  NavMeshGeometry.swift
//  SwiftRecastNavigation
//
//  Created by Nadia Yilmaz on 6/18/25.
//

import CRecast
import os.log
import RealityKit
import simd

/// Immutable, thread-safe snapshot of a Detour nav-mesh for debug visualisation.
public struct NavMeshGeometry {
    public struct Polygon {
        public let ref: dtPolyRef
        public let vertices: [SIMD3<Float>] // world-space
        public let neighbours: [dtPolyRef]
        public let area: UInt8
        public let flags: UInt16
        public let type: UInt8

        // Tile information
        public let tileX: Int32
        public let tileY: Int32
        public let tileIndex: Int
    }

    public struct TileInfo {
        public let index: Int
        public let x: Int32
        public let y: Int32
        public let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
        public let polyCount: Int
        public let vertCount: Int
    }

    public let polygons: [Polygon]
    public let tiles: [TileInfo]

    public init(polygons: [Polygon], tiles: [TileInfo]) {
        self.polygons = polygons
        self.tiles = tiles
    }
}

private let geomLog = Logger(subsystem: "NavMesh", category: "Extract")

public extension NavMesh {
    /// Pulls vertices + adjacency out of the live Detour structure.
    /// Set `verbose` to `true` to trace progress in Xcode's console.
    func extractGeometry(verbose: Bool = false) -> NavMeshGeometry {
        @inline(__always) func trace(_ items: Any...) {
            guard verbose else { return }
            geomLog.debug("\(items.map { "\($0)" }.joined(separator: " "))")
        }

        var polys: [NavMeshGeometry.Polygon] = []
        var tileInfos: [NavMeshGeometry.TileInfo] = []

        let maxTiles = Int(dtNavMeshGetMaxTiles(navMesh))
        trace("Mesh holds", maxTiles, "tiles")

        // Walk every allocated tile
        for tileIdx in 0 ..< maxTiles {
            // ───────────────────────────────────────────────
            // 1️⃣ Get tile as opaque pointer
            // ───────────────────────────────────────────────
            guard let tilePtr = dtNavMeshGetTile(navMesh, Int32(tileIdx)) else {
                trace("· tile", tileIdx, "is nil – skipped")
                continue
            }

            // Get tile header
            guard let headerPtr = dtMeshTileGetHeader(tilePtr) else {
                // Skip empty tiles - this is normal behavior
                continue
            }

            // Get vertices and polygons
            guard let vertsPtr = dtMeshTileGetVerts(tilePtr),
                  let polysPtr = dtMeshTileGetPolys(tilePtr)
            else {
                trace("· tile", tileIdx, "missing verts/polys – skipped")
                continue
            }

            let polyCount = Int(dtMeshHeaderGetPolyCount(headerPtr))
            let vertCount = Int(dtMeshHeaderGetVertCount(headerPtr))

            // Get tile coordinates
            var tileX: Int32 = 0
            var tileY: Int32 = 0
            var tileLayer: Int32 = 0
            dtNavMeshGetTileStateAt(navMesh, Int32(tileIdx), &tileX, &tileY, &tileLayer)

            // Calculate tile bounds
            var tileBounds = (min: SIMD3<Float>(Float.greatestFiniteMagnitude,
                                                Float.greatestFiniteMagnitude,
                                                Float.greatestFiniteMagnitude),
                              max: SIMD3<Float>(-Float.greatestFiniteMagnitude,
                                                -Float.greatestFiniteMagnitude,
                                                -Float.greatestFiniteMagnitude))

            // Update bounds based on all vertices in this tile
            for i in 0 ..< vertCount {
                let vertIdx = i * 3
                let vert = SIMD3<Float>(
                    vertsPtr[vertIdx + 0],
                    vertsPtr[vertIdx + 1],
                    vertsPtr[vertIdx + 2]
                )
                tileBounds.min = min(tileBounds.min, vert)
                tileBounds.max = max(tileBounds.max, vert)
            }

            // Store tile info
            tileInfos.append(.init(
                index: tileIdx,
                x: tileX,
                y: tileY,
                bounds: tileBounds,
                polyCount: polyCount,
                vertCount: vertCount
            ))

            // Walk every polygon inside the tile
            for polyIdx in 0 ..< polyCount {
                let polyPtr = polysPtr.advanced(by: polyIdx)
                let vCount = Int(dtPolyGetVertCount(polyPtr))

                // -------- vertices --------
                var verts: [SIMD3<Float>] = []
                verts.reserveCapacity(vCount)
                for i in 0 ..< vCount {
                    let vertIdx = Int(dtPolyGetVert(polyPtr, Int32(i))) * 3
                    verts.append(SIMD3<Float>(
                        vertsPtr[vertIdx + 0],
                        vertsPtr[vertIdx + 1],
                        vertsPtr[vertIdx + 2]
                    ))
                }

                // -------- neighbours ------
                var neis: [dtPolyRef] = []
                neis.reserveCapacity(vCount)
                for i in 0 ..< vCount {
                    let n = dtPolyGetNeighbor(polyPtr, Int32(i))
                    if n != 0 {
                        neis.append(dtPolyRef(n))
                    }
                }

                // -------- global ref ------
                let refBase = dtNavMeshGetPolyRefBase(navMesh, tilePtr)
                let ref = dtPolyRef(refBase) | dtPolyRef(polyIdx)

                polys.append(.init(
                    ref: ref,
                    vertices: verts,
                    neighbours: neis,
                    area: dtPolyGetArea(polyPtr),
                    flags: dtPolyGetFlags(polyPtr),
                    type: dtPolyGetType(polyPtr),
                    tileX: tileX,
                    tileY: tileY,
                    tileIndex: tileIdx
                ))
            }
        }

        trace("Extraction finished – total polys:", polys.count, "tiles:", tileInfos.count)
        return NavMeshGeometry(polygons: polys, tiles: tileInfos)
    }
}

public extension NavMeshGeometry {
    /// Bounding sphere around the whole nav-mesh (after your centring step).
    func boundingSphere() -> (center: SIMD3<Float>, radius: Float) {
        var minB = SIMD3<Float>(.greatestFiniteMagnitude,
                                .greatestFiniteMagnitude,
                                .greatestFiniteMagnitude)
        var maxB = -minB
        for p in polygons {
            for v in p.vertices {
                minB = min(minB, v)
                maxB = max(maxB, v)
            }
        }
        let center = (minB + maxB) * 0.5
        let radius = length(maxB - center) // half the diagonal
        return (center, radius)
    }

    /// Axis-aligned bounding box of all vertices.
    func boundingBox() -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var minB = SIMD3<Float>(.greatestFiniteMagnitude,
                                .greatestFiniteMagnitude,
                                .greatestFiniteMagnitude)
        var maxB = -minB
        for p in polygons {
            for v in p.vertices {
                minB = min(minB, v)
                maxB = max(maxB, v)
            }
        }
        return (min: minB, max: maxB)
    }
}

public extension NavMeshGeometry {
    /// Prints geometry statistics to the console.
    func printStatistics() {
        // Total polys
        print("\n📊 Geometry Statistics:")
        print("  Total polygons: \(polygons.count)")
        print("  Total tiles: \(tiles.count)")

        // Count by area type
        var areaTypes: [UInt8: Int] = [:]
        for poly in polygons {
            areaTypes[poly.area, default: 0] += 1
        }
        print("\n🏷️ Area types:")
        for (area, count) in areaTypes.sorted(by: { $0.key < $1.key }) {
            print("  Area \(area): \(count) polygon\(count == 1 ? "" : "s")")
        }

        // Polygons per tile
        var polysPerTile: [Int: Int] = [:]
        for poly in polygons {
            polysPerTile[poly.tileIndex, default: 0] += 1
        }
        print("\n🗺️ Tile distribution:")
        for tileInfo in tiles {
            let polyCount = polysPerTile[tileInfo.index] ?? 0
            print("  Tile [\(tileInfo.x),\(tileInfo.y)] (index \(tileInfo.index)): \(polyCount) polygons")
        }

        // Bounds (reuse your existing boundingBox())
        let bounds = boundingBox()
        let minB = bounds.min
        let maxB = bounds.max

        print("\n📏 Mesh bounds:")
        print("  Min: \(minB)")
        print("  Max: \(maxB)")
        print("  Size: \(maxB - minB)")
    }

    /// Get all polygons belonging to a specific tile
    func polygons(forTileX x: Int32, tileY y: Int32) -> [Polygon] {
        return polygons.filter { $0.tileX == x && $0.tileY == y }
    }

    /// Get all polygons belonging to a specific tile index
    func polygons(forTileIndex index: Int) -> [Polygon] {
        return polygons.filter { $0.tileIndex == index }
    }

    /// Find which tile contains a given world position
    func tile(containingPosition pos: SIMD3<Float>) -> TileInfo? {
        for tile in tiles {
            if pos.x >= tile.bounds.min.x, pos.x <= tile.bounds.max.x,
               pos.y >= tile.bounds.min.y, pos.y <= tile.bounds.max.y,
               pos.z >= tile.bounds.min.z, pos.z <= tile.bounds.max.z
            {
                return tile
            }
        }
        return nil
    }
}
