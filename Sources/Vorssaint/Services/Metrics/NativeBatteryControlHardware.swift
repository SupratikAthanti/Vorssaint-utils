// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import IOKit.pwr_mgt

final class NativeBatteryControlHardware: BatteryControlHardware {
    private let smc = SMCClient()
    private lazy var sampler = PowerSampler(smc: smc)
    private var sleepAssertion: IOPMAssertionID = 0

    func sample() -> BatteryTelemetry? {
        let power = sampler.sample()
        guard power.hasBattery, let charge = power.chargePercent, (0...100).contains(charge) else { return nil }
        // Read the battery sensor now; a cached monitor temperature is not fresh evidence.
        let temperature = smc?.key(named: "TB0T").flatMap { smc?.readValue($0) }
        let rawCharge = smc?.key(named: "B0RawSoC").flatMap { smc?.readValue($0) }
        return BatteryTelemetry(charge: charge, pluggedIn: power.externalConnected,
                                charging: power.isCharging, temperature: temperature,
                                hardwareCharge: rawCharge, wallWatts: power.adapterWatts ?? 0,
                                batteryWatts: power.batteryWatts ?? 0, macWatts: power.systemWatts ?? 0,
                                observedAt: Date())
    }

    private func write(_ byte: UInt8, key name: String) -> Bool {
        guard let smc, let key = smc.key(named: name), key.dataSize == 1,
              key.dataType == "ui8 " else { return false }
        do {
            try smc.writeBytes([byte], to: key)
            return smc.readBytes(key) == [byte]
        } catch { return false }
    }
    func setChargingInhibited(_ inhibited: Bool) -> Bool { write(inhibited ? 1 : 0, key: "CH0I") }
    func setDischargeMode(_ discharge: Bool) -> Bool { write(discharge ? 1 : 0, key: "CH0D") }
    func setMagSafeLED(_ state: BatteryManager.MagSafeState) -> Bool {
        let byte: UInt8
        switch state { case .green: byte = 1; case .amber: byte = 2; case .amberBlinking: byte = 3; case .off: byte = 0 }
        return write(byte, key: "ACLC")
    }
    func preventSleep(_ prevent: Bool) -> Bool {
        if prevent, sleepAssertion == 0 {
            return IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                              "Vorssaint Battery Limit Sleep Hold" as CFString,
                                              &sleepAssertion) == kIOReturnSuccess
        }
        if !prevent, sleepAssertion != 0 {
            guard IOPMAssertionRelease(sleepAssertion) == kIOReturnSuccess else { return false }
            sleepAssertion = 0
        }
        return true
    }
    deinit { if sleepAssertion != 0 { IOPMAssertionRelease(sleepAssertion) } }
}
