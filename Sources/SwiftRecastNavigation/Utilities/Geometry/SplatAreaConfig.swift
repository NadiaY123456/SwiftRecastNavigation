// SPDX-License-Identifier: MIT
//
//  SplatAreaConfig.swift
//  SwiftRecastNavigation
//

// MARK: – Area Code Configuration ------------------------------------------------

/// Configuration for area codes and costs extracted from a splat image.
public struct SplatAreaConfig: Codable {
    public struct ChannelConfig: Codable {
        public let channel: SplatMeshGenerator.Channel
        public let areaCode: UInt8
        public let cost: Float        // Traversal cost (default = 1.0)
        public let exclude: Bool      // If true the area is completely impassable

        public init(
            channel: SplatMeshGenerator.Channel,
            areaCode: UInt8,
            cost: Float = 1.0,
            exclude: Bool = false
        ) {
            self.channel = channel
            self.areaCode = areaCode
            self.cost     = cost
            self.exclude  = exclude
        }
    }

    public let splatName: String
    public let channelConfigs: [ChannelConfig]

    public init(splatName: String, channelConfigs: [ChannelConfig]) {
        self.splatName      = splatName
        self.channelConfigs = channelConfigs
    }
}

// MARK: – NavQueryFilter helper --------------------------------------------------

public extension NavQueryFilter {
    /// Applies per-area traversal costs *and* exclusions.
    ///
    /// In a vanilla Recast/Detour build every polygon’s **flags** field is
    /// `DT_POLYFLAGS_WALK` (`0x01`), so relying solely on `excludeFlags` has
    /// no effect.
    /// The clean workaround is to make excluded areas **infinitely expensive**
    /// while still keeping `excludeFlags` for projects that *do* export
    /// per-area polygon flags.
    ///
    /// - Parameter areaConfigs: One or more `SplatAreaConfig` groups.
    func configure(with areaConfigs: [SplatAreaConfig]) {
        // 1️⃣  Start from a known state
        for i in 0..<64 { setAreaCost(Int32(i), cost: 1.0) }   // default cost
        includeFlags = 0xffff      // allow everything by default
        excludeFlags = 0           // clear any previous mask

        // 2️⃣  Apply user configuration
        var localExcludeMask: UInt32 = 0

        for config in areaConfigs {
            for cfg in config.channelConfigs {
                let areaIdx = Int32(cfg.areaCode)

                if cfg.exclude {
                    // Impassable even when the mesh has only DT_POLYFLAGS_WALK
                    setAreaCost(areaIdx, cost: .greatestFiniteMagnitude)
                    localExcludeMask |= 1 << cfg.areaCode
                } else {
                    setAreaCost(areaIdx, cost: cfg.cost)
                }
            }
        }

        // 3️⃣  Commit the combined exclude mask (Detour looks at the low-16 bits)
        excludeFlags = UInt16(localExcludeMask & 0xffff)
    }
}

// MARK: – Example usage (unchanged) ---------------------------------------------

/*
splatName = the name of the PNG RGBA splat file

// 1. Simple configuration with default costs
let simpleConfig = [
    SplatAreaConfig(
        splatName: "terrain_splat",
        channelConfigs: [
            .init(channel: .red,   areaCode: 2), // cost 1.0
            .init(channel: .green, areaCode: 3)  // cost 1.0
        ]
    )
]

// 2. Configuration with custom costs & exclusions
let costConfig = [
    SplatAreaConfig(
        splatName: "roads_splat",
        channelConfigs: [
            .init(channel: .red,   areaCode: 2, cost: 0.5), // roads – cheap
            .init(channel: .green, areaCode: 3, cost: 0.8)  // sidewalks
        ]
    ),
    SplatAreaConfig(
        splatName: "water_splat",
        channelConfigs: [
            .init(channel: .blue,  areaCode: 6, exclude: true) // water – impassable
        ]
    )
]

// Build the NavMesh, then:
let filter = NavQueryFilter()
filter.configure(with: costConfig)
// Use `filter` for all query calls – water will be avoided automatically.
*/
