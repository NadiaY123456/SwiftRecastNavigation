# SwiftRecastNavigation

Swift-first bindings for Recast & Detour navigation mesh generation and pathfinding on Apple platforms.

## What is it for?
When you play a game, it feels obvious that characters know where they can walk and how to get from A to B, but making that happen is hard. Without a reliable system, developers would have to hand‑place routes and write fragile rules that could break with a level change. SwiftRecastNavigation fixes this by automatically building a “walkable map” of the world and using it to choose reasonable routes around walls, ledges, and tight spaces. It also keeps characters from bumping into each other and allows designers to input information such as “roads are faster than grass” or “avoid water.” In short, it turns believable movement into a built‑in service for Apple apps, saving time while making characters look like they understand the world.

## About

SwiftRecastNavigation brings the industry-standard Recast & Detour navigation libraries to Swift with a clean, modern API. Built upon Miguel de Icaza's SwiftNavigation foundation, this framework helps you generate navigation meshes, find paths, simulate crowds, and handle complex terrain without touching C++.

There’s also an open‑source companion app, SwiftRecastDemo (macOS), that uses this library end‑to‑end. It’s both a reference implementation and an offline navmesh tool: load terrain (USDZ/USD/OBJ), apply “splat” area masks, tune agent/world parameters, preview the mesh, run path tests, and export ready‑to‑ship files (`.bin`, `.obj`, `.usda`) you can load at runtime if you don’t need on‑device generation. Repo: TO ADD


The framework includes pathfinding, crowd simulation with avoidance, RealityKit integration for spatial computing, and a "splat painting" system that ingests textures with painted navigation areas (roads, water, grass) to automatically generate area-coded geometry that affects pathfinding costs and behavior.

Not included: off-mesh connections authoring, dynamic obstacles with DetourTileCache, some advanced Detour queries like raycast and distance-to-wall, and per-tile runtime rebuilding.

## What Makes This Different?

It's Swift-first. Unlike other Recast wrappers, it’s not a thin binding over C++. We've built a Swift API that uses Swift's type system, error handling, and modern features.

Core navigation features. Includes pathfinding, crowd simulation, and area painting integration for common navigation use cases.

RealityKit ready. If you're building for Apple's spatial platforms, the RealityKit integration means navigation works with your existing scene setup.


## Supported Platforms

iOS 17.0+ macOS 14.0+ visionOS 1.0+

## Installation

### Swift Package Manager

Swift Package Manager is integrated into Xcode and the Swift compiler. Just add SwiftRecastNavigation to your dependencies:

Xcode: File → Add Package Dependencies… and paste the repository URL

Package.swift:
```swift
dependencies: [
    .package(url: "https://github.com/<you>/SwiftRecastNavigation.git", from: "0.1.0")
]
```

#### Enable Swift C++ Interoperability (required)

SwiftRecastNavigation itself is compiled with Swift’s C++ interoperability enabled. To import it from your app or test targets, enable C++ interop on those targets too—otherwise you’ll see:

> `Module 'SwiftRecastNavigation' was built with C++ interoperability enabled, but current compilation does not enable C++ interoperability.`

**Xcode (recommended)**  
1. Select your App (and any Unit/UI Test) target → Build Settings.  
2. Search for “C++ and Objective‑C Interoperability”.  
3. Change from C/Objective‑C → C++/Objective‑C++.  
4. Clean Build Folder (Shift‑Cmd‑K) and build.

**Alternative: Other Swift Flags**  
Build Settings → Swift Compiler – Custom Flags → Other Swift Flags, add:
-cxx-interoperability-mode=default

## Features

### Navigation Mesh Building
Tiled navmesh generation with multiple partitioning styles (watershed, monotone, layer) Custom area marking for different terrain types (roads, water, grass) that affect pathfinding Smart filtering that handles low obstacles, ledges, and tight spaces based on your agent size Binary export/import for saving and loading pre-built navigation meshes

### Pathfinding & Queries
Simple path finding with a single findPath(from:to:) call Advanced queries like finding nearby polygons, checking visibility, getting wall segments Area-based queries for finding all navigable space within bounds or radius Per-polygon metadata access for custom game logic

