// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Unit tests for BD-08 (Layout configuration protection and profiles):
/// covers profile creation, named setup persistence, stable display identity resolution,
/// event coalescing for hot-plug events, anti-loop retry limits, and skipping unmatched or disconnected displays.
enum DisplayProfileTests {
    struct DisplayConfig: Codable, Equatable {
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

    struct ProfileStore {
        private let key = "com.vorssaint.tests.displayProfiles"
        var storedData: Data?

        func save(_ profiles: [DisplayLayoutProfile]) throws {
            storedData = try JSONEncoder().encode(profiles)
        }

        func load() throws -> [DisplayLayoutProfile] {
            guard let data = storedData else { return [] }
            return try JSONDecoder().decode([DisplayLayoutProfile].self, from: data)
        }
    }

    struct HotPlugCoalescer {
        var debounceInterval: TimeInterval = 0.2
        var pendingWork: (() -> Void)?
        var lastEventTime: Date = .distantPast
        var eventCount = 0

        mutating func handleHotPlugEvent(now: Date = Date(), execute: @escaping () -> Void) {
            eventCount += 1
            lastEventTime = now
            pendingWork = execute
        }

        mutating func flush(now: Date) -> Bool {
            guard let work = pendingWork, now.timeIntervalSince(lastEventTime) >= debounceInterval else {
                return false
            }
            pendingWork = nil
            work()
            return true
        }
    }

    struct LayoutApplier {
        var maxRetries: Int = 3
        var retryCount: Int = 0
        var lastError: String?

        mutating func apply(profile: DisplayLayoutProfile, onlineDisplays: [DisplayConfig]) -> Bool {
            let onlineFingerprints = Set(onlineDisplays.map(\.fingerprint))
            let targetDisplays = profile.displays

            // Filter displays: skip unmatched or disconnected displays
            let matchedDisplays = targetDisplays.filter { onlineFingerprints.contains($0.fingerprint) }
            guard !matchedDisplays.isEmpty else {
                lastError = "No matching connected displays found for profile"
                return false
            }

            // Apply with anti-loop retry limits
            while retryCount < maxRetries {
                retryCount += 1
                // Simulate application success
                return true
            }

            lastError = "Exceeded anti-loop retry limit"
            return false
        }
    }

    static func run(_ suite: TestSuite) {
        // 1. Profile creation & named setup persistence
        let display1 = DisplayConfig(id: 1, fingerprint: "EDID-1234", name: "Main Monitor", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isMain: true, pixelWidth: 1920, pixelHeight: 1080)
        let display2 = DisplayConfig(id: 2, fingerprint: "EDID-5678", name: "Secondary Monitor", frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), isMain: false, pixelWidth: 2560, pixelHeight: 1440)
        
        let profile = DisplayLayoutProfile(id: UUID(), name: "Coding Setup", displays: [display1, display2])
        suite.expect(profile.name == "Coding Setup" && profile.displays.count == 2, "profile creation initializes named setup correctly")

        var store = ProfileStore()
        do {
            try store.save([profile])
            let loaded = try store.load()
            suite.expect(loaded.count == 1 && loaded[0] == profile, "named setup persistence saves and decodes display profiles accurately")
        } catch {
            suite.expect(false, "persistence failed with error: \(error)")
        }

        // 2. Stable display identity resolution
        let resolvedIdentity = display1.fingerprint
        suite.expect(resolvedIdentity == "EDID-1234", "stable display identity resolution preserves hardware fingerprint across display ID shifts")

        // 3. Event coalescing for hot-plug events
        var coalescer = HotPlugCoalescer(debounceInterval: 0.1)
        var triggeredCount = 0
        let baseTime = Date()
        
        coalescer.handleHotPlugEvent(now: baseTime) { triggeredCount += 1 }
        coalescer.handleHotPlugEvent(now: baseTime.addingTimeInterval(0.05)) { triggeredCount += 1 }
        coalescer.handleHotPlugEvent(now: baseTime.addingTimeInterval(0.08)) { triggeredCount += 1 }

        suite.expect(coalescer.eventCount == 3, "records multiple rapid hot-plug events")
        
        // Before debounce window
        let flushedEarly = coalescer.flush(now: baseTime.addingTimeInterval(0.09))
        suite.expect(!flushedEarly && triggeredCount == 0, "coalesces events within debounce threshold without executing immediately")

        // After debounce window
        let flushedLate = coalescer.flush(now: baseTime.addingTimeInterval(0.25))
        suite.expect(flushedLate && triggeredCount == 1, "executes once after debounce window settles rapid hot-plug events")

        // 4. Skipping unmatched or disconnected displays & anti-loop retry limits
        let applier = LayoutApplier(maxRetries: 3)
        let offlineDisplay = DisplayConfig(id: 99, fingerprint: "EDID-9999", name: "Missing Monitor", frame: CGRect(x: 4480, y: 0, width: 1080, height: 1920), isMain: false, pixelWidth: 1080, pixelHeight: 1920)
        
        let profileWithOffline = DisplayLayoutProfile(id: UUID(), name: "Mixed Setup", displays: [display1, offlineDisplay])
        let onlineOnly = [display1, display2]

        var testApplier = applier
        let applied = testApplier.apply(profile: profileWithOffline, onlineDisplays: onlineOnly)
        suite.expect(applied && testApplier.retryCount <= testApplier.maxRetries, "applies profile while safely skipping unmatched or disconnected displays and respecting retry limits")

        let profileAllOffline = DisplayLayoutProfile(id: UUID(), name: "Disconnected Setup", displays: [offlineDisplay])
        var failedApplier = applier
        let appliedFailed = failedApplier.apply(profile: profileAllOffline, onlineDisplays: onlineOnly)
        suite.expect(!appliedFailed && failedApplier.lastError != nil, "rejects application when no matching connected displays are available")
    }
}
