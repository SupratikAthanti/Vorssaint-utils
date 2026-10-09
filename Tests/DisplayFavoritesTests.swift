// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

/// Unit tests for BD-09 (Favorite resolutions and keyboard shortcuts):
/// covers saving favorite display modes per display, hotkey bindings for brightness, mode,
/// profile, and rotation, and validation at trigger time.
enum DisplayFavoritesTests {
    struct FavoriteMode: Codable, Equatable, Identifiable {
        let id: UUID
        let displayFingerprint: String
        let width: Int
        let height: Int
        let refreshRate: Double
        let name: String
    }

    enum HotkeyAction: Codable, Equatable {
        case brightness(level: Double)
        case displayMode(favoriteID: UUID)
        case profile(profileName: String)
        case rotation(angle: Int) // 0, 90, 180, 270
    }

    struct HotkeyBinding: Codable, Equatable, Identifiable {
        let id: UUID
        let keyCombination: String // e.g. "cmd+shift+1"
        let action: HotkeyAction
    }

    struct FavoritesStore {
        private var favoriteModes: [String: [FavoriteMode]] = [:] // fingerprint -> modes
        private var bindings: [String: HotkeyBinding] = [:] // keyCombination -> binding

        mutating func saveFavorite(_ mode: FavoriteMode) {
            var modes = favoriteModes[mode.displayFingerprint] ?? []
            if !modes.contains(where: { $0.width == mode.width && $0.height == mode.height && abs($0.refreshRate - mode.refreshRate) < 0.01 }) {
                modes.append(mode)
                favoriteModes[mode.displayFingerprint] = modes
            }
        }

        func favorites(for displayFingerprint: String) -> [FavoriteMode] {
            return favoriteModes[displayFingerprint] ?? []
        }

        mutating func registerBinding(_ binding: HotkeyBinding) {
            bindings[binding.keyCombination] = binding
        }

        func binding(for keyCombination: String) -> HotkeyBinding? {
            return bindings[keyCombination]
        }
    }

    struct TriggerValidator {
        struct ValidationResult {
            let isValid: Bool
            let errorMessage: String?
        }

        static func validate(action: HotkeyAction, onlineFingerprints: Set<String>, availableModes: [FavoriteMode]) -> ValidationResult {
            switch action {
            case .brightness(let level):
                if level < 0.0 || level > 1.0 {
                    return ValidationResult(isValid: false, errorMessage: "Brightness level must be between 0.0 and 1.0")
                }
                return ValidationResult(isValid: true, errorMessage: nil)

            case .displayMode(let favoriteID):
                guard let mode = availableModes.first(where: { $0.id == favoriteID }) else {
                    return ValidationResult(isValid: false, errorMessage: "Favorite display mode not found")
                }
                guard onlineFingerprints.contains(mode.displayFingerprint) else {
                    return ValidationResult(isValid: false, errorMessage: "Target display for favorite mode is disconnected")
                }
                return ValidationResult(isValid: true, errorMessage: nil)

            case .profile(let profileName):
                guard !profileName.isEmpty else {
                    return ValidationResult(isValid: false, errorMessage: "Profile name cannot be empty")
                }
                return ValidationResult(isValid: true, errorMessage: nil)

            case .rotation(let angle):
                let validAngles = [0, 90, 180, 270]
                guard validAngles.contains(angle) else {
                    return ValidationResult(isValid: false, errorMessage: "Invalid rotation angle, must be 0, 90, 180, or 270")
                }
                return ValidationResult(isValid: true, errorMessage: nil)
            }
        }
    }