### Crowd Simulation
Full crowd system with collision avoidance between agents Configurable agent behaviors with presets for pushiness, quality, and avoidance styles Real-time updates that work with your game loop RealityKit integration via AgentComponent and CrowdSystem for automatic entity movement

### Area Painting Integration
Ingests pre-painted textures where designers have marked navigation areas (roads, water, grass) Automatic mesh generation from painted areas with smart simplification Height mapping onto terrain for 3D navigation meshes Per-area costs - make roads faster to traverse than grass, avoid water, etc.

### Import/Export Tools
Binary format for efficient storage and loading of navigation meshes Zero-copy loading with memory mapping for large meshes USD ASCII export for visualization in other tools OBJ export with color-coded areas for debugging Debug utilities for inspecting and validating mesh files

## Usage

Here are examples showing how to build a navigation mesh, find paths, and save/load meshes:

### Building a Navigation Mesh

```swift
import SwiftRecastNavigation

// Your level geometry
let vertices: [SIMD3<Float>] = /* your mesh vertices */
let triangles: [Int32] = /* triangle indices (3 per triangle) */

// Configure for your game's scale and agent size
var config = NavMeshConfig()
config.cellSize = 0.2        // Voxel size for rasterization
config.cellHeight = 0.1      // Vertical voxel size
config.agentRadius = 0.6     // How wide your characters are
config.agentHeight = 2.0     // How tall your characters are
config.partitionStyle = .watershed  // Best general-purpose option

// Build the navigation mesh
let builder = try NavMeshBuilder(vertices: vertices, triangles: triangles, config: config)
let navMesh = try builder.makeNavMesh()
```

### Finding Paths

```swift
// Create a query object (you can reuse this)
let query = try navMesh.makeQuery()

// Find a path - it's that simple!
let waypoints = try query.findPath(from: [0, 0, 0], to: [10, 0, 10])

// The waypoints are ready to use for moving your character
for point in waypoints {
    print("Move to: \(point)")
}
```

### Working with RealityKit

```swift
import RealityKit

// Build directly from a RealityKit model
let builder = try NavMeshBuilder(model: myModelComponent)
let navMesh = try builder.makeNavMesh()

// Visualize the navigation mesh
let meshResource = try navMesh.getAllTilesMeshResource()
let debugEntity = ModelEntity(mesh: meshResource)
scene.addChild(debugEntity)

// Set up crowd simulation with automatic entity movement
CrowdSystem.registerSystem()        // Call once at startup
AgentComponent.registerComponent()  // Call once at startup

// Create a crowd and add agents
let crowd = try navMesh.makeCrowd(maxAgents: 64, agentRadius: 0.6)
let agent = crowd.addAgent(at: startPosition)

// The CrowdSystem will automatically update entity positions each frame!
```

### Using Area Painting

```swift
// Ingest designer-painted navigation areas from a texture
let generator = SplatMeshGenerator(maxEdgeLength: 6, channel: .grayscale)
let areaMesh = try await generator.mesh(from: paintedImage)

// Map the painted areas onto your terrain
let overlay = MeshLoader(splatMesh2D: areaMesh, terrainModel: terrainEntity)

// Configure how different colors affect navigation
let filter = NavQueryFilter()
filter.configure(with: [
    SplatAreaConfig(
        splatName: "roads",
        channelConfigs: [.init(channel: .red, areaCode: 2, cost: 0.5)]  // Roads are fast
    ),
    SplatAreaConfig(
        splatName: "water", 
        channelConfigs: [.init(channel: .blue, areaCode: 3, cost: 10.0)] // Water is slow
    )
])
```

### Saving and Loading

```swift
// Save your navigation mesh to disk
try navMesh.save(to: URL(fileURLWithPath: "level1.navmesh"))

// Load it later (uses zero-copy memory mapping for efficiency)
let loadedMesh = try NavMesh(tiledContentsOf: URL(fileURLWithPath: "level1.navmesh"))
```
#### Loading a navmesh exported by the companion app

If you exported `all_tiles_navmesh.bin` from SwiftRecastDemo, you can load it directly:

```swift
// Add all_tiles_navmesh.bin to your app bundle (or provide a file URL you manage)
let url = Bundle.main.url(forResource: "all_tiles_navmesh", withExtension: "bin")!
let navMesh = try NavMesh(tiledContentsOf: url, zeroCopy: true) // memory-mapped for fast loads
let query = try navMesh.makeQuery()
// …use `query` for findPath, straight paths, etc.
```

