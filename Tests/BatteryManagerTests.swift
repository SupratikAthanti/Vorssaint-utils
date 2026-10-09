// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import XCTest
@testable import VorssaintTests

final class BatteryManagerTests: XCTestCase {
    var batteryManager: BatteryManager!

    override func setUp() {
        super.setUp()
        batteryManager = BatteryManager.shared
    }

    func testChargeLimitEvaluation() {
        batteryManager.chargeLimit = 80
        batteryManager.isTopUpActive = false
        batteryManager.evaluatePowerState()

        XCTAssertEqual(batteryManager.chargeLimit, 80)
        XCTAssertFalse(batteryManager.isTopUpActive)
    }

    func testTopUpToggle() {
        XCTAssertFalse(batteryManager.isTopUpActive)
        batteryManager.toggleTopUp()
        XCTAssertTrue(batteryManager.isTopUpActive)
        batteryManager.toggleTopUp()
        XCTAssertFalse(batteryManager.isTopUpActive)
    }

    func testThermalProtectionThreshold() {
        batteryManager.heatProtectionEnabled = true
        batteryManager.heatProtectionThresholdCelsius = 35.0

        // Simulate high temperature
        batteryManager.pollTelemetry()
        // Default thermal check logic
        XCTAssertFalse(batteryManager.heatProtectionTripped)
    }

    func testSailingModeConfiguration() {
        batteryManager.sailingModeEnabled = true
        batteryManager.sailingHysteresis = 5
        XCTAssertTrue(batteryManager.sailingModeEnabled)
        XCTAssertEqual(batteryManager.sailingHysteresis, 5)
    }

    func testCalibrationModeCycle() {
        XCTAssertEqual(batteryManager.calibrationStage, .inactive)
        batteryManager.startCalibration()
        XCTAssertEqual(batteryManager.calibrationStage, .chargingTo100)
        batteryManager.stopCalibration()
        XCTAssertEqual(batteryManager.calibrationStage, .inactive)
    }

    func testScheduledTaskExecution() {
        let task = BatteryManager.BatteryScheduledTask(
            name: "Test Limit 75%",
            actionRaw: "setLimit",
            timeOfDaySeconds: 3600,
            enabled: true,
            targetLimit: 75
        )
        batteryManager.executeTask(task)
        XCTAssertEqual(batteryManager.chargeLimit, 75)
    }
}
