// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DisplayGroupTests {
    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.displayGroups.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = DisplayServiceContracts.DisplayGroupService(defaults: defaults)
        typealias Member = DisplayServiceContracts.DisplayGroupService.DisplayMember
        func member(_ fingerprint: String, nits: Double, capable: Bool = true) -> Member {
            Member(id: UUID(), fingerprint: fingerprint, name: fingerprint,
                   capabilities: capable ? [.hardwareBrightness, .softwareImageControls, .uiScale] : [],
                   brightness: 0.8, perceivedNits: nits, softwareImageControlValue: 0.5,
                   uiScale: 1, isIndividualOverride: false)
        }
        var displays = ["a": member("a", nits: 500), "b": member("b", nits: 400), "c": member("c", nits: 0, capable: false)]
        let group = service.createGroup(name: "Desk", fingerprints: ["a", "b", "c"], matchPerceivedBrightness: true)
        service.updateControl(for: "a", displays: &displays, brightness: 0.4, imageControl: 0.8, uiScale: 1.5)
        suite.expectClose(displays["b"]!.brightness, 0.5, "production group normalizes brightness by perceived nits")
        suite.expect(displays["b"]?.softwareImageControlValue == 0.8 && displays["b"]?.uiScale == 1.5,
                     "production group synchronizes supported controls")
        suite.expect(displays["c"]?.brightness == 0.8 && displays["c"]?.softwareImageControlValue == 0.5,
                     "production group preserves unsupported controls")
        service.setIndividualOverride(for: "b", override: true)
        service.updateControl(for: "a", displays: &displays, brightness: 0.2)
        suite.expect(displays["b"]?.brightness == 0.5, "production member override prevents propagation")
        service.setIndividualOverride(for: "b", override: false)
        service.setGroupEnabled(groupID: group.id, enabled: false)
        service.updateControl(for: "a", displays: &displays, brightness: 0.1)
        suite.expect(displays["b"]?.brightness == 0.5, "disabled production groups do not propagate")
        service.setGroupEnabled(groupID: group.id, enabled: true)
        displays.removeValue(forKey: "c")
        service.updateControl(for: "a", displays: &displays, brightness: 0.4)
        suite.expect(displays["b"]?.brightness == 0.5, "a missing group member does not block connected members")
        suite.expect(DisplayServiceContracts.DisplayGroupService(defaults: defaults).groups == service.groups,
                     "production groups persist in an isolated preference suite")
    }
}
