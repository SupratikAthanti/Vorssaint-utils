// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every physical reading is injected; the software side is the production
/// engine, and the hardware side independently records accepted states.
final class SimulationDoubleStateMachinesTests {
    static func runSimulationSuite() -> Bool {
        var transitions = 0
        for plugged in [false, true] {
            for charge in [10, 70, 80, 90, 100] {
                for temperature in [28.0, 34.0, 36.0] {
                    let fixture = BatteryTestFixture()
                    fixture.read(charge: charge, plugged: plugged, temperature: temperature)
                    let engine = fixture.manager
                    engine.controlEnabled = true; engine.heatProtectionEnabled = true
                    engine.isDischargeActive = true; engine.isTopUpActive = true
                    if !plugged && fixture.hardware.discharging { return false }
                    if plugged && temperature >= 35 && (!fixture.hardware.inhibited || fixture.hardware.discharging) { return false }
                    engine.controlEnabled = false
                    if fixture.hardware.discharging || fixture.hardware.inhibited || fixture.hardware.sleepHeld { return false }
                    transitions += 1
                }
            }
        }
        print("Battery physical/software transitions verified: \(transitions)")
        return transitions == 30
    }
}
