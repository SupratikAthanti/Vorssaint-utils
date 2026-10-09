// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings / Panel UI view for BD-04 (Resolution and display mode selector)
/// featuring available mode picker and timeout confirmation banner for rollbacks.
struct DisplayModeSelectorView: View {
    @ObservedObject private var service = DisplayModeService.shared
    @State private var selectedModeID: Int = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Display Resolution & Mode")
                .font(.headline)

            if service.availableModes.isEmpty {
                Text("No available display modes found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Picker("Resolution", selection: $selectedModeID) {
                    ForEach(service.availableModes) { mode in
                        Text(mode.summary).tag(mode.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModeID) { _, newID in
                    if let mode = service.availableModes.first(where: { $0.id == newID }) {
                        service.applyMode(mode)
                    }
                }
            }

            if case .pendingConfirmation(_, _, let targetW, let targetH, let remaining) = service.confirmationState {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep new resolution (\(targetW) × \(targetH))?")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Reverting automatically in \(Int(remaining.rounded()))s...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Keep") {
                        service.confirmModeChange()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Revert") {
                        service.rollbackModeChange()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
        }
        .padding()
        .onAppear {
            service.refreshModes()
            if let current = service.currentMode {
                selectedModeID = current.id
            }
        }
    }
}
