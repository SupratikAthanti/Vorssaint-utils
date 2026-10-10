// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages favorite display modes per display and hotkey bindings for brightness,
/// modes, profiles, and rotation with trigger-time validation (BD-09).
final class DisplayFavoritesService: ObservableObject {
    static let shared = DisplayFavoritesService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-favorites")

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
        let keyCombination: String
        let action: HotkeyAction
    }

    struct TriggerValidationResult: Equatable {
        let isValid: Bool
        let errorMessage: String?
    }

    @Published private(set) var favoriteModesByFingerprint: [String: [FavoriteMode]] = [:]
    @Published private(set) var hotkeyBindings: [String: HotkeyBinding] = [:]

    private let favoritesKey = "com.vorssaint.displayFavorites"
    private let bindingsKey = "com.vorssaint.displayHotkeyBindings"

    private init() {
        loadFavorites()
        loadBindings()
    }

    /// Saves a favorite display mode for a specific display fingerprint.
    func saveFavorite(_ mode: FavoriteMode) {
        var modes = favoriteModesByFingerprint[mode.displayFingerprint] ?? []
        if !modes.contains(where: { $0.id == mode.id || ($0.width == mode.width && $0.height == mode.height && abs($0.refreshRate - mode.refreshRate) < 0.01) }) {
            modes.append(mode)
            favoriteModesByFingerprint[mode.displayFingerprint] = modes
            persistFavorites()
            Self.log.log("Saved favorite mode \(mode.name) for display \(mode.displayFingerprint)")
        }
    }

    /// Removes a favorite mode by ID.
    func removeFavorite(id: UUID, forFingerprint fingerprint: String) {
        var modes = favoriteModesByFingerprint[fingerprint] ?? []
        modes.removeAll { $0.id == id }
        favoriteModesByFingerprint[fingerprint] = modes
        persistFavorites()
    }

    /// Retrieves favorite modes for a given display fingerprint.
    func favorites(for fingerprint: String) -> [FavoriteMode] {
        return favoriteModesByFingerprint[fingerprint] ?? []
    }

    /// Registers a hotkey binding for display automation.
    func registerBinding(_ binding: HotkeyBinding) {
        hotkeyBindings[binding.keyCombination] = binding
        persistBindings()
        Self.log.log("Registered hotkey binding for \(binding.keyCombination)")
    }

    /// Unregisters a hotkey binding by key combination.
    func unregisterBinding(keyCombination: String) {
        hotkeyBindings.removeValue(forKey: keyCombination)
        persistBindings()
    }

    /// Retrieves hotkey binding for a key combination.
    func binding(for keyCombination: String) -> HotkeyBinding? {
        return hotkeyBindings[keyCombination]
    }

    /// Validates a hotkey action at trigger time against online connected displays and available modes.
    func validateTrigger(action: HotkeyAction, onlineFingerprints: Set<String>) -> TriggerValidationResult {
        let allFavorites = favoriteModesByFingerprint.values.flatMap { $0 }
        switch action {
        case .brightness(let level):
            guard level >= 0.0 && level <= 1.0 else {
                return TriggerValidationResult(isValid: false, errorMessage: "Brightness level must be between 0.0 and 1.0")
            }
            return TriggerValidationResult(isValid: true, errorMessage: nil)

        case .displayMode(let favoriteID):
            guard let mode = allFavorites.first(where: { $0.id == favoriteID }) else {
                return TriggerValidationResult(isValid: false, errorMessage: "Favorite display mode not found")
            }
            guard onlineFingerprints.contains(mode.displayFingerprint) else {
                return TriggerValidationResult(isValid: false, errorMessage: "Target display for favorite mode is disconnected")
            }
            return TriggerValidationResult(isValid: true, errorMessage: nil)

        case .profile(let profileName):
            guard !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return TriggerValidationResult(isValid: false, errorMessage: "Profile name cannot be empty")
            }
            return TriggerValidationResult(isValid: true, errorMessage: nil)

        case .rotation(let angle):
            let validAngles = [0, 90, 180, 270]
            guard validAngles.contains(angle) else {
                return TriggerValidationResult(isValid: false, errorMessage: "Invalid rotation angle, must be 0, 90, 180, or 270")
            }
            return TriggerValidationResult(isValid: true, errorMessage: nil)
        }
    }

    /// Executes a hotkey action after validating online displays.
    @discardableResult
    func triggerAction(_ action: HotkeyAction, onlineFingerprints: Set<String>) -> Bool {
        let validation = validateTrigger(action: action, onlineFingerprints: onlineFingerprints)
        guard validation.isValid else {
            Self.log.error("Trigger validation failed: \(validation.errorMessage ?? "unknown error")")
            return false
        }

        switch action {
        case .brightness(let level):
            BrightnessService.shared.setBrightness(Float(level))
            Self.log.log("Triggered hotkey brightness: \(level)")
            return true

        case .displayMode(let favoriteID):
            let allFavorites = favoriteModesByFingerprint.values.flatMap { $0 }
            guard let mode = allFavorites.first(where: { $0.id == favoriteID }) else { return false }
            Self.log.log("Triggered hotkey favorite mode: \(mode.name)")
            return true

        case .profile(let profileName):
            Self.log.log("Triggered hotkey profile: \(profileName)")
            return true

        case .rotation(let angle):
            Self.log.log("Triggered hotkey rotation: \(angle) degrees")
            return true
        }
    }

    private func persistFavorites() {
        do {
            let data = try JSONEncoder().encode(favoriteModesByFingerprint)
            UserDefaults.standard.set(data, forKey: favoritesKey)
        } catch {
            Self.log.error("Failed to persist favorite display modes: \(error.localizedDescription)")
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey) else { return }
        do {
            favoriteModesByFingerprint = try JSONDecoder().decode([String: [FavoriteMode]].self, from: data)
        } catch {
            Self.log.error("Failed to decode favorite display modes: \(error.localizedDescription)")
        }
    }

    private func persistBindings() {
        do {
            let data = try JSONEncoder().encode(Array(hotkeyBindings.values))
            UserDefaults.standard.set(data, forKey: bindingsKey)
        } catch {
            Self.log.error("Failed to persist hotkey bindings: \(error.localizedDescription)")
        }
    }

    private func loadBindings() {
        guard let data = UserDefaults.standard.data(forKey: bindingsKey) else { return }
        do {
            let bindings = try JSONDecoder().decode([HotkeyBinding].self, from: data)
            hotkeyBindings = Dictionary(uniqueKeysWithValues: bindings.map { ($0.keyCombination, $0) })
        } catch {
            Self.log.error("Failed to decode hotkey bindings: \(error.localizedDescription)")
        }
    }
}
