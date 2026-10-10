// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum DisplayLUTSecurityTests {
    static func run(_ suite: TestSuite) {
        let samples = Array(repeating: "0 0 0", count: 8).joined(separator: "\n")
        func valid(_ content: String) -> Bool { DisplayLUTContracts.validateLUTFile(content: content).isValid }
        suite.expect(valid("LUT_3D_SIZE 2\n" + samples), "production parser accepts a complete finite cube")
        for header in ["2097152", "9223372036854775807", "-1", "0", "257", "2 extra"] {
            suite.expect(!valid("LUT_3D_SIZE " + header + "\n" + samples), "invalid size rejected before arithmetic: " + header)
        }
        suite.expect(!valid("LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n" + samples), "duplicate headers rejected")
        suite.expect(!valid("LUT_3D_SIZE 2\nnan 0 0\n" + samples), "nonfinite samples rejected")
        suite.expect(!valid("LUT_3D_SIZE 2\n" + samples + "\n0 0 0"), "extra samples rejected")
        suite.expect(!valid(samples + "\nLUT_3D_SIZE 2"), "samples before the size rejected")
    }
}
