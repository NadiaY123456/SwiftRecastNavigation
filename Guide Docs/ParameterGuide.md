# Recast Navigation Mesh Generation Master Guide

Recast Navigation stands as the industry's definitive navmesh generation library, powering AI navigation in Unity, Unreal Engine, and countless commercial games. This comprehensive guide covers every aspect of configuring Recast's mesh generation parameters, from basic setup to advanced optimization techniques that can make or break your game's AI performance.

## Core parameter fundamentals

Recast uses a **voxel-based rasterization process** to convert 3D geometry into navigation meshes. The system works in stages: voxelization, filtering, region partitioning, contouring, and detail mesh generation. Every parameter controls a specific aspect of this pipeline, with **cellSize and cellHeight** serving as the foundation that determines voxel resolution and affects all subsequent calculations.

The key insight is that parameters fall into two categories: **world units (wu)** like cellSize and agentRadius, and **voxel units (vx)** that are derived from world units. For example, walkableRadius equals ceil(agentRadius / cellSize), meaning your voxel resolution directly impacts how precisely agent dimensions are represented.

### Essential voxelization parameters

**cellSize** controls horizontal voxel resolution and represents the most critical parameter for balancing quality versus performance. Values typically range from 0.05 to 0.5 world units, with **0.1-0.2 recommended for indoor environments** requiring precise navigation through doorways and corridors, while **0.2-0.4 works well for outdoor terrain** where performance matters more than millimeter precision. The rule of thumb: cellSize should be ≤ agentRadius/2 to ensure adequate resolution for your character size.

**cellHeight** defines vertical voxel resolution and typically equals cellSize/2 for optimal height precision. This parameter proves critical for handling stairs, curbs, and small elevation changes. Values around 0.05-0.15 work for most scenarios, with smaller values providing better vertical accuracy at the cost of increased processing time.

### Agent dimension parameters

**agentRadius** defines your character's collision radius and determines how far walkable areas are eroded from obstacles. Set this to match your character capsule radius (typically 0.3-0.6 for human-sized agents). The system converts this to walkableRadius = ceil(agentRadius / cellSize), which is why the cellSize relationship matters so much.

**agentHeight** specifies minimum ceiling clearance, usually 1.8-2.0 units for human characters. Areas with lower ceilings become unwalkable. 

**agentMaxClimb** controls maximum step height (typically 0.5-0.9 units), allowing agents to traverse stairs and small ledges while blocking unrealistic climbing.

### Region and quality parameters

**minRegionArea** and **mergeRegionArea** work together to clean up fragmented navigation regions. minRegionArea (typically 8-64 voxel units squared) removes tiny isolated walkable areas that agents couldn't practically use, while mergeRegionArea (20-400 vx²) combines small regions with larger neighbors to reduce fragmentation in complex geometry.

**maxEdgeLen** controls polygon edge complexity, with values around 12 world units providing good balance. Smaller values create more vertices for curved surfaces but increase polygon count. Setting to 0 disables edge length limiting entirely.

## Troubleshooting common mesh generation issues

### Holes in smooth terrain

The most frequent problem occurs when **holes appear in areas that should be walkable**. This typically stems from cellSize being too large relative to terrain detail, causing the voxelization process to miss narrow walkable areas. Start by reducing cellSize by 50% and lowering minRegionArea to preserve small walkable patches.

For Unity terrain, use cellSize values of 0.1-0.2 instead of the default 0.3. Large terrains (>1000x1000 units) may need geometry scaled down 10-100x during generation to avoid floating-point precision issues.

### Missing walkable areas

When expected walkable areas don't appear in the navmesh, check agent dimension parameters first. **Increase maxSlope from 30° to 45°** for natural terrain navigation. Verify that agentRadius matches your character's actual capsule radius, and ensure maxClimb allows traversal of stairs and curbs (typically 0.9 units for standard steps).

Use debug visualization to examine slope analysis and identify areas marked as too steep or too narrow for the specified agent size.

### Over-simplified meshes

Meshes lacking sufficient detail usually result from **cellSize being too large**. Halve the cellSize to double resolution, reduce maxEdgeLength to preserve edge detail, and decrease detailSampleDistance for better height accuracy. However, remember that smaller cell sizes exponentially increase generation time - use 0.3 for prototyping but 0.1-0.2 for final detailed meshes.

## Performance versus quality optimization

