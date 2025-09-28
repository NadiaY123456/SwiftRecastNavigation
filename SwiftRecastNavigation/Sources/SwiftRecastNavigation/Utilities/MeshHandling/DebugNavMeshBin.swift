// SPDX-License-Identifier: MIT
//
//  DebugAndTest.swift
//  SwiftRecastNavigation
//
//  Created by Nadia Yilmaz on 6/16/25.
//


import Foundation
import CRecast

// MARK: - File Analysis

public func analyzeNavMeshFile(_ url: URL) throws {
    let data = try Data(contentsOf: url)
    print("\n=== File Analysis ===")
    print("File size: \(data.count) bytes")
    
    // Show raw bytes at start
    print("\nFirst 32 bytes (hex):")
    data.prefix(32).enumerated().forEach { idx, byte in
        if idx % 16 == 0 { print("\n\(String(format: "%04X:", idx))", terminator: " ") }
        print(String(format: "%02X", byte), terminator: " ")
    }
    print("\n")
    
    // Analyze structure
    data.withUnsafeBytes { ptr in
        guard let base = ptr.baseAddress else { return }
        
        // Check for MSET header
        if data.count >= MemoryLayout<NavMeshSetHeader>.size {
            let setHeader = base.bindMemory(to: NavMeshSetHeader.self, capacity: 1).pointee
            
            print("\nChecking for multi-tile format:")
            print("  Magic: 0x\(String(format: "%08X", setHeader.magic)) ", terminator: "")
            
            if setHeader.magic == NAVMESHSET_MAGIC {
                print("✅ Valid MSET")
                print("  Version: \(setHeader.version)")
                print("  Tiles: \(setHeader.numTiles)")
                print("  Origin: (\(setHeader.params.orig.0), \(setHeader.params.orig.1), \(setHeader.params.orig.2))")
                print("  Tile Size: \(setHeader.params.tileWidth) x \(setHeader.params.tileHeight)")
                print("  Max Tiles: \(setHeader.params.maxTiles)")
                print("  Max Polys: \(setHeader.params.maxPolys)")
                
                // Check tiles
                if setHeader.numTiles == 0 {
                    print("  ⚠️ WARNING: No tiles in mesh!")
                } else {
                    var offset = MemoryLayout<NavMeshSetHeader>.size
                    for i in 0..<min(setHeader.numTiles, 3) {
                        if offset + MemoryLayout<NavMeshTileHeader>.size > data.count { break }
                        
                        let tileHeader = base.advanced(by: offset)
                            .bindMemory(to: NavMeshTileHeader.self, capacity: 1).pointee
                        print("\n  Tile \(i): ref=\(tileHeader.tileRef), size=\(tileHeader.dataSize)")
                        
                        offset += MemoryLayout<NavMeshTileHeader>.size
                        if offset + Int(tileHeader.dataSize) <= data.count && tileHeader.dataSize > 0 {
                            let meshHdr = base.advanced(by: offset)
                                .bindMemory(to: dtMeshHeader.self, capacity: 1).pointee
                            print("    Polys: \(meshHdr.polyCount), Verts: \(meshHdr.vertCount)")
                        }
                        offset += Int(tileHeader.dataSize)
                    }
                }
            } else {
                print("❌ Not MSET format")
            }
        }
        
        // Check for single-tile format
        if data.count >= MemoryLayout<dtMeshHeader>.size {
            let meshHeader = base.bindMemory(to: dtMeshHeader.self, capacity: 1).pointee
            print("\nChecking for single-tile format:")
            print("  Magic: 0x\(String(format: "%08X", meshHeader.magic)) ", terminator: "")
            
            if meshHeader.magic == DT_NAVMESH_MAGIC {
                print("✅ Valid single-tile")
                print("  Version: \(meshHeader.version)")
                print("  Polys: \(meshHeader.polyCount), Verts: \(meshHeader.vertCount)")
            } else {
                print("☢️ Not single-tile format")
            }
        }
    }
}


// MARK: - Error Debugging
public func debugError(_ error: Error) {
    print("  Error type: \(type(of: error))")
    
    if let navError = error as? NavMesh.NavMeshError {
        print("  NavMeshError: \(navError)")
        
        // Try to get more details about the error
        switch navError {
        case .wrongMagic:
            print("  → File has incorrect magic number")
        case .wrongVersion:
            print("  → File version mismatch")
        case .alloc:
            print("  → Memory allocation failed")
        case .invalidParam:
            print("  → Invalid parameter passed to Detour")
        case .bufferTooSmall:
            print("  → Buffer too small for operation")
        case .outOfNodes:
            print("  → Query ran out of nodes")
        case .partialResult:
            print("  → Query returned partial result")
        case .alreadyOccupied:
            print("  → Tile position already occupied")
        case .unknown:
            print("  → Unknown Detour error")
        }
    }
}
