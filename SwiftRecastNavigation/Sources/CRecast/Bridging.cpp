// Bridging.cpp
// Tiled navigation mesh generation

// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Nadia Yilmaz

#include "Bridging.h"
#include "Recast.h"
#include "RecastAlloc.h"
#include "RecastAssert.h"
#include "DetourNavMeshBuilder.h"
#include "DetourNavMesh.h"

#include <math.h>
#include <string.h>
#include <stdio.h>
#include <float.h>
#include <stdlib.h>

// Helper functions
static inline unsigned int nextPow2(unsigned int v)
{
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
}

static inline unsigned int ilog2(unsigned int v)
{
    unsigned int r;
    unsigned int shift;
    r = (v > 0xffff) << 4; v >>= r;
    shift = (v > 0xff) << 3; v >>= shift; r |= shift;
    shift = (v > 0xf) << 2; v >>= shift; r |= shift;
    shift = (v > 0x3) << 1; v >>= shift; r |= shift;
    r |= (v >> 1);
    return r;
}

// Structure to hold area marking data
struct AreaMarkingData {
    const float* verts;
    int nverts;
    const int* tris;
    int ntris;
    unsigned char areaCode;
};

// Mark areas from triangle mesh data
static void markAreasFromMesh(rcContext* ctx, rcCompactHeightfield& chf,
                              const AreaMarkingData* areas, int numAreas)
{
    if (!areas || numAreas <= 0) return;
    
    // Calculate the Y range of the heightfield for better tolerance
    float hfMinY = chf.bmin[1];
    float hfMaxY = chf.bmax[1];
    float hfYRange = hfMaxY - hfMinY;
    
    for (int i = 0; i < numAreas; ++i) {
        const AreaMarkingData& area = areas[i];
        if (!area.verts || !area.tris || area.nverts == 0 || area.ntris == 0) continue;
        
        ctx->log(RC_LOG_PROGRESS, "Marking area %d with code %d (%d triangles)",
                 i, area.areaCode, area.ntris);
        
        // Process each triangle as a convex polygon
        int markedCount = 0;
        for (int j = 0; j < area.ntris; ++j) {
            const int* tri = &area.tris[j * 3];
            
            // Get triangle vertices
            float triVerts[9];
            for (int k = 0; k < 3; ++k) {
                triVerts[k*3 + 0] = area.verts[tri[k]*3 + 0];
                triVerts[k*3 + 1] = area.verts[tri[k]*3 + 1];
                triVerts[k*3 + 2] = area.verts[tri[k]*3 + 2];
            }
            
            // Calculate height bounds
            float hmin = triVerts[1];
            float hmax = triVerts[1];
            for (int k = 1; k < 3; ++k) {
                hmin = rcMin(hmin, triVerts[k*3 + 1]);
                hmax = rcMax(hmax, triVerts[k*3 + 1]);
            }
            
            // Use adaptive tolerance based on the heightfield's Y range and position
            // For high Y values, we need more tolerance
            float baseTolerance = chf.ch * 10.0f;
            float rangeTolerance = hfYRange * 0.05f; // 5% of Y range
            float positionTolerance = rcAbs(hfMinY) * 0.001f; // 0.1% of absolute Y position
            
            float tolerance = rcMax(baseTolerance, rcMax(rangeTolerance, positionTolerance));
            
            // Also ensure minimum tolerance for very high Y values
            if (hfMinY > 100.0f) {
                tolerance = rcMax(tolerance, 1.0f); // At least 1 unit tolerance for high terrains
            }
            
            hmin -= tolerance;
            hmax += tolerance;
            
            ctx->log(RC_LOG_PROGRESS, "Triangle %d: Y range [%.2f, %.2f], tolerance: %.2f",
                     j, hmin, hmax, tolerance);
            
            // Mark the triangle area
            rcMarkConvexPolyArea(ctx,
                                 triVerts, 3,
                                 hmin, hmax,
                                 area.areaCode, chf);
            ++markedCount;
        }
        
        ctx->log(RC_LOG_PROGRESS, "Marked %d/%d triangles for area %d",
                 markedCount, area.ntris, i);
    }
}

