// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure logic and data structures for BD-15 (HDR/XDR brightness, color modes, Apple display presets,
/// and extra XDR brightness headroom with thermal/comfort advisories).
enum DisplayHDRSupport {
    enum ColorMode: String, CaseIterable, Equatable {
        case sRGB
        case displayP3 = "Apple Display P3"
        case dciP3 = "DCI-P3"
        case hdrReference = "HDR Reference"
        case hdrVideoP3ST2084 = "HDR Video (P3-ST 2084)"
        case photographyP3D65 = "Photography (P3-D65)"
        case designPrintP3D50 = "Design & Print (P3-D50)"
    }

    struct DisplayPreset: Equatable, Identifiable {
        let id: String
        let name: String
        let colorMode: ColorMode
        let targetSDRNits: Double
        let maxHDRNits: Double
        let supportsXDRHeadroom: Bool

        var isHDR: Bool {
            maxHDRNits > targetSDRNits || supportsXDRHeadroom
        }
    }

    struct BrightnessMetrics: Equatable {
        let sdrReferenceNits: Double
        let hdrPeakNits: Double
        let currentEDRHeadroom: Double
        let potentialEDRHeadroom: Double

        var isXDRActive: Bool {
            currentEDRHeadroom > 1.05 && hdrPeakNits > sdrReferenceNits
        }
    }

    enum ThermalState: Equatable, Comparable {
        case normal
        case warm
        case thermalThrottling
        case critical
    }

    static func defaultPresets() -> [DisplayPreset] {
        [
            DisplayPreset(id: "default", name: "Apple Display (Native)", colorMode: .displayP3, targetSDRNits: 500, maxHDRNits: 1600, supportsXDRHeadroom: true),
            DisplayPreset(id: "hdr-video", name: "HDR Video (P3-ST 2084)", colorMode: .hdrVideoP3ST2084, targetSDRNits: 500, maxHDRNits: 1000, supportsXDRHeadroom: true),
            DisplayPreset(id: "photo", name: "Photography (P3-D65)", colorMode: .photographyP3D65, targetSDRNits: 160, maxHDRNits: 160, supportsXDRHeadroom: false),
            DisplayPreset(id: "design", name: "Design & Print (P3-D50)", colorMode: .designPrintP3D50, targetSDRNits: 160, maxHDRNits: 160, supportsXDRHeadroom: false),
            DisplayPreset(id: "web", name: "Internet & Web (sRGB)", colorMode: .sRGB, targetSDRNits: 100, maxHDRNits: 100, supportsXDRHeadroom: false)
        ]
    }

    static func calculateEffectiveHeadroom(potentialHeadroom: Double, thermalState: ThermalState, ambientLightLux: Double) -> Double {
        let thermalMultiplier: Double
        switch thermalState {
        case .normal: thermalMultiplier = 1.0
        case .warm: thermalMultiplier = 0.85
        case .thermalThrottling: thermalMultiplier = 0.60
        case .critical: thermalMultiplier = 0.40
        }
        let ambientBoost = ambientLightLux > 10000 ? 1.05 : 1.0
        return max(1.0, potentialHeadroom * thermalMultiplier * ambientBoost)
    }

    static func generateThermalAdvisory(thermalState: ThermalState, headroom: Double) -> String? {
        switch thermalState {
        case .normal:
            return nil
        case .warm:
            return "Device temperature is elevated. Sustained XDR peak brightness is moderately limited."
        case .thermalThrottling:
            return "Thermal throttling active. XDR brightness headroom capped to protect display longevity."
        case .critical:
            return "Critical thermal state. XDR boost disabled to ensure device safety and comfort."
        }
    }

    static func validateColorModeCompatibility(preset: DisplayPreset, requestedMode: ColorMode) -> Bool {
        if preset.supportsXDRHeadroom {
            return requestedMode == preset.colorMode || requestedMode == .displayP3 || requestedMode == .hdrVideoP3ST2084
        } else {
            return requestedMode == preset.colorMode || requestedMode == .sRGB || requestedMode == .photographyP3D65 || requestedMode == .designPrintP3D50
        }
    }
}
