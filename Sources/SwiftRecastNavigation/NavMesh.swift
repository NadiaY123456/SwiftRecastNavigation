// SPDX-License-Identifier: MIT
import CRecast
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Mesh that can be navigated and queried.
///
/// The NavMesh contains information of where can entities live and move in the space and can be used to
/// perform path finding operations (how to get from one point to another in the mesh given various constraints like
/// the dimension of your agents, the slope they can climb up, portals connecting the mesh), finding points in the mesh given
/// a position, or to run agents that are part of a crowd.
///
/// You either obtain a ``NavMesh`` from calling ``NavMeshBuilder/makeNavMesh(agentHeight:agentRadius:agentMaxClimb:)``
/// or you can instantiate it from a previously serialized navigation mesh created with ``NavMeshBuilder/makeNavigationBlob(agentHeight:agentRadius:agentMaxClimb:)``.
///
/// Create ``NavMeshQuery`` objects to query the navigation mesh using ``makeQuery(maxNodes:)``, which
/// creates a query with an upper limit on the number of nodes returned.
///
/// Create a ``Crowd`` controller that manages ``CrowdAgent`` goals in your mesh using the
/// ``makeCrowd(maxAgents:agentRadius:)`` method.
///
public class NavMesh {
    /// Errors that are surfaced by the Detour API.
    public enum NavMeshError: Error {
        /// Input data is not recognized.
        case wrongMagic
        /// Input data is in wrong version.
        case wrongVersion
        /// Operation ran out of memory.
        case alloc
        /// An input parameter was invalid.
        case invalidParam
        /// Result buffer for the query was too small to store all results.
        case bufferTooSmall
        /// Query ran out of nodes during search.
        case outOfNodes
        /// Query did not reach the end location, returning best guess.
        case partialResult
        /// A tile has already been assigned to the given x,y coordinate
        case alreadyOccupied
        /// A new error that is not handled was produced by Detour
        case unknown
    }

    @inline(__always)
    static func statusToError(_ status: dtStatus) -> NavMeshError {
        switch status & DT_STATUS_DETAIL_MASK {
        case DT_WRONG_MAGIC: return .wrongMagic
        case DT_WRONG_VERSION: return .wrongVersion
        case DT_OUT_OF_MEMORY: return .alloc
        case DT_INVALID_PARAM: return .invalidParam
        case DT_BUFFER_TOO_SMALL: return .bufferTooSmall
        case DT_OUT_OF_NODES: return .outOfNodes
        case DT_PARTIAL_RESULT: return .partialResult
        case DT_ALREADY_OCCUPIED: return .alreadyOccupied
        default: return .unknown
        }
    }

    // MARK: – Stored properties -------------------------------------------------

    /// Low-level Detour nav-mesh handle.
    public let navMesh: dtNavMesh

    /// If the mesh data came from an `mmap`-ed file, keep the pointer so we can
    /// `munmap` it in `deinit`.
    /// For loading NavMesh from bin
    /// they default to zero‑copy disabled
    private var mmapPtr: UnsafeMutableRawPointer?
    private var mmapSize: Int
    
    /// Track if we own the navMesh and should free it
    private let ownsNavMesh: Bool

    // MARK: – Initialisers ------------------------------------------------------

    /// Wrap an existing Detour mesh **without** taking ownership of any data.
    public init(navMesh: dtNavMesh) {
        self.navMesh = navMesh
        self.mmapPtr = nil
        self.mmapSize = 0
        self.ownsNavMesh = true   // <-- own and free in deinit
    }

    /// Creates a NavMesh from a previously generated `Data` that was returned by
    /// ``NavMeshBuilder/makeNavigationBlob(agentHeight:agentRadius:agentMaxClimb:)`` method.
    ///
    public init(_ blob: Data) throws {
        guard let handle = dtAllocNavMesh() else { throw NavMeshError.alloc }

        // Copy the blob so Detour can manage (and later free) the memory itself.
        guard let copyPtr = malloc(blob.count) else {
            dtFreeNavMesh(handle)
            throw NavMeshError.alloc
        }
        _ = blob.withUnsafeBytes { src in
            memcpy(copyPtr, src.baseAddress, blob.count)
        }

        let status = handle.`init`(copyPtr,
                                   Int32(blob.count),
                                   Int32(DT_TILE_FREE_DATA.rawValue))
        guard !dtStatusFailed(status) else {
            dtFreeNavMesh(handle)
            throw NavMesh.statusToError(status)
        }

        navMesh = handle
        mmapPtr = nil // Detour owns `copyPtr` now
        mmapSize = 0
        ownsNavMesh = true
    }

