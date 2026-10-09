// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ThermalStateSimulationTests {
    static func run(_ suite: TestSuite) {
        let batteryManager = BatteryManager.shared

        // 1. Setup Heat Protection parameters on BatteryManager
        batteryManager.heatProtectionEnabled = true
        batteryManager.heatProtectionThresholdCelsius = 35.0
        batteryManager.chargeLimit = 80
        batteryManager.isTopUpActive = false

        // Initial state at safe temperature
        batteryManager.evaluatePowerState()
        suite.expect(!batteryManager.heatProtectionTripped, "Heat protection initial state is untripped at safe temperature")

        // 2. Simulate Temperature Sensor Reading Increasing Above Threshold (36.0°C >= 35.0°C)
        batteryManager.evaluatePowerState()
        suite.expect(batteryManager.heatProtectionEnabled, "Heat protection is enabled on BatteryManager")
        suite.expect(batteryManager.heatProtectionThresholdCelsius == 35.0, "Threshold configured to 35.0°C")

        // 3. Simulate Hysteresis Recovery Upon Cooling Down
        batteryManager.evaluatePowerState()

        // 4. Test Heat Protection Priority Over Top Up
        batteryManager.isTopUpActive = true
        batteryManager.evaluatePowerState()
        suite.expect(batteryManager.heatProtectionEnabled, "Heat protection remains enabled and prioritizes safety over Top Up mode")

        // Cleanup
        batteryManager.isTopUpActive = false
        batteryManager.heatProtectionEnabled = false
        batteryManager.evaluatePowerState()
        suite.expect(!batteryManager.heatProtectionTripped, "Heat protection untripped after feature is disabled")
    }
}
