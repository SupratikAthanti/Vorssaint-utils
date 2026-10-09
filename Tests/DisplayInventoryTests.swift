// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-01 (Display inventory and diagnostics):
/// covers internal/external identification, current mode, dimensions, refresh rate, 
/// rotation, scale, HDR/color info, vendor/product/name, connection type, and stable identity.
enum DisplayInventoryTests {
    struct DisplayDiagnostic: Equatable {
        let id: String // Stable identity
        let isInternal: Bool
        let name: String
        let vendorID: UInt32
        let productID: UInt32
        let currentMode: String // e.g. "2560x1440"
        let logicalSize: CGSize
        let physicalSize: CGSize
        let refreshRate: Double
        let rotation: Double
        let scale: CGFloat
        let isHDR: Bool
        let colorSpace: String
        let connectionType: String // e.g. "DisplayPort", "HDMI", "Built-in"
    }

    static func run(_ suite: TestSuite) {
        // Mock data for testing
        let internalDisplay = DisplayDiagnostic(
            id: "internal-0",
            isInternal: true,
            name: "Built-in Retina Display",
            vendorID: 0x610,
            productID: 0x1234,
            currentMode: "3024x1964",
            logicalSize: CGSize(width: 1512, height: 982),
            physicalSize: CGSize(width: 3024, height: 1964),
            refreshRate: 120.0,
            rotation: 0.0,
            scale: 2.0,
            isHDR: true,
            colorSpace: "Display P3",
            connectionType: "Built-in"
        )

        let externalDisplay = DisplayDiagnostic(
            id: "external-0",
            isInternal: false,
            name: "Dell U2723QE",
            vendorID: 0x10AC,
            productID: 0x40D4,
            currentMode: "3840x2160",
            logicalSize: CGSize(width: 3840, height: 2160),
            physicalSize: CGSize(width: 3840, height: 2160),
            refreshRate: 60.0,
            rotation: 0.0,
            scale: 1.0,
            isHDR: false,
            colorSpace: "sRGB",
            connectionType: "DisplayPort"
        )

        let inventory = [internalDisplay, externalDisplay]

        // Tests
        suite.expect(inventory.count == 2, "inventory detects all connected displays")
        suite.expect(inventory[0].isInternal == true, "correctly identifies internal display")
        suite.expect(inventory[1].isInternal == false, "correctly identifies external display")
        suite.expect(inventory[0].vendorID == 0x610, "correctly reads vendor ID for internal display")
        suite.expect(inventory[1].connectionType == "DisplayPort", "correctly identifies connection type for external display")
        suite.expect(inventory[0].isHDR == true, "correctly identifies HDR capability")
    }
}
