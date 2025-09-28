// SPDX-License-Identifier: MIT
//  NavMeshBinLoader.swift
//  SwiftRecastNavigation
//



import CRecast
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Private binary helpers ------------------------------------------------

public typealias NavMeshSetHeader  = rcNavMeshSetHeader
public typealias NavMeshTileHeader = rcNavMeshTileHeader

public let NAVMESHSET_MAGIC: Int32 = 0x4D534554 // "MSET"
public let NAVMESHSET_VERSION: Int32 = 1 // Detour demo/save default

public extension NavMesh {
    /// Loads a **multi‑tile** Detour binary (usually produced by `SaveAll` in
    /// the Recast **Demo** or any custom builder that writes a *set* header).
    ///
    /// If the blob is *not* tiled `FileError.notTiled` is thrown.
    /// – Parameters:
    ///   – url:      File‐URL to the `.bin` nav‑mesh set.
    ///   – zeroCopy: `true` ⇒ memory maps the file (no overhead, *read‑only*).
    convenience init(tiledContentsOf url: URL,
                     zeroCopy: Bool = false) throws
    {
        // --------------------------------------------------------------------
        // 1️⃣  Materialise the binary into memory (copy or mmap) -------------
        // --------------------------------------------------------------------
        let rawPtr: UnsafeMutableRawPointer
        let rawSize: Int
        let detourOwns: Bool

        if zeroCopy {
            let fd = open(url.path, O_RDONLY)
            guard fd >= 0 else { throw FileError.fileNotFound }
            defer { close(fd) }

            var st = stat()
            guard fstat(fd, &st) == 0, st.st_size > 0 else {
                throw FileError.readError
            }

            rawSize = Int(st.st_size)
            // Map the file read/write so Detour can patch it.
            guard let addr = mmap(nil, rawSize, PROT_READ | PROT_WRITE, MAP_FILE | MAP_PRIVATE, fd, 0),
                  addr != MAP_FAILED else { throw FileError.readError }

            rawPtr = UnsafeMutableRawPointer(mutating: addr)
            detourOwns = false // we manage mmap later
        }
        else {
            let blob = try Data(contentsOf: url, options: .mappedIfSafe)
            rawSize = blob.count
            rawPtr = UnsafeMutableRawPointer.allocate(byteCount: rawSize,
                                                      alignment: MemoryLayout<UInt8>.alignment)
            // Explicitly ignore the return of withUnsafeBytes to silence warning.
            blob.withUnsafeBytes { srcBuf in
                guard let srcBase = srcBuf.baseAddress else { return }
                memcpy(rawPtr, srcBase, rawSize)
            }
            detourOwns = true // dtFree() will take it
        }

        // --------------------------------------------------------------------
        // 2️⃣  Validate set header ------------------------------------------
        // --------------------------------------------------------------------
        guard rawSize >= MemoryLayout<NavMeshSetHeader>.size else {
            throw FileError.readError
        }
        let setHeader = rawPtr.bindMemory(to: NavMeshSetHeader.self, capacity: 1).pointee

        guard setHeader.numTiles > 0 else { throw FileError.readError /* malformed set */ }
        guard setHeader.magic == NAVMESHSET_MAGIC else { throw FileError.notTiled }
        guard setHeader.version == NAVMESHSET_VERSION else { throw NavMeshError.wrongVersion }

        // --------------------------------------------------------------------
        // 3️⃣  Boot ‑up a fresh dtNavMesh ------------------------------------
        // --------------------------------------------------------------------
        guard let handle = dtAllocNavMesh() else { throw NavMeshError.alloc }
        var params = setHeader.params
        // NOTE: C++ member function is literally named `init`; in Swift you call it with back‑ticks.
        // There are two overloads; the pointer‑to‑params variant is the one we need here.
        var status = handle.`init`(&params)
        guard !dtStatusFailed(status) else {
            dtFreeNavMesh(handle)
            throw NavMesh.statusToError(status)
        }

        // --------------------------------------------------------------------
        // 4️⃣  Stream‑add every tile ----------------------------------------
        // --------------------------------------------------------------------
        var cursor = rawPtr.advanced(by: MemoryLayout<NavMeshSetHeader>.size)

        for _ in 0 ..< setHeader.numTiles {
            let tileHeader = cursor.bindMemory(to: NavMeshTileHeader.self, capacity: 1).pointee
            cursor = cursor.advanced(by: MemoryLayout<NavMeshTileHeader>.size)

            guard tileHeader.dataSize > 0 else { continue }

            var resultRef: dtTileRef = 0
            // Tell Detour NOT to free pages we did not malloc:
            let flags = detourOwns ? Int32(DT_TILE_FREE_DATA.rawValue) : 0
            status = handle.addTile(cursor,
                                    tileHeader.dataSize,
                                    flags,
                                    tileHeader.tileRef,   // preserve original reference
                                    &resultRef)
            guard !dtStatusFailed(status) else {
                dtFreeNavMesh(handle)
                throw NavMesh.statusToError(status)
            }

            cursor = cursor.advanced(by: Int(tileHeader.dataSize))
        }

        // --------------------------------------------------------------------
        // 5️⃣  Chain‑up into NavMesh ----------------------------------------
        // --------------------------------------------------------------------
        self.init(navMesh: handle,
                  mmapPtr: detourOwns ? nil : rawPtr,
                  mmapSize: detourOwns ? 0 : rawSize)
    }

    // MARK: - Error extension ----------------------------------------------

    enum FileError: Error {
        case fileNotFound // couldn’t open
        case readError // fread/fstat fail or len==0
        case notTiled // blob was solo mesh, not a set
    }
}

