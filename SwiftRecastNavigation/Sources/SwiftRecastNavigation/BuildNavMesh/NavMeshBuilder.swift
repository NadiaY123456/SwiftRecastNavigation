// SPDX-License-Identifier: MIT
//
//  NavMeshBuilder.swift
//  SwiftRecastNavigation
//
//  Main navigation mesh builder
//

import CRecast
import Foundation

/// Creates a navigational mesh based on your geometry.
///
/// The builder always uses a tiled approach internally. For single-tile (solo) meshes,
/// set tileSize to 0 in the configuration.
public class NavMeshBuilder {
    // Internal tiled mesh result
    public var tiledResult: UnsafeMutablePointer<BindingTileMeshResult>?
    
    /// The minimum boundary used for building
    public let boundaryMin: SIMD3<Float>
    
    /// The maximum boundary used for building
    public let boundaryMax: SIMD3<Float>
    
    /// The configuration used to build this mesh
    public let config: NavMeshConfig
    
    /// Number of tiles built successfully
    public var tilesBuilt: Int {
        return Int(tiledResult?.pointee.tilesBuilt ?? 0)
    }
    
    /// Total number of tiles in the mesh
    public var totalTiles: Int {
        return Int(tiledResult?.pointee.totalTiles ?? 0)
    }
    
    /// Creates a navigation mesh from vertices and triangles
    /// - Parameters:
    ///   - vertices: Array of vertices
    ///   - triangles: Triangle index array
    ///   - config: Configuration for mesh creation
    ///   - areas: Optional array of area definitions for marking special regions
    public convenience init(
        vertices: [SIMD3<Float>],
        triangles: [Int32],
        config: NavMeshConfig = NavMeshConfig(),
        areas: [AreaDefinition] = []
    ) throws {
        try self.init(
            vertices: NavMeshBuilder.flatten(vertices),
            triangles: triangles,
            config: config,
            areas: areas
        )
    }
    
    /// Creates a navigation mesh from flattened vertices and triangles
    public init(
        vertices: [Float],
        triangles: [Int32],
        config: NavMeshConfig = NavMeshConfig(),
        areas: [AreaDefinition] = []
    ) throws {
        self.config = config
        
        // Calculate bounds if not provided
        if let customBounds = config.bounds {
            boundaryMin = customBounds.min
            boundaryMax = customBounds.max
        } else {
            var minBounds = SIMD3<Float>()
            var maxBounds = SIMD3<Float>()
            
            vertices.withUnsafeBufferPointer { ptr in
                ptr.withMemoryRebound(to: Float.self) { castPtr in
                    withUnsafeMutablePointer(to: &minBounds) { minPtr in
                        minPtr.withMemoryRebound(to: Float.self, capacity: 3) { minPtrCast in
                            withUnsafeMutablePointer(to: &maxBounds) { maxPtr in
                                maxPtr.withMemoryRebound(to: Float.self, capacity: 3) { maxPtrCast in
                                    rcCalcBounds(castPtr.baseAddress, Int32(vertices.count / 3), minPtrCast, maxPtrCast)
                                }
                            }
                        }
                    }
                }
            }
            boundaryMin = minBounds
            boundaryMax = maxBounds
        }
        
        // Create rcConfig
        var cfg = rcConfig()
        cfg.cs = config.cellSize
        cfg.ch = config.cellHeight
        cfg.walkableSlopeAngle = config.agentMaxSlope
        cfg.walkableHeight = config.walkableHeight
        cfg.walkableClimb = config.walkableClimb
        cfg.walkableRadius = config.walkableRadius
        cfg.maxEdgeLen = config.maxEdgeLen
        cfg.maxSimplificationError = config.maxSimplificationError
        cfg.minRegionArea = config.minRegionArea
        cfg.mergeRegionArea = config.mergeRegionArea
        cfg.maxVertsPerPoly = config.maxVertsPerPoly
        cfg.detailSampleDist = config.detailSampleDist
        cfg.detailSampleMaxError = config.detailSampleMaxError
        
        // Set bounds
        cfg.bmin = (boundaryMin.x, boundaryMin.y, boundaryMin.z)
        cfg.bmax = (boundaryMax.x, boundaryMax.y, boundaryMax.z)
        
        // Calculate grid size
        withUnsafeMutablePointer(to: &cfg.bmin) { minPtr in
            minPtr.withMemoryRebound(to: Float.self, capacity: 3) { minPtrCast in
                withUnsafeMutablePointer(to: &cfg.bmax) { maxPtr in
                    maxPtr.withMemoryRebound(to: Float.self, capacity: 3) { maxPtrCast in
                        rcCalcGridSize(minPtrCast, maxPtrCast, cfg.cs, &cfg.width, &cfg.height)
                    }
                }
            }
        }
        
        // Set tile size
        cfg.tileSize = config.tileSize > 0 ? config.tileSize : max(cfg.width, cfg.height)
        cfg.borderSize = config.walkableRadius + 3
        
        // Create flags
        var flags: Int32 = 0
        switch config.partitionStyle {
        case .watershed:
            flags = Int32(PARTITION_WATERSHED)
        case .monotone:
            flags = Int32(PARTITION_MONOTONE)
        case .layer:
            flags = Int32(PARTITION_LAYER)
        }
        
        flags |= config.filterLedgeSpans ? Int32(FILTER_LEDGE_SPANS) : 0
        flags |= config.filterLowHangingObstacles ? Int32(FILTER_LOW_HANGING_OBSTACLES) : 0
        flags |= config.filterWalkableLowHeightSpans ? Int32(FILTER_WALKABLE_LOW_HEIGHT_SPANS) : 0
        
        // Create tile config
        var tileConfig = TileConfig(tileSize: cfg.tileSize)
        
        // Build tiled navmesh
        let result = try buildTiledNavMesh(
            config: &cfg,
            tileConfig: &tileConfig,
            flags: flags,
            vertices: vertices,
            triangles: triangles,
            areas: areas,
            agentHeight: config.agentHeight,
            agentRadius: config.agentRadius,
            agentMaxClimb: config.agentMaxClimb
        )
        
        tiledResult = result
    }
    