// Build a single tile
static unsigned char* buildTileMesh(int tx, int ty,
                                   const float* bmin, const float* bmax,
                                   int& dataSize,
                                   rcConfig* cfg,
                                   const TileConfig* tileConfig,
                                   int flags,
                                   const float* verts, int nverts,
                                   const int* tris, int ntris,
                                   const AreaMarkingData* areas,
                                   int numAreas,
                                   float agentHeight,
                                   float agentRadius,
                                   float agentMaxClimb,
                                   rcContext* ctx)
{
    dataSize = 0;
    
    // Expand bounds by border size
    float tileBmin[3], tileBmax[3];
    rcVcopy(tileBmin, bmin);
    rcVcopy(tileBmax, bmax);
    tileBmin[0] -= cfg->borderSize * cfg->cs;
    tileBmin[2] -= cfg->borderSize * cfg->cs;
    tileBmax[0] += cfg->borderSize * cfg->cs;
    tileBmax[2] += cfg->borderSize * cfg->cs;
    
    // Update config for this tile
    rcConfig tileCfg = *cfg;
    rcVcopy(tileCfg.bmin, tileBmin);
    rcVcopy(tileCfg.bmax, tileBmax);
    tileCfg.width = tileConfig->tileSize + tileCfg.borderSize * 2;
    tileCfg.height = tileConfig->tileSize + tileCfg.borderSize * 2;
    
    ctx->log(RC_LOG_PROGRESS, "Building tile (%d,%d) bounds: (%.2f,%.2f,%.2f) to (%.2f,%.2f,%.2f)",
             tx, ty, tileBmin[0], tileBmin[1], tileBmin[2], tileBmax[0], tileBmax[1], tileBmax[2]);
    
    // Build heightfield
    rcHeightfield* solid = rcAllocHeightfield();
    if (!solid) return nullptr;
    
    if (!rcCreateHeightfield(ctx, *solid, tileCfg.width, tileCfg.height,
                            tileCfg.bmin, tileCfg.bmax, tileCfg.cs, tileCfg.ch)) {
        rcFreeHeightfield(solid);
        return nullptr;
    }
    
    // Rasterize main geometry triangles
    unsigned char* triareas = new unsigned char[ntris];
    memset(triareas, 0, ntris * sizeof(unsigned char));
    
    rcMarkWalkableTriangles(ctx, tileCfg.walkableSlopeAngle, verts, nverts, tris, ntris, triareas);
    
    if (!rcRasterizeTriangles(ctx, verts, nverts, tris, triareas, ntris, *solid, tileCfg.walkableClimb)) {
        delete[] triareas;
        rcFreeHeightfield(solid);
        return nullptr;
    }
    
    // Also rasterize area triangles into the heightfield
    // This ensures the area geometry is part of the navmesh
    if (areas && numAreas > 0) {
        for (int i = 0; i < numAreas; ++i) {
            const AreaMarkingData& area = areas[i];
            if (!area.verts || !area.tris || area.nverts == 0 || area.ntris == 0) continue;
            
            unsigned char* areaTriFlags = new unsigned char[area.ntris];
            memset(areaTriFlags, 0, area.ntris * sizeof(unsigned char));
            
            // Mark all area triangles as walkable
            rcMarkWalkableTriangles(ctx, tileCfg.walkableSlopeAngle,
                                  area.verts, area.nverts,
                                  area.tris, area.ntris, areaTriFlags);
            
            // Rasterize area triangles
            rcRasterizeTriangles(ctx, area.verts, area.nverts,
                               area.tris, areaTriFlags, area.ntris,
                               *solid, tileCfg.walkableClimb);
            
            delete[] areaTriFlags;
        }
    }
    
    delete[] triareas;
    
    // Filter walkable surfaces
    if (flags & FILTER_LOW_HANGING_OBSTACLES)
        rcFilterLowHangingWalkableObstacles(ctx, tileCfg.walkableClimb, *solid);
    if (flags & FILTER_LEDGE_SPANS)
        rcFilterLedgeSpans(ctx, tileCfg.walkableHeight, tileCfg.walkableClimb, *solid);
    if (flags & FILTER_WALKABLE_LOW_HEIGHT_SPANS)
        rcFilterWalkableLowHeightSpans(ctx, tileCfg.walkableHeight, *solid);
    
    // Compact heightfield
    rcCompactHeightfield* chf = rcAllocCompactHeightfield();
    if (!chf) {
        rcFreeHeightfield(solid);
        return nullptr;
    }
    
    if (!rcBuildCompactHeightfield(ctx, tileCfg.walkableHeight, tileCfg.walkableClimb, *solid, *chf)) {
        rcFreeHeightfield(solid);
        rcFreeCompactHeightfield(chf);
        return nullptr;
    }
    
    rcFreeHeightfield(solid);
    
    // Erode walkable area
    if (!rcErodeWalkableArea(ctx, tileCfg.walkableRadius, *chf)) {
        rcFreeCompactHeightfield(chf);
        return nullptr;
    }
    
    // Mark custom areas AFTER erosion
    if (areas && numAreas > 0) {
        ctx->log(RC_LOG_PROGRESS, "Tile (%d,%d): Marking %d custom area meshes", tx, ty, numAreas);
        markAreasFromMesh(ctx, *chf, areas, numAreas);
    }
    
    // Partition heightfield
    int partition = flags & PARTITION_MASK;
    if (partition == PARTITION_WATERSHED) {
        if (!rcBuildDistanceField(ctx, *chf) ||
            !rcBuildRegions(ctx, *chf, tileCfg.borderSize, tileCfg.minRegionArea, tileCfg.mergeRegionArea)) {
            rcFreeCompactHeightfield(chf);
            return nullptr;
        }
    } else if (partition == PARTITION_MONOTONE) {
        if (!rcBuildRegionsMonotone(ctx, *chf, tileCfg.borderSize, tileCfg.minRegionArea, tileCfg.mergeRegionArea)) {
            rcFreeCompactHeightfield(chf);
            return nullptr;
        }
    } else {
        if (!rcBuildLayerRegions(ctx, *chf, tileCfg.borderSize, tileCfg.minRegionArea)) {
            rcFreeCompactHeightfield(chf);
            return nullptr;
        }
    }
    
    // Build contours
    rcContourSet* cset = rcAllocContourSet();
    if (!cset) {
        rcFreeCompactHeightfield(chf);
        return nullptr;
    }
    
    if (!rcBuildContours(ctx, *chf, tileCfg.maxSimplificationError, tileCfg.maxEdgeLen, *cset)) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        return nullptr;
    }
    
    // Build polygon mesh
    rcPolyMesh* pmesh = rcAllocPolyMesh();
    if (!pmesh) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        return nullptr;
    }
    
    if (!rcBuildPolyMesh(ctx, *cset, tileCfg.maxVertsPerPoly, *pmesh)) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        return nullptr;
    }
    
    // Build detail mesh
    rcPolyMeshDetail* dmesh = rcAllocPolyMeshDetail();
    if (!dmesh) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        return nullptr;
    }
    
    if (!rcBuildPolyMeshDetail(ctx, *pmesh, *chf, tileCfg.detailSampleDist,
                              tileCfg.detailSampleMaxError, *dmesh)) {
        rcFreeCompactHeightfield(chf);
        rcFreeContourSet(cset);
        rcFreePolyMesh(pmesh);
        rcFreePolyMeshDetail(dmesh);
        return nullptr;
    }
    
    rcFreeCompactHeightfield(chf);
    rcFreeContourSet(cset);
    
    // Update poly flags and areas
    int areaStats[256] = {0};
    
    for (int i = 0; i < pmesh->npolys; ++i) {
        ++areaStats[pmesh->areas[i]];
        
        // Only update walkable areas to default ground
        if (pmesh->areas[i] == RC_WALKABLE_AREA) {
            pmesh->areas[i] = 1; // Default ground area
        }
        
        // Set flags based on area
        if (pmesh->areas[i] == RC_NULL_AREA) {
            pmesh->flags[i] = 0;
        } else {
            pmesh->flags[i] = 1; // All areas walkable by default
        }
    }
    
    // Log area statistics
    ctx->log(RC_LOG_PROGRESS, "Tile (%d,%d) area distribution:", tx, ty);
    for (int i = 0; i < 256; ++i) {
        if (areaStats[i] > 0) {
            ctx->log(RC_LOG_PROGRESS, "  Area %d: %d polygons", i, areaStats[i]);
        }
    }
    
    // Create Detour data
    dtNavMeshCreateParams params;
    memset(&params, 0, sizeof(params));
    params.verts = pmesh->verts;
    params.vertCount = pmesh->nverts;
    params.polys = pmesh->polys;
    params.polyAreas = pmesh->areas;
    params.polyFlags = pmesh->flags;
    params.polyCount = pmesh->npolys;
    params.nvp = pmesh->nvp;
    params.detailMeshes = dmesh->meshes;
    params.detailVerts = dmesh->verts;
    params.detailVertsCount = dmesh->nverts;
    params.detailTris = dmesh->tris;
    params.detailTriCount = dmesh->ntris;
    params.walkableHeight = agentHeight;
    params.walkableRadius = agentRadius;
    params.walkableClimb = agentMaxClimb;
    params.tileX = tx;
    params.tileY = ty;
    params.tileLayer = 0;
    rcVcopy(params.bmin, pmesh->bmin);
    rcVcopy(params.bmax, pmesh->bmax);
    params.cs = tileCfg.cs;
    params.ch = tileCfg.ch;
    params.buildBvTree = true;
    
    unsigned char* navData = nullptr;
    int navDataSize = 0;
    
    if (!dtCreateNavMeshData(&params, &navData, &navDataSize)) {
        rcFreePolyMesh(pmesh);
        rcFreePolyMeshDetail(dmesh);
        return nullptr;
    }
    
    dataSize = navDataSize;
    
    rcFreePolyMesh(pmesh);
    rcFreePolyMeshDetail(dmesh);
    
    return navData;
}

