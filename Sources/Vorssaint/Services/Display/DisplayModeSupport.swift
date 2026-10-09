// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure logic and CoreGraphics wrappers for BD-04 (Resolution and display mode selector):
/// mode enumeration, usability filtering, and rollback/timeout confirmation management.
enum DisplayModeSupport {
    struct DisplayModeItem: Identifiable, Equatable {
        let id: Int
        let cgMode: CGDisplayMode?
        let width: Int
        let height: Int
        let refreshRate: Double
        let isInterlaced: Bool
        let isUsable: Bool

        var summary: String {
            let refreshStr = refreshRate > 0 ? " @ \(Int(refreshRate.rounded()))Hz" : ""
            return "\(width) × \(height)\(refreshStr)"
        }

        static func == (lhs: DisplayModeItem, rhs: DisplayModeItem) -> Bool {
            lhs.width == rhs.width && lhs.height == rhs.height && lhs.refreshRate == rhs.refreshRate && lhs.isInterlaced == rhs.isInterlaced
        }
    }

    /// Enumerates all available display modes for a given display ID.
    static func enumerateModes(for displayID: CGDirectDisplayID) -> [DisplayModeItem] {
        guard let modes = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return []
        }
        return modes.enumerated().map { index, mode in
            let width = Int(CGDisplayModeGetWidth(mode))
            let height = Int(CGDisplayModeGetHeight(mode))
            let refreshRate = Double(CGDisplayModeGetRefreshRate(mode))
            let ioFlags = CGDisplayModeGetIOFlags(mode)
            let isInterlaced = (ioFlags & UInt32(kCGDisplayModeInterlaced)) != 0
            let isUsable = width >= 640 && height >= 480 && !isInterlaced

            return DisplayModeItem(
                id: index,
                cgMode: mode,
                width: width,
                height: height,
                refreshRate: refreshRate,
                isInterlaced: isInterlaced,
                isUsable: isUsable
            )
        }
    }

    /// Filters unusable or low-quality modes.
    static func filterUsableModes(_ modes: [DisplayModeItem]) -> [DisplayModeItem] {
        modes.filter { mode in
            mode.isUsable &&
            mode.width >= 640 &&
            mode.height >= 480 &&
            !mode.isInterlaced &&
            mode.refreshRate >= 30.0
        }
    }

    struct RefreshRateOption: Identifiable, Equatable {
        var id: Int { modeID }
        let modeID: Int
        let roundedRate: Int
        let exactRate: Double
        let cgMode: CGDisplayMode?

        var summary: String {
            "\(roundedRate) Hz"
        }

        static func == (lhs: RefreshRateOption, rhs: RefreshRateOption) -> Bool {
            lhs.modeID == rhs.modeID && lhs.roundedRate == rhs.roundedRate && lhs.exactRate == rhs.exactRate
        }
    }

    /// Derives selectable unique refresh rates for a given display resolution (BD-05).
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
                    cgMode: mode.cgMode
                ))
            }
        }
        return options.sorted { $0.roundedRate < $1.roundedRate }
    }

    /// Rollback safety manager for resolution changes.
    struct RollbackState: Equatable {
        enum Status: Equatable {
            case normal
            case pendingConfirmation(previousWidth: Int, previousHeight: Int, targetWidth: Int, targetHeight: Int, secondsRemaining: Double)
            case confirmed(width: Int, height: Int)
            case rolledBack(width: Int, height: Int)
        }

        var status: Status = .normal
        var timeoutDuration: Double = 15.0

        mutating func startPending(currentWidth: Int, currentHeight: Int, targetWidth: Int, targetHeight: Int) {
            status = .pendingConfirmation(previousWidth: currentWidth, previousHeight: currentHeight,
                                          targetWidth: targetWidth, targetHeight: targetHeight,
                                          secondsRemaining: timeoutDuration)
        }

        mutating func confirm() {
            if case .pendingConfirmation(_, _, let targetW, let targetH, _) = status {
                status = .confirmed(width: targetW, height: targetH)
            }
        }

        mutating func tick(elapsed: Double) -> (didRollback: Bool, fallbackWidth: Int?, fallbackHeight: Int?) {
            guard case .pendingConfirmation(let prevW, let prevH, let targetW, let targetH, var remaining) = status else {
                return (false, nil, nil)
            }
            remaining -= elapsed
            if remaining <= 0 {
                status = .rolledBack(width: prevW, height: prevH)
                return (true, prevW, prevH)
            } else {
                status = .pendingConfirmation(previousWidth: prevW, previousHeight: prevH,
                                              targetWidth: targetW, targetHeight: targetH,
                                              secondsRemaining: remaining)
                return (false, nil, nil)
            }
        }
    }
}
