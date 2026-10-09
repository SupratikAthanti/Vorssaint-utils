// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct DisplayProfileSettings: View {
    @ObservedObject private var service = DisplayProfileService.shared
    @State private var newProfileName = ""

    var body: some View {
        Form {
            Section("Display Profiles (BD-08)") {
                Text("Protect and restore your multi-monitor arrangements with named layout profiles, stable display identity resolution, and hot-plug coalescing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    TextField("Profile Name", text: $newProfileName)
                        .textFieldStyle(.roundedBorder)
                    Button("Save Current Layout") {
                        let trimmed = newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        service.createProfile(name: trimmed)
                        newProfileName = ""
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("Saved Profiles") {
                if service.profiles.isEmpty {
                    Text("No display profiles saved yet.")
                        .foregroundColor(.secondary)
                } else {
                    List {
                        ForEach(service.profiles) { profile in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.headline)
                                    Text("\(profile.displays.count) display(s) configured")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if service.activeProfileID == profile.id {
                                    Text("Active")
                                        .font(.caption)
                                        .padding(4)
                                        .background(Color.green.opacity(0.2))
                                        .cornerRadius(4)
                                }
                                Button("Apply") {
                                    _ = service.applyProfile(profile)
                                }
                                .controlSize(.small)
                                Button("Delete", role: .destructive) {
                                    service.deleteProfile(id: profile.id)
                                }
                                .controlSize(.small)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