// Main tiled navmesh building function - updated to use raw geometry
static struct BindingTileMeshResult* buildTiledNavMeshImpl(
    rcConfig* config,
    const TileConfig* tileConfig,
    int flags,
    const float* verts,
    int numVerts,
    const int* tris,
    int numTris,
    const float** areaVerts,      // Array of vertex arrays
    const int* areaVertCounts,    // Number of vertices for each area
    const int** areaTris,         // Array of triangle arrays
    const int* areaTriCounts,     // Number of triangles for each area
    const unsigned char* areaCodes,
    int numAreaMeshes,
    float agentHeight,
    float agentRadius,
    float agentMaxClimb)
{
    BindingTileMeshResult* result = (BindingTileMeshResult*)calloc(1, sizeof(BindingTileMeshResult));
    if (!result) return nullptr;
    
    result->code = BCODE_ERR_UNKNOWN;
    result->navMesh = nullptr;
    result->tilesBuilt = 0;
    
    rcContext ctx;
    
    // Calculate grid size
    int gw = 0, gh = 0;
    rcCalcGridSize(config->bmin, config->bmax, config->cs, &gw, &gh);
    const int ts = tileConfig->tileSize;
    const int tw = (gw + ts - 1) / ts;
    const int th = (gh + ts - 1) / ts;
    result->totalTiles = tw * th;
    
    // Calculate max tiles and polys per tile
    int tileBits = rcMin((int)ilog2(nextPow2(tw * th)), 14);
    if (tileBits > 14) tileBits = 14;
    int polyBits = 22 - tileBits;
    int maxTiles = 1 << tileBits;
    int maxPolysPerTile = 1 << polyBits;
    
    // Allocate navmesh
    result->navMesh = dtAllocNavMesh();
    if (!result->navMesh) {
        result->code = BCODE_ERR_MEMORY;
        return result;
    }
    
    // Initialize navmesh
    dtNavMeshParams params;
    rcVcopy(params.orig, config->bmin);
    params.tileWidth = tileConfig->tileSize * config->cs;
    params.tileHeight = tileConfig->tileSize * config->cs;
    params.maxTiles = maxTiles;
    params.maxPolys = maxPolysPerTile;
    
    dtStatus status = result->navMesh->init(&params);
    if (dtStatusFailed(status)) {
        result->code = BCODE_ERR_INIT_TILE_NAVMESH;
        return result;
    }
    
    // Prepare area marking data
    AreaMarkingData* areas = nullptr;
    if (numAreaMeshes > 0 && areaVerts && areaTris && areaCodes) {
        areas = new AreaMarkingData[numAreaMeshes];
        for (int i = 0; i < numAreaMeshes; ++i) {
            areas[i].verts = areaVerts[i];
            areas[i].nverts = areaVertCounts[i];
            areas[i].tris = areaTris[i];
            areas[i].ntris = areaTriCounts[i];
            areas[i].areaCode = areaCodes[i];
        }
    }
    
    // Build all tiles
    const float tcs = tileConfig->tileSize * config->cs;
    
    for (int y = 0; y < th; ++y) {
        for (int x = 0; x < tw; ++x) {
            float tileBmin[3], tileBmax[3];
            tileBmin[0] = config->bmin[0] + x * tcs;
            tileBmin[1] = config->bmin[1];
            tileBmin[2] = config->bmin[2] + y * tcs;
            
            tileBmax[0] = config->bmin[0] + (x + 1) * tcs;
            tileBmax[1] = config->bmax[1];
            tileBmax[2] = config->bmin[2] + (y + 1) * tcs;
            
            int dataSize = 0;
            unsigned char* data = buildTileMesh(x, y, tileBmin, tileBmax, dataSize,
                                               config, tileConfig, flags,
                                               verts, numVerts, tris, numTris,
                                               areas, numAreaMeshes,
                                               agentHeight, agentRadius, agentMaxClimb,
                                               &ctx);
            
            if (data) {
                result->navMesh->removeTile(result->navMesh->getTileRefAt(x, y, 0), 0, 0);
                
                status = result->navMesh->addTile(data, dataSize, DT_TILE_FREE_DATA, 0, 0);
                if (dtStatusFailed(status)) {
                    dtFree(data);
                    result->code = BCODE_ERR_ADD_TILE;
                } else {
                    result->tilesBuilt++;
                }
            }
        }
    }
    
    delete[] areas;
    
    result->code = (result->tilesBuilt > 0) ? BCODE_OK : BCODE_ERR_BUILD_TILE;
    return result;
}

