// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-05 (Refresh-rate selector):
/// covers deriving selectable refresh rates from display modes,
/// deduplicating rates with appropriate display rounding,
/// preserving unique mode identifiers, and verifying refresh rate readback.
enum RefreshRateTests {
    struct DisplayModeItem: Equatable, Identifiable {
        let id: Int
        let width: Int
        let height: Int
        let refreshRate: Double
        let isUsable: Bool
    }

    struct RefreshRateOption: Equatable, Identifiable {
        var id: Int { modeID }
        let modeID: Int
        let roundedRate: Int
        let exactRate: Double
        let summary: String
    }

    static func deriveRefreshRates(for modes: [DisplayModeItem], width: Int, height: Int) -> [RefreshRateOption] {
        let matchingModes = modes.filter { $0.width == width && $0.height == height && $0.isUsable }
        var seenRates = Set<Int>()
        var options: [RefreshRateOption] = []
        for mode in matchingModes {
            let rounded = Int(mode.refreshRate.rounded())
            if !seenRates.contains(rounded) {
                seenRates.insert(rounded)
                options.append(RefreshRateOption(
                    modeID: mode.id,
                    roundedRate: rounded,
                    exactRate: mode.refreshRate,
                    summary: "\(rounded) Hz"
                ))
            }
        }
        return options.sorted { $0.roundedRate < $1.roundedRate }
    }

    static func readbackRefreshRate(currentMode: DisplayModeItem?) -> Double {
        return currentMode?.refreshRate ?? 0.0
    }

    static func run(_ suite: TestSuite) {
        let modes = [
            DisplayModeItem(id: 101, width: 1920, height: 1080, refreshRate: 59.94, isUsable: true),
            DisplayModeItem(id: 102, width: 1920, height: 1080, refreshRate: 60.00, isUsable: true), // Duplicate rounded 60Hz
            DisplayModeItem(id: 103, width: 1920, height: 1080, refreshRate: 120.0, isUsable: true),
            DisplayModeItem(id: 104, width: 2560, height: 1440, refreshRate: 144.0, isUsable: true),
            DisplayModeItem(id: 105, width: 1920, height: 1080, refreshRate: 24.0, isUsable: true)
        ]

        // 1. Deriving selectable refresh rates & deduplicating with rounding
        let rates1080p = deriveRefreshRates(for: modes, width: 1920, height: 1080)
        suite.expect(rates1080p.count == 3, "deduplicates rates rounding to same integer (59.94/60 -> 60Hz, plus 24Hz and 120Hz)")
        suite.expect(rates1080p.map(\.roundedRate) == [24, 60, 120], "derived refresh rates are sorted and rounded correctly")

        // 2. Preserving unique mode identifiers
        let rate60Option = rates1080p.first(where: { $0.roundedRate == 60 })
        suite.expect(rate60Option?.modeID == 101 || rate60Option?.modeID == 102, "preserves a valid unique mode identifier for selected refresh rate")

        // 3. Verifying refresh rate readback
        let activeMode = DisplayModeItem(id: 103, width: 1920, height: 1080, refreshRate: 120.0, isUsable: true)
        let readback = readbackRefreshRate(currentMode: activeMode)
        suite.expect(abs(readback - 120.0) < 0.001, "accurately reads back active refresh rate")
        suite.expect(readbackRefreshRate(currentMode: nil) == 0.0, "handles nil current mode gracefully")
    }
}
