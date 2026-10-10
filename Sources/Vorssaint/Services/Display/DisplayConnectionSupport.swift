// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation

/// Pure logic and CoreGraphics wrappers for BD-11 (Connection/disconnection management):
/// switching between display setups, disconnect/reconnect external displays,
/// optionally disabling internal panel when external display is connected on compatible Apple Silicon Macs,
/// and recovery timeout / keyboard restore safeguard.
enum DisplayConnectionSupport {
    struct DisplayConnectionInfo: Codable, Equatable, Identifiable {
        let id: UInt32
        let fingerprint: String
        let name: String
        let isInternal: Bool
        var isConnected: Bool
        var isEnabled: Bool
        let resolution: CGSize
    }

    struct DisplaySetupModel: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var activeDisplayFingerprints: Set<String>
        var disableInternalWhenExternal: Bool
    }

    /// Checks whether the running machine is an Apple Silicon Mac supporting built-in panel blanking / clamshell management.
    static var isAppleSiliconMac: Bool {
        var size = 0
        sysctlbyname("hw.cpusubtype", nil, &size, nil, 0)
        var cpuSubtype: Int32 = 0
        sysctlbyname("hw.cpusubtype", &cpuSubtype, &size, nil, 0)
        // CPU_SUBTYPE_ARM64E or ARM64 typically indicates Apple Silicon
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Evaluates if an external display is currently connected among online displays.
    static func hasExternalDisplayConnected(displays: [DisplayConnectionInfo]) -> Bool {
        displays.contains { !$0.isInternal && $0.isConnected }
    }

    /// Computes updated display states when switching to a setup or handling a hot-plug event.
    static func evaluateSetup(
        setup: DisplaySetupModel,
        displays: [DisplayConnectionInfo],
        isAppleSilicon: Bool
    ) -> [DisplayConnectionInfo] {
        let externalConnected = hasExternalDisplayConnected(displays: displays)

        return displays.map { display in
            var updated = display
            let shouldBeActive = setup.activeDisplayFingerprints.contains(display.fingerprint)
            
            if shouldBeActive {
                updated.isConnected = true
                if updated.isInternal && externalConnected && setup.disableInternalWhenExternal && isAppleSilicon {
                    updated.isEnabled = false // Disable internal panel on Apple Silicon when external connected
                } else {
                    updated.isEnabled = true
                }
            } else {
                updated.isEnabled = false
            }
            return updated
        }
    }
}
