// SPDX-License-Identifier: MIT
//
//  NavMeshBinExporter.swift
//  SwiftRecastNavigation
//

import CRecast
import Foundation

// MARK: - NavMesh Export Extension
public extension NavMesh {
    /// Exports and saves the navigation mesh to disk in binary format
    /// - Parameter url: The file URL where the navigation mesh should be saved (typically with .bin extension)
    /// - Throws: `NavMeshExportError` if export fails, or file system errors if save fails
    func save(to url: URL) throws {
        // Export the mesh to binary format
        var ptr: UnsafeMutableRawPointer?
        var size: Int32 = 0
        
        let status = bindingExportTiledNavMesh(navMesh, &ptr, &size)
        
        switch status {
        case BD_OK:
            guard let ptr = ptr else {
                throw NavMeshExportError.allocationFailed
            }
            
            // Create Data object that will free the pointer when done
            let data = Data(bytesNoCopy: ptr, count: Int(size), deallocator: .free)
            
            // Write to disk
            try data.write(to: url)
            
        case BD_ERR_INVALID_PARAM:
            throw NavMeshExportError.invalidParameters
            
        case BD_ERR_ALLOC_NAVMESH:
            throw NavMeshExportError.allocationFailed
            
        default:
            throw NavMeshExportError.exportFailed
        }
    }
    
    /// Exports the navigation mesh to Data
    /// - Returns: Binary data representing the navigation mesh
    /// - Throws: `NavMeshExportError` if export fails
    func exportToData() throws -> Data {
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
}

/* usage examples
// After building a navigation mesh
let builder = try NavMeshBuilder(vertices: vertices, triangles: triangles, config: config)
let navMesh = try builder.makeNavMesh()

// Save to disk
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let saveURL = documentsURL.appendingPathComponent("my_navmesh.bin")

try navMesh.save(to: saveURL)

// Later, load it back
let loadedNavMesh = try NavMesh(tiledContentsOf: saveURL)
 */
