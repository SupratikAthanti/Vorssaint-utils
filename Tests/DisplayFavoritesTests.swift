// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DisplayFavoritesTests {
    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.displayFavorites.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = DisplayServiceContracts.DisplayFavoritesService(defaults: defaults)
        let mode = DisplayServiceContracts.DisplayFavoritesService.FavoriteMode(id: UUID(), displayFingerprint: "a", width: 1920,
                                                        height: 1080, refreshRate: 60, name: "Desk")
        service.saveFavorite(mode); service.saveFavorite(mode)
        suite.expect(service.favorites(for: "a") == [mode], "production favorites deduplicate repeated saves")
        suite.expect(DisplayServiceContracts.DisplayFavoritesService(defaults: defaults).favorites(for: "a") == [mode],
                     "production favorites persist without standard defaults")
        for level in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            suite.expect(!service.validateTrigger(action: .brightness(level: level), onlineFingerprints: ["a"]).isValid,
                         "production validator refuses invalid brightness: \(level)")
        }
        suite.expect(service.validateTrigger(action: .brightness(level: 0.5), onlineFingerprints: ["a"]).isValid,
                     "production validator accepts valid brightness")
        suite.expect(service.validateTrigger(action: .displayMode(favoriteID: mode.id), onlineFingerprints: ["a"]).isValid
                     && !service.validateTrigger(action: .displayMode(favoriteID: mode.id), onlineFingerprints: []).isValid,
                     "production mode validation requires the connected target")
        suite.expect(!service.validateTrigger(action: .profile(profileName: " \n"), onlineFingerprints: []).isValid,
                     "production profile validator refuses whitespace names")
        suite.expect(!service.validateTrigger(action: .rotation(angle: 45), onlineFingerprints: []).isValid,
                     "production rotation validator refuses unsupported angles")
        let binding = DisplayServiceContracts.DisplayFavoritesService.HotkeyBinding(id: UUID(), keyCombination: "ctrl+opt+m",
                                                            action: .displayMode(favoriteID: mode.id))
        service.registerBinding(binding)
        suite.expect(DisplayServiceContracts.DisplayFavoritesService(defaults: defaults).binding(for: binding.keyCombination) == binding,
                     "production hotkey bindings round trip")
    }
}
