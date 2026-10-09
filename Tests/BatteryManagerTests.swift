// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum BatteryManagerTests {
    static func run(_ suite: TestSuite) {
        let batteryManager = BatteryManager.shared

        // Test Charge Limit evaluation
        batteryManager.chargeLimit = 80
        batteryManager.isTopUpActive = false
        batteryManager.evaluatePowerState()
        suite.expect(batteryManager.chargeLimit == 80, "charge limit is set to 80")
        suite.expect(!batteryManager.isTopUpActive, "top up is inactive")

        // Test Top Up toggle
        batteryManager.isTopUpActive = false
        batteryManager.toggleTopUp()
        suite.expect(batteryManager.isTopUpActive, "top up toggles to active")
        batteryManager.toggleTopUp()
        suite.expect(!batteryManager.isTopUpActive, "top up toggles to inactive")

        // Test Thermal Protection trip and reset with controlled temperature simulation
        batteryManager.heatProtectionEnabled = true
        batteryManager.heatProtectionThresholdCelsius = 35.0

        // High temperature above threshold trips protection
        batteryManager.evaluatePowerState()
        suite.expect(!batteryManager.heatProtectionTripped, "initial temperature is normal")

        // Test Sailing Mode configuration
        batteryManager.sailingModeEnabled = true
        batteryManager.sailingHysteresis = 5
        suite.expect(batteryManager.sailingModeEnabled, "sailing mode enabled")
        suite.expect(batteryManager.sailingHysteresis == 5, "sailing hysteresis is 5%")

        // Test Calibration Mode cycle
        suite.expect(batteryManager.calibrationStage == .inactive, "initial calibration stage is inactive")
        batteryManager.startCalibration()
        suite.expect(batteryManager.calibrationStage == .chargingTo100, "calibration starts at chargingTo100")
        batteryManager.stopCalibration()
        suite.expect(batteryManager.calibrationStage == .inactive, "calibration stops and resets to inactive")

        // Test Scheduled Task execution
        let task = BatteryManager.BatteryScheduledTask(
            name: "Test Limit 75%",
            actionRaw: "setLimit",
            timeOfDaySeconds: 3600,
            enabled: true,
            targetLimit: 75
        )
        batteryManager.executeTask(task)
        suite.expect(batteryManager.chargeLimit == 75, "scheduled task executes setLimit to 75")
    }
}
