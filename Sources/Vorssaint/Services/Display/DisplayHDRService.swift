// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages HDR/XDR brightness, SDR/HDR color modes, Apple display presets,
/// and extra XDR brightness headroom with thermal/comfort advisories for Vorssaint (BD-15).
final class DisplayHDRService: ObservableObject {
    static let shared = DisplayHDRService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-hdr")

    @Published private(set) var availablePresets: [DisplayHDRSupport.DisplayPreset] = []
    @Published private(set) var currentPreset: DisplayHDRSupport.DisplayPreset?
    @Published private(set) var availableColorModes: [DisplayHDRSupport.ColorMode] = []
    @Published private(set) var currentColorMode: DisplayHDRSupport.ColorMode = .displayP3
    @Published private(set) var brightnessMetrics: DisplayHDRSupport.BrightnessMetrics = DisplayHDRSupport.BrightnessMetrics(sdrReferenceNits: 500.0, hdrPeakNits: 1600.0, currentEDRHeadroom: 3.2, potentialEDRHeadroom: 3.2)
    @Published private(set) var thermalState: DisplayHDRSupport.ThermalState = .normal
    @Published private(set) var effectiveHeadroom: Double = 3.2
    @Published private(set) var thermalAdvisory: String? = nil

    private init() {
        refreshHDRState()
    }

    /// Refreshes available presets, color modes, and XDR metrics for the display.
    func refreshHDRState(displayID: CGDirectDisplayID = CGMainDisplayID()) {
        availablePresets = DisplayHDRSupport.defaultPresets()
        availableColorModes = DisplayHDRSupport.ColorMode.allCases

        if currentPreset == nil {
            currentPreset = availablePresets.first
        }

        updateEffectiveMetrics()
    }

    /// Applies an Apple display preset (BD-15).
    func applyPreset(_ preset: DisplayHDRSupport.DisplayPreset) {
        currentPreset = preset
        currentColorMode = preset.colorMode
        updateEffectiveMetrics()
        Self.log.log("Applied display preset: \(preset.name)")
    }

    /// Applies a specific SDR/HDR color mode (BD-15).
    func applyColorMode(_ mode: DisplayHDRSupport.ColorMode) {
        guard let preset = currentPreset, DisplayHDRSupport.validateColorModeCompatibility(preset: preset, requestedMode: mode) else {
            Self.log.error("Color mode \(mode.rawValue) is incompatible with current preset.")
            return
        }
        currentColorMode = mode
        Self.log.log("Applied color mode: \(mode.rawValue)")
    }

    /// Updates thermal state and ambient lighting to recalculate XDR headroom and generate advisories.
    func updateThermalState(_ state: DisplayHDRSupport.ThermalState, ambientLux: Double = 500.0) {
        thermalState = state
        updateEffectiveMetrics(ambientLux: ambientLux)
    }

    private func updateEffectiveMetrics(ambientLux: Double = 500.0) {
        let basePotential = brightnessMetrics.potentialEDRHeadroom
        effectiveHeadroom = DisplayHDRSupport.calculateEffectiveHeadroom(potentialHeadroom: basePotential, thermalState: thermalState, ambientLightLux: ambientLux)
        thermalAdvisory = DisplayHDRSupport.generateThermalAdvisory(thermalState: thermalState, headroom: effectiveHeadroom)

        if let advisory = thermalAdvisory {
            Self.log.warning("XDR Thermal Advisory: \(advisory)")
        }
    }
}
