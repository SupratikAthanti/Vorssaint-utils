// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages BD-11 Connection/disconnection management:
/// switching between display setups, disconnect/reconnect external display hot-plug detection,
/// optionally disabling internal panel when external display is connected on compatible Apple Silicon Macs,
/// and recovery timeout / keyboard restore safeguard.
final class DisplayConnectionService: ObservableObject {
    static let shared = DisplayConnectionService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-connection")

    @Published private(set) var setups: [DisplayConnectionSupport.DisplaySetupModel] = []
    @Published private(set) var activeSetupID: UUID?
    @Published private(set) var displays: [UInt32: DisplayConnectionSupport.DisplayConnectionInfo] = [:]
    @Published private(set) var isPendingConfirmation: Bool = false
    @Published private(set) var countdownRemaining: Double = 0.0

    private let storageKey = "com.vorssaint.displayConnection.setups"
    private var recoveryTimer: Timer?
    private var hotPlugTimer: Timer?
    private let defaultRecoveryTimeout: Double = 10.0

    typealias DisplayInfo = DisplayConnectionSupport.DisplayConnectionInfo
    typealias DisplaySetup = DisplayConnectionSupport.DisplaySetupModel

    private init() {
        loadSetups()
        refreshDisplays()
    }

    /// Loads saved display setups from UserDefaults.
    func loadSetups() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            setups = []
            return
        }
        do {
            setups = try JSONDecoder().decode([DisplaySetup].self, from: data)
        } catch {
            Self.log.error("Failed to decode saved display setups: \(error.localizedDescription)")
            setups = []
        }
    }

    /// Saves display setups to UserDefaults.
    func saveSetups() {
        do {
            let data = try JSONEncoder().encode(setups)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.log.error("Failed to encode display setups: \(error.localizedDescription)")
        }
    }

    /// Creates and saves a new display connection setup.
    @discardableResult
    func createSetup(name: String, fingerprints: Set<String>, disableInternalWhenExternal: Bool) -> DisplaySetup {
        let setup = DisplaySetup(
            id: UUID(),
            name: name,
            activeDisplayFingerprints: fingerprints,
            disableInternalWhenExternal: disableInternalWhenExternal
        )
        setups.append(setup)
        saveSetups()
        Self.log.log("Created display connection setup: \(name)")
        return setup
    }

    /// Deletes a display setup by ID.
    func deleteSetup(id: UUID) {
        setups.removeAll { $0.id == id }
        saveSetups()
        if activeSetupID == id {
            activeSetupID = nil
        }
    }

    /// Switches to a specific display setup.
    func switchSetup(id: UUID) -> Bool {
        guard let setup = setups.first(where: { $0.id == id }) else {
            Self.log.error("Display setup not found: \(id)")
            return false
        }
        activeSetupID = id
        
        let displayList = Array(displays.values)
        let updatedList = DisplayConnectionSupport.evaluateSetup(
            setup: setup,
            displays: displayList,
            isAppleSilicon: DisplayConnectionSupport.isAppleSiliconMac
        )

        displays = Dictionary(uniqueKeysWithValues: updatedList.map { ($0.id, $0) })

        let externalConnected = DisplayConnectionSupport.hasExternalDisplayConnected(displays: updatedList)
        if setup.disableInternalWhenExternal && externalConnected && DisplayConnectionSupport.isAppleSiliconMac {
            startRecoveryCountdown()
        }

        Self.log.log("Switched to display setup '\(setup.name)'.")
        return true
    }

    /// Handles external display connection/disconnection hot-plug event.
    func handleHotPlug(displayID: UInt32, connected: Bool) {
        guard var info = displays[displayID] else { return }
        info.isConnected = connected
        if !connected {
            info.isEnabled = false
        }
        displays[displayID] = info

        if connected, !info.isInternal, let activeID = activeSetupID, let setup = setups.first(where: { $0.id == activeID }) {
            if setup.disableInternalWhenExternal && DisplayConnectionSupport.isAppleSiliconMac {
                for (id, var disp) in displays {
                    if disp.isInternal {
                        disp.isEnabled = false
                        displays[id] = disp
                    }
                }
                startRecoveryCountdown()
            }
        } else if !connected, !info.isInternal {
            for (id, var disp) in displays {
                if disp.isInternal {
                    disp.isEnabled = true
                    displays[id] = disp
                }
            }
        }
        Self.log.log("Handled hot-plug for display ID \(displayID): connected=\(connected)")
    }

    /// Confirms current display setup changes, canceling the recovery countdown safeguard.
    func confirmSetup() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        isPendingConfirmation = false
        countdownRemaining = 0.0
        Self.log.log("Display setup confirmed by user.")
    }

    /// Emergency keyboard restore safeguard / timeout rollback: restores internal panel and default setup.
    func triggerEmergencyRestore() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        isPendingConfirmation = false
        countdownRemaining = 0.0

        for (id, var disp) in displays {
            if disp.isInternal {
                disp.isEnabled = true
                displays[id] = disp
            }
        }
        Self.log.warning("Emergency keyboard restore triggered! Restored internal display panel.")
    }

    private func startRecoveryCountdown() {
        recoveryTimer?.invalidate()
        isPendingConfirmation = true
        countdownRemaining = defaultRecoveryTimeout

        let startTime = Date()
        let timeout = defaultRecoveryTimeout

        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let elapsed = Date().timeIntervalSince(startTime)
            let remaining = max(timeout - elapsed, 0.0)
            self.countdownRemaining = remaining

            if remaining <= 0 {
                timer.invalidate()
                self.triggerEmergencyRestore()
            }
        }
    }

    private func refreshDisplays() {
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))

        guard CGGetOnlineDisplayList(maxDisplays, &displayIDs, &displayCount) == .success else {
            return
        }

        var map: [UInt32: DisplayInfo] = []
        let mainID = CGMainDisplayID()

        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            let bounds = CGDisplayBounds(id)
            let isMain = (id == mainID)
            let isInternal = CGDisplayIsBuiltin(id) != 0
            let fingerprint = generateFingerprint(for: id)
            let name = isMain ? "Main Display" : "External Display #\(i + 1)"

            map[id] = DisplayInfo(
                id: id,
                fingerprint: fingerprint,
                name: name,
                isInternal: isInternal,
                isConnected: true,
                isEnabled: true,
                resolution: CGSize(width: bounds.width, height: bounds.height)
            )
        }
        displays = map
    }

    private func generateFingerprint(for displayID: CGDirectDisplayID) -> String {
        let width = Int(CGDisplayPixelsWide(displayID))
        let height = Int(CGDisplayPixelsHigh(displayID))
        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = CGDisplaySerialNumber(displayID)
        return "\(vendor):\(model):\(serial):\(width)x\(height)"
    }
}