    // MARK: – Internal helpers

    /// Returns the Detour nav-mesh as an opaque type Swift understands.
    public func getNavMesh() -> dtNavMesh? {
        guard
            let result = tiledResult,
            let voidPtr = getNavMeshFromResultAsVoidPtr(result) // C → void*
        else { return nil }

        // Cast the void pointer directly to the opaque dtNavMesh type
        // In Swift, dtNavMesh is imported as an opaque type that represents the C++ pointer
        return unsafeBitCast(voidPtr, to: dtNavMesh?.self)
    }

    // MARK: – Public API ---------------------------------------------------------

    /// Creates a `NavMesh` wrapper around the live C++ object.
    public func makeNavMesh() throws -> NavMesh {
        // 1. Sanity-check the builder actually produced a mesh.
        guard let result = tiledResult, result.pointee.navMesh != nil else {
            throw NavMeshError.invalidConfiguration
        }

        // 2. (Optional) export once so we verify the mesh serialises cleanly.
        var blobPtr: UnsafeMutableRawPointer?
        var blobSize: Int32 = 0
        let ok = bindingExportTiledNavMesh(result.pointee.navMesh, &blobPtr, &blobSize)
        guard ok == BD_OK else { throw NavMeshExportError.exportFailed }
        if let p = blobPtr { free(p) } // we don't need the copy

        // 3. Fetch the mesh pointer and wrap it.
        guard let navMeshHandle = getNavMesh() else {
            throw NavMeshError.invalidConfiguration
        }
        let navMesh = NavMesh(navMesh: navMeshHandle)

        // 4. Detach the pointer from the build result so each is freed only once.
        tiledResult?.pointee.navMesh = nil
        return navMesh
    }
    
    /// Exports the navigation mesh to a binary format suitable for saving
    public func exportToData() throws -> Data {
        guard let result = tiledResult,
              let navMesh = result.pointee.navMesh
        else {
            throw NavMeshExportError.invalidParameters
        }
        
        var ptr: UnsafeMutableRawPointer?
        var size: Int32 = 0
        
        let status = bindingExportTiledNavMesh(navMesh, &ptr, &size)
        
        switch status {
        case BD_OK:
            guard let ptr = ptr else {
                throw NavMeshExportError.allocationFailed
            }
            return Data(bytesNoCopy: ptr, count: Int(size), deallocator: .free)
        case BD_ERR_INVALID_PARAM:
            throw NavMeshExportError.invalidParameters
        case BD_ERR_ALLOC_NAVMESH:
            throw NavMeshExportError.allocationFailed
        default:
            throw NavMeshExportError.exportFailed
        }
    }
    
    deinit {
        if let result = tiledResult {
            bindingReleaseTiledNavMesh(result)
        }
    }
    
    // MARK: - Private Helpers
    
    private static func flatten(_ d: [SIMD3<Float>]) -> [Float] {
        var ret = [Float](repeating: 0, count: d.count * 3)
        var j = 0
        for e in d {
            ret[j] = e.x
            ret[j + 1] = e.y
            ret[j + 2] = e.z
            j += 3
        }
        return ret
    }
    
