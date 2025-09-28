// SPDX-License-Identifier: MIT
//
//  OBJParser.swift
//  SwiftRecastNavigation
//
//  Handles parsing and writing of Wavefront OBJ mesh files
//

import Foundation
import simd

/*
 
 // Standard writing (good for small/medium meshes)
 try OBJParser.write(vertices: verts, triangles: tris, to: url)

 // Buffered writing (better for large meshes)
 try OBJParser.writeBuffered(vertices: verts, triangles: tris, to: path)

 // Also supports UInt32 indices for compatibility
 try OBJParser.writeBuffered(vertices: verts, triangles: uint32Tr
 
 //MeshLoader Interface
 let mesh = MeshLoader(file: "terrain.obj")

 // Standard write
 try mesh.writeOBJ(to: URL(fileURLWithPath: "/path/to/output.obj"))

 // Buffered write for better performance
 try mesh.writeOBJBuffered(to: "/path/to/output.obj")
 
 */

/// Handles parsing and writing of OBJ mesh files
public enum OBJParser {
    /// Errors that can occur during OBJ file operations
    enum ParseError: Error {
        case invalidFormat
        case unsupportedFeature(String)
        
        var localizedDescription: String {
            switch self {
            case .invalidFormat:
                return "Invalid OBJ format"
            case .unsupportedFeature(let feature):
                return "Unsupported OBJ feature: \(feature)"
            }
        }
    }
    
    /// Result of parsing an OBJ file
    public struct ParseResult {
        let vertices: [SIMD3<Float>]
        let triangles: [Int32]
        let normals: [SIMD3<Float>]
    }
    
    /// Parses OBJ format text into mesh data
    static func parse(_ rawOBJ: String) throws -> ParseResult {
        var vertices: [SIMD3<Float>] = []
        var triangles: [Int32] = []
        
        let lines = rawOBJ
            .replacingOccurrences(of: "\r", with: "")
            .split(separator: "\n")
        
        for line in lines {
            switch line.first {
            case "v": // vertex
                if line.starts(with: "v ") {
                    let p = line.split(separator: " ")
                    guard p.count >= 4 else { throw ParseError.invalidFormat }
                    vertices.append([
                        Float(p[1]) ?? 0,
                        Float(p[2]) ?? 0,
                        Float(p[3]) ?? 0
                    ])
                }
            case "f": // face (as polygon or triangle fan)
                let vCount = Int32(vertices.count)
                let parts = line.split(whereSeparator: { $0.isWhitespace }).dropFirst()
                let faceIdxs = parts.map { part -> Int32 in
                    // Handle vertex/texture/normal format
                    if let slash = part.firstIndex(of: "/") {
                        return Int32(part[..<slash]) ?? 0
                    } else {
                        return Int32(part) ?? 0
                    }
                }.map { $0 < 0 ? vCount + $0 + 1 : $0 } // Handle negative indices
                
                // Convert to zero-based indices
                let zeroBasedIdxs = faceIdxs.map { $0 - 1 }
                
                // Triangulate polygon
                guard zeroBasedIdxs.count > 2 else { break }
                let a = zeroBasedIdxs[0]
                
                for i in 2..<zeroBasedIdxs.count {
                    let b = zeroBasedIdxs[i - 1]
                    let c = zeroBasedIdxs[i]
                    
                    // Validate indices
                    guard (0..<vCount).contains(a),
                          (0..<vCount).contains(b),
                          (0..<vCount).contains(c) else { continue }
                    
                    triangles.append(contentsOf: [a, b, c])
                }
            case "#": break // Comment
            case "m": break // mtllib
            case "u": break // usemtl
            case "o": break // object name
            case "g": break // group name
            case "s": break // smooth shading
            case "v":
                if line.starts(with: "vn ") || line.starts(with: "vt ") {
                    break // Skip vertex normals and texture coordinates for now
                }
            default: break
            }
        }
        
        // Generate normals from triangles
        let normals = generateNormals(vertices: vertices, triangles: triangles)
        
        return ParseResult(vertices: vertices, triangles: triangles, normals: normals)
    }
    
    /// Loads and parses an OBJ file from disk
    public static func load(from path: String) throws -> ParseResult {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(content)
    }
    
