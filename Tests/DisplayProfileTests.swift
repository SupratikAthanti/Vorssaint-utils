// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DisplayProfileTests {
    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.displayProfiles.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        typealias Config = DisplayServiceContracts.DisplayProfileService.DisplayConfig
        let first = Config(id: 1, fingerprint: "monitor-a", name: "A", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                           isMain: true, pixelWidth: 1920, pixelHeight: 1080)
        let second = Config(id: 2, fingerprint: "monitor-b", name: "B", frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
                            isMain: false, pixelWidth: 1920, pixelHeight: 1080)
        var online = [first, second]
        var applications: [[Config]] = []
        var succeeds = true
        let service = DisplayServiceContracts.DisplayProfileService(defaults: defaults, onlineDisplays: { online }, applyLayout: {
            applications.append($0); return succeeds
        })
        let profile = service.createProfile(name: "Desk")
        let restored = DisplayServiceContracts.DisplayProfileService(defaults: defaults, onlineDisplays: { [] }, applyLayout: { _ in false })
        suite.expect(restored.profiles == [profile], "production profile store round trips isolated defaults")
        online = [Config(id: 42, fingerprint: first.fingerprint, name: first.name, frame: first.frame,
                         isMain: true, pixelWidth: first.pixelWidth, pixelHeight: first.pixelHeight)]
        suite.expect(service.applyProfile(profile) && applications.last?.map(\.id) == [42],
                     "production matching skips disconnected displays and resolves current IDs")
        applications = []; succeeds = false
        suite.expect(!service.applyProfile(profile) && applications.count == 3,
                     "production layout retry stops after three rejected applications")
        online = [first, Config(id: 99, fingerprint: first.fingerprint, name: "duplicate", frame: first.frame,
                                isMain: false, pixelWidth: first.pixelWidth, pixelHeight: first.pixelHeight)]
        applications = []
        suite.expect(!service.applyProfile(profile) && applications.isEmpty,
                     "duplicate physical fingerprints are refused instead of trapping or targeting an arbitrary monitor")
        online = [first]; succeeds = true
        let malformed = DisplayServiceContracts.DisplayProfileService.DisplayLayoutProfile(id: UUID(), name: "bad", displays: [
            Config(id: 1, fingerprint: first.fingerprint, name: "bad", frame: CGRect(x: Double.infinity, y: 0, width: 1, height: 1),
                   isMain: true, pixelWidth: 1, pixelHeight: 1)])
        suite.expect(!service.applyProfile(malformed) && applications.isEmpty,
                     "nonfinite persisted coordinates never reach the layout adapter")
    }
}
