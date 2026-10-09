// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure logic and CoreGraphics wrappers for BD-07 (Visual multi-display arrangement):
/// coordinate calculations, drag-to-position clamping, edge/grid snapping, main display assignment,
/// and layout preview/apply/rollback logic.
enum DisplayArrangementSupport {
    struct DisplayItem: Identifiable, Equatable {
        let id: CGDirectDisplayID
        var name: String
        var frame: CGRect // virtual desktop frame (origin and size)
        var isMain: Bool
        var pixelWidth: Int
        var pixelHeight: Int

        static func == (lhs: DisplayItem, rhs: DisplayItem) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name && lhs.frame == rhs.frame && lhs.isMain == rhs.isMain
        }
    }

    struct ArrangementLayout: Equatable {
        var displays: [DisplayItem]

        var virtualBounds: CGRect {
            guard !displays.isEmpty else { return .zero }
            var combined = displays[0].frame
            for display in displays.dropFirst() {
                combined = combined.union(display.frame)
            }
            return combined
        }
    }

    /// Clamps drag position within virtual canvas boundaries.
    static func clamp(position: CGPoint, displaySize: CGSize, canvasBounds: CGRect) -> CGPoint {
        let minX = canvasBounds.minX
        let minY = canvasBounds.minY
        let maxX = canvasBounds.maxX - displaySize.width
        let maxY = canvasBounds.maxY - displaySize.height
        let clampedX = min(max(position.x, minX), max(minX, maxX))
        let clampedY = min(max(position.y, minY), max(minY, maxY))
        return CGPoint(x: clampedX, y: clampedY)
    }

    /// Snaps display frame edges against other display edges and/or grid.
    static func snap(frame: CGRect, against others: [CGRect], snapThreshold: CGFloat = 12.0, gridSize: CGFloat = 20.0, gridEnabled: Bool = true) -> CGRect {
        var x = frame.origin.x
        var y = frame.origin.y

        for other in others {
            if abs(x - other.minX) <= snapThreshold { x = other.minX }
            else if abs(x - other.maxX) <= snapThreshold { x = other.maxX }
            else if abs((x + frame.width) - other.minX) <= snapThreshold { x = other.minX - frame.width }
            else if abs((x + frame.width) - other.maxX) <= snapThreshold { x = other.maxX - frame.width }

            if abs(y - other.minY) <= snapThreshold { y = other.minY }
            else if abs(y - other.maxY) <= snapThreshold { y = other.maxY }
            else if abs((y + frame.height) - other.minY) <= snapThreshold { y = other.minY - frame.height }
            else if abs((y + frame.height) - other.maxY) <= snapThreshold { y = other.maxY - frame.height }
        }

        if gridEnabled {
            x = (x / gridSize).rounded() * gridSize
            y = (y / gridSize).rounded() * gridSize
        }

        return CGRect(x: x, y: y, width: frame.width, height: frame.height)
    }

    /// Shifts all displays in layout so the specified display ID is assigned as main at origin (0,0).
    static func assignMainDisplay(in layout: ArrangementLayout, displayID: CGDirectDisplayID) -> ArrangementLayout {
        var updated = layout
        guard let mainIdx = updated.displays.firstIndex(where: { $0.id == displayID }) else { return layout }
        let oldMainFrame = updated.displays[mainIdx].frame
        let delta = CGVector(dx: -oldMainFrame.origin.x, dy: -oldMainFrame.origin.y)

        for i in updated.displays.indices {
            updated.displays[i].isMain = (updated.displays[i].id == displayID)
            updated.displays[i].frame.origin.x += delta.dx
            updated.displays[i].frame.origin.y += delta.dy
        }
        return updated
    }

    /// Rollback safety manager for display arrangement changes.
    struct RollbackState: Equatable {
        enum Status: Equatable {
            case normal
            case pendingConfirmation(secondsRemaining: Double)
            case confirmed
            case rolledBack
        }

        var status: Status = .normal
        var timeoutDuration: Double = 15.0

        mutating func startPending() {
            status = .pendingConfirmation(secondsRemaining: timeoutDuration)
        }

        mutating func confirm() {
            if case .pendingConfirmation = status {
                status = .confirmed
            }
        }

        mutating func tick(elapsed: Double) -> Bool {
            guard case .pendingConfirmation(var remaining) = status else { return false }
            remaining -= elapsed
            if remaining <= 0 {
                status = .rolledBack
                return true
            } else {
                status = .pendingConfirmation(secondsRemaining: remaining)
                return false
            }
        }
    }
}
