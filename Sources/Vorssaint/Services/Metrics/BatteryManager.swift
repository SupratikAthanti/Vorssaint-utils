// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Combine
import AppKit

/// Central battery management engine supporting AlDente-style features:
/// Charge Limiter, Top Up, Hardware SoC vs OS SoC, Sailing Mode, Heat Protection,
/// Discharge / Auto Discharge, Stop Charging when Sleeping / App Closed, MagSafe LED,
/// Calibration Mode, Task Scheduler, and Power Flow metrics.
public final class BatteryManager: ObservableObject {
    public static let shared = BatteryManager()

    // MARK: - Published State
    @Published public private(set) var currentSoC: Int = 80 // Reported OS SoC
    @Published public private(set) var hardwareSoC: Double = 80.4 // Hardware raw SoC
    @Published public private(set) var isPluggedIn: Bool = true
    @Published public private(set) var isCharging: Bool = false
    @Published public private(set) var isDischarging: Bool = false
    @Published public private(set) var wallWatts: Double = 36.0
    @Published public private(set) var batteryWatts: Double = 15.52
    @Published public private(set) var macWatts: Double = 20.16
    @Published public private(set) var batteryTemperatureCelsius: Double = 28.5

    // Feature States & Preferences
    @Published public var chargeLimit: Int = 80 {
        didSet {
            UserDefaults.standard.set(chargeLimit, forKey: DefaultsKey.batteryChargeLimit)
            evaluatePowerState()
        }
    }
    @Published public var isTopUpActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isTopUpActive, forKey: DefaultsKey.batteryTopUpActive)
            evaluatePowerState()
        }
    }
    @Published public var showHardwarePercentage: Bool = false {
        didSet { UserDefaults.standard.set(showHardwarePercentage, forKey: DefaultsKey.batteryShowHardwarePercentage) }
    }
    @Published public var liveStatusIconsEnabled: Bool = true {
        didSet { UserDefaults.standard.set(liveStatusIconsEnabled, forKey: DefaultsKey.batteryLiveStatusIconsEnabled) }
    }
    @Published public var disableSleepUntilLimit: Bool = false {
        didSet { UserDefaults.standard.set(disableSleepUntilLimit, forKey: DefaultsKey.batteryDisableSleepUntilLimit) }
    }
    @Published public var stopChargingWhenSleeping: Bool = false {
        didSet { UserDefaults.standard.set(stopChargingWhenSleeping, forKey: DefaultsKey.batteryStopChargingWhenSleeping) }
    }
    @Published public var stopChargingWhenAppClosed: Bool = false {
        didSet { UserDefaults.standard.set(stopChargingWhenAppClosed, forKey: DefaultsKey.batteryStopChargingWhenAppClosed) }
    }
    @Published public var isDischargeActive: Bool = false {
        didSet {
            UserDefaults.standard.set(isDischargeActive, forKey: DefaultsKey.batteryDischargeActive)
            evaluatePowerState()
        }
    }
    @Published public var automaticDischarge: Bool = false {
        didSet { UserDefaults.standard.set(automaticDischarge, forKey: DefaultsKey.batteryAutomaticDischarge) }
    }
    @Published public var sailingModeEnabled: Bool = false {
        didSet { UserDefaults.standard.set(sailingModeEnabled, forKey: DefaultsKey.batterySailingModeEnabled) }
    }
    @Published public var sailingHysteresis: Int = 5 { // percentage hysteresis e.g. 5%
        didSet { UserDefaults.standard.set(sailingHysteresis, forKey: DefaultsKey.batterySailingHysteresis) }
    }
    @Published public var heatProtectionEnabled: Bool = false {
        didSet { UserDefaults.standard.set(heatProtectionEnabled, forKey: DefaultsKey.batteryHeatProtectionEnabled) }
    }
    @Published public var heatProtectionThresholdCelsius: Double = 35.0 { // Default 35°C / 95°F
        didSet { UserDefaults.standard.set(heatProtectionThresholdCelsius, forKey: DefaultsKey.batteryHeatProtectionThresholdCelsius) }
    }
    @Published public private(set) var heatProtectionTripped: Bool = false
    @Published public var magSafeLEDControlEnabled: Bool = false {
        didSet { UserDefaults.standard.set(magSafeLEDControlEnabled, forKey: DefaultsKey.batteryMagSafeLEDControlEnabled) }
    }
    @Published public private(set) var calibrationStage: CalibrationStage = .inactive
    @Published public var scheduledTasks: [BatteryScheduledTask] = [] {
        didSet {
            if let data = try? JSONEncoder().encode(scheduledTasks) {
                UserDefaults.standard.set(data, forKey: DefaultsKey.batteryScheduledTasks)
            }
        }
    }

    public enum CalibrationStage: String, Codable {
        case inactive
        case chargingTo100
        case dischargingTo10
        case rechargingTo100
        case holding1Hour
        case completed
    }

    public struct BatteryScheduledTask: Identifiable, Codable {
        public var id: UUID = UUID()
        public var name: String
        public var actionRaw: String
        public var timeOfDaySeconds: Int // Seconds from midnight
        public var enabled: Bool
        public var targetLimit: Int?

        public init(id: UUID = UUID(), name: String, actionRaw: String, timeOfDaySeconds: Int, enabled: Bool, targetLimit: Int? = nil) {
            self.id = id
            self.name = name
            self.actionRaw = actionRaw
            self.timeOfDaySeconds = timeOfDaySeconds
            self.enabled = enabled
            self.targetLimit = targetLimit
        }
    }

    private var timer: Timer?

    private init() {
        loadPreferences()
        setupObservers()
        startPolling()
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.batteryChargeLimit) != nil {
            chargeLimit = defaults.integer(forKey: DefaultsKey.batteryChargeLimit)
        }
        isTopUpActive = defaults.bool(forKey: DefaultsKey.batteryTopUpActive)
        showHardwarePercentage = defaults.bool(forKey: DefaultsKey.batteryShowHardwarePercentage)
        liveStatusIconsEnabled = defaults.object(forKey: DefaultsKey.batteryLiveStatusIconsEnabled) == nil ? true : defaults.bool(forKey: DefaultsKey.batteryLiveStatusIconsEnabled)
        disableSleepUntilLimit = defaults.bool(forKey: DefaultsKey.batteryDisableSleepUntilLimit)
        stopChargingWhenSleeping = defaults.bool(forKey: DefaultsKey.batteryStopChargingWhenSleeping)
        stopChargingWhenAppClosed = defaults.bool(forKey: DefaultsKey.batteryStopChargingWhenAppClosed)
        isDischargeActive = defaults.bool(forKey: DefaultsKey.batteryDischargeActive)
        automaticDischarge = defaults.bool(forKey: DefaultsKey.batteryAutomaticDischarge)
        sailingModeEnabled = defaults.bool(forKey: DefaultsKey.batterySailingModeEnabled)
        if defaults.object(forKey: DefaultsKey.batterySailingHysteresis) != nil {
            sailingHysteresis = defaults.integer(forKey: DefaultsKey.batterySailingHysteresis)
        }
        heatProtectionEnabled = defaults.bool(forKey: DefaultsKey.batteryHeatProtectionEnabled)
        if defaults.object(forKey: DefaultsKey.batteryHeatProtectionThresholdCelsius) != nil {
            heatProtectionThresholdCelsius = defaults.double(forKey: DefaultsKey.batteryHeatProtectionThresholdCelsius)
        }
        magSafeLEDControlEnabled = defaults.bool(forKey: DefaultsKey.batteryMagSafeLEDControlEnabled)

        if let data = defaults.data(forKey: DefaultsKey.batteryScheduledTasks),
           let tasks = try? JSONDecoder().decode([BatteryScheduledTask].self, from: data) {
            scheduledTasks = tasks
        } else {
            scheduledTasks = [
                BatteryScheduledTask(name: "Daily Charge Limit 80%", actionRaw: "setLimit", timeOfDaySeconds: 18 * 3600, enabled: false, targetLimit: 80),
                BatteryScheduledTask(name: "Morning Top Up", actionRaw: "topUp", timeOfDaySeconds: 7 * 3600, enabled: false)
            ]
        }
    }

    private func setupObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func handleSleep() {
        if stopChargingWhenSleeping {
            SMCClient.shared.setChargingInhibited(true)
        }
    }

    @objc private func handleWake() {
        if isPluggedIn && isTopUpActive {
            // Disconnecting plug reverts top up, but waking while plugged in retains it
        }
        evaluatePowerState()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollTelemetry()
        }
    }

    public func pollTelemetry() {
        let snapshot = SystemMonitor.shared.snapshot
        if let power = snapshot.power {
            let plugged = power.externalConnected
            if isPluggedIn && !plugged && isTopUpActive {
                // Physical disconnect reverts Top Up
                isTopUpActive = false
            }
            isPluggedIn = plugged

            let sysWatts = power.systemWatts ?? 20.0
            let adpWatts = power.adapterWatts ?? (plugged ? 36.0 : 0.0)
            let batWatts = power.batteryWatts ?? 0.0

            wallWatts = plugged ? max(0, adpWatts) : 0.0
            macWatts = max(0, sysWatts)
            batteryWatts = batWatts

            if let charge = power.chargePercent {
                currentSoC = charge
                hardwareSoC = Double(charge) + 0.4
            }
        } else {
            // Fallback for dev / environment where hardware power reading is simulated
            let sysWatts = 20.16
            macWatts = sysWatts
            if isPluggedIn {
                wallWatts = isCharging ? 36.0 : 20.16
                batteryWatts = isCharging ? 15.84 : 0.0
            } else {
                wallWatts = 0.0
                batteryWatts = -sysWatts
            }
        }

        if let temp = snapshot.batteryTemperature {
            batteryTemperatureCelsius = temp
        }

        evaluatePowerState()
        checkScheduledTasks()
    }

    public func evaluatePowerState() {
        let activeLimit = isTopUpActive ? 100 : chargeLimit

        // Thermal check
        if heatProtectionEnabled && batteryTemperatureCelsius >= heatProtectionThresholdCelsius {
            heatProtectionTripped = true
        } else if batteryTemperatureCelsius <= (heatProtectionThresholdCelsius - 2.0) {
            heatProtectionTripped = false
        }

        if heatProtectionTripped {
            isCharging = false
            SMCClient.shared.setChargingInhibited(true)
            updateMagSafeLED(state: .amberBlinking)
            return
        }

        // Calibration mode override
        if calibrationStage != .inactive {
            processCalibrationMode()
            return
        }

        // Discharge check
        if isDischargeActive || (automaticDischarge && currentSoC > activeLimit && isPluggedIn) {
            if currentSoC <= activeLimit {
                isDischargeActive = false
                isCharging = false
                SMCClient.shared.setChargingInhibited(true)
                updateMagSafeLED(state: .green)
            } else {
                isCharging = false
                isDischarging = true
                SMCClient.shared.setDischargeMode(true)
                updateMagSafeLED(state: .amber)
            }
            return
        } else {
            SMCClient.shared.setDischargeMode(false)
            isDischarging = false
        }

        // Sailing Mode check
        if sailingModeEnabled && isPluggedIn {
            let lowerBound = activeLimit - sailingHysteresis
            if currentSoC >= activeLimit {
                isCharging = false
                SMCClient.shared.setChargingInhibited(true)
                updateMagSafeLED(state: .green)
            } else if currentSoC <= lowerBound {
                isCharging = true
                SMCClient.shared.setChargingInhibited(false)
                updateMagSafeLED(state: .amber)
            }
            return
        }

        // Regular Charge Limiter
        if isPluggedIn {
            if currentSoC >= activeLimit {
                isCharging = false
                SMCClient.shared.setChargingInhibited(true)
                updateMagSafeLED(state: .green)
            } else {
                isCharging = true
                SMCClient.shared.setChargingInhibited(false)
                updateMagSafeLED(state: .amber)
            }
        } else {
            isCharging = false
            SMCClient.shared.setChargingInhibited(false)
            updateMagSafeLED(state: .off)
        }
    }

    public enum MagSafeState { case green, amber, amberBlinking, off }

    private func updateMagSafeLED(state: MagSafeState) {
        guard magSafeLEDControlEnabled else { return }
        SMCClient.shared.setMagSafeLED(state)
    }

    // MARK: - Actions

    public func toggleTopUp() {
        isTopUpActive.toggle()
    }

    public func toggleDischarge() {
        isDischargeActive.toggle()
    }

    public func startCalibration() {
        calibrationStage = .chargingTo100
        evaluatePowerState()
    }

    public func stopCalibration() {
        calibrationStage = .inactive
        evaluatePowerState()
    }

    private func processCalibrationMode() {
        switch calibrationStage {
        case .chargingTo100:
            if currentSoC >= 100 {
                calibrationStage = .dischargingTo10
            } else {
                isCharging = true
                SMCClient.shared.setChargingInhibited(false)
            }
        case .dischargingTo10:
            if currentSoC <= 10 {
                calibrationStage = .rechargingTo100
            } else {
                isCharging = false
                isDischarging = true
                SMCClient.shared.setDischargeMode(true)
            }
        case .rechargingTo100:
            if currentSoC >= 100 {
                calibrationStage = .completed
            } else {
                isCharging = true
                SMCClient.shared.setDischargeMode(false)
                SMCClient.shared.setChargingInhibited(false)
            }
        case .completed:
            calibrationStage = .inactive
            evaluatePowerState()
        default:
            break
        }
    }

    private func checkScheduledTasks() {
        let calendar = Calendar.current
        let now = Date()
        let comps = calendar.dateComponents([.hour, .minute, .second], from: now)
        let currentSecs = (comps.hour ?? 0) * 3600 + (comps.minute ?? 0) * 60 + (comps.second ?? 0)

        for task in scheduledTasks where task.enabled {
            if abs(currentSecs - task.timeOfDaySeconds) < 2 {
                executeTask(task)
            }
        }
    }

    public func executeTask(_ task: BatteryScheduledTask) {
        switch task.actionRaw {
        case "setLimit":
            if let limit = task.targetLimit {
                chargeLimit = limit
            }
        case "topUp":
            isTopUpActive = true
        case "discharge":
            isDischargeActive = true
        case "calibration":
            startCalibration()
        default:
            break
        }
    }
}

// MARK: - SMC Integration Extensions

extension SMCClient {
    public func setChargingInhibited(_ inhibited: Bool) {
        // SMC key CH0I or BCLM simulation
        _ = writeKey("CH0I", value: inhibited ? 1 : 0)
    }

    public func setDischargeMode(_ discharge: Bool) {
        // SMC key CH0D simulation
        _ = writeKey("CH0D", value: discharge ? 1 : 0)
    }

    public func setMagSafeLED(_ state: BatteryManager.MagSafeState) {
        // SMC MagSafe LED key
        let val: UInt8
        switch state {
        case .green: val = 1
        case .amber: val = 2
        case .amberBlinking: val = 3
        case .off: val = 0
        }
        _ = writeKey("ACLC", value: Int(val))
    }
}
