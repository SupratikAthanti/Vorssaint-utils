// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Key-Value Mock Store for AppleSMC registers CH0I, CH0D, ACLC, and B0RawSoC.
final class SMCRegisterStore {
    static let shared = SMCRegisterStore()

    let ch0iKey = SMCClient.Key(code: 0x43483049, name: "CH0I", dataSize: 1, dataType: "ui8 ")
    let ch0dKey = SMCClient.Key(code: 0x43483044, name: "CH0D", dataSize: 1, dataType: "ui8 ")
    let aclcKey = SMCClient.Key(code: 0x41434C43, name: "ACLC", dataSize: 1, dataType: "ui8 ")
    let b0RawSocKey = SMCClient.Key(code: 0x4230536F, name: "B0RawSoC", dataSize: 2, dataType: "ui16")

    private var rawStorage: [String: [UInt8]] = [:]
    private(set) var writeLog: [(key: String, value: Double, bytes: [UInt8])] = []

    func read(_ key: SMCClient.Key) -> Double? {
        guard let bytes = rawStorage[key.name] else { return nil }
        return SMCValueCodec.decode(bytes, type: key.dataType)
    }

    func write(_ value: Double, to key: SMCClient.Key) -> Bool {
        guard let bytes = SMCValueCodec.encode(value, type: key.dataType, size: Int(key.dataSize)) else {
            return false
        }
        rawStorage[key.name] = bytes
        writeLog.append((key: key.name, value: value, bytes: bytes))
        return true
    }

    func reset() {
        rawStorage.removeAll()
        writeLog.removeAll()
    }
}

enum MockSMCClientTests {
    static func run(_ suite: TestSuite) {
        let store = SMCRegisterStore.shared
        store.reset()

        // 1. CH0I Charge Limiter Inhibition (0 = charge, 1 = inhibit)
        let ch0iSuccess = store.write(1.0, to: store.ch0iKey)
        suite.expect(ch0iSuccess, "SMCValueCodec encoded CH0I = 1")
        suite.expect(store.read(store.ch0iKey) == 1.0, "CH0I reads back 1.0 (inhibit charging)")

        _ = store.write(0.0, to: store.ch0iKey)
        suite.expect(store.read(store.ch0iKey) == 0.0, "CH0I reads back 0.0 (enable charging)")

        // 2. CH0D Manual Discharge (0 = normal, 1 = discharge)
        let ch0dSuccess = store.write(1.0, to: store.ch0dKey)
        suite.expect(ch0dSuccess, "SMCValueCodec encoded CH0D = 1")
        suite.expect(store.read(store.ch0dKey) == 1.0, "CH0D reads back 1.0 (discharge mode active)")

        _ = store.write(0.0, to: store.ch0dKey)
        suite.expect(store.read(store.ch0dKey) == 0.0, "CH0D reads back 0.0 (discharge mode inactive)")

        // 3. ACLC MagSafe LED State (0 = auto, 1 = green, 2 = amber)
        let aclcSuccess = store.write(2.0, to: store.aclcKey)
        suite.expect(aclcSuccess, "SMCValueCodec encoded ACLC = 2")
        suite.expect(store.read(store.aclcKey) == 2.0, "ACLC reads back 2.0 (amber LED)")

        // 4. B0RawSoC Raw Hardware Charge Percentage (ui16)
        let rawSocSuccess = store.write(85.0, to: store.b0RawSocKey)
        suite.expect(rawSocSuccess, "SMCValueCodec encoded B0RawSoC = 85")
        suite.expect(store.read(store.b0RawSocKey) == 85.0, "B0RawSoC reads back 85% hardware charge")

        // 5. Assert complete write log sequence and bytes
        suite.expect(store.writeLog.count == 6, "Captured exactly 6 SMC register writes")
        suite.expect(store.writeLog[0].key == "CH0I" && store.writeLog[0].bytes == [1], "CH0I byte payload is [1]")
        suite.expect(store.writeLog[2].key == "CH0D" && store.writeLog[2].bytes == [1], "CH0D byte payload is [1]")
        suite.expect(store.writeLog[4].key == "ACLC" && store.writeLog[4].bytes == [2], "ACLC byte payload is [2]")
        suite.expect(store.writeLog[5].key == "B0RawSoC" && store.writeLog[5].bytes == [0, 85], "B0RawSoC ui16 byte payload is [0, 85]")
    }
}
