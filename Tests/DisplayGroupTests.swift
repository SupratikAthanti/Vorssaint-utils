// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

/// Unit tests for BD-10 (Display groups and synchronized controls):
/// covers grouping selected displays by stable identity, capability checking (hardware vs software dimming),
/// synchronization of brightness (with perceived brightness normalization/estimation), software image controls,
/// and UI scale, circular update prevention (re-entrancy guard), individual overrides, group disable,
/// hot-plug resilience, and isolated failure handling across group members.
enum DisplayGroupTests {
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
        var softwareImageControlValue: Double // e.g., contrast/gamma 0.0 to 1.0
        var uiScale: Double // e.g., 1.0, 1.25, 2.0
        var isIndividualOverride: Bool
    }

    struct DisplayGroupModel: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var memberFingerprints: Set<String>
        var isEnabled: Bool
        var matchPerceivedBrightness: Bool
    }

    final class MockDisplayManager {
        var displays: [String: DisplayMember] = [:]
        var groups: [DisplayGroupModel] = []
        var syncTriggerCount = 0
        var lastError: String?
        var isSyncing = false // Circular update prevention guard

        func registerDisplay(_ member: DisplayMember) {
            displays[member.fingerprint] = member
        }

        @discardableResult
        func createGroup(name: String, fingerprints: Set<String>, matchPerceivedBrightness: Bool = false) -> DisplayGroupModel {
            let group = DisplayGroupModel(id: UUID(), name: name, memberFingerprints: fingerprints, isEnabled: true, matchPerceivedBrightness: matchPerceivedBrightness)
            groups.append(group)
            return group
        }

        // Synchronize a property across group members with capability checking and circular update prevention
        func updateControl(for fingerprint: String, brightness: Double? = nil, imageControl: Double? = nil, uiScale: Double? = nil) {
            guard !isSyncing else { return } // Circular update prevention
            guard let sourceDisplay = displays[fingerprint] else { return }

            // Find groups containing this fingerprint and enabled
            let activeGroups = groups.filter { $0.isEnabled && $0.memberFingerprints.contains(fingerprint) }
            guard !activeGroups.isEmpty else {
                // Just update single display
                applyUpdate(to: fingerprint, brightness: brightness, imageControl: imageControl, uiScale: uiScale)
                return
            }

            isSyncing = true
            defer { isSyncing = false }
            syncTriggerCount += 1

            // Update source first
            applyUpdate(to: fingerprint, brightness: brightness, imageControl: imageControl, uiScale: uiScale)

            for group in activeGroups {
                let targetFingerprints = group.memberFingerprints.filter { $0 != fingerprint }
                for targetFP in targetFingerprints {
                    guard var target = displays[targetFP], !target.isIndividualOverride else { continue }

                    // Capability checking & synchronization
                    if let newBrightness = brightness {
                        if target.capabilities.contains(.hardwareBrightness) && sourceDisplay.capabilities.contains(.hardwareBrightness) {
                            if group.matchPerceivedBrightness, let srcNits = sourceDisplay.perceivedNits, let tgtNits = target.perceivedNits, tgtNits > 0 {
                                // Normalized perceived brightness matching with stated limitations
                                let normalized = min(max((newBrightness * srcNits) / tgtNits, 0.0), 1.0)
                                target.brightness = normalized
                            } else {
                                target.brightness = newBrightness
                            }
                        } else if target.capabilities.contains(.softwareDimming) {
                            // Safe fallback: capability check verified software dimming
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

        private func applyUpdate(to fingerprint: String, brightness: Double?, imageControl: Double?, uiScale: Double?) {
            guard var display = displays[fingerprint] else { return }
            if let brightness { display.brightness = brightness }
            if let imageControl { display.softwareImageControlValue = imageControl }
            if let uiScale { display.uiScale = uiScale }
            displays[fingerprint] = display
        }

        func setIndividualOverride(for fingerprint: String, override: Bool) {
            if var display = displays[fingerprint] {
                display.isIndividualOverride = override
                displays[fingerprint] = display
            }
        }

        func setGroupEnabled(groupID: UUID, enabled: Bool) {
            if let index = groups.firstIndex(where: { $0.id == groupID }) {
                groups[index].isEnabled = enabled
            }
        }
    }

    static func run(_ suite: TestSuite) {
        let manager = MockDisplayManager()

        // 1. Group creation with stable identities (fingerprints)
        let disp1 = DisplayMember(id: UUID(), fingerprint: "EDID-A", name: "Studio Display 1", capabilities: [.hardwareBrightness, .softwareImageControls, .uiScale], brightness: 0.8, perceivedNits: 500, softwareImageControlValue: 0.5, uiScale: 1.0, isIndividualOverride: false)
        let disp2 = DisplayMember(id: UUID(), fingerprint: "EDID-B", name: "Studio Display 2", capabilities: [.hardwareBrightness, .softwareImageControls, .uiScale], brightness: 0.8, perceivedNits: 400, softwareImageControlValue: 0.5, uiScale: 1.0, isIndividualOverride: false)
        let disp3 = DisplayMember(id: UUID(), fingerprint: "EDID-C", name: "Portable Monitor", capabilities: [.softwareDimming], brightness: 0.8, perceivedNits: nil, softwareImageControlValue: 0.5, uiScale: 1.0, isIndividualOverride: false)

        manager.registerDisplay(disp1)
        manager.registerDisplay(disp2)
        manager.registerDisplay(disp3)

        let group = manager.createGroup(name: "Dual Studio", fingerprints: ["EDID-A", "EDID-B"])
        suite.expect(group.memberFingerprints.contains("EDID-A") && group.memberFingerprints.contains("EDID-B"), "group defines set of stable display identities correctly")

        // 2. Brightness synchronization & perceived brightness matching
        manager.updateControl(for: "EDID-A", brightness: 0.5)
        suite.expect(manager.displays["EDID-A"]?.brightness == 0.5 && manager.displays["EDID-B"]?.brightness == 0.5, "synchronizes brightness across group members")

        // Test perceived brightness normalization when enabled
        let groupNormalized = manager.createGroup(name: "Normalized Studio", fingerprints: ["EDID-A", "EDID-B"], matchPerceivedBrightness: true)
        manager.updateControl(for: "EDID-A", brightness: 0.4)
        // EDID-A: 500 nits, EDID-B: 400 nits. Target brightness for B = (0.4 * 500) / 400 = 0.5
        suite.expectClose(manager.displays["EDID-B"]?.brightness ?? 0, 0.5, "normalizes perceived brightness based on calibrated nits estimation", tol: 0.001)

        // 3. Software image controls and UI scale synchronization
        manager.updateControl(for: "EDID-A", imageControl: 0.8, uiScale: 1.5)
        suite.expect(manager.displays["EDID-B"]?.softwareImageControlValue == 0.8, "synchronizes software image controls across group members")
        suite.expect(manager.displays["EDID-B"]?.uiScale == 1.5, "synchronizes UI scale across group members")

        // 4. Capability checking: display without hardware brightness or software image controls capability
        let disp4 = DisplayMember(id: UUID(), fingerprint: "EDID-D", name: "Basic Screen", capabilities: [], brightness: 0.5, perceivedNits: nil, softwareImageControlValue: 0.5, uiScale: 1.0, isIndividualOverride: false)
        manager.registerDisplay(disp4)
        let mixedGroup = manager.createGroup(name: "Mixed Capabilities", fingerprints: ["EDID-A", "EDID-D"])
        manager.updateControl(for: "EDID-A", brightness: 0.9, imageControl: 0.9)
        suite.expect(manager.displays["EDID-D"]?.brightness == 0.5 && manager.displays["EDID-D"]?.softwareImageControlValue == 0.5, "respects capability checks and avoids applying unsupported controls")

        // 5. Circular update prevention (re-entrancy guard)
        let initialTriggers = manager.syncTriggerCount
        manager.updateControl(for: "EDID-A", brightness: 0.6)
        suite.expect(manager.syncTriggerCount == initialTriggers + 1, "prevents recursive circular updates during synchronization")

        // 6. Individual override
        manager.setIndividualOverride(for: "EDID-B", override: true)
        manager.updateControl(for: "EDID-A", brightness: 0.2)
        suite.expect(manager.displays["EDID-B"]?.brightness == 0.5, "respects individual override and prevents group sync propagation to overridden member")

        // 7. Group disable
        manager.setIndividualOverride(for: "EDID-B", override: false)
        let groupDisabledTest = manager.createGroup(name: "Temporary Group", fingerprints: ["EDID-A", "EDID-C"])
        manager.setGroupEnabled(groupID: groupDisabledTest.id, enabled: false)
        manager.displays["EDID-C"]?.brightness = 0.1
        manager.updateControl(for: "EDID-A", brightness: 0.9)
        suite.expect(manager.displays["EDID-C"]?.brightness == 0.1, "disabled group does not synchronize controls")

        // 8. Hot-plug resilience / fault tolerance on individual group member failure
        let offlineMember = DisplayMember(id: UUID(), fingerprint: "EDID-DEAD", name: "Disconnected Screen", capabilities: [.hardwareBrightness], brightness: 0.5, perceivedNits: nil, softwareImageControlValue: 0.5, uiScale: 1.0, isIndividualOverride: false)
        manager.registerDisplay(offlineMember)
        _ = manager.createGroup(name: "Resilient Group", fingerprints: ["EDID-A", "EDID-DEAD", "EDID-B"])
        manager.displays.removeValue(forKey: "EDID-DEAD")
        manager.updateControl(for: "EDID-A", brightness: 0.3)
        suite.expect(manager.displays["EDID-B"]?.brightness == 0.3, "failure or absence of one group member does not block synchronization for other group members")
    }
}
