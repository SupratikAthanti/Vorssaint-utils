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

    private let smcClient = SMCClient()

    // MARK: - Published State
    @Published public private(set) var currentSoC: Int = 80 // Reported OS SoC
    @Published public private(set) var hardwareSoC: Double? = 80.4 // Hardware raw SoC (nil if unavailable)
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
        didSet {
            UserDefaults.standard.set(heatProtectionEnabled, forKey: DefaultsKey.batteryHeatProtectionEnabled)
            if !heatProtectionEnabled {
                heatProtectionTripped = false
            }
            evaluatePowerState()
        }
    }
    @Published public var heatProtectionThresholdCelsius: Double = 35.0 { // Default 35°C / 95°F
        didSet {
            UserDefaults.standard.set(heatProtectionThresholdCelsius, forKey: DefaultsKey.batteryHeatProtectionThresholdCelsius)
            evaluatePowerState()
        }
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
        public var lastRunDate: Date?

        public init(id: UUID = UUID(), name: String, actionRaw: String, timeOfDaySeconds: Int, enabled: Bool, targetLimit: Int? = nil, lastRunDate: Date? = nil) {
            self.id = id
            self.name = name
            self.actionRaw = actionRaw
            self.timeOfDaySeconds = timeOfDaySeconds
            self.enabled = enabled
            self.targetLimit = targetLimit
            self.lastRunDate = lastRunDate
        }
    }

    private var timer: Timer?
    private var sleepAssertionID: IOPMAssertionID = 0

    private func updateSleepAssertion(shouldPreventSleep: Bool) {
        if shouldPreventSleep && sleepAssertionID == 0 {
            IOPMAssertionCreateWithName("PreventUserIdleSystemSleep" as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Vorssaint Battery Limit Sleep Hold" as CFString,
                                        &sleepAssertionID)
        } else if !shouldPreventSleep && sleepAssertionID != 0 {
            IOPMAssertionRelease(sleepAssertionID)
            sleepAssertionID = 0
        }
    }

    public init() {
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
            smcClient?.setChargingInhibited(true)
        }
    }

    @objc private func handleWake() {
        evaluatePowerState()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.pollTelemetry()
        }
    }

    public func pollTelemetry() {
        // Request active power monitoring from SystemMonitor so telemetry stays fresh
        SystemMonitor.shared.requestPowerSampling()

        let snapshot = SystemMonitor.shared.snapshot
        guard let power = snapshot.power else { return }

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
            // Read raw SoC from SMC if key available, else match charge
            if let client = smcClient, let key = client.key(named: "B0RawSoC"), let raw = client.readValue(key) {
                hardwareSoC = raw
            } else {
                hardwareSoC = Double(charge)
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
        if heatProtectionEnabled {
            if batteryTemperatureCelsius >= heatProtectionThresholdCelsius {
                heatProtectionTripped = true
            } else if batteryTemperatureCelsius <= (heatProtectionThresholdCelsius - 2.0) {
                heatProtectionTripped = false
            }
        } else {
            heatProtectionTripped = false
        }

        if heatProtectionTripped {
            isCharging = false
            smcClient?.setChargingInhibited(true)
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
                smcClient?.setChargingInhibited(true)
                updateMagSafeLED(state: .green)
            } else {
                isCharging = false
                isDischarging = true
                smcClient?.setDischargeMode(true)
                updateMagSafeLED(state: .amber)
            }
            return
        } else {
            smcClient?.setDischargeMode(false)
            isDischarging = false
        }

        // Sailing Mode check
        if sailingModeEnabled && isPluggedIn {
            let lowerBound = activeLimit - sailingHysteresis
            if currentSoC >= activeLimit {
                isCharging = false
                smcClient?.setChargingInhibited(true)
                updateMagSafeLED(state: .green)
            } else if currentSoC <= lowerBound {
                isCharging = true
                smcClient?.setChargingInhibited(false)
                updateMagSafeLED(state: .amber)
            }
            return
        }

        // Sleep prevention check
        if disableSleepUntilLimit && isPluggedIn && currentSoC < activeLimit {
            updateSleepAssertion(shouldPreventSleep: true)
        } else {
            updateSleepAssertion(shouldPreventSleep: false)
        }

        // Regular Charge Limiter
        if isPluggedIn {
            if currentSoC >= activeLimit {
                isCharging = false
                smcClient?.setChargingInhibited(true)
                updateMagSafeLED(state: .green)
            } else {
                isCharging = true
                smcClient?.setChargingInhibited(false)
                updateMagSafeLED(state: .amber)
            }
        } else {
            isCharging = false
            smcClient?.setChargingInhibited(false)
            updateMagSafeLED(state: .off)
        }
    }

    public enum MagSafeState { case green, amber, amberBlinking, off }

    private func updateMagSafeLED(state: MagSafeState) {
        guard magSafeLEDControlEnabled else { return }
        smcClient?.setMagSafeLED(state)
    }

    // MARK: - Actions

    public func toggleTopUp() {
        isTopUpActive.toggle()
    }

    public func toggleDischarge() {
        isDischargeActive.toggle()
    }

    public func startCalibration() {
        isDischargeActive = false
        smcClient?.setDischargeMode(false)
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
                smcClient?.setChargingInhibited(false)
            }
        case .dischargingTo10:
            if currentSoC <= 10 {
                calibrationStage = .rechargingTo100
            } else {
                isCharging = false
                isDischarging = true
                smcClient?.setDischargeMode(true)
            }
        case .rechargingTo100:
            if currentSoC >= 100 {
                calibrationStage = .completed
            } else {
                isCharging = true
                smcClient?.setDischargeMode(false)
                smcClient?.setChargingInhibited(false)
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

        for i in 0..<scheduledTasks.count where scheduledTasks[i].enabled {
            let task = scheduledTasks[i]
            let taskTime = task.timeOfDaySeconds

            let alreadyRunToday: Bool = {
                guard let last = task.lastRunDate else { return false }
                return calendar.isDate(last, inSameDayAs: now)
            }()

            if !alreadyRunToday && currentSecs >= taskTime {
                executeTask(task)
                scheduledTasks[i].lastRunDate = now
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
        guard let key = self.key(named: "CH0I") else { return }
        try? self.writeBytes([inhibited ? 1 : 0], to: key)
    }

    public func setDischargeMode(_ discharge: Bool) {
        guard let key = self.key(named: "CH0D") else { return }
        try? self.writeBytes([discharge ? 1 : 0], to: key)
    }

    public func setMagSafeLED(_ state: BatteryManager.MagSafeState) {
        guard let key = self.key(named: "ACLC") else { return }
        let val: UInt8
        switch state {
        case .green: val = 1
        case .amber: val = 2
        case .amberBlinking: val = 3
        case .off: val = 0
        }
        try? self.writeBytes([val], to: key)
    }
}
