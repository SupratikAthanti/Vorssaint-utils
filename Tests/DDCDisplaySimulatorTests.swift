// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum DDCDisplaySimulatorTests {
    static func run(_ suite: TestSuite) {
        // 1. Test DDC packet construction for Luminance (0x10) and Contrast (0x12)
        let lumPacket = BrightnessSupport.writePacket(code: BrightnessSupport.luminanceCode, value: 75)
        let conPacket = BrightnessSupport.writePacket(code: BrightnessSupport.contrastCode, value: 60)

        suite.expect(lumPacket.count == 6, "Write packet has 6 bytes (length header, payload, checksum)")
        suite.expect(conPacket.count == 6, "Contrast write packet has 6 bytes")
        suite.expect(lumPacket[2] == 0x10, "Luminance VCP code is 0x10")
        suite.expect(conPacket[2] == 0x12, "Contrast VCP code is 0x12")

        // 2. Test DDC reply parsing and checksum validation
        var replyBytes: [UInt8] = [0x6e, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32]
        let checksum = replyBytes.reduce(UInt8(0x50)) { $0 ^ $1 }
        replyBytes.append(checksum)

        let parsed = BrightnessSupport.parseReply(replyBytes)
        suite.expect(parsed != nil, "Valid DDC reply parses successfully")
        if let parsed = parsed {
            suite.expect(parsed.maximum == 100, "Maximum luminance parsed as 100")
            suite.expect(parsed.current == 50, "Current luminance parsed as 50")
        }

        // Malformed checksum should fail parsing
        var invalidReply = replyBytes
        invalidReply[replyBytes.count - 1] ^= 0xFF
        suite.expect(BrightnessSupport.parseReply(invalidReply) == nil, "DDC reply with bad checksum is rejected")

        // 3. Test Channel Outcome classification
        let liveOutcome = BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: true)
        let writeOnlyOutcome = BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: false)
        let deadOutcome = BrightnessSupport.channelOutcome(writeAccepted: false, replyParsed: false)

        suite.expect(liveOutcome == .live, "Channel with replies is classified as live")
        suite.expect(writeOnlyOutcome == .writeOnly, "Channel accepting writes without reply is writeOnly")
        suite.expect(deadOutcome == .dead, "Channel rejecting writes is classified as dead")

        // 4. Test Software Dim Factor fallback
        let dimFactor = BrightnessSupport.softwareDimFactor(for: 0.4)
        suite.expectClose(Double(dimFactor), 0.4, "Software dim factor for 0.4 is 0.4")
    }
}