// New wrapper for the updated API
struct BindingTileMeshResult* bindingBuildTiledNavMeshWithAreas(
    rcConfig* config,
    const TileConfig* tileConfig,
    int flags,
    const float* verts,
    int numVerts,
    const int* tris,
    int numTris,
    const float** areaVerts,
    const int* areaVertCounts,
    const int** areaTris,
    const int* areaTriCounts,
    const unsigned char* areaCodes,
    int numAreaMeshes,
    float agentHeight,
    float agentRadius,
    float agentMaxClimb)
{
    return buildTiledNavMeshImpl(config, tileConfig, flags,
                                   verts, numVerts, tris, numTris,
                                   areaVerts, areaVertCounts,
                                   areaTris, areaTriCounts,
                                   areaCodes, numAreaMeshes,
                                   agentHeight, agentRadius, agentMaxClimb);
}

// Keep the old API for backward compatibility
struct BindingTileMeshResult* bindingBuildTiledNavMesh(
    rcConfig* config,
    const TileConfig* tileConfig,
    int flags,
    const float* verts,
    int numVerts,
    const int* tris,
    int numTris,
    const rcPolyMesh** areaMeshes,     // Deprecated
    const unsigned char* areaCodes,     // Deprecated
    int numAreaMeshes,                  // Deprecated
    float agentHeight,
    float agentRadius,
    float agentMaxClimb)
{
    // Call the new version without areas
    return buildTiledNavMeshImpl(config, tileConfig, flags,
                                   verts, numVerts, tris, numTris,
                                   nullptr, nullptr, nullptr, nullptr,
                                   nullptr, 0,
                                   agentHeight, agentRadius, agentMaxClimb);
}