The central trade-off in Recast configuration balances **generation speed, runtime performance, and mesh accuracy**. Smaller cell sizes provide better precision but exponentially increase processing time and memory usage. 

### High-performance configuration
For large outdoor areas or mobile platforms, use cellSize 0.3-0.5, cellHeight 0.15-0.25, and detailSampleDistance 12-24. This configuration prioritizes speed over precision and works well for racing games or large RTS battlefields.

### Balanced configuration  
Most games benefit from cellSize 0.2-0.3, cellHeight 0.1-0.15, with moderate detail sampling. This provides good navigation accuracy while maintaining reasonable performance for complex 3D environments.

### High-quality configuration
Indoor environments or precision platformers need cellSize 0.1-0.2, cellHeight 0.05-0.1, and detailed sampling parameters. Reserve this level of precision for critical areas or small environments where the performance cost is manageable.

## Advanced partitioning and filtering systems

### Partition style selection

Recast offers three partitioning algorithms, each with distinct advantages. 

**Watershed partitioning** produces the highest quality tessellation with well-shaped regions, making it ideal for offline generation and large open areas. However, it's the slowest method and can create holes near small obstacles.

**Monotone partitioning** generates regions in sub-millisecond timeframes, guaranteeing no holes or overlaps. Use this for runtime navmesh generation or when speed is paramount, accepting that it creates longer, thinner polygons that may cause path detours.

**Layer partitioning** provides a middle ground, offering better quality than monotone while remaining faster than watershed. It works well for medium-complexity environments where you need balanced performance.

### Essential filter operations

Enable **filterLowHangingObstacles** in environments with overhangs, bridges, or low ceilings. This prevents agents from getting stuck in areas with insufficient headroom by marking spans as unwalkable when clearance is inadequate.

**filterLedgeSpans** prevents agents from walking off edges by identifying and marking ledge spans as non-walkable. This is crucial for multi-level environments and any area with significant height variations.

**filterWalkableLowHeightSpans** ensures agents have adequate headroom by checking clearance against walkableHeight requirements. Apply these filters in order: low-hanging obstacles first, then ledge spans, finally low-height spans for optimal results.

## Platform-specific optimization strategies

### Mobile optimization
Mobile platforms require aggressive optimization due to memory and processing constraints. Use cellSize 0.3-0.5, limit agents to 50-150 maximum, and implement 15-30 Hz update frequencies. Consider single navmeshes for small levels and tiled approaches only when necessary.

### PC and console optimization
Desktop platforms can afford higher precision with cellSize 0.1-0.3 and support 200-500+ agents. Use full DetourCrowd features and 60 Hz update rates. Implement agent LOD systems where distant agents update less frequently.

### Large world streaming
Worlds exceeding 1 square kilometer require tiled navmesh approaches with streaming. Use tile sizes of 64-128 cells per side, implement predictive loading ahead of player movement, and consider hierarchical pathfinding with coarse meshes for long-distance planning.

## Implementation best practices

Start with **agent-based parameter selection** - define realistic character dimensions first, then derive other parameters. Use the relationship cellSize ≤ agentRadius/3 as your foundation, set cellHeight = cellSize/2, and calculate walkable parameters from these base values.

**Profile generation performance early** in development. A 2x increase in cellSize provides roughly 4x faster generation but significantly reduces precision. Test with realistic geometry and agent counts to understand your performance envelope.

**Implement incremental testing** by changing one parameter at a time to isolate effects. Document working configurations for different scenarios - indoor versus outdoor, different agent sizes, and various quality levels. This documentation becomes invaluable for tweaking performance during optimization phases.

## Conclusion

Mastering Recast Navigation requires understanding the interplay between voxel resolution, agent dimensions, and performance constraints. The key insight is that **cellSize and agent parameters form the foundation** - get these right first, then optimize region cleanup, edge quality, and detail sampling based on your specific requirements.

Success comes from matching parameter choices to your game's needs rather than pursuing maximum quality everywhere. A racing game needs different optimization than a tactical shooter, and mobile platforms require different trade-offs than high-end PCs. Use this guide's recommendations as starting points, then profile and adjust based on your actual performance requirements and quality standards.

Remember that Recast's power lies in its flexibility - these parameters enable fine-tuned control over every aspect of navmesh generation, allowing you to optimize for your specific use case while understanding the technical implications of each choice.
