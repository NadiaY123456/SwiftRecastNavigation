// SPDX-License-Identifier: MIT
//
//  ExportUSDA.swift
//  SwiftRecastNavigation
//
//  Created by Nadia Yilmaz on 6/24/25.
//

import Foundation
import simd

extension NavMeshGeometry {
    /// Export the navigation mesh geometry to a USDA file with colored polygons by area code
    public func exportToUSDA(filePath: String) throws {
        var usdContent = ""
        
        // USDA header
        usdContent += """
        #usda 1.0
        (
            defaultPrim = "NavMesh"
            metersPerUnit = 1
            upAxis = "Y"
        )
        
        def Xform "NavMesh" (
            kind = "assembly"
        )
        {
        """
        
        // Collect unique area codes
        let uniqueAreaCodes = Set(polygons.map { $0.area }).sorted()
        
        // Create materials for each area code
        usdContent += "\n    def Scope \"Materials\"\n    {\n"
        
        for areaCode in uniqueAreaCodes {
            let color = colorForAreaCode(areaCode)
            usdContent += """
            
                def Material "AreaMaterial_\(areaCode)"
                {
                    token outputs:surface.connect = </NavMesh/Materials/AreaMaterial_\(areaCode)/PbrShader.outputs:surface>
                    
                    def Shader "PbrShader"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (\(color.r), \(color.g), \(color.b))
                        float inputs:metallic = 0
                        float inputs:roughness = 0.5
                        token outputs:surface
                    }
                }
            
            """
        }
        
        usdContent += "    }\n\n"
        
        // Create geometry scope
        usdContent += "    def Scope \"Geometry\"\n    {\n"
        
        // Export each polygon as a separate mesh
        for (index, polygon) in polygons.enumerated() {
            usdContent += exportPolygonToUSD(polygon, index: index)
        }
        
        usdContent += "    }\n}\n"
        
        // Write to file
        try usdContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
    
    private func exportPolygonToUSD(_ polygon: Polygon, index: Int) -> String {
        let meshName = "Polygon_\(index)"
        var usd = """
        
                def Mesh "\(meshName)"
                {
                    float3[] extent = [\(formatExtent(polygon.vertices))]
                    point3f[] points = [
        """
        
        // Add vertices
        for (i, vertex) in polygon.vertices.enumerated() {
            if i > 0 { usd += "," }
            usd += "\n                        (\(vertex.x), \(vertex.y), \(vertex.z))"
        }
        usd += "\n                    ]\n"
        
        // Face vertex count - just one face with all vertices
        usd += "                    int[] faceVertexCounts = [\(polygon.vertices.count)]\n"
        
        // Face vertex indices - just sequential indices for the polygon
        let indices = Array(0..<polygon.vertices.count)
        usd += "                    int[] faceVertexIndices = ["
        usd += indices.map { String($0) }.joined(separator: ", ")
        usd += "]\n"
        
        // Normals (compute a simple face normal)
        let normal = computePolygonNormal(polygon.vertices)
        usd += """
                            normal3f[] normals = [(\(normal.x), \(normal.y), \(normal.z))] (
                                interpolation = "constant"
                            )
                            
                            # Bind material for area code \(polygon.area)
                            rel material:binding = </NavMesh/Materials/AreaMaterial_\(polygon.area)>
                            
                            # Store metadata
                            uint polyRef = \(polygon.ref)
                            uint8 areaCode = \(polygon.area)
                            int tileX = \(polygon.tileX)
                            int tileY = \(polygon.tileY)
                        }
                    
                    """
        
        return usd
    }
    
    private func computePolygonNormal(_ vertices: [SIMD3<Float>]) -> SIMD3<Float> {
        guard vertices.count >= 3 else { return SIMD3<Float>(0, 1, 0) }
        
        // Use first three vertices to compute normal
        let v0 = vertices[0]
        let v1 = vertices[1]
        let v2 = vertices[2]
        
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let normal = normalize(cross(edge1, edge2))
        
        return normal
    }
    
    private func formatExtent(_ vertices: [SIMD3<Float>]) -> String {
        var minBound = vertices[0]
        var maxBound = vertices[0]
        
        for vertex in vertices {
            minBound = min(minBound, vertex)
            maxBound = max(maxBound, vertex)
        }
        
        return "(\(minBound.x), \(minBound.y), \(minBound.z)), (\(maxBound.x), \(maxBound.y), \(maxBound.z))"
    }
    
    private func colorForAreaCode(_ areaCode: UInt8) -> (r: Float, g: Float, b: Float) {
        // Generate distinct colors for different area codes
        switch areaCode {
        case 63:  // RC_WALKABLE_AREA
            return (0.0, 0.7, 0.0)  // Green
        case 0:  // RC_NULL_AREA (unwalkable)
            return (0.8, 0.0, 0.0)  // Red
        case 1:
            return (0.0, 0.0, 0.8)  // Blue
        case 2:
            return (0.8, 0.8, 0.0)  // Yellow
        case 3:
            return (0.8, 0.0, 0.8)  // Magenta
        case 4:
            return (0.0, 0.8, 0.8)  // Cyan
        case 5:
            return (0.8, 0.4, 0.0)  // Orange
        case 6:
            return (0.4, 0.0, 0.8)  // Purple
        case 7:
            return (0.5, 0.5, 0.5)  // Gray
        default:
            // Generate a color based on the area code
            let hue = Float(areaCode) / 64.0 // Assuming max 64 area types
            return hsvToRgb(h: hue * 360.0, s: 0.7, v: 0.8)
        }
    }
    
    private func hsvToRgb(h: Float, s: Float, v: Float) -> (r: Float, g: Float, b: Float) {
        let c = v * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        
        if h < 60 {
            r = c; g = x; b = 0
        } else if h < 120 {
            r = x; g = c; b = 0
        } else if h < 180 {
            r = 0; g = c; b = x
        } else if h < 240 {
            r = 0; g = x; b = c
        } else if h < 300 {
            r = x; g = 0; b = c
        } else {
            r = c; g = 0; b = x
        }
        
        return (r + m, g + m, b + m)
    }
}

// Extension to export with tile-based organization
extension NavMeshGeometry {
    /// Export navigation mesh organized by tiles
    public func exportToUSDATiled(filePath: String) throws {
        var usdContent = ""
        
        // USDA header
        usdContent += """
        #usda 1.0
        (
            defaultPrim = "NavMesh"
            metersPerUnit = 1
            upAxis = "Y"
        )
        
        def Xform "NavMesh" (
            kind = "assembly"
        )
        {
        """
        
        // Collect unique area codes
        let uniqueAreaCodes = Set(polygons.map { $0.area }).sorted()
        
        // Create materials
        usdContent += "\n    def Scope \"Materials\"\n    {\n"
        for areaCode in uniqueAreaCodes {
            let color = colorForAreaCode(areaCode)
            usdContent += """
            
                def Material "AreaMaterial_\(areaCode)"
                {
                    token outputs:surface.connect = </NavMesh/Materials/AreaMaterial_\(areaCode)/PbrShader.outputs:surface>
                    
                    def Shader "PbrShader"
                    {
                        uniform token info:id = "UsdPreviewSurface"
                        color3f inputs:diffuseColor = (\(color.r), \(color.g), \(color.b))
                        float inputs:metallic = 0
                        float inputs:roughness = 0.5
                        token outputs:surface
                    }
                }
            
            """
        }
        usdContent += "    }\n\n"
        
        // Organize by tiles
        usdContent += "    def Scope \"Tiles\"\n    {\n"
        
        for tile in tiles {
            let tilePolygons = polygons(forTileIndex: tile.index)
            if !tilePolygons.isEmpty {
                usdContent += """
                
                        def Xform "Tile_\(tile.x)_\(tile.y)" (
                            customData = {
                                int tileX = \(tile.x)
                                int tileY = \(tile.y)
                                int polyCount = \(tilePolygons.count)
                            }
                        )
                        {
                
                """
                
                for (polyIndex, polygon) in tilePolygons.enumerated() {
                    usdContent += exportPolygonToUSDIndented(polygon,
                                                            index: polyIndex,
                                                            globalIndex: polygons.firstIndex(where: { $0.ref == polygon.ref })!,
                                                            indent: "            ")
                }
                
                usdContent += "        }\n"
            }
        }
        
        usdContent += "    }\n}\n"
        
        try usdContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }
    
