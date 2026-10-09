// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Visual multi-display arrangement canvas view with drag-and-drop positioning,
/// edge/grid snapping, main display assignment, and layout preview/apply/rollback controls (BD-07).
struct DisplayArrangementCanvas: View {
    @ObservedObject var service = DisplayArrangementService.shared
    @State private var draggedDisplayID: CGDirectDisplayID? = nil
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 16) {
            // Header / Toolbar
            HStack {
                Text("Display Arrangement")
                    .font(.headline)
                Spacer()

                if service.isPreviewing {
                    HStack(spacing: 8) {
                        Text("Keep changes?")
                            .foregroundColor(.orange)
                        Button("Revert") {
                            service.rollbackLayout()
                        }
                        .buttonStyle(.bordered)
                        Button("Apply") {
                            service.applyLayout()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Button("Preview Layout") {
                        service.previewLayout()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)

            // Visual Canvas Area
            GeometryReader { geometry in
                let virtualBounds = service.layout.virtualBounds
                let scale = min(
                    (geometry.size.width - 64) / max(virtualBounds.width, 1000),
                    (geometry.size.height - 64) / max(virtualBounds.height, 800)
                )

                ZStack(alignment: .topLeading) {
                    // Background grid / workspace representation
                    Rectangle()
                        .fill(Color(.windowBackgroundColor).opacity(0.5))
                        .border(Color.secondary.opacity(0.2), width: 1)

                    // Render display cards
                    ForEach(service.layout.displays) { display in
                        DisplayCardView(
                            display: display,
                            scale: scale,
                            isMainSelected: display.isMain,
                            onMakeMain: {
                                service.assignMainDisplay(id: display.id)
                            }
                        )
                        .position(
                            x: (display.frame.midX - virtualBounds.minX) * scale + 32,
                            y: (display.frame.midY - virtualBounds.minY) * scale + 32
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let newX = display.frame.origin.x + (value.translation.width / scale)
                                    let newY = display.frame.origin.y + (value.translation.height / scale)
                                    
                                    // Check snap against other displays
                                    let otherFrames = service.layout.displays.filter { $0.id != display.id }.map(\.frame)
                                    let tentativeFrame = CGRect(x: newX, y: newY, width: display.frame.width, height: display.frame.height)
                                    let snappedFrame = DisplayArrangementSupport.snap(frame: tentativeFrame, against: otherFrames)
                                    
                                    service.updateDisplayPosition(id: display.id, newOrigin: snappedFrame.origin)
                                }
                        )
                    }
                }
                .frame(width: max(virtualBounds.width * scale + 64, geometry.size.width),
                       height: max(virtualBounds.height * scale + 64, geometry.size.height))
            }
            .frame(minHeight: 400)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)

            // Instructions footer
            Text("Drag displays to rearrange. Snap edges to align. Click 'Set as Main' to assign primary display.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
        }
    }
}

struct DisplayCardView: View {
    let display: DisplayArrangementSupport.DisplayItem
    let scale: CGFloat
    let isMainSelected: Bool
    let onMakeMain: () -> Void

    var body: some View {
        let cardWidth = max(display.frame.width * scale, 120)
        let cardHeight = max(display.frame.height * scale, 80)

        VStack(spacing: 4) {
            HStack {
                Image(systemName: isMainServiceIcon)
                    .foregroundColor(isMainSelected ? .accentColor : .secondary)
                Text(display.name)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer()
            }

            Text("\(Int(display.frame.width)) × \(Int(display.frame.height))")
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            Spacer()

            if !isMainSelected {
                Button("Set as Main") {
                    onMakeMain()
                }
                .font(.system(size: 9))
                .buttonStyle(.bordered)
                .controlSize(.mini)
            } else {
                Text("Main Display")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(8)
        .frame(width: cardWidth, height: cardHeight)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isMainSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: isMainSelected ? 2 : 1)
        )
        .shadow(radius: 2)
    }

    private var isMainServiceIcon: String {
        isMainSelected ? "rectangle.inset.filled" : "display"
    }
}