    static func run(_ suite: TestSuite) {
        // 1. Saving favorite display modes per display
        var store = FavoritesStore()
        let fingerprint = "EDID-DISPLAY-1"
        let fav1 = FavoriteMode(id: UUID(), displayFingerprint: fingerprint, width: 2560, height: 1440, refreshRate: 144.0, name: "Gaming 144Hz")
        let fav2 = FavoriteMode(id: UUID(), displayFingerprint: fingerprint, width: 1920, height: 1080, refreshRate: 60.0, name: "Work 1080p")
        let otherFingerprint = "EDID-DISPLAY-2"
        let favOther = FavoriteMode(id: UUID(), displayFingerprint: otherFingerprint, width: 3840, height: 2160, refreshRate: 60.0, name: "4K Studio")

        store.saveFavorite(fav1)
        store.saveFavorite(fav1) // duplicate should be handled / deduplicated
        store.saveFavorite(fav2)
        store.saveFavorite(favOther)

        let display1Favorites = store.favorites(for: fingerprint)
        suite.expect(display1Favorites.count == 2, "saves and retrieves favorite modes correctly per display fingerprint")
        suite.expect(display1Favorites.contains(fav1) && display1Favorites.contains(fav2), "contains exact favorite items for display 1")
        suite.expect(store.favorites(for: otherFingerprint).count == 1, "separates favorites across different displays")

        // 2. Hotkey bindings for brightness, mode, profile, and rotation
        let brightnessBinding = HotkeyBinding(id: UUID(), keyCombination: "ctrl+opt+b", action: .brightness(level: 0.75))
        let modeBinding = HotkeyBinding(id: UUID(), keyCombination: "ctrl+opt+m", action: .displayMode(favoriteID: fav1.id))
        let profileBinding = HotkeyBinding(id: UUID(), keyCombination: "ctrl+opt+p", action: .profile(profileName: "Coding Layout"))
        let rotationBinding = HotkeyBinding(id: UUID(), keyCombination: "ctrl+opt+r", action: .rotation(angle: 90))

        store.registerBinding(brightnessBinding)
        store.registerBinding(modeBinding)
        store.registerBinding(profileBinding)
        store.registerBinding(rotationBinding)

        suite.expect(store.binding(for: "ctrl+opt+b")?.action == .brightness(level: 0.75), "registers and retrieves brightness hotkey binding")
        suite.expect(store.binding(for: "ctrl+opt+m")?.action == .displayMode(favoriteID: fav1.id), "registers and retrieves mode hotkey binding")
        suite.expect(store.binding(for: "ctrl+opt+p")?.action == .profile(profileName: "Coding Layout"), "registers and retrieves profile hotkey binding")
        suite.expect(store.binding(for: "ctrl+opt+r")?.action == .rotation(angle: 90), "registers and retrieves rotation hotkey binding")

        // 3. Validation at trigger time
        let onlineDisplays: Set<String> = [fingerprint]
        let allFavorites = [fav1, fav2, favOther]

        // Valid triggers
        let validBrightness = TriggerValidator.validate(action: .brightness(level: 0.5), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(validBrightness.isValid, "validates correct brightness level successfully")

        let validModeTrigger = TriggerValidator.validate(action: .displayMode(favoriteID: fav1.id), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(validModeTrigger.isValid, "validates connected favorite display mode successfully")

        let validProfile = TriggerValidator.validate(action: .profile(profileName: "Minimal"), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(validProfile.isValid, "validates non-empty profile name successfully")

        let validRotation = TriggerValidator.validate(action: .rotation(angle: 180), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(validRotation.isValid, "validates supported rotation angle successfully")

        // Invalid triggers / error handling
        let invalidBrightnessLow = TriggerValidator.validate(action: .brightness(level: -0.1), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(!invalidBrightnessLow.isValid && invalidBrightnessLow.errorMessage != nil, "rejects out-of-range negative brightness")

        let invalidBrightnessHigh = TriggerValidator.validate(action: .brightness(level: 1.5), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(!invalidBrightnessHigh.isValid && invalidBrightnessHigh.errorMessage != nil, "rejects out-of-range high brightness")

        let disconnectedModeTrigger = TriggerValidator.validate(action: .displayMode(favoriteID: favOther.id), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(!disconnectedModeTrigger.isValid && disconnectedModeTrigger.errorMessage != nil, "rejects favorite mode when target display is disconnected")

        let emptyProfileTrigger = TriggerValidator.validate(action: .profile(profileName: ""), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(!emptyProfileTrigger.isValid && emptyProfileTrigger.errorMessage != nil, "rejects empty profile name")

        let invalidRotationTrigger = TriggerValidator.validate(action: .rotation(angle: 45), onlineFingerprints: onlineDisplays, availableModes: allFavorites)
        suite.expect(!invalidRotationTrigger.isValid && invalidRotationTrigger.errorMessage != nil, "rejects unsupported rotation angle")
    }
}
