// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

struct DisplayDiagnostic: Identifiable, Equatable {
    let id: String // Stable identity
    let displayID: CGDirectDisplayID
    let isInternal: Bool
    let name: String
    let vendorID: UInt32
    let productID: UInt32
    let currentMode: String
    let logicalSize: CGSize
    let physicalSize: CGSize
    let refreshRate: Double
    let rotation: Double
    let scale: CGFloat
    let isHDR: Bool
    let colorSpace: String
    let connectionType: String
}
