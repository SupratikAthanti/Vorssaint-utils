// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages BD-08 Layout configuration protection and profiles:
/// profile creation, named setup persistence, stable display identity resolution,
/// event coalescing for hot-plug events, anti-loop retry limits, and skipping unmatched or disconnected displays.
final class DisplayProfileService: ObservableObject {
    static let shared = DisplayProfileService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-profile")

    @Published private(set) var profiles: [DisplayLayoutProfile] = []
    @Published private(set) var activeProfileID: UUID?

    struct DisplayConfig: Codable, Equatable, Identifiable {
        let id: UInt32
        let fingerprint: String
        let name: String
        let frame: CGRect
        let isMain: Bool
        let pixelWidth: Int
        let pixelHeight: Int
    }

    struct DisplayLayoutProfile: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var displays: [DisplayConfig]
    }

    private let storageKey = "com.vorssaint.displayProfiles.saved"
    private var hotPlugTimer: Timer?
    private var lastHotPlugDate: Date = .distantPast
    private var retryCount = 0
    private let maxRetries = 3

    private init() {
        loadProfiles()
    }

    /// Loads saved display profiles from UserDefaults.
    func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            profiles = []
            return
        }
        do {
            profiles = try JSONDecoder().decode([DisplayLayoutProfile].self, from: data)
        } catch {
            Self.log.error("Failed to decode saved display profiles: \(error.localizedDescription)")
            profiles = []
        }
    }

    /// Saves display profiles to UserDefaults.
    func saveProfiles() {
        do {
            let data = try JSONEncoder().encode(profiles)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.log.error("Failed to encode display profiles: \(error.localizedDescription)")
        }
    }

    /// Creates and saves a new display layout profile with current online displays.
    @discardableResult
    func createProfile(name: String) -> DisplayLayoutProfile {
        let onlineDisplays = fetchOnlineDisplays()
        let profile = DisplayLayoutProfile(id: UUID(), name: name, displays: onlineDisplays)
        profiles.append(profile)
        saveProfiles()
        Self.log.log("Created and saved display profile: \(name)")
        return profile
    }

    /// Deletes a profile by ID.
    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        saveProfiles()
        if activeProfileID == id {
            activeProfileID = nil
        }
    }

    /// Applies a display layout profile, skipping unmatched or disconnected displays with anti-loop retry limits.
    func applyProfile(_ profile: DisplayLayoutProfile) -> Bool {
        let onlineDisplays = fetchOnlineDisplays()
        let onlineMap = Dictionary(uniqueKeysWithValues: onlineDisplays.map { ($0.fingerprint, $0.id) })

        // Filter: skip unmatched or disconnected displays, updating display IDs to current active CGDirectDisplayIDs
        let matchedDisplays = profile.displays.compactMap { config -> DisplayConfig? in
            guard let currentID = onlineMap[config.fingerprint] else { return nil }
            return DisplayConfig(
                id: currentID,
                fingerprint: config.fingerprint,
                name: config.name,
                frame: config.frame,
                isMain: config.isMain,
                pixelWidth: config.pixelWidth,
                pixelHeight: config.pixelHeight
            )
        }
        guard !matchedDisplays.isEmpty else {
            Self.log.error("Cannot apply profile '\(profile.name)': no online displays match profile fingerprint.")
            return false
        }

        retryCount = 0
        while retryCount < maxRetries {
            retryCount += 1
            let success = applyLayoutToSystem(displays: matchedDisplays)
            if success {
                activeProfileID = profile.id
                Self.log.log("Successfully applied profile '\(profile.name)' (attempt \(self.retryCount)).")
                return true
            }
        }

        Self.log.error("Exceeded anti-loop retry limit (\(maxRetries)) while applying profile '\(profile.name)'.")
        return false
    }

    /// Handles hot-plug display events with event coalescing (debouncing rapid events).
    func handleHotPlugEvent() {
        let now = Date()
        let interval: TimeInterval = 0.3
        
        hotPlugTimer?.invalidate()
        if now.timeIntervalSince(lastHotPlugDate) < interval {
            // Coalesce rapid events
            lastHotPlugDate = now
        } else {
            lastHotPlugDate = now
        }

        hotPlugTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Self.log.log("Hot-plug event coalesced and settled. Re-evaluating display layout...")
            self.evaluateAutoSwitch()
        }
    }

    private func evaluateAutoSwitch() {
        let onlineDisplays = fetchOnlineDisplays()
        let onlineFingerprints = Set(onlineDisplays.map(\.fingerprint))

        for profile in profiles {
            let profileFingerprints = Set(profile.displays.map(\.fingerprint))
            if profileFingerprints == onlineFingerprints {
                _ = applyProfile(profile)
                break
            }
        }
    }

    private func fetchOnlineDisplays() -> [DisplayConfig] {
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        
        guard CGGetOnlineDisplayList(maxDisplays, &displayIDs, &displayCount) == .success else {
            return []
        }

        var configs: [DisplayConfig] = []
        let mainID = CGMainDisplayID()

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            let bounds = CGDisplayBounds(id)
            let isMain = (id == mainID)
            let fingerprint = generateFingerprint(for: id)
            let name = isMain ? "Main Display" : "External Display #\(i + 1)"

            configs.append(DisplayConfig(
                id: id,
                fingerprint: fingerprint,
                name: name,
                frame: bounds,
                isMain: isMain,
                pixelWidth: Int(CGDisplayPixelsWide(id)),
                pixelHeight: Int(CGDisplayPixelsHigh(id))
            ))
        }
        return configs
    }

    private func generateFingerprint(for displayID: CGDirectDisplayID) -> String {
        let width = Int(CGDisplayPixelsWide(displayID))
        let height = Int(CGDisplayPixelsHigh(displayID))
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        return "\(vendor):\(model):\(serial):\(width)x\(height)"
    }

    private func applyLayoutToSystem(displays: [DisplayConfig]) -> Bool {
        var configRef: CGDisplayConfigRef?
        let beginResult = CGBeginDisplayConfiguration(&configRef)
        guard beginResult == .success, let ref = configRef else {
            return false
        }

        for display in displays {
            _ = CGConfigureDisplayOrigin(ref, display.id, Int32(display.frame.origin.x), Int32(display.frame.origin.y))
        }

        let completeResult = CGCompleteDisplayConfiguration(ref, kCGConfigurePermanently)
        return completeResult == .success
    }
}
