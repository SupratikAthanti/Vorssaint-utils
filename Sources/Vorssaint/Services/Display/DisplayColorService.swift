// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages color profiles, RGB/YCbCr modes, and software color controls for Vorssaint (BD-16).
final class DisplayColorService: ObservableObject {
    static let shared = DisplayColorService()
    
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-color")
    
    @Published private(set) var availableProfiles: [DisplayColorSupport.ColorProfile] = []
    @Published var currentProfileID: String = "sRGB"
    @Published var adjustments = DisplayColorSupport.SoftwareAdjustments.default()
    
    private init() {
        refreshColorState()
    }
    
    func refreshColorState() {
        availableProfiles = DisplayColorSupport.getAvailableColorProfiles()
    }
    
    func applyProfile(_ profileID: String) {
        currentProfileID = profileID
        Self.log.log("Applied color profile: \(profileID)")
    }
    
    func resetAdjustments() {
        adjustments.reset()
        Self.log.log("Reset software color adjustments")
    }
}