    /// Flattens an array of polygons (each with its own `vertices`)
    /// and emits them as triangles in OBJ format.
    public static func write(polygons: [NavMeshGeometry.Polygon], to url: URL) throws {
        // 1) Gather all vertices into one big buffer
        var allVertices: [SIMD3<Float>] = []
        // 2) And build a global triangle‐index list
        var allIndices: [Int32] = []

        for poly in polygons {
            let baseIndex = Int32(allVertices.count)
            allVertices += poly.vertices

            let vCount = poly.vertices.count
            // Fan‐triangulate: (0, i, i+1) for i = 1..<vCount-1
            for i in 1..<vCount - 1 {
                allIndices += [
                    baseIndex,
                    baseIndex + Int32(i),
                    baseIndex + Int32(i + 1)
                ]
            }
        }

        // Delegate to the existing write(vertices:triangles:to:)
        try write(vertices: allVertices,
                  triangles: allIndices,
                  to: url)
    }

    /// Writes mesh data to OBJ format
    public static func write(vertices: [SIMD3<Float>],
                             triangles: [Int32],
                             to url: URL) throws
    {
        var obj = ""
        
        // Write header
        obj += "# Mesh exported from SwiftRecastNavigation\n"
        obj += "# Vertices: \(vertices.count)\n"
        obj += "# Triangles: \(triangles.count / 3)\n\n"
        
        // Write vertices
        for v in vertices {
            obj += String(format: "v %.6f %.6f %.6f\n", v.x, v.y, v.z)
        }
        
        obj += "\n"
        
        // Write faces (1-indexed)
        for i in stride(from: 0, to: triangles.count, by: 3) {
            obj += "f \(triangles[i] + 1) \(triangles[i + 1] + 1) \(triangles[i + 2] + 1)\n"
        }
        
        try obj.write(to: url, atomically: true, encoding: .utf8)
    }
    
    /// Writes mesh data to OBJ format with buffered I/O for better performance
    public static func writeBuffered(vertices: [SIMD3<Float>],
                                     triangles: [Int32],
                                     to path: String,
                                     bufferSize: Int = 16 * 1024) throws
    {
        enum WriteError: Error {
            case ioError
        }
        
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw WriteError.ioError
        }
        
        defer { handle.closeFile() }
        
        try bufferedWrite(to: handle, bufferSize: bufferSize) { writer in
            // Write header
            try writer("# Mesh exported from SwiftRecastNavigation\n")
            try writer("# Vertices: \(vertices.count)\n")
            try writer("# Triangles: \(triangles.count / 3)\n\n")
            
            // Write vertices
            for vertex in vertices {
                try writer("v \(vertex.x) \(vertex.y) \(vertex.z)\n")
            }
            
            try writer("\n")
            
            // Write faces (1-indexed)
            for idx in stride(from: 0, to: triangles.count, by: 3) {
                try writer("f \(triangles[idx] + 1) \(triangles[idx + 1] + 1) \(triangles[idx + 2] + 1)\n")
            }
        }
    }
    
    /// Alternative interface supporting UInt32 indices for compatibility
    public static func writeBuffered(vertices: [SIMD3<Float>],
                                     triangles: [UInt32],
                                     to path: String,
                                     bufferSize: Int = 16 * 1024) throws
    {
        let int32Triangles = triangles.map { Int32($0) }
        try writeBuffered(vertices: vertices, triangles: int32Triangles, to: path, bufferSize: bufferSize)
    }
    
    /// Performs buffered writing to a FileHandle
    private static func bufferedWrite(to handle: FileHandle,
                                      bufferSize: Int = 16 * 1024,
                                      body: (_ writer: (String) throws -> Void) throws -> Void) throws
    {
        var buffer: [UInt8] = []
        buffer.reserveCapacity(bufferSize)
        
        func writeFunc(_ s: String) throws {
            buffer.append(contentsOf: s.utf8)
            if buffer.count >= bufferSize {
                try handle.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        
        try body(writeFunc)
        
        // Write any remaining buffer content
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
    }
    
    /// Generates per-triangle normals from vertices and triangles
    private static func generateNormals(vertices: [SIMD3<Float>], triangles: [Int32]) -> [SIMD3<Float>] {
        var normals: [SIMD3<Float>] = []
        
        for i in stride(from: 0, to: triangles.count, by: 3) {
            let v0 = triangles[i]
            let v1 = triangles[i + 1]
            let v2 = triangles[i + 2]
            
            // Validate indices
            guard v0 >= 0, v0 < vertices.count,
                  v1 >= 0, v1 < vertices.count,
                  v2 >= 0, v2 < vertices.count
            else {
                normals.append([0, 1, 0]) // Default up normal
                continue
            }
            
            // Calculate normal using cross product
            let e0 = vertices[Int(v1)] - vertices[Int(v0)]
            let e1 = vertices[Int(v2)] - vertices[Int(v0)]
            let n = cross(e0, e1)
            let len = simd_length(n)
            normals.append(len > 0 ? n / len : [0, 1, 0])
        }
        
        return normals
    }
}