## Companion Example App (SwiftRecastDemo)

**What it does**

- Interactive viewport (RealityKit) with orbit/pan/zoom camera controls and overlay UI. 
- Load terrain from USDZ/USD/OBJ and import PNG splat masks (multi‑select). 
- Tune navmesh parameters (agent radius/height/slope/climb, cell size/height, tile size, region areas) and per‑channel splat generation parameters (threshold, max edge length, simplification, morphology, interior spacing).
- Generate & visualize the navmesh (area‑tinted polygons, optional edges/tile grouping), and run path tests (random start/end, straight‑path waypoints). 
- Export the result to `all_tiles_navmesh.bin`, `swiftNavMesh.obj`, and `navmesh(.tiled).usda` in a user‑selected folder; the app remembers your export directory. 
- Save/Load presets for navmesh and splat parameters to JSON for repeatable builds.

**Why it's useful**

- Serves as a working reference for how to wire the library into a SwiftUI/RealityKit app (navmesh build, query setup, visualization, path display).
- Provides a backend/offline step: prebuild navmeshes once on desktop and ship the `.bin` with your app when runtime generation isn't needed.

**Get started**

1. Clone SwiftRecastDemo and open in Xcode (macOS 14+, Xcode 15+). Build & run the SwiftRecastDemo target.
2. In NavMesh tab: *Select Export Directory* → *Choose Terrain…* (USDZ/USD/OBJ) → optionally *Choose Splats…* (PNGs) → adjust parameters → Generate NavMesh.
3. Exports appear in your chosen folder:  
   - `all_tiles_navmesh.bin` (Detour tiled binary, zero‑copy mappable),  
   - `swiftNavMesh.obj` (debug/visualization),  
   - `navmesh.usda` and `navmesh_tiled.usda` (USD ASCII). 

> Repo: TO_ADD

## API Quick Reference

> SwiftRecastNavigation exposes a small, Swift‑first surface area on top of Recast/Detour.  
> This is a quick index of public types and their most useful functions.

### NavMeshBuilder (build)

```swift
// Create from raw triangle mesh (Float or SIMD3)
init(vertices: [Float], triangles: [Int32], config: NavMeshConfig = NavMeshConfig(), areas: [AreaDefinition] = []) throws
init(vertices: [SIMD3<Float>], triangles: [Int32], config: NavMeshConfig = NavMeshConfig(), areas: [AreaDefinition] = []) throws

// RealityKit source mesh
init(model: ModelComponent, config: NavMeshConfig = NavMeshConfig()) throws

// Build & export
func makeNavMesh() throws -> NavMesh
func exportToData() throws -> Data

// Tile helpers
func getTilePosition(for worldPos: SIMD3<Float>) -> (x: Int32, y: Int32)?
func getTileBounds(tileX: Int32, tileY: Int32) -> (min: SIMD3<Float>, max: SIMD3<Float>)?

// RealityKit debug visualization
func getTileMeshResource(tileX: Int32, tileY: Int32) throws -> MeshResource?
func getAllTilesMeshResource() throws -> MeshResource?
```

### NavMesh (use, save/load, crowd)

```swift
// Load/save
convenience init(tiledContentsOf url: URL, zeroCopy: Bool = false) throws
func save(to url: URL) throws
func exportToData() throws -> Data

// Queries & crowd
func makeQuery(maxNodes: Int = 2048) throws -> NavMeshQuery
func makeCrowd(maxAgents: Int, agentRadius: Float) throws -> Crowd

// Geometry extraction (for visualization/export)
func extractGeometry(verbose: Bool = false) -> NavMeshGeometry

// Tile info (introspection)
func getTileStateAt(_ tileIndex: Int32, _ tx: inout Int32, _ ty: inout Int32, _ tlayer: inout Int32)
func getTileCoordinates(at tileIndex: Int) -> (x: Int32, y: Int32, layer: Int32)?
```


### NavMeshQuery (pathfinding & spatial queries)