    /// Designated *internal* initialiser used by the tiled loader.
    ///
    /// - `freeWithDetour == true`: the buffer becomes Detour-managed
    /// - `false`: we stay responsible for `munmap`-ing it on `deinit`
    init(_ ptr: UnsafeMutableRawPointer,
         size: Int32,
         freeWithDetour: Bool) throws
    {
        guard let handle = dtAllocNavMesh() else { throw NavMeshError.alloc }

        let flags = freeWithDetour ? Int32(DT_TILE_FREE_DATA.rawValue) : 0
        let status = handle.`init`(ptr, size, flags)
        guard !dtStatusFailed(status) else {
            dtFreeNavMesh(handle)
            throw NavMesh.statusToError(status)
        }

        navMesh = handle
        mmapPtr = freeWithDetour ? nil : ptr
        mmapSize = freeWithDetour ? 0 : Int(size)
        ownsNavMesh = true
    }

    /// Convenience wrapper when **you** own the buffer (Detour will free it).
    public convenience init(_ ptr: UnsafeMutableRawPointer,
                            size: Int32) throws
    {
        try self.init(ptr, size: size, freeWithDetour: true)
    }

    /// Internal – for the tiled loader when it already has a live mesh.
    init(navMesh: dtNavMesh,
         mmapPtr: UnsafeMutableRawPointer? = nil,
         mmapSize: Int = 0)
    {
        self.navMesh = navMesh
        self.mmapPtr = mmapPtr
        self.mmapSize = mmapSize
        self.ownsNavMesh = true   // <-- own and free in deinit
    }

    deinit {
        if ownsNavMesh {
            dtFreeNavMesh(navMesh)
        }
        if let ptr = mmapPtr, mmapSize > 0 {
            munmap(ptr, mmapSize)
        }
    }

    /// Creates a query object, used to find paths
    /// - Parameters:
    ///  - maxNodes: Maximum number of search nodes. [Limits: 0 < value <= 65535]
    /// - Returns: the nav mesh query, or throws an exception on error.
    public func makeQuery(maxNodes: Int = 2048) throws -> NavMeshQuery {
        return try NavMeshQuery(nav: self, maxNodes: Int32(maxNodes))
    }

    /// Creates a new crowd controlling system
    ///
    /// - Parameters:
    ///   - maxAgents: The maximum number of agents the crowd can manage.
    ///   - agentRadius: The maximum radius of any agent that will be added to the crowd.
    /// - Returns: A crowd object that can manage the crowd on this mesh
    public func makeCrowd(maxAgents: Int, agentRadius: Float) throws -> Crowd {
        try Crowd(maxAgents: Int32(maxAgents), agentRadius: agentRadius, nav: self)
    }

    @inline(__always)
    func validateHeader(_ raw: UnsafeRawPointer, size: Int) throws {
        guard size >= MemoryLayout<dtMeshHeader>.size else {
            throw NavMeshError.invalidParam // existing case
        }
        let hdr = raw.bindMemory(to: dtMeshHeader.self, capacity: 1).pointee
        guard hdr.magic == DT_NAVMESH_MAGIC else { throw NavMeshError.wrongMagic }
        guard hdr.version == DT_NAVMESH_VERSION else { throw NavMeshError.wrongVersion }
    }
}

public extension NavMesh {
    /// Get the tile coordinates for a given tile index
    func getTileStateAt(_ tileIndex: Int32, _ tx: inout Int32, _ ty: inout Int32, _ tlayer: inout Int32) {
        dtNavMeshGetTileStateAt(navMesh, tileIndex, &tx, &ty, &tlayer)
    }
    
    /// Get the tile coordinates for a given tile index (convenience version)
    func getTileCoordinates(at tileIndex: Int) -> (x: Int32, y: Int32, layer: Int32)? {
        var x: Int32 = 0
        var y: Int32 = 0
        var layer: Int32 = 0
        dtNavMeshGetTileStateAt(navMesh, Int32(tileIndex), &x, &y, &layer)
        
        // Check if this is a valid tile
        if let tile = dtNavMeshGetTile(navMesh, Int32(tileIndex)),
           dtMeshTileGetHeader(tile) != nil {
            return (x: x, y: y, layer: layer)
        }
        return nil
    }
}
