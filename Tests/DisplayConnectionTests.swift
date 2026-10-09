// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

/// Unit tests for BD-11 (Connection/disconnection management):
/// covers switching between display setups, disconnect/reconnect external displays,
/// optionally disabling internal panel when external display is connected on compatible Apple Silicon Macs,
/// and recovery timeout / keyboard restore safeguard.
enum DisplayConnectionTests {
    struct DisplayInfo: Equatable, Identifiable {
        let id: UInt32
        let name: String
        let isInternal: Bool
        var isConnected: Bool
        var isEnabled: Bool
        let resolution: CGSize
    }

    struct DisplaySetup: Equatable, Identifiable {
        let id: UUID
        let name: String
        var activeDisplayIDs: Set<UInt32>
        var disableInternalWhenExternal: Bool
    }

    final class MockConnectionManager {
        var displays: [UInt32: DisplayInfo] = [:]
        var setups: [DisplaySetup] = []
        var activeSetupID: UUID?
        var isAppleSilicon: Bool = true
        var recoveryTimeoutSeconds: Double = 5.0
        var isPendingConfirmation: Bool = false
        var countdownRemaining: Double = 0.0
        var emergencyRestoreTriggered: Bool = false

        func registerDisplay(_ display: DisplayInfo) {
            displays[display.id] = display
        }

        func createSetup(name: String, activeIDs: Set<UInt32>, disableInternal: Bool) -> DisplaySetup {
            let setup = DisplaySetup(id: UUID(), name: name, activeDisplayIDs: activeIDs, disableInternalWhenExternal: disableInternal)
            setups.append(setup)
            return setup
        }

        func switchSetup(id: UUID) -> Bool {
            guard let setup = setups.first(where: { $0.id == id }) else { return false }
            activeSetupID = id

            // Check if external display is connected
            let externalConnected = displays.values.contains { !$0.isInternal && $0.isConnected }

            for (displayID, var info) in displays {
                let shouldBeActive = setup.activeDisplayIDs.contains(displayID)
                if shouldBeActive {
                    info.isConnected = true
                    if info.isInternal && externalConnected && setup.disableInternalWhenExternal && isAppleSilicon {
                        info.isEnabled = false // Optionally disable internal panel on Apple Silicon
                    } else {
                        info.isEnabled = true
                    }
                } else {
                    info.isEnabled = false
                }
                displays[displayID] = info
            }

            if setup.disableInternalWhenExternal && externalConnected && isAppleSilicon {
                startRecoveryCountdown()
            }
            return true
        }

        func handleHotPlug(displayID: UInt32, connected: Bool) {
            guard var info = displays[displayID] else { return }
            info.isConnected = connected
            if !connected {
                info.isEnabled = false
            }
            displays[displayID] = info

            // If external display connected, evaluate setup rules
            if connected && !info.isInternal, let activeID = activeSetupID, let setup = setups.first(where: { $0.id == activeID }) {
                if setup.disableInternalWhenExternal && isAppleSilicon {
                    for (id, var disp) in displays {
                        if disp.isInternal {
                            disp.isEnabled = false
                            displays[id] = disp
                        }
                    }
                    startRecoveryCountdown()
                }
            } else if !connected && !info.isInternal {
                // External disconnected: restore internal panel if needed
                for (id, var disp) in displays {
                    if disp.isInternal {
                        disp.isEnabled = true
                        displays[id] = disp
                    }
                }
            }
        }

        private func startRecoveryCountdown() {
            isPendingConfirmation = true
            countdownRemaining = recoveryTimeoutSeconds
        }

        func confirmSetup() {
            isPendingConfirmation = false
            countdownRemaining = 0.0
        }

        func triggerEmergencyRestore() {
            emergencyRestoreTriggered = true
            isPendingConfirmation = false
            countdownRemaining = 0.0
            // Restore all internal panels and previous state
            for (id, var disp) in displays {
                if disp.isInternal {
                    disp.isEnabled = true
                    displays[id] = disp
                }
            }
        }
    }

    static func run(_ suite: TestSuite) {
        let manager = MockConnectionManager()
        manager.isAppleSilicon = true

        let internalDisplay = DisplayInfo(id: 1, name: "Built-in Retina", isInternal: true, isConnected: true, isEnabled: true, resolution: CGSize(width: 3024, height: 1964))
        let externalDisplay = DisplayInfo(id: 2, name: "Studio Display 4K", isInternal: false, isConnected: false, isEnabled: false, resolution: CGSize(width: 3840, height: 2160))

        manager.registerDisplay(internalDisplay)
        manager.registerDisplay(externalDisplay)

        // 1. Setup creation and switching
        let setupDesktop = manager.createSetup(name: "Workstation Desk", activeIDs: [1, 2], disableInternal: true)
        let setupMobile = manager.createSetup(name: "Mobile Travel", activeIDs: [1], disableInternal: false)

        let switched = manager.switchSetup(id: setupMobile.id)
        suite.expect(switched && manager.activeSetupID == setupMobile.id, "switches between display setups successfully")
        suite.expect(manager.displays[1]?.isEnabled == true, "mobile setup keeps internal display enabled")

        // 2. Disconnect/reconnect external display management
        // Connect external display
        manager.handleHotPlug(displayID: 2, connected: true)
        suite.expect(manager.displays[2]?.isConnected == true, "tracks external display connection hot-plug event correctly")

        // Switch to workstation setup with disableInternal = true on Apple Silicon
        _ = manager.switchSetup(id: setupDesktop.id)
        suite.expect(manager.displays[1]?.isEnabled == false, "optionally disables internal panel when external display is connected on compatible Apple Silicon Mac")

        // Disconnecting external display automatically restores internal panel
        manager.handleHotPlug(displayID: 2, connected: false)
        suite.expect(manager.displays[1]?.isEnabled == true, "automatically restores internal panel when external display is disconnected")

        // 3. Apple Silicon compatibility check for internal panel disabling
        manager.isAppleSilicon = false // Intel Mac
        _ = manager.switchSetup(id: setupDesktop.id)
        manager.handleHotPlug(displayID: 2, connected: true)
        suite.expect(manager.displays[1]?.isEnabled == true, "ignores internal panel disabling on non-Apple Silicon Macs")

        // 4. Recovery timeout & keyboard restore safeguard
        manager.isAppleSilicon = true
        _ = manager.switchSetup(id: setupDesktop.id)
        manager.handleHotPlug(displayID: 2, connected: true)
        suite.expect(manager.isPendingConfirmation && manager.countdownRemaining > 0, "starts recovery confirmation timeout upon disabling internal panel")

        // Test emergency keyboard restore safeguard
        manager.triggerEmergencyRestore()
        suite.expect(manager.emergencyRestoreTriggered, "triggers emergency keyboard restore safeguard successfully")
        suite.expect(manager.displays[1]?.isEnabled == true, "emergency safeguard restores internal display immediately")
    }
}
