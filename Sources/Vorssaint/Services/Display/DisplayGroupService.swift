// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages BD-10 Display groups and synchronized controls:
/// grouping selected displays by stable identity, capability checking (hardware brightness vs software dimming),
/// synchronization of brightness (with perceived brightness normalization/estimation), software image controls,
/// and UI scale, circular update prevention (re-entrancy guard), individual overrides, group disable,
/// hot-plug resilience, and isolated failure handling across group members.
final class DisplayGroupService: ObservableObject {
    static let shared = DisplayGroupService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-group")

    struct DisplayCapabilities: OptionSet, Codable, Equatable {
        let rawValue: Int
        static let hardwareBrightness = DisplayCapabilities(rawValue: 1 << 0)
        static let softwareDimming = DisplayCapabilities(rawValue: 1 << 1)
        static let softwareImageControls = DisplayCapabilities(rawValue: 1 << 2)
        static let uiScale = DisplayCapabilities(rawValue: 1 << 3)
    }

    struct DisplayMember: Codable, Equatable, Identifiable {
        let id: UUID
        let fingerprint: String
        let name: String
        var capabilities: DisplayCapabilities
        var brightness: Double // 0.0 to 1.0
        var perceivedNits: Double? // For perceived brightness matching / calibration
        var softwareImageControlValue: Double // contrast/gamma 0.0 to 1.0
        var uiScale: Double // 1.0, 1.25, 2.0
        var isIndividualOverride: Bool
    }

    struct DisplayGroupModel: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var memberFingerprints: Set<String>
        var isEnabled: Bool
        var matchPerceivedBrightness: Bool
    }

    @Published private(set) var groups: [DisplayGroupModel] = []
    @Published var memberOverrides: [String: Bool] = [:] // fingerprint -> isOverridden

    private let storageKey = "com.vorssaint.displayGroups.saved"
    private var isSyncing = false // Circular update prevention guard

    private init() {
        loadGroups()
    }

    /// Loads saved display groups from UserDefaults.
    func loadGroups() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            groups = []
            return
        }
        do {
            groups = try JSONDecoder().decode([DisplayGroupModel].self, from: data)
        } catch {
            Self.log.error("Failed to decode saved display groups: \(error.localizedDescription)")
            groups = []
        }
    }

    /// Saves display groups to UserDefaults.
    func saveGroups() {
        do {
            let data = try JSONEncoder().encode(groups)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.log.error("Failed to encode display groups: \(error.localizedDescription)")
        }
    }

    /// Creates and saves a new display group.
    @discardableResult
    func createGroup(name: String, fingerprints: Set<String>, matchPerceivedBrightness: Bool = false) -> DisplayGroupModel {
        let group = DisplayGroupModel(
            id: UUID(),
            name: name,
            memberFingerprints: fingerprints,
            isEnabled: true,
            matchPerceivedBrightness: matchPerceivedBrightness
        )
        groups.append(group)
        saveGroups()
        Self.log.log("Created and saved display group: \(name)")
        return group
    }

    /// Deletes a display group by ID.
    func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        saveGroups()
    }

    /// Enables or disables a display group.
    func setGroupEnabled(groupID: UUID, enabled: Bool) {
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index].isEnabled = enabled
            saveGroups()
        }
    }

    /// Sets individual override status for a display fingerprint.
    func setIndividualOverride(for fingerprint: String, override: Bool) {
        memberOverrides[fingerprint] = override
    }

    /// Synchronizes controls across group members with capability checking, perceived brightness matching, and circular update prevention.
    func updateControl(for fingerprint: String, displays: inout [String: DisplayMember], brightness: Double? = nil, imageControl: Double? = nil, uiScale: Double? = nil) {
        guard !isSyncing else { return } // Circular update prevention (re-entrancy guard)
        guard let sourceDisplay = displays[fingerprint] else { return }

        let activeGroups = groups.filter { $0.isEnabled && $0.memberFingerprints.contains(fingerprint) }
        guard !activeGroups.isEmpty else {
            applyUpdate(to: fingerprint, displays: &displays, brightness: brightness, imageControl: imageControl, uiScale: uiScale)
            return
        }

        isSyncing = true
        defer { isSyncing = false }

        // Update source display first
        applyUpdate(to: fingerprint, displays: &displays, brightness: brightness, imageControl: imageControl, uiScale: uiScale)

        for group in activeGroups {
            let targetFingerprints = group.memberFingerprints.filter { $0 != fingerprint }
            for targetFP in targetFingerprints {
                let isOverridden = memberOverrides[targetFP] ?? displays[targetFP]?.isIndividualOverride ?? false
                guard var target = displays[targetFP], !isOverridden else { continue }

                // Capability checking & synchronization
                if let newBrightness = brightness {
                    if target.capabilities.contains(.hardwareBrightness) && sourceDisplay.capabilities.contains(.hardwareBrightness) {
                        if group.matchPerceivedBrightness, let srcNits = sourceDisplay.perceivedNits, let tgtNits = target.perceivedNits, tgtNits > 0 {
                            let normalized = min(max((newBrightness * srcNits) / tgtNits, 0.0), 1.0)
                            target.brightness = normalized
                        } else {
                            target.brightness = newBrightness
                        }
                    } else if target.capabilities.contains(.softwareDimming) {
                        // Safe fallback when software dimming is supported
                        target.brightness = newBrightness
                    }
                }

                if let newImageControl = imageControl, target.capabilities.contains(.softwareImageControls) {
                    target.softwareImageControlValue = newImageControl
                }

                if let newScale = uiScale, target.capabilities.contains(.uiScale) {
                    target.uiScale = newScale
                }

                displays[targetFP] = target
            }
        }
    }

    private func applyUpdate(to fingerprint: String, displays: inout [String: DisplayMember], brightness: Double?, imageControl: Double?, uiScale: Double?) {
        guard var display = displays[fingerprint] else { return }
        if let brightness { display.brightness = brightness }
        if let imageControl { display.softwareImageControlValue = imageControl }
        if let uiScale { display.uiScale = uiScale }
        displays[fingerprint] = display
    }
}
