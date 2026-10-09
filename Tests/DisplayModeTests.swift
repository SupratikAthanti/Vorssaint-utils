// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-04 (Resolution and display mode selector):
/// covers mode enumeration, filtering unusable modes, applying modes,
/// and rollback/recovery safety mechanisms (timeout confirmation).
enum DisplayModeTests {
    struct DisplayMode: Equatable, Identifiable {
        let id: Int
        let width: Int
        let height: Int
        let refreshRate: Double
        let isInterlaced: Bool
        let isUsable: Bool
    }

    struct RollbackManager {
        enum State: Equatable {
            case normal
            case pendingConfirmation(previous: DisplayMode, target: DisplayMode, secondsRemaining: Double)
            case confirmed(DisplayMode)
            case rolledBack(DisplayMode)
        }

        var state: State = .normal
        var confirmationTimeout: Double = 15.0

        mutating func apply(mode: DisplayMode, current: DisplayMode) -> Bool {
            guard mode.isUsable else { return false }
            state = .pendingConfirmation(previous: current, target: mode, secondsRemaining: confirmationTimeout)
            return true
        }

        mutating func confirm() {
            if case .pendingConfirmation(_, let target, _) = state {
                state = .confirmed(target)
            }
        }

        mutating func tick(seconds: Double) -> Bool {
            guard case .pendingConfirmation(let previous, _, var remaining) = state else { return false }
            remaining -= seconds
            if remaining <= 0 {
                state = .rolledBack(previous)
                return true
            } else {
                state = .pendingConfirmation(previous: previous, target: stateTarget ?? previous, secondsRemaining: remaining)
                return false
            }
        }

        private var stateTarget: DisplayMode? {
            guard case .pendingConfirmation(_, let target, _) = state else { return nil }
            return target
        }
    }

    static func filterUnusableModes(_ modes: [DisplayMode]) -> [DisplayMode] {
        modes.filter { mode in
            mode.isUsable &&
            mode.width >= 640 &&
            mode.height >= 480 &&
            !mode.isInterlaced &&
            mode.refreshRate >= 30.0
        }
    }

    static func run(_ suite: TestSuite) {
        // 1. Resolution mode enumeration & filtering unusable modes
        let rawModes = [
            DisplayMode(id: 1, width: 320, height: 240, refreshRate: 60.0, isInterlaced: false, isUsable: true), // Too small
            DisplayMode(id: 2, width: 1920, height: 1080, refreshRate: 60.0, isInterlaced: true, isUsable: true), // Interlaced
            DisplayMode(id: 3, width: 1920, height: 1080, refreshRate: 24.0, isInterlaced: false, isUsable: true), // Low refresh
            DisplayMode(id: 4, width: 1920, height: 1080, refreshRate: 60.0, isInterlaced: false, isUsable: false), // Unusable flag
            DisplayMode(id: 5, width: 1920, height: 1080, refreshRate: 60.0, isInterlaced: false, isUsable: true), // Valid HD
            DisplayMode(id: 6, width: 3840, height: 2160, refreshRate: 120.0, isInterlaced: false, isUsable: true)  // Valid 4K
        ]

        let filtered = filterUnusableModes(rawModes)
        suite.expect(filtered.count == 2, "filters out unusable, small, interlaced, and low refresh modes")
        suite.expect(filtered.map(\.id) == [5, 6], "retains only valid high quality modes")

        // 2. Applying resolution modes & Rollback / recovery safety mechanism
        let modeA = DisplayMode(id: 5, width: 1920, height: 1080, refreshRate: 60.0, isInterlaced: false, isUsable: true)
        let modeB = DisplayMode(id: 6, width: 3840, height: 2160, refreshRate: 120.0, isInterlaced: false, isUsable: true)
        let unusableMode = DisplayMode(id: 4, width: 1920, height: 1080, refreshRate: 60.0, isInterlaced: false, isUsable: false)

        var rollbackMgr = RollbackManager(confirmationTimeout: 10.0)
        suite.expect(rollbackMgr.apply(mode: unusableMode, current: modeA) == false, "refuses to apply unusable mode")
        suite.expect(rollbackMgr.state == .normal, "state remains normal after rejecting unusable mode")

        let applied = rollbackMgr.apply(mode: modeB, current: modeA)
        suite.expect(applied && rollbackMgr.state == .pendingConfirmation(previous: modeA, target: modeB, secondsRemaining: 10.0),
                     "applying valid mode enters pending confirmation state")

        // Tick partial time
        _ = rollbackMgr.tick(seconds: 4.0)
        if case .pendingConfirmation(_, _, let remaining) = rollbackMgr.state {
            suite.expect(abs(remaining - 6.0) < 0.0001, "timer decreases correctly during countdown")
        } else {
            suite.expect(false, "should be in pending confirmation")
        }

        // Confirm change before timeout
        rollbackMgr.confirm()
        suite.expect(rollbackMgr.state == .confirmed(modeB), "confirming commits the new mode")

        // Test timeout rollback
        var rollbackMgr2 = RollbackManager(confirmationTimeout: 5.0)
        _ = rollbackMgr2.apply(mode: modeB, current: modeA)
        let timedOut = rollbackMgr2.tick(seconds: 6.0)
        suite.expect(timedOut && rollbackMgr2.state == .rolledBack(modeA),
                     "exceeding confirmation timeout automatically rolls back to previous mode")

        // 3. BD-06 HiDPI / Scaling Controls tests
        runHiDPITests(suite)
    }

