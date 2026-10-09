// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-07 (Visual multi-display arrangement):
/// covers display arrangement coordinate calculations, drag-to-position clamping,
/// edge/grid snapping, main display assignment, and layout preview/apply/rollback logic.
enum DisplayArrangementTests {
    struct DisplayNode: Identifiable, Equatable {
        let id: UInt32
        var name: String
        var frame: CGRect
        var isMain: Bool
    }

    struct ArrangementLayout: Equatable {
        var displays: [DisplayNode]

        var virtualBounds: CGRect {
            guard !displays.isEmpty else { return .zero }
            var combined = displays[0].frame
            for display in displays.dropFirst() {
                combined = combined.union(display.frame)
            }
            return combined
        }
    }

    struct DragClamper {
        static func clamp(position: CGPoint, displaySize: CGSize, canvasBounds: CGRect) -> CGPoint {
            let minX = canvasBounds.minX
            let minY = canvasBounds.minY
            let maxX = canvasBounds.maxX - displaySize.width
            let maxY = canvasBounds.maxY - displaySize.height
            let clampedX = min(max(position.x, minX), max(minX, maxX))
            let clampedY = min(max(position.y, minY), max(minY, maxY))
            return CGPoint(x: clampedX, y: clampedY)
        }
    }

    struct Snapper {
        static let snapThreshold: CGFloat = 12.0
        static let gridSize: CGFloat = 20.0

        static func snap(frame: CGRect, against others: [CGRect], gridEnabled: Bool = true) -> CGRect {
            var x = frame.origin.x
            var y = frame.origin.y

            // Edge snapping against other displays
            for other in others {
                // Left edge to left/right
                if abs(x - other.minX) <= snapThreshold { x = other.minX }
                else if abs(x - other.maxX) <= snapThreshold { x = other.maxX }
                else if abs((x + frame.width) - other.minX) <= snapThreshold { x = other.minX - frame.width }
                else if abs((x + frame.width) - other.maxX) <= snapThreshold { x = other.maxX - frame.width }

                // Top edge to top/bottom
                if abs(y - other.minY) <= snapThreshold { y = other.minY }
                else if abs(y - other.maxY) <= snapThreshold { y = other.maxY }
                else if abs((y + frame.height) - other.minY) <= snapThreshold { y = other.minY - frame.height }
                else if abs((y + frame.height) - other.maxY) <= snapThreshold { y = other.maxY - frame.height }
            }

            // Grid snapping if no edge snap occurred or combined
            if gridEnabled {
                x = (x / gridSize).rounded() * gridSize
                y = (y / gridSize).rounded() * gridSize
            }

            return CGRect(x: x, y: y, width: frame.width, height: frame.height)
        }
    }

    struct LayoutManager {
        var layout: ArrangementLayout
        var previousLayout: ArrangementLayout?
        var isPreviewing: Bool = false
        var rollbackTimeout: Double = 10.0

        mutating func assignMainDisplay(id: UInt32) {
            guard let mainIdx = layout.displays.firstIndex(where: { $0.id == id }) else { return }
            let oldMainFrame = layout.displays[mainIdx].frame
            // Shift all displays so the new main display is at (0, 0)
            let delta = CGVector(dx: -oldMainFrame.origin.x, dy: -oldMainFrame.origin.y)
            for i in layout.displays.indices {
                layout.displays[i].isMain = (layout.displays[i].id == id)
                layout.displays[i].frame.origin.x += delta.dx
                layout.displays[i].frame.origin.y += delta.dy
            }
        }

        mutating func previewLayout(_ newLayout: ArrangementLayout) -> Bool {
            previousLayout = layout
            layout = newLayout
            isPreviewing = true
            return true
        }

        mutating func applyLayout() {
            isPreviewing = false
            previousLayout = nil
        }

        mutating func rollbackLayout() {
            if let prev = previousLayout {
                layout = prev
            }
            isPreviewing = false
            previousLayout = nil
        }
    }

    static func run(_ suite: TestSuite) {
        // 1. Coordinate calculations & virtual bounds
        let d1 = DisplayNode(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true)
        let d2 = DisplayNode(id: 2, name: "External", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), isMain: false)
        let arrangement = ArrangementLayout(displays: [d1, d2])

        let virtual = arrangement.virtualBounds
        suite.expect(virtual == CGRect(x: 0, y: 0, width: 4480, height: 1440), "virtual desktop bounds span all displays correctly")

        // 2. Drag-to-position clamping
        let canvas = CGRect(x: -2000, y: -2000, width: 8000, height: 8000)
        let clampedOut = DragClamper.clamp(position: CGPoint(x: -5000, y: 9000), displaySize: CGSize(width: 800, height: 600), canvasBounds: canvas)
        suite.expect(clampedOut.x == -2000 && clampedOut.y == 7400, "clamp enforces canvas boundaries correctly during drag")

        let clampedNormal = DragClamper.clamp(position: CGPoint(x: 500, y: 300), displaySize: CGSize(width: 800, height: 600), canvasBounds: canvas)
        suite.expect(clampedNormal.x == 500 && clampedNormal.y == 300, "clamp leaves valid drag positions untouched")

        // 3. Edge and grid snapping
        let otherRects = [CGRect(x: 1920, y: 0, width: 2560, height: 1440)]
        let testFrame = CGRect(x: 1925, y: 22, width: 1920, height: 1080)
        let snapped = Snapper.snap(frame: testFrame, against: otherRects, gridEnabled: false)
        suite.expect(snapped.origin.x == 1920 && snapped.origin.y == 20, "snaps edges to adjacent display and grid correctly")

        // 4. Main display assignment & coordinate normalization
        var mgr = LayoutManager(layout: arrangement)
        mgr.assignMainDisplay(id: 2)
        suite.expect(mgr.layout.displays.first(where: { $0.id == 2 })?.isMain == true, "assigns main display flag correctly")
        suite.expect(mgr.layout.displays.first(where: { $0.id == 2 })?.frame.origin == .zero, "shifts main display origin to (0,0)")
        suite.expect(mgr.layout.displays.first(where: { $0.id == 1 })?.frame.origin == CGPoint(x: -1920, y: 0), "adjusts secondary display relative coordinates correctly")

        // 5. Layout preview, apply, and rollback logic
        let modifiedLayout = ArrangementLayout(displays: [
            DisplayNode(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 1080, width: 1920, height: 1080), isMain: true),
            DisplayNode(id: 2, name: "External", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440), isMain: false)
        ])

        var previewMgr = LayoutManager(layout: arrangement)
        _ = previewMgr.previewLayout(modifiedLayout)
        suite.expect(previewMgr.isPreviewing && previewMgr.layout == modifiedLayout, "previewing layout updates state temporarily")

        previewMgr.rollbackLayout()
        suite.expect(!previewMgr.isPreviewing && previewMgr.layout == arrangement, "rollback restores previous layout successfully")

        _ = previewMgr.previewLayout(modifiedLayout)
        previewMgr.applyLayout()
        suite.expect(!previewMgr.isPreviewing && previewMgr.layout == modifiedLayout, "applying layout commits changes permanently")
    }
}
