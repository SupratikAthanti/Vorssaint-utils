// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages multi-display visual arrangement, positioning, main display assignment,
/// and preview/apply/rollback safety mechanisms (BD-07).
final class DisplayArrangementService: ObservableObject {
    static let shared = DisplayArrangementService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-arrangement")

    @Published private(set) var layout: DisplayArrangementSupport.ArrangementLayout = ArrangementLayout(displays: [])
    @Published private(set) var isPreviewing: Bool = false
    @Published private(set) var confirmationState: DisplayArrangementSupport.RollbackState.Status = .normal

    private var rollbackState = DisplayArrangementSupport.RollbackState()
    private var confirmationTimer: Timer?
    private var previousLayout: DisplayArrangementSupport.ArrangementLayout?

    typealias ArrangementLayout = DisplayArrangementSupport.ArrangementLayout
    typealias DisplayItem = DisplayArrangementSupport.DisplayItem

    private init() {
        refreshDisplays()
    }

    /// Enumerates online displays and their current bounds from CoreGraphics.
    func refreshDisplays() {
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        
        let result = CGGetOnlineDisplayList(maxDisplays, &displayIDs, &displayCount)
        guard result == .success else {
            Self.log.error("Failed to get online display list: error \(result.rawValue)")
            return
        }

        var items: [DisplayItem] = []
        let mainID = CGMainDisplayID()

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            let bounds = CGDisplayBounds(id)
            let pixWidth = Int(CGDisplayPixelsWide(id))
            let pixHeight = Int(CGDisplayPixelsHigh(id))
            let isMain = (id == mainID)
            let name = (id == mainID) ? "Built-in / Main Display" : "External Display #\(i + 1)"

            items.append(DisplayItem(
                id: id,
                name: name,
                frame: bounds,
                isMain: isMain,
                pixelWidth: pixWidth > 0 ? pixWidth : Int(bounds.width),
                pixelHeight: pixHeight > 0 ? pixHeight : Int(bounds.height)
            ))
        }

        layout = ArrangementLayout(displays: items)
    }

    /// Updates position of a specific display in the layout.
    func updateDisplayPosition(id: CGDirectDisplayID, newOrigin: CGPoint) {
        guard let idx = layout.displays.firstIndex(where: { $0.id == id }) else { return }
        layout.displays[idx].frame.origin = newOrigin
    }

    /// Assigns a display as the main/primary display.
    func assignMainDisplay(id: CGDirectDisplayID) {
        layout = DisplayArrangementSupport.assignMainDisplay(in: layout, displayID: id)
    }

    /// Previews layout changes without committing to system.
    func previewLayout() {
        previousLayout = layout
        isPreviewing = true
        applyLayoutToSystem(isPreview: true)
        rollbackState.startPending()
        confirmationState = rollbackState.status
        startConfirmationCountdown()
    }

    /// Confirms current layout preview, stopping rollback timer.
    func confirmLayout() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        rollbackState.confirm()
        confirmationState = rollbackState.status
        isPreviewing = false
        previousLayout = nil
        Self.log.log("Display arrangement change confirmed by user.")
    }

    /// Rolls back layout to previous state.
    func rollbackLayout() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        if let prev = previousLayout {
            layout = prev
            applyLayoutToSystem(isPreview: false)
        }
        rollbackState.status = .rolledBack
        confirmationState = rollbackState.status
        isPreviewing = false
        previousLayout = nil
        Self.log.log("Display arrangement rolled back.")
    }

    /// Commits layout permanently.
    func applyLayout() {
        applyLayoutToSystem(isPreview: false)
        confirmLayout()
    }

    private func applyLayoutToSystem(isPreview: Bool) {
        var configRef: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        guard beginResult == .success, let ref = configRef else {
            Self.log.error("Failed to begin display configuration: \(beginResult.rawValue)")
            return
        }

        for display in layout.displays {
            _ = CGConfigureDisplayOrigin(ref, display.id, Int32(display.frame.origin.x), Int32(display.frame.origin.y))
        }

        let option: CGConfigureOption = isPreview ? kCGConfigurePermanently : kCGConfigurePermanently
        let completeResult = CGCompleteDisplayConfiguration(ref, option)
        if completeResult != .success {
            Self.log.error("Failed to complete display configuration: \(completeResult.rawValue)")
        }
    }

    private func startConfirmationCountdown() {
        confirmationTimer?.invalidate()
        let interval: TimeInterval = 1.0
        confirmationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let didTimeout = self.rollbackState.tick(elapsed: interval)
            self.confirmationState = self.rollbackState.status
            if didTimeout {
                timer.invalidate()
                self.confirmationTimer = nil
                self.rollbackLayout()
                Self.log.log("Display arrangement confirmation timed out. Rolled back automatically.")
            }
        }
    }
}