void bindingReleaseTiledNavMesh(BindingTileMeshResult* result)
{
    if (result) {
        if (result->navMesh) {
            dtFreeNavMesh(result->navMesh);
        }
        free(result);
    }
}

BDetourStatus bindingExportTiledNavMesh(const dtNavMesh* navMesh, void** result, int* resultSize)
{
    if (!navMesh || !result || !resultSize) {
        return BD_ERR_INVALID_PARAM;
    }
    
    // Calculate total size
    int totalSize = sizeof(rcNavMeshSetHeader);
    
    for (int i = 0; i < navMesh->getMaxTiles(); ++i) {
        const dtMeshTile* tile = navMesh->getTile(i);
        if (!tile || !tile->header || !tile->dataSize) continue;
        totalSize += sizeof(rcNavMeshTileHeader) + tile->dataSize;
    }
    
    // Allocate buffer
    unsigned char* buf = (unsigned char*)malloc(totalSize);
    if (!buf) return BD_ERR_ALLOC_NAVMESH;
    
    // Write header
    rcNavMeshSetHeader* header = (rcNavMeshSetHeader*)buf;
    header->magic = NAVMESHSET_MAGIC;
    header->version = NAVMESHSET_VERSION;
    header->numTiles = 0;
    
    for (int i = 0; i < navMesh->getMaxTiles(); ++i) {
        const dtMeshTile* tile = navMesh->getTile(i);
        if (tile && tile->header && tile->dataSize) {
            header->numTiles++;
        }
    }
    
    const dtNavMeshParams* navParams = navMesh->getParams();
    memcpy(&header->params, navParams, sizeof(dtNavMeshParams));
    
    // Write tiles
    unsigned char* ptr = buf + sizeof(rcNavMeshSetHeader);
    
    for (int i = 0; i < navMesh->getMaxTiles(); ++i) {
        const dtMeshTile* tile = navMesh->getTile(i);
        if (!tile || !tile->header || !tile->dataSize) continue;
        
        rcNavMeshTileHeader* tileHeader = (rcNavMeshTileHeader*)ptr;
        tileHeader->tileRef = navMesh->getTileRef(tile);
        tileHeader->dataSize = tile->dataSize;
        ptr += sizeof(rcNavMeshTileHeader);
        
        memcpy(ptr, tile->data, tile->dataSize);
        ptr += tile->dataSize;
    }
    
    *result = buf;
    *resultSize = totalSize;
    
    return BD_OK;
}

