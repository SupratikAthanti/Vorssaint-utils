// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
#if canImport(Combine)
import Combine
#endif

protocol BatteryControlHardware: AnyObject {
    func sample() -> BatteryTelemetry?
    /// Returns true only when the hardware read-back matches the request.
    func setChargingInhibited(_ inhibited: Bool) -> Bool
    func setDischargeMode(_ discharge: Bool) -> Bool
    func setMagSafeLED(_ state: BatteryManager.MagSafeState) -> Bool
    func preventSleep(_ prevent: Bool) -> Bool
}

struct BatteryTelemetry {
    var charge: Int
    var pluggedIn: Bool
    var charging: Bool = false
    var temperature: Double?
    var hardwareCharge: Double?
    var wallWatts: Double = 0
    var batteryWatts: Double = 0
    var macWatts: Double = 0
    var observedAt: Date
}

/// Requested preferences never stand in for verified hardware state. The
/// production adapter is separate so unit tests cannot accidentally open SMC.
public final class BatteryManager: ObservableObject {
    #if VORSSAINT_TESTING
    // No production singleton or hardware factory exists in the test build.
    #else
    public static let shared = BatteryManager(hardware: NativeBatteryControlHardware(),
                                              defaults: .standard, startsPolling: true)
    #endif
    private let hardware: BatteryControlHardware
    private let defaults: UserDefaults
    private let now: () -> Date
    private var timer: Timer?
    private var telemetry: BatteryTelemetry?
    private var loading = true
    private var evaluating = false
    private var stopped = false
    private var ownsOverride = false
    private var chargingInhibited: Bool?
    static let enabledKey = "batteryControlEnabled"
    static let recoveryKey = "batteryControlRecoveryNeeded"
    static let maximumTelemetryAge: TimeInterval = 6

    @Published public private(set) var currentSoC = 0
    @Published public private(set) var hardwareSoC: Double?
    @Published public private(set) var isPluggedIn = false
    @Published public private(set) var isCharging = false
    @Published public private(set) var isDischarging = false
    @Published public private(set) var wallWatts = 0.0
    @Published public private(set) var batteryWatts = 0.0
    @Published public private(set) var macWatts = 0.0
    @Published public private(set) var batteryTemperatureCelsius = Double.nan
    @Published public private(set) var controlError: String?
    @Published public private(set) var heatProtectionTripped = false
    @Published public private(set) var calibrationStage: CalibrationStage = .inactive

    @Published public var controlEnabled = false {
        didSet { changed(Self.enabledKey, controlEnabled) }
    }
    @Published public var chargeLimit = 80 {
        didSet { changed(DefaultsKey.batteryChargeLimit, chargeLimit) }
    }
    @Published public var isTopUpActive = false {
        didSet { changed(DefaultsKey.batteryTopUpActive, isTopUpActive) }
    }
    @Published public var showHardwarePercentage = false {
        didSet { changed(DefaultsKey.batteryShowHardwarePercentage, showHardwarePercentage) }
    }
    @Published public var liveStatusIconsEnabled = true {
        didSet { changed(DefaultsKey.batteryLiveStatusIconsEnabled, liveStatusIconsEnabled) }
    }
    @Published public var disableSleepUntilLimit = false {
        didSet { changed(DefaultsKey.batteryDisableSleepUntilLimit, disableSleepUntilLimit) }
    }
    @Published public var stopChargingWhenSleeping = false {
        didSet { changed(DefaultsKey.batteryStopChargingWhenSleeping, stopChargingWhenSleeping) }
    }
    @Published public var stopChargingWhenAppClosed = false {
        didSet { changed(DefaultsKey.batteryStopChargingWhenAppClosed, stopChargingWhenAppClosed) }
    }
    @Published public var isDischargeActive = false {
        didSet { changed(DefaultsKey.batteryDischargeActive, isDischargeActive) }
    }
    @Published public var automaticDischarge = false {
        didSet { changed(DefaultsKey.batteryAutomaticDischarge, automaticDischarge) }
    }
    @Published public var sailingModeEnabled = false {
        didSet { changed(DefaultsKey.batterySailingModeEnabled, sailingModeEnabled) }
    }
    @Published public var sailingHysteresis = 5 {
        didSet { changed(DefaultsKey.batterySailingHysteresis, sailingHysteresis) }
    }
    @Published public var heatProtectionEnabled = false {
        didSet { changed(DefaultsKey.batteryHeatProtectionEnabled, heatProtectionEnabled) }
    }
    @Published public var heatProtectionThresholdCelsius = 35.0 {
        didSet { changed(DefaultsKey.batteryHeatProtectionThresholdCelsius, heatProtectionThresholdCelsius) }
    }
    @Published public var magSafeLEDControlEnabled = false {
        didSet { changed(DefaultsKey.batteryMagSafeLEDControlEnabled, magSafeLEDControlEnabled) }
    }
    @Published public var scheduledTasks: [BatteryScheduledTask] = [] {
        didSet {
            guard !loading, let data = try? JSONEncoder().encode(scheduledTasks) else { return }
            defaults.set(data, forKey: DefaultsKey.batteryScheduledTasks)
        }
    }