    private func exportPolygonToUSDIndented(_ polygon: Polygon, index: Int, globalIndex: Int, indent: String) -> String {
        let meshName = "Polygon_\(globalIndex)"
        var usd = """
        
        \(indent)def Mesh "\(meshName)"
        \(indent){
        \(indent)    point3f[] points = [
        """
        
        // Add vertices
        for (i, vertex) in polygon.vertices.enumerated() {
            if i > 0 { usd += "," }
            usd += "\n\(indent)        (\(vertex.x), \(vertex.y), \(vertex.z))"
        }
        usd += "\n\(indent)    ]\n"
        
        // Face vertex count - just one face with all vertices
        usd += "\(indent)    int[] faceVertexCounts = [\(polygon.vertices.count)]\n"
        
        // Face vertex indices - sequential for the polygon
        let indices = Array(0..<polygon.vertices.count)
        usd += "\(indent)    int[] faceVertexIndices = ["
        usd += indices.map { String($0) }.joined(separator: ", ")
        usd += "]\n"
        
        // Material binding and metadata
        usd += """
        \(indent)    
        \(indent)    rel material:binding = </NavMesh/Materials/AreaMaterial_\(polygon.area)>
        \(indent)    
        \(indent)    uint polyRef = \(polygon.ref)
        \(indent)    uint8 areaCode = \(polygon.area)
        \(indent)}
        
        """
        
        return usd
    }
}

// Usage example:
/*
let geometry = navMesh.extractGeometry(verbose: true)

// Export flat structure
try geometry.exportToUSDA(filePath: "/path/to/navmesh.usda")

// Or export with tile organization
try geometry.exportToUSDATiled(filePath: "/path/to/navmesh_tiled.usda")
*/