```swift
// Convenience: one‑shot path that string‑pulls to waypoints
func findPath(from: SIMD3<Float>, to: SIMD3<Float>, filter: NavQueryFilter? = nil) throws -> [SIMD3<Float>]

// Low‑level corridor + straight path (Detour)
func findPathCorridor(filter: NavQueryFilter?, start: PointInPoly, end: PointInPoly, maxPaths: Int = 256) -> Result<[dtPolyRef], NavMesh.NavMeshError>
func findStraightPath(filter: NavQueryFilter?, startPos: SIMD3<Float>, endPos: SIMD3<Float>, pathCorridor: [dtPolyRef], maxPaths: Int = 256, options: Int32 = 0) -> Result<([SIMD3<Float>], [Int32], [dtPolyRef]), NavMesh.NavMeshError>

// Nearest, random, clamp helpers (selected)
func findNearestPoint(point: SIMD3<Float>, halfExtents: SIMD3<Float>, filter: NavQueryFilter? = nil) -> Result<PointInPoly, NavMesh.NavMeshError>
func findRandomPoint(filter: NavQueryFilter? = nil) -> Result<PointInPoly, NavMesh.NavMeshError>

// Spatial queries
func findPolysWithinRange(center: PointInPoly, radius: Float, filter: NavQueryFilter? = nil, maxPolys: Int = 256) -> Result<[dtPolyRef], NavMesh.NavMeshError>
func findPolysWithinRangeWithCosts(center: PointInPoly, radius: Float, filter: NavQueryFilter? = nil, maxPolys: Int = 256) -> Result<(polyRefs: [dtPolyRef], parentRefs: [dtPolyRef], costs: [Float]), NavMesh.NavMeshError>
func findPolysInTile(tileX: Int, tileY: Int, layer: Int = 0) -> [dtPolyRef]

// Walls & polygon metadata
struct WallSegment { let start: SIMD3<Float>; let end: SIMD3<Float>; var length: Float; var direction: SIMD3<Float> }
func getPolyWallSegments(_ poly: dtPolyRef) -> [WallSegment]
struct PolyInfo { let polyRef: dtPolyRef; let vertices: [SIMD3<Float>]; let neighbors: [dtPolyRef]; let flags: UInt16; let area: UInt8; var center: SIMD3<Float> }
func getPolyInfo(_ poly: dtPolyRef) -> PolyInfo?
```

Sources: one‑shot `findPath`, corridor/straight path, within‑range (+costs), per‑tile, walls, metadata.

---

### NavQueryFilter (costs & exclusions)

```swift
init()
var includeFlags: UInt16 { get set }
var excludeFlags: UInt16 { get set }
func setAreaCost(_ idx: Int32, cost: Float)
func getAreaCost(_ idx: Int32) -> Float

// Helper for splat‑area configs: sets per‑area costs and exclusions in one go
func configure(with areaConfigs: [SplatAreaConfig])
```

### Crowd & CrowdAgent (DetourCrowd)

```swift
// Create a crowd from a NavMesh
// (see NavMesh.makeCrowd above)

// Manage avoidance presets shared by agents
func setObstacleAvoidance(idx: Int, config: Crowd.ObstacleAvoidanceConfig)
func getObstacleAvoidance(idx: Int) throws -> Crowd.ObstacleAvoidanceConfig

// Agents
func addAgent(_ position: SIMD3<Float>, radius: Float = 0.6, height: Float = 2.0, maxAcceleration: Float = 8, maxSpeed: Float = 3.5, collisionQueryRange: Float? = nil, pathOptimizationRange: Float? = nil, updateFlags: CrowdAgent.UpdateFlags = [], obstableAvoidanceType: UInt8 = 3, queryFilterIndex: UInt8 = 0, separationWeight: Float = 2) -> CrowdAgent?
func addAgent(_ position: SIMD3<Float>, params: CrowdAgent.Params) -> CrowdAgent?
func remove(agent: CrowdAgent)
func update(time: Float)

// CrowdAgent controls
@discardableResult func requestMove(target: PointInPoly) -> Bool
@discardableResult func requestMove(velocity: SIMD3<Float>) -> Bool
@discardableResult func resetMove() -> Bool
var position: SIMD3<Float> { get }
var velocity: SIMD3<Float> { get }

// Presets
func set(navigationQuality: CrowdAgent.NavigationQuality)
func set(navigationPushiness: CrowdAgent.NavigationPushiness)

// Per‑agent parameters & flags (editable via properties)
struct CrowdAgent.Params { /* radius, height, maxAcceleration, maxSpeed, collisionQueryRange, pathOptimizationRange, separationWeight, updateFlags, obstacleAvoidanceType, queryFilterType, userData */ }
struct CrowdAgent.UpdateFlags: OptionSet { /* anticipateTurns, obstacleAvoidance, separation, optimizeVisibility, optimizeTopology */ }
```


