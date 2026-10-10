// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-04 (Resolution and display mode selector):
/// Covers enumeration, usability filtering, labels, and apply/rollback flow.
enum DisplayModeSelectorTests {
    static func run(_ suite: TestSuite) {
        // 1. Test Mode Enumeration and Filtering
        let rawModes = [
            DisplayModeSupport.DisplayModeItem(id: 1, width: 320, height: 240, refreshRate: 60.0, isUsable: true), // Too small
            DisplayModeSupport.DisplayModeItem(id: 2, width: 1920, height: 1080, refreshRate: 60.0, isInterlaced: true, isUsable: true), // Interlaced
            DisplayModeSupport.DisplayModeItem(id: 3, width: 1920, height: 1080, refreshRate: 20.0, isUsable: true), // Low refresh
            DisplayModeSupport.DisplayModeItem(id: 4, width: 1920, height: 1080, refreshRate: 60.0, isUsable: false), // Unusable flag
            DisplayModeSupport.DisplayModeItem(id: 5, width: 1920, height: 1080, refreshRate: 60.0, isUsable: true), // Valid
            DisplayModeSupport.DisplayModeItem(id: 6, width: 3840, height: 2160, refreshRate: 120.0, isUsable: true)  // Valid 4K
        ]
        
        let filtered = DisplayModeSupport.filterUsableModes(rawModes)
        suite.expect(filtered.count == 2, "Filters out unusable, small, interlaced, and low refresh modes")
        suite.expect(filtered.map(\.id) == [5, 6], "Retains only valid high quality modes")

        // 2. Test Labels
        let mode = DisplayModeSupport.DisplayModeItem(id: 7, width: 2560, height: 1440, refreshRate: 60.0, isUsable: true)
        suite.expect(mode.summary == "2560 × 1440 @ 60Hz", "Display mode label format is correct: \(mode.summary)")

        // 3. Test Apply Flow with Rollback Safeguard
        var rollbackState = DisplayModeSupport.RollbackState()
        let modeA = DisplayModeSupport.DisplayModeItem(id: 5, width: 1920, height: 1080, refreshRate: 60.0, isUsable: true)
        let modeB = DisplayModeSupport.DisplayModeItem(id: 6, width: 3840, height: 2160, refreshRate: 120.0, isUsable: true)

        rollbackState.startPending(currentWidth: modeA.width, currentHeight: modeA.height,
                                   targetWidth: modeB.width, targetHeight: modeB.height)
        
        if case .pendingConfirmation(let prevW, let prevH, let targetW, let targetH, _) = rollbackState.status {
            suite.expect(prevW == 1920 && prevH == 1080 && targetW == 3840 && targetH == 2160, "Rollback state correctly tracks previous and target resolution")
        } else {
            suite.expect(false, "Should be in pending confirmation state")
        }

        // Test timeout rollback
        let tickResult = rollbackState.tick(elapsed: 20.0) // Timeout is 15s
        suite.expect(tickResult.didRollback == true, "Rollback triggers after timeout")
        if case .rolledBack(let w, let h) = rollbackState.status {
            suite.expect(w == 1920 && h == 1080, "Rollback restores previous resolution")
        } else {
            suite.expect(false, "Should have rolled back")
        }
    }
}
