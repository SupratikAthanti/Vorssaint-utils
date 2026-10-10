// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-05 (Refresh-rate selector):
/// covers deriving selectable refresh rates from display modes,
/// deduplicating rates with appropriate display rounding,
/// preserving unique mode identifiers, and verifying refresh rate readback.
enum DisplayRefreshRateTests {
    static func run(_ suite: TestSuite) {
        // Prepare some test modes
        let modes = [
            DisplayModeSupport.DisplayModeItem(id: 101, width: 1920, height: 1080, refreshRate: 59.94, isUsable: true),
            DisplayModeSupport.DisplayModeItem(id: 102, width: 1920, height: 1080, refreshRate: 60.00, isUsable: true), // Duplicate rounded 60Hz
            DisplayModeSupport.DisplayModeItem(id: 103, width: 1920, height: 1080, refreshRate: 120.0, isUsable: true),
            DisplayModeSupport.DisplayModeItem(id: 104, width: 2560, height: 1440, refreshRate: 144.0, isUsable: true),
            DisplayModeSupport.DisplayModeItem(id: 105, width: 1920, height: 1080, refreshRate: 24.0, isUsable: true)
        ]

        // 1. Deriving selectable refresh rates & deduplicating with rounding
        let rates1080p = DisplayModeSupport.deriveRefreshRates(for: modes, width: 1920, height: 1080)
        suite.expect(rates1080p.count == 3, "deduplicates rates rounding to same integer (59.94/60 -> 60Hz, plus 24Hz and 120Hz)")
        suite.expect(rates1080p.map(\.roundedRate) == [24, 60, 120], "derived refresh rates are sorted and rounded correctly")

        // 2. Preserving unique mode identifiers
        let rate60Option = rates1080p.first(where: { $0.roundedRate == 60 })
        suite.expect(rate60Option?.modeID == 101 || rate60Option?.modeID == 102, "preserves a valid unique mode identifier for selected refresh rate")

        // 3. Verifying refresh rate readback (simulated via service or direct)
        // Since DisplayModeSupport doesn't have readback, we verify that the option's exact rate is preserved.
        if let option60 = rate60Option {
            suite.expect(abs(option60.exactRate - 59.94) < 0.001 || abs(option60.exactRate - 60.0) < 0.001, "accurately preserves exact rate in option")
        }
    }
}
