// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages display resolution and mode selection with safety rollback mechanisms
/// for Vorssaint (BD-04).
final class DisplayModeService: ObservableObject {
    static let shared = DisplayModeService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-mode")

    @Published private(set) var availableModes: [DisplayModeSupport.DisplayModeItem] = []
    @Published private(set) var currentMode: DisplayModeSupport.DisplayModeItem?
    @Published private(set) var confirmationState: DisplayModeSupport.RollbackState.Status = .normal

    private var rollbackState = DisplayModeSupport.RollbackState()
    private var confirmationTimer: Timer?
    private var pendingTargetMode: DisplayModeSupport.DisplayModeItem?
    private var previousActiveMode: DisplayModeSupport.DisplayModeItem?

    private init() {}

    /// Refreshes available modes for the specified display (defaults to main display).
    func refreshModes(for displayID: CGDirectDisplayID = CGMainDisplayID()) {
        let modes = DisplayModeSupport.enumerateModes(for: displayID)
        availableModes = DisplayModeSupport.filterUsableModes(modes)

        if let currentCGMode = CGDisplayCopyDisplayMode(displayID) {
            let curWidth = Int(CGDisplayModeGetWidth(currentCGMode))
            let curHeight = Int(CGDisplayModeGetHeight(currentCGMode))
            let curRefresh = Double(CGDisplayModeGetRefreshRate(currentCGMode))
            currentMode = availableModes.first(where: { abs($0.width - curWidth) < 2 && abs($0.height - curHeight) < 2 })
                ?? DisplayModeSupport.DisplayModeItem(id: -1, cgMode: currentCGMode, width: curWidth, height: curHeight, refreshRate: curRefresh, isInterlaced: false, isUsable: true)
        }
    }

    /// Applies a display mode with a timeout confirmation safety mechanism.
    func applyMode(_ mode: DisplayModeSupport.DisplayModeItem, displayID: CGDirectDisplayID = CGMainDisplayID()) {
        guard mode.isUsable, let cgMode = mode.cgMode else { return }
        guard let current = currentMode else { return }

        previousActiveMode = current
        pendingTargetMode = mode

        // Attempt setting display mode
        let result = CGDisplaySetDisplayMode(displayID, cgMode, nil)
        guard result == .success else {
            Self.log.error("Failed to set display mode: error \(result.rawValue)")
            return
        }

        rollbackState.startPending(currentWidth: current.width, currentHeight: current.height,
                                   targetWidth: mode.width, targetHeight: mode.height)
        confirmationState = rollbackState.status
        currentMode = mode

        startConfirmationCountdown(displayID: displayID)
    }

    /// Confirms the current resolution change, cancelling the rollback timer.
    func confirmModeChange() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        rollbackState.confirm()
        confirmationState = rollbackState.status
        pendingTargetMode = nil
        previousActiveMode = nil
        Self.log.log("Display mode change confirmed by user.")
    }

    /// Rolls back immediately to the previous resolution mode.
    func rollbackModeChange(displayID: CGDirectDisplayID = CGMainDisplayID()) {
        confirmationTimer?.invalidate()
        confirmationTimer = nil

        if let prev = previousActiveMode, let cgMode = prev.cgMode {
            _ = CGDisplaySetDisplayMode(displayID, cgMode, nil)
            currentMode = prev
            Self.log.log("Rolled back display mode to \(prev.width)x\(prev.height)")
        }

        rollbackState.status = .rolledBack(width: previousActiveMode?.width ?? 0, height: previousActiveMode?.height ?? 0)
        confirmationState = rollbackState.status
        pendingTargetMode = nil
        previousActiveMode = nil
    }

    private func startConfirmationCountdown(displayID: CGDirectDisplayID) {
        confirmationTimer?.invalidate()
        let interval: TimeInterval = 1.0
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let tickResult = self.rollbackState.tick(elapsed: interval)
            self.confirmationState = self.rollbackState.status
            if tickResult.didRollback {
                timer.invalidate()
                self.confirmationTimer = nil
                if let prev = self.previousActiveMode, let cgMode = prev.cgMode {
                    _ = CGDisplaySetDisplayMode(displayID, cgMode, nil)
                    self.currentMode = prev
                }
                Self.log.log("Resolution change confirmation timed out. Rolled back automatically.")
            }
        }
    }
}
