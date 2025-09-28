// SPDX-License-Identifier: MIT
//
//  NavMeshErrors.swift
//  SwiftRecastNavigation
//
//  Error definitions for navigation mesh building
//

import Foundation

/// Errors thrown during navigation mesh building
public enum NavMeshError: Error {
    case memory
    case initTileNavMesh
    case buildTile
    case addTile
    case unknown
    case noTilesBuilt
    case invalidConfiguration
    case buildPolyMesh
    case markCustomAreas
}

/// Errors raised when exporting navigation data
public enum NavMeshExportError: Error {
    case invalidParameters
    case allocationFailed
    case exportFailed
}
