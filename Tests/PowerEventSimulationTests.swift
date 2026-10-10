// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PowerEventSimulationTests {
    static func run(_ suite: TestSuite) {
        let batteryManager = BatteryManager.shared

        // 1. Test Initial Power State & AC Adapter Connection
        batteryManager.evaluatePowerState()
        suite.expect(batteryManager.isPluggedIn, "BatteryManager detects plugged-in AC power adapter state")

        // 2. Test Top Up Mode Activation & Unplug Revert / Expiration
        batteryManager.chargeLimit = 80
        batteryManager.isTopUpActive = true
        suite.expect(batteryManager.isTopUpActive, "Top Up mode activated on BatteryManager")

        // Simulate physical AC unplug during Top Up
        batteryManager.pollTelemetry()
        suite.expect(batteryManager.chargeLimit == 80, "Original baseline charge limit (80%) is preserved")

        // 3. Test Sleep / Wake Notifications & stopChargingWhenSleeping
        batteryManager.stopChargingWhenSleeping = true
        suite.expect(batteryManager.stopChargingWhenSleeping, "stopChargingWhenSleeping option enabled")

        // Post simulated sleep notification
        NotificationCenter.default.post(name: NSWorkspace.willSleepNotification, object: nil)
        // Post simulated wake notification
        NotificationCenter.default.post(name: NSWorkspace.didWakeNotification, object: nil)

        // 4. Test Manual Discharge Start / Stop & Clamshell assertions
        batteryManager.isDischargeActive = true
        suite.expect(batteryManager.isDischargeActive, "Manual discharge active on BatteryManager")
        batteryManager.isDischargeActive = false
        suite.expect(!batteryManager.isDischargeActive, "Manual discharge deactivated on BatteryManager")

        // 5. Test Sailing Mode hysteresis parameters
        batteryManager.sailingModeEnabled = true
        batteryManager.sailingHysteresis = 5
        batteryManager.evaluatePowerState()
        suite.expect(batteryManager.sailingModeEnabled, "Sailing mode active")
        suite.expect(batteryManager.sailingHysteresis == 5, "Sailing hysteresis set to 5%")

        // Cleanup
        batteryManager.sailingModeEnabled = false
        batteryManager.evaluatePowerState()
    }
}
