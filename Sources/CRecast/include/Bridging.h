// Bridging.h

#ifndef BRIDGING_H
#define BRIDGING_H 1
#include <stdint.h>
#include "Recast.h"
#include "DetourNavMesh.h"

#ifdef __cplusplus
extern "C" {
#endif

// Constants for navmesh file format
#define NAVMESHSET_MAGIC    'M'<<24 | 'S'<<16 | 'E'<<8 | 'T'
#define NAVMESHSET_VERSION  1

typedef enum {
    BCODE_OK = 0,
    BCODE_ERR_MEMORY = 1,
    BCODE_ERR_INIT_TILE_NAVMESH = 2,
    BCODE_ERR_BUILD_TILE = 3,
    BCODE_ERR_ADD_TILE = 4,
    BCODE_ERR_UNKNOWN = 5,
} BCodeStatus;

typedef enum {
    BD_OK = 0,
    BD_ERR_VERTICES = 1,
    BD_ERR_BUILD_NAVMESH = 2,
    BD_ERR_ALLOC_NAVMESH = 3,
    BD_ERR_INVALID_PARAM = 4
} BDetourStatus;

// Tile configuration
struct TileConfig {
    int tileSize;           // Size of each tile in voxels
};

// Result structure for tiled mesh building
struct BindingTileMeshResult {
    BCodeStatus code;
    dtNavMesh* navMesh;     // The multi-tile navigation mesh
    int tilesBuilt;         // Number of tiles successfully built
    int totalTiles;         // Total number of tiles
};

// Filter flags
enum {
    FILTER_LOW_HANGING_OBSTACLES = 1,
    FILTER_LEDGE_SPANS = 2,
    FILTER_WALKABLE_LOW_HEIGHT_SPANS = 4,
    
    // Partition options (3 bits)
    PARTITION_MASK = 24,
    PARTITION_WATERSHED = 8,
    PARTITION_MONOTONE = 16,
    PARTITION_LAYER = 0
};

// New API that takes raw geometry for areas
struct BindingTileMeshResult* bindingBuildTiledNavMeshWithAreas(
    rcConfig* config,
    const TileConfig* tileConfig,
    int flags,
    const float* verts,
    int numVerts,
    const int* tris,
    int numTris,
    const float** areaVerts,      // Array of vertex arrays for each area
    const int* areaVertCounts,    // Number of vertices for each area
    const int** areaTris,         // Array of triangle arrays for each area
    const int* areaTriCounts,     // Number of triangles for each area
    const unsigned char* areaCodes,
    int numAreaMeshes,
    float agentHeight,
    float agentRadius,
    float agentMaxClimb
);

// Backward compatibility
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
    float agentMaxClimb
);

// Release tiled navmesh result
void bindingReleaseTiledNavMesh(BindingTileMeshResult* result);

// Export tiled navmesh to binary format
BDetourStatus bindingExportTiledNavMesh(
    const dtNavMesh* navMesh,
    void** result,
    int* resultSize
);

// Utility functions
void bindingGetTilePos(const float* pos, int* tx, int* ty,
                      const float* bmin, float tileSize, float cellSize);

void bindingCalcTileBounds(const float* bmin, const float* bmax,
                          int tx, int ty, float tileSize, float cellSize,
                          float* tileBmin, float* tileBmax);

// For extracting mesh visualization data
struct BindingVertsAndTriangles {
    int nverts;
    int ntris;
    float *verts;
    uint32_t *triangles;
};

struct BindingVertsAndTriangles* bindingExtractTileGeometry(
    const dtNavMesh* navMesh,
    int tileX,
    int tileY
);

void freeVertsAndTriangles(BindingVertsAndTriangles *data);

#ifdef __cplusplus
}   /* extern "C" */
#endif

// ──────────────────────────────────────────────────

// ================================================
//       For tile navMesh bin load
// ================================================

typedef struct {
    int32_t         magic;
    int32_t         version;
    int32_t         numTiles;
    dtNavMeshParams params;
} rcNavMeshSetHeader;

typedef struct {
    dtTileRef tileRef;
    int32_t   dataSize;
} rcNavMeshTileHeader;

// ================================================
//       Geometry Detour helper symbols
// ================================================

#ifdef __cplusplus
extern "C" {
#endif

/* ─── Forward declarations that Swift must see ─── */
typedef struct dtMeshTile dtMeshTile;
typedef struct dtPoly     dtPoly;
typedef struct dtMeshHeader dtMeshHeader;

/* -------------------------------------------------------------------
 *  Thin, zero-cost shims that expose the C++ methods Swift cannot see
 *  when dtNavMesh is imported as an opaque pointer.
 * ------------------------------------------------------------------*/
static inline int32_t
dtNavMeshGetMaxTiles(const dtNavMesh *m)            { return m->getMaxTiles(); }

static inline const dtMeshTile *
dtNavMeshGetTile(const dtNavMesh *m, int32_t i)     { return m->getTile(i); }

static inline dtPolyRef
dtNavMeshGetPolyRefBase(const dtNavMesh *m,
                        const dtMeshTile *t)        { return m->getPolyRefBase(t); }

/* -------------------------------------------------------------------
 *  dtMeshTile accessors for Swift
 * ------------------------------------------------------------------*/
static inline const dtMeshHeader*
dtMeshTileGetHeader(const dtMeshTile *tile)         { return tile->header; }

static inline const float*
dtMeshTileGetVerts(const dtMeshTile *tile)          { return tile->verts; }

static inline const dtPoly*
dtMeshTileGetPolys(const dtMeshTile *tile)          { return tile->polys; }

/* -------------------------------------------------------------------
 *  dtMeshHeader accessors for Swift
 * ------------------------------------------------------------------*/
static inline int32_t
dtMeshHeaderGetPolyCount(const dtMeshHeader *header) { return header->polyCount; }

static inline int32_t
dtMeshHeaderGetVertCount(const dtMeshHeader *header) { return header->vertCount; }

/* -------------------------------------------------------------------
 *  dtPoly accessors for Swift
 * ------------------------------------------------------------------*/
static inline uint16_t
dtPolyGetVertCount(const dtPoly *poly)               { return poly->vertCount; }

static inline uint16_t
dtPolyGetVert(const dtPoly *poly, int32_t idx)      { return poly->verts[idx]; }

static inline uint16_t
dtPolyGetNeighbor(const dtPoly *poly, int32_t idx)  { return poly->neis[idx]; }

static inline uint16_t
dtPolyGetFlags(const dtPoly *poly)                   { return poly->flags; }

static inline uint8_t
dtPolyGetType(const dtPoly *poly)                    { return poly->getType(); }

static inline uint8_t
dtPolyGetArea(const dtPoly *poly)                    { return poly->getArea(); }

static inline void* getNavMeshFromResultAsVoidPtr(BindingTileMeshResult* result) {
    return result ? (void*)result->navMesh : NULL;
}

/* -------------------------------------------------------------------
 *  Get tile state (coordinates) for a given tile
 * ------------------------------------------------------------------*/
static inline void
dtNavMeshGetTileStateAt(const dtNavMesh *m, int32_t tileIdx,
                        int32_t *tx, int32_t *ty, int32_t *tlayer)
{
    const dtMeshTile* tile = m->getTile(tileIdx);
    if (tile && tile->header) {
        if (tx) *tx = tile->header->x;
        if (ty) *ty = tile->header->y;
        if (tlayer) *tlayer = tile->header->layer;
    } else {
        if (tx) *tx = 0;
        if (ty) *ty = 0;
        if (tlayer) *tlayer = 0;
    }
}

#ifdef __cplusplus
}   /* extern "C" */
#endif


#endif
