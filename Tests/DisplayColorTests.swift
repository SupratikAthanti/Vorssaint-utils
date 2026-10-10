// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import XCTest
@testable import Vorssaint

final class DisplayColorTests: XCTestCase {
    
    func testColorProfileEnumeration() {
        let profiles = DisplayColorSupport.getAvailableColorProfiles()
        XCTAssertFalse(profiles.isEmpty, "Should find at least one color profile")
    }
    
    func testSoftwareColorAdjustmentsDefault() {
        let adjustments = DisplayColorSupport.SoftwareAdjustments.default()
        XCTAssertEqual(adjustments.temperature, 6500)
        XCTAssertEqual(adjustments.hue, 0.0)
        XCTAssertEqual(adjustments.saturation, 1.0)
        XCTAssertEqual(adjustments.contrast, 1.0)
    }
    
    func testSoftwareColorAdjustmentReset() {
        var adjustments = DisplayColorSupport.SoftwareAdjustments(temperature: 5000, hue: 0.5, saturation: 0.8, contrast: 1.2)
        adjustments.reset()
        XCTAssertEqual(adjustments.temperature, 6500)
        XCTAssertEqual(adjustments.hue, 0.0)
        XCTAssertEqual(adjustments.saturation, 1.0)
        XCTAssertEqual(adjustments.contrast, 1.0)
    }
}
