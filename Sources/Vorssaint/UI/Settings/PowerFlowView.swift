// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Sankey-style animated Power Flow diagram showing energy flow from source(s)
/// on the left (Wall Charger / Battery) to destination(s) on the right (Battery / Mac System).
public struct PowerFlowView: View {
    @ObservedObject private var batteryManager = BatteryManager.shared
    @State private var phase: CGFloat = 0.0

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            // Top Controls Bar (Charge Limiter + Top Up)
            topControlsHeader

            // Power Flow Sankey Graphic Container
            sankeyDiagram
                .frame(height: 180)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase -= 20
            }
        }
    }

    // MARK: - Top Controls Header
    private var topControlsHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Limit: \(batteryManager.chargeLimit)%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                Button {
                    batteryManager.toggleTopUp()
                } label: {
                    HStack(spacing: 4) {
                        Text("Top Up")
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: batteryManager.isTopUpActive ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(batteryManager.isTopUpActive ? Color.accentColor : Color.secondary.opacity(0.15))
                    .foregroundStyle(batteryManager.isTopUpActive ? Color.white : Color.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Interactive Charge Limit Slider Bar
            HStack(spacing: 10) {
                Image(systemName: batteryManager.isPluggedIn ? "powerplug.fill" : "battery.100")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))

                Slider(value: Binding(
                    get: { Double(batteryManager.chargeLimit) },
                    set: { batteryManager.chargeLimit = Int($0) }
                ), in: 50...100, step: 5)
                .accentColor(.green)

                Text("\(batteryManager.chargeLimit)%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Sankey Diagram Component
    private var sankeyDiagram: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height

            let leftX = width * 0.18
            let rightX = width * 0.82

            let isPlugged = batteryManager.isPluggedIn
            let isCharging = batteryManager.isCharging
            let isDischarging = batteryManager.isDischarging

            HStack(spacing: 0) {
                // Left Source Card
                VStack {
                    if isPlugged {
                        VStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.yellow)
                            Text(String(format: "%.1fW", batteryManager.wallWatts))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                    } else {
                        VStack(spacing: 4) {
                            Image(systemName: "battery.100.bolt")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Color.green)
                            Text(String(format: "%.1fW", batteryManager.macWatts))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                    }
                }
                .frame(width: width * 0.18, height: height * 0.85)
                .background(Color.secondary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()

                // Right Destination Cards
                VStack(spacing: 12) {
                    // Battery Sink
                    HStack(spacing: 6) {
                        Text(String(format: "%.2f W", abs(batteryManager.batteryWatts)))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: isCharging ? "battery.100.bolt" : "battery.75")
                            .font(.system(size: 16))
                            .foregroundStyle(isCharging ? .green : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: width * 0.22, height: height * 0.38)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Mac System Sink
                    HStack(spacing: 6) {
                        Text(String(format: "%.2f W", batteryManager.macWatts))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Spacer()
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 10)
                    .frame(width: width * 0.22, height: height * 0.38)
                    .background(Color.secondary.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .overlay(
                // Animated Curved Streams
                Canvas { context, size in
                    let leftCenter = CGPoint(x: leftX, y: size.height / 2)
                    let topRightCenter = CGPoint(x: rightX, y: size.height * 0.28)
                    let bottomRightCenter = CGPoint(x: rightX, y: size.height * 0.72)

                    // Stream to Battery
                    if isCharging || isDischarging {
                        var path1 = Path()
                        path1.move(to: leftCenter)
                        path1.addCurve(to: topRightCenter,
                                       control1: CGPoint(x: size.width * 0.5, y: leftCenter.y),
                                       control2: CGPoint(x: size.width * 0.5, y: topRightCenter.y))

                        let strokeStyle1 = StrokeStyle(lineWidth: 18, lineCap: .round, dash: [10, 10], dashPhase: phase)
                        context.stroke(path1, with: .color(Color.secondary.opacity(0.35)), style: strokeStyle1)
                    }

                    // Stream to Mac System
                    var path2 = Path()
                    path2.move(to: leftCenter)
                    path2.addCurve(to: bottomRightCenter,
                                   control1: CGPoint(x: size.width * 0.5, y: leftCenter.y),
                                   control2: CGPoint(x: size.width * 0.5, y: bottomRightCenter.y))

                    let strokeStyle2 = StrokeStyle(lineWidth: 24, lineCap: .round, dash: [12, 12], dashPhase: phase)
                    context.stroke(path2, with: .color(Color.secondary.opacity(0.35)), style: strokeStyle2)
                }
            )
        }
    }
}