### RealityKit Integration

```swift
// Attach a nav agent to an Entity and auto‑update per frame
struct AgentComponent: Component  // AgentComponent.registerComponent()
final class CrowdSystem: System   // CrowdSystem.registerSystem()
```

### NavMeshGeometry + Exporters (debug/interop)

```swift
// Snapshot Detour mesh for tooling/visualization (see NavMesh.extractGeometry)
struct NavMeshGeometry {
    struct Polygon { let ref: dtPolyRef; let vertices: [SIMD3<Float>]; let neighbours: [dtPolyRef]; let area: UInt8; let flags: UInt16; let type: UInt8; let tileX: Int32; let tileY: Int32; let tileIndex: Int }
    struct TileInfo { let index: Int; let x: Int32; let y: Int32; let bounds: (min: SIMD3<Float>, max: SIMD3<Float>); let polyCount: Int; let vertCount: Int }
}

// USD ASCII (USDA)
extension NavMeshGeometry {
    func exportToUSDA(filePath: String) throws
    func exportToUSDATiled(filePath: String) throws
}

// OBJ helpers (via OBJParser/MeshLoader)
enum OBJParser { /* write(...), writeBuffered(...), etc. */ }
final class MeshLoader {
    public convenience init(file: String) throws
    public convenience init(splatMesh2D: MeshResult2D, terrainModel: ModelEntity, debugPrint: Bool = false)
    // plus writeOBJ(...) helpers (see source)
}
```

### Splat Pipeline (designer‑painted areas → costs/exclusions)

```swift
struct SplatMeshGenerator {
    enum Channel { case red, green, blue, alpha, grayscale }
    init(maxEdgeLength: CGFloat, simplificationTolerance: CGFloat = 0.005, threshold: Float? = nil, channel: Channel = .grayscale, invertMask: Bool? = nil, morphologyRadius: Int = 2, interiorSpacingFactor: CGFloat = 0.8, debugPrint: Bool = false)

    // Image→mesh (platform convenience)
    func mesh(from image: NSImage,  debugURL: URL? = nil) async throws -> MeshResult2D   // macOS
    func mesh(from image: UIImage,  debugURL: URL? = nil) async throws -> MeshResult2D   // iOS/visionOS
}

struct SplatAreaConfig {
    struct ChannelConfig {
        init(channel: SplatMeshGenerator.Channel, areaCode: UInt8, cost: Float = 1.0, exclude: Bool = false)
    }
    init(splatName: String, channelConfigs: [ChannelConfig])
}
```

## Documentation

### Parameter Tuning Guide 
See Guide Docs/ParameterGuide.md for detailed explanations of all navmesh generation parameters 

### Splat System Guide
See Guide Docs/SplatMeshGeneratorParams.md for the area painting pipeline API Documentation: 

Browse the source files - they're extensively documented with usage examples

## Under the Hood

This package wraps the battle-tested Recast & Detour libraries (used in everything from Unreal Engine to League of Legends) with additional features: iTriangle for robust triangulation in the splat system Simplify-Swift for polygon simplification (ported from Leaflet's simplification algorithms) Custom Swift implementations for RealityKit bridging and file I/O

## Credits

SwiftRecastNavigation started as an expansion of SwiftNavigation by Miguel de Icaza (which included RealityKit integration) and has been substantially enhanced with expanded Recast/Detour functionality coverage and the splat painting system.

Special thanks to: Miguel de Icaza for the initial Swift navigation work and RealityKit integration The Recast & Detour team for their incredible navigation libraries Vladimir Agafonkin for the simplification algorithms

## License

SwiftRecastNavigation is released under the MIT license. See LICENSE for details and THIRD-PARTY-NOTICES.md for dependency licenses.
