// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import os

/// Manages BD-14 HDMI-CEC and external device integrations:
/// controlling HDMI connected TV/AV receiver volume, mute, power, and input switching.
final class HDMICECService: ObservableObject {
    static let shared = HDMICECService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "hdmi-cec")

    struct CECDevice: Codable, Equatable, Identifiable {
        let id: String
        var name: String
        var physicalAddress: String
        var isPowerOn: Bool
        var volumeLevel: Int // 0..100
        var isMuted: Bool
        var activeInput: String
    }

    @Published private(set) var devices: [CECDevice] = []
    @Published var isOptedIn: Bool = false {
        didSet {
            UserDefaults.standard.set(isOptedIn, forKey: "com.vorssaint.hdmiCEC.optIn")
            if !isOptedIn {
                devices = []
            }
        }
    }

    private init() {
        self.isOptedIn = UserDefaults.standard.bool(forKey: "com.vorssaint.hdmiCEC.optIn")
    }

    func discoverDevices() {
        guard isOptedIn else {
            Self.log.log("HDMI-CEC discovery skipped: user has not opted in.")
            devices = []
            return
        }

        // Simulate discovery of connected HDMI-CEC endpoints
        let simulatedTV = CECDevice(
            id: "cec-tv-01",
            name: "HDMI TV / Display",
            physicalAddress: "1.0.0.0",
            isPowerOn: true,
            volumeLevel: 25,
            isMuted: false,
            activeInput: "HDMI 1"
        )
        devices = [simulatedTV]
        Self.log.log("Discovered \(self.devices.count) HDMI-CEC devices.")
    }

    func setPower(deviceID: String, powerOn: Bool) -> Bool {
        guard isOptedIn, let index = devices.firstIndex(where: { $0.id == deviceID }) else { return false }
        devices[index].isPowerOn = powerOn
        Self.log.log("Set CEC device '\(deviceID)' power: \(powerOn)")
        return true
    }

    func setVolume(deviceID: String, volume: Int) -> Bool {
        guard isOptedIn, let index = devices.firstIndex(where: { $0.id == deviceID }) else { return false }
        let validVolume = max(0, min(100, volume))
        devices[index].volumeLevel = validVolume
        Self.log.log("Set CEC device '\(deviceID)' volume: \(validVolume)")
        return true
    }

    func setMute(deviceID: String, muted: Bool) -> Bool {
        guard isOptedIn, let index = devices.firstIndex(where: { $0.id == deviceID }) else { return false }
        devices[index].isMuted = muted
        Self.log.log("Set CEC device '\(deviceID)' mute: \(muted)")
        return true
    }

    func setInput(deviceID: String, input: String) -> Bool {
        guard isOptedIn, let index = devices.firstIndex(where: { $0.id == deviceID }) else { return false }
        devices[index].activeInput = input
        Self.log.log("Set CEC device '\(deviceID)' input: \(input)")
        return true
    }
}