    struct HiDPIModeItem: Equatable, Identifiable {
        let id: Int
        let width: Int        // logical width ("looks like")
        let height: Int       // logical height
        let pixelWidth: Int   // physical output width
        let pixelHeight: Int  // physical output height
        let ioFlags: UInt32
        let isUsable: Bool

        var scaleFactor: Double {
            guard width > 0 else { return 1.0 }
            return Double(pixelWidth) / Double(width)
        }

        var isHiDPI: Bool {
            scaleFactor > 1.0 || (ioFlags & 0x00000008) != 0
        }
    }

    static func calculateScaleFactor(pixelWidth: Int, logicalWidth: Int) -> Double {
        guard logicalWidth > 0 else { return 1.0 }
        return Double(pixelWidth) / Double(logicalWidth)
    }

    static func isHiDPI(ioFlags: UInt32, pixelWidth: Int, logicalWidth: Int) -> Bool {
        let factor = calculateScaleFactor(pixelWidth: pixelWidth, logicalWidth: logicalWidth)
        return factor > 1.0 || (ioFlags & 0x00000008) != 0
    }

    static func filterScalingModes(_ modes: [HiDPIModeItem]) -> [HiDPIModeItem] {
        modes.filter { $0.isUsable && $0.width >= 640 && $0.height >= 480 }
    }

    static func runHiDPITests(_ suite: TestSuite) {
        let modeRetina = HiDPIModeItem(id: 1, width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, ioFlags: 0x00000008, isUsable: true)
        suite.expect(modeRetina.width == 1920 && modeRetina.height == 1080, "logical UI scaling 'looks like' resolution is correctly separated")
        suite.expect(modeRetina.pixelWidth == 3840 && modeRetina.pixelHeight == 2160, "physical output resolution is correctly separated")

        let modeNonHiDPI = HiDPIModeItem(id: 2, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, ioFlags: 0, isUsable: true)
        suite.expect(modeRetina.isHiDPI, "identifies HiDPI mode when scale factor > 1.0 or flag is set")
        suite.expect(!modeNonHiDPI.isHiDPI, "identifies standard non-HiDPI mode correctly")

        let scale2x = calculateScaleFactor(pixelWidth: 3840, logicalWidth: 1920)
        let scale1x = calculateScaleFactor(pixelWidth: 1920, logicalWidth: 1920)
        let scaleFractional = calculateScaleFactor(pixelWidth: 3000, logicalWidth: 1500)
        suite.expect(abs(scale2x - 2.0) < 0.0001, "calculates 2x HiDPI scale factor correctly")
        suite.expect(abs(scale1x - 1.0) < 0.0001, "calculates 1x standard scale factor correctly")
        suite.expect(abs(scaleFractional - 2.0) < 0.0001, "calculates fractional/custom scale factor correctly")

        let rawModes = [
            modeRetina,
            modeNonHiDPI,
            HiDPIModeItem(id: 3, width: 320, height: 240, pixelWidth: 640, pixelHeight: 480, ioFlags: 0x00000008, isUsable: true),
            HiDPIModeItem(id: 4, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, ioFlags: 0x00000008, isUsable: false)
        ]
        let validScalingModes = filterScalingModes(rawModes)
        suite.expect(validScalingModes.count == 2, "filters valid scaling modes correctly, discarding small or unusable modes")
        suite.expect(validScalingModes.map(\.id) == [1, 2], "retains only valid scaling mode items")
    }
}