    public enum CalibrationStage: String, Codable {
        case inactive, chargingTo100, dischargingTo10, rechargingTo100, holding1Hour, completed
    }
    public enum MagSafeState { case green, amber, amberBlinking, off }
    public struct BatteryScheduledTask: Identifiable, Codable {
        public var id: UUID
        public var name: String
        public var actionRaw: String
        public var timeOfDaySeconds: Int
        public var enabled: Bool
        public var targetLimit: Int?
        public var lastRunDate: Date?
        public init(id: UUID = UUID(), name: String, actionRaw: String, timeOfDaySeconds: Int,
                    enabled: Bool, targetLimit: Int? = nil, lastRunDate: Date? = nil) {
            self.id = id; self.name = name; self.actionRaw = actionRaw
            self.timeOfDaySeconds = timeOfDaySeconds; self.enabled = enabled
            self.targetLimit = targetLimit; self.lastRunDate = lastRunDate
        }
    }

    init(hardware: BatteryControlHardware, defaults: UserDefaults,
         now: @escaping () -> Date = Date.init, startsPolling: Bool = false) {
        self.hardware = hardware; self.defaults = defaults; self.now = now
        controlEnabled = defaults.bool(forKey: Self.enabledKey)
        if defaults.object(forKey: DefaultsKey.batteryChargeLimit) != nil {
            chargeLimit = defaults.integer(forKey: DefaultsKey.batteryChargeLimit)
        }
        // Transient top-up/discharge requests never resume after a crash.
        showHardwarePercentage = defaults.bool(forKey: DefaultsKey.batteryShowHardwarePercentage)
        liveStatusIconsEnabled = defaults.object(forKey: DefaultsKey.batteryLiveStatusIconsEnabled) as? Bool ?? true
        disableSleepUntilLimit = defaults.bool(forKey: DefaultsKey.batteryDisableSleepUntilLimit)
        stopChargingWhenSleeping = defaults.bool(forKey: DefaultsKey.batteryStopChargingWhenSleeping)
        stopChargingWhenAppClosed = defaults.bool(forKey: DefaultsKey.batteryStopChargingWhenAppClosed)
        automaticDischarge = defaults.bool(forKey: DefaultsKey.batteryAutomaticDischarge)
        sailingModeEnabled = defaults.bool(forKey: DefaultsKey.batterySailingModeEnabled)
        sailingHysteresis = defaults.object(forKey: DefaultsKey.batterySailingHysteresis) as? Int ?? 5
        heatProtectionEnabled = defaults.bool(forKey: DefaultsKey.batteryHeatProtectionEnabled)
        heatProtectionThresholdCelsius = defaults.object(forKey: DefaultsKey.batteryHeatProtectionThresholdCelsius) as? Double ?? 35
        magSafeLEDControlEnabled = defaults.bool(forKey: DefaultsKey.batteryMagSafeLEDControlEnabled)
        if let data = defaults.data(forKey: DefaultsKey.batteryScheduledTasks), data.count <= 64 * 1024 {
            scheduledTasks = Array(((try? JSONDecoder().decode([BatteryScheduledTask].self, from: data)) ?? []).prefix(100))
        }
        loading = false
        if defaults.bool(forKey: Self.recoveryKey) {
            ownsOverride = true
            restoreAutomatic()
        }
        if startsPolling {
            pollTelemetry()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.pollTelemetry() }
        }
    }

    private func changed(_ key: String, _ value: Any) {
        guard !loading else { return }
        defaults.set(value, forKey: key)
        evaluatePowerState()
    }

    public func pollTelemetry() {
        guard !stopped else { return }
        acceptTelemetry(hardware.sample())
        if controlEnabled, freshTelemetry { checkScheduledTasks() }
    }

    func acceptTelemetry(_ reading: BatteryTelemetry?) {
        telemetry = reading
        if let reading, (0...100).contains(reading.charge) {
            let unplugged = isPluggedIn && !reading.pluggedIn
            currentSoC = reading.charge; isPluggedIn = reading.pluggedIn
            hardwareSoC = reading.hardwareCharge.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
            batteryTemperatureCelsius = reading.temperature ?? .nan
            wallWatts = reading.wallWatts.isFinite ? max(0, reading.wallWatts) : 0
            batteryWatts = reading.batteryWatts.isFinite ? reading.batteryWatts : 0
            macWatts = reading.macWatts.isFinite ? max(0, reading.macWatts) : 0
            if unplugged { isTopUpActive = false; isDischargeActive = false; calibrationStage = .inactive }
            if !controlEnabled { isCharging = reading.charging; isDischarging = !reading.pluggedIn }
        }
        evaluatePowerState()
    }

    private var freshTelemetry: Bool {
        guard let telemetry, (0...100).contains(telemetry.charge) else { return false }
        let age = now().timeIntervalSince(telemetry.observedAt)
        return age >= 0 && age <= Self.maximumTelemetryAge
    }

    public func evaluatePowerState() {
        guard !loading, !evaluating, !stopped else { return }
        evaluating = true
        defer { evaluating = false }
        guard controlEnabled else {
            calibrationStage = .inactive; heatProtectionTripped = false
            restoreAutomatic()
            return
        }
        guard freshTelemetry, (20...100).contains(chargeLimit), (1...20).contains(sailingHysteresis),
              heatProtectionThresholdCelsius.isFinite, (25...50).contains(heatProtectionThresholdCelsius) else {
            restoreAutomatic()
            controlError = "Battery control paused: invalid settings or stale telemetry."
            return
        }
        if heatProtectionEnabled {
            guard batteryTemperatureCelsius.isFinite, (0...80).contains(batteryTemperatureCelsius) else {
                restoreAutomatic(); controlError = "Battery control paused: temperature unavailable."; return
            }
            if batteryTemperatureCelsius >= heatProtectionThresholdCelsius { heatProtectionTripped = true }
            else if batteryTemperatureCelsius <= heatProtectionThresholdCelsius - 2 { heatProtectionTripped = false }
        } else { heatProtectionTripped = false }
        guard isPluggedIn else { restoreAutomatic(); return }
        if heatProtectionTripped {
            _ = apply(inhibited: true, discharge: false, preventSleep: false, led: .amberBlinking)
            return
        }
        if calibrationStage != .inactive {
            if calibrationStage == .chargingTo100 && currentSoC >= 100 { calibrationStage = .dischargingTo10 }
            if calibrationStage == .dischargingTo10 && currentSoC <= 10 { calibrationStage = .rechargingTo100 }
            if calibrationStage == .rechargingTo100 && currentSoC >= 100 { calibrationStage = .inactive }
            if calibrationStage != .inactive {
                let discharge = calibrationStage == .dischargingTo10
                _ = apply(inhibited: discharge, discharge: discharge, preventSleep: false, led: .amber)
                return
            }
        }
        let limit = isTopUpActive ? 100 : chargeLimit
        if currentSoC <= limit && isDischargeActive { isDischargeActive = false }
        let discharge = currentSoC > limit && (isDischargeActive || automaticDischarge)
        var inhibited = currentSoC >= limit
        if sailingModeEnabled, currentSoC < limit, currentSoC > limit - sailingHysteresis {
            inhibited = chargingInhibited ?? false
        }
        _ = apply(inhibited: inhibited || discharge, discharge: discharge,
                  preventSleep: disableSleepUntilLimit && !discharge && currentSoC < limit,
                  led: inhibited && !discharge ? .green : .amber)
    }

    @discardableResult
    private func apply(inhibited: Bool, discharge: Bool, preventSleep: Bool, led: MagSafeState) -> Bool {
        // Write-ahead recovery debt persists until all restorations read back.
        defaults.set(true, forKey: Self.recoveryKey); ownsOverride = true
        guard hardware.setDischargeMode(discharge), hardware.setChargingInhibited(inhibited),
              hardware.preventSleep(preventSleep) else {
            restoreAutomatic()
            controlError = "Battery hardware rejected the requested state; automatic control restoration was attempted."
            return false
        }
        chargingInhibited = inhibited
        isCharging = !inhibited && isPluggedIn; isDischarging = discharge
        controlError = nil
        if magSafeLEDControlEnabled, !hardware.setMagSafeLED(led) {
            controlError = "Battery state verified, but the MagSafe LED change failed."
        }
        return true
    }

    private func restoreAutomatic() {
        guard ownsOverride else { return }
        let discharge = hardware.setDischargeMode(false)
        let charge = hardware.setChargingInhibited(false)
        let sleep = hardware.preventSleep(false)
        if discharge && charge && sleep {
            ownsOverride = false; chargingInhibited = nil
            defaults.removeObject(forKey: Self.recoveryKey)
            isDischarging = telemetry.map { !$0.pluggedIn } ?? false
            isCharging = telemetry?.charging ?? false
            controlError = nil
        } else {
            controlError = "Unable to verify automatic battery control restoration. Retry or restart the Mac."
        }
        if magSafeLEDControlEnabled, !hardware.setMagSafeLED(.off) {
            controlError = "Unable to restore the MagSafe LED."
        }
    }

    func handleSleep() {
        guard controlEnabled, freshTelemetry else { restoreAutomatic(); return }
        _ = apply(inhibited: stopChargingWhenSleeping, discharge: false, preventSleep: false, led: .off)
        telemetry = nil
    }
    func handleWake() { telemetry = nil; pollTelemetry() }
    public func shutdown() {
        guard !stopped else { return }
        timer?.invalidate(); timer = nil
        if controlEnabled, stopChargingWhenAppClosed, freshTelemetry {
            _ = apply(inhibited: true, discharge: false, preventSleep: false, led: .off)
            // Keep recovery debt so the next launch restores system control first.
        } else { restoreAutomatic() }
        stopped = true
    }
    public func toggleTopUp() { isTopUpActive.toggle() }
    public func toggleDischarge() { isDischargeActive.toggle() }
    public func startCalibration() {
        guard controlEnabled, freshTelemetry else { return }
        isDischargeActive = false; calibrationStage = .chargingTo100; evaluatePowerState()
    }
    public func stopCalibration() { calibrationStage = .inactive; isDischargeActive = false; evaluatePowerState() }

    private func checkScheduledTasks() {
        let calendar = Calendar.current; let date = now()
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        for index in scheduledTasks.indices where scheduledTasks[index].enabled {
            let task = scheduledTasks[index]
            guard (0..<86400).contains(task.timeOfDaySeconds), seconds >= task.timeOfDaySeconds,
                  task.lastRunDate.map({ calendar.isDate($0, inSameDayAs: date) }) != true else { continue }
            executeTask(task); scheduledTasks[index].lastRunDate = date
        }
    }
    public func executeTask(_ task: BatteryScheduledTask) {
        guard controlEnabled, freshTelemetry else { return }
        switch task.actionRaw {
        case "setLimit": if let limit = task.targetLimit, (20...100).contains(limit) { chargeLimit = limit }
        case "topUp": isTopUpActive = true
        case "discharge": isDischargeActive = true
        case "calibration": startCalibration()
        default: break
        }
    }
}