    //  ──────────────────────────────────────────────────────────────────────────────
    private func buildTiledNavMesh(
        config: inout rcConfig,
        tileConfig: inout TileConfig,
        flags: Int32,
        vertices: [Float],
        triangles: [Int32],
        areas: [AreaDefinition],
        agentHeight: Float,
        agentRadius: Float,
        agentMaxClimb: Float
    ) throws -> UnsafeMutablePointer<BindingTileMeshResult> {
        // ── 1.  Pre-flatten area buffers (unchanged) ───────────────────────────────
        var areaVertArrays: [[Float]] = []
        var areaTriArrays: [[Int32]] = []
        var areaCodes: [UInt8] = []

        for area in areas {
            areaVertArrays.append(Self.flatten(area.vertices))
            areaTriArrays.append(area.triangles)
            areaCodes.append(area.areaCode)
        }

        // ── 2.  Helper that does *all* the real work, with no generics in sight ────
        @inline(never)
        func makeMesh(
            vBase: UnsafePointer<Float>,
            tBase: UnsafePointer<Int32>
        ) -> UnsafeMutablePointer<BindingTileMeshResult>? {
            if areas.isEmpty {
                // 2-A  No custom areas
                return bindingBuildTiledNavMesh(
                    &config, &tileConfig, flags,
                    vBase, Int32(vertices.count / 3),
                    tBase, Int32(triangles.count / 3),
                    nil, nil, /* areaCount */ 0,
                    agentHeight, agentRadius, agentMaxClimb
                )
            }

            // 2-B  Build per-area pointer lists once
            var areaVertPtrs: [UnsafePointer<Float>?] = []
            var areaVertCnts: [Int32] = []
            var areaTriPtrs: [UnsafePointer<Int32>?] = []
            var areaTriCnts: [Int32] = []

            for i in 0 ..< areaVertArrays.count {
                areaVertArrays[i].withUnsafeBufferPointer { p in
                    areaVertPtrs.append(p.baseAddress)
                }
                areaVertCnts.append(Int32(areaVertArrays[i].count / 3))

                areaTriArrays[i].withUnsafeBufferPointer { p in
                    areaTriPtrs.append(p.baseAddress)
                }
                areaTriCnts.append(Int32(areaTriArrays[i].count / 3))
            }

            // 2-C  Final C bridge call
            return areaVertPtrs.withUnsafeMutableBufferPointer { vPtrBuf in
                areaVertCnts.withUnsafeMutableBufferPointer { vCntBuf in
                    areaTriPtrs.withUnsafeMutableBufferPointer { tPtrBuf in
                        areaTriCnts.withUnsafeMutableBufferPointer { tCntBuf in
                            areaCodes.withUnsafeBufferPointer { codeBuf in

                                bindingBuildTiledNavMeshWithAreas(
                                    &config, &tileConfig, flags,
                                    vBase, Int32(vertices.count / 3),
                                    tBase, Int32(triangles.count / 3),
                                    vPtrBuf.baseAddress, // now UnsafeMutablePointer
                                    vCntBuf.baseAddress,
                                    tPtrBuf.baseAddress,
                                    tCntBuf.baseAddress,
                                    codeBuf.baseAddress,
                                    Int32(areas.count),
                                    agentHeight, agentRadius, agentMaxClimb
                                )
                            }
                        }
                    }
                }
            }
        }

        // ── 3.  Two *tiny* generic closures – compiler is happy now ────────────────
        let maybePtr: UnsafeMutablePointer<BindingTileMeshResult>? =
            vertices.withUnsafeBufferPointer { vBuf in
                triangles.withUnsafeBufferPointer { tBuf in
                    guard let vBase = vBuf.baseAddress,
                          let tBase = tBuf.baseAddress else { return nil }
                    return makeMesh(vBase: vBase, tBase: tBase)
                }
            }

        // ── 4.  Error handling / result unwrap (unchanged) ─────────────────────────
        guard let resultPtr = maybePtr else { throw NavMeshError.memory }

        switch resultPtr.pointee.code {
        case BCODE_OK where resultPtr.pointee.tilesBuilt == 0: throw NavMeshError.noTilesBuilt
        case BCODE_OK: return resultPtr
        case BCODE_ERR_MEMORY: throw NavMeshError.memory
        case BCODE_ERR_INIT_TILE_NAVMESH: throw NavMeshError.initTileNavMesh
        case BCODE_ERR_BUILD_TILE: throw NavMeshError.buildTile
        case BCODE_ERR_ADD_TILE: throw NavMeshError.addTile
        default: throw NavMeshError.unknown
        }
    }
}