// Utility functions
void bindingGetTilePos(const float* pos, int* tx, int* ty,
                      const float* bmin, float tileSize, float cellSize)
{
    const float ts = tileSize * cellSize;
    *tx = (int)((pos[0] - bmin[0]) / ts);
    *ty = (int)((pos[2] - bmin[2]) / ts);
}

void bindingCalcTileBounds(const float* bmin, const float* bmax,
                          int tx, int ty, float tileSize, float cellSize,
                          float* tileBmin, float* tileBmax)
{
    const float ts = tileSize * cellSize;
    
    tileBmin[0] = bmin[0] + tx * ts;
    tileBmin[1] = bmin[1];
    tileBmin[2] = bmin[2] + ty * ts;
    
    tileBmax[0] = bmin[0] + (tx + 1) * ts;
    tileBmax[1] = bmax[1];
    tileBmax[2] = bmin[2] + (ty + 1) * ts;
}

// Extract geometry for visualization
struct BindingVertsAndTriangles* bindingExtractTileGeometry(
    const dtNavMesh* navMesh,
    int tileX,
    int tileY)
{
    if (!navMesh) return nullptr;
    
    const dtMeshTile* tile = navMesh->getTileAt(tileX, tileY, 0);
    if (!tile || !tile->header) return nullptr;
    
    BindingVertsAndTriangles* ret = (BindingVertsAndTriangles*)calloc(1, sizeof(BindingVertsAndTriangles));
    if (!ret) return nullptr;
    
    // Count triangles
    int ntris = 0;
    for (int i = 0; i < tile->header->polyCount; ++i) {
        const dtPoly* p = &tile->polys[i];
        if (p->getType() == DT_POLYTYPE_OFFMESH_CONNECTION) continue;
        ntris += (p->vertCount - 2) * 3;
    }
    
    // Allocate arrays
    ret->nverts = tile->header->vertCount;
    ret->ntris = ntris;
    ret->verts = (float*)calloc(ret->nverts * 4, sizeof(float));
    ret->triangles = (uint32_t*)calloc(ntris, sizeof(uint32_t));
    
    if (!ret->verts || !ret->triangles) {
        freeVertsAndTriangles(ret);
        return nullptr;
    }
    
    // Copy vertices
    for (int i = 0; i < tile->header->vertCount; ++i) {
        const float* v = &tile->verts[i * 3];
        ret->verts[i * 4 + 0] = v[0];
        ret->verts[i * 4 + 1] = v[1];
        ret->verts[i * 4 + 2] = v[2];
        ret->verts[i * 4 + 3] = 0;
    }
    
    // Build triangles
    int tidx = 0;
    for (int i = 0; i < tile->header->polyCount; ++i) {
        const dtPoly* p = &tile->polys[i];
        if (p->getType() == DT_POLYTYPE_OFFMESH_CONNECTION) continue;
        
        for (int j = 2; j < p->vertCount; ++j) {
            ret->triangles[tidx++] = p->verts[0];
            ret->triangles[tidx++] = p->verts[j - 1];
            ret->triangles[tidx++] = p->verts[j];
        }
    }
    
    return ret;
}

void freeVertsAndTriangles(BindingVertsAndTriangles* data)
{
    if (data) {
        if (data->verts) free(data->verts);
        if (data->triangles) free(data->triangles);
        free(data);
    }
}
