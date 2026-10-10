// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Unit tests for BD-15 (HDR/XDR brightness and presets):
/// covers system-supported HDR/XDR brightness metrics, SDR/HDR color modes,
/// Apple display presets, and extra XDR brightness headroom with thermal/comfort advisories.
enum DisplayHDRTests {
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

    struct HDRPolicy {
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

    static func run(_ suite: TestSuite) {
        // 1. System-supported HDR/XDR brightness metrics
        let xdrMetrics = BrightnessMetrics(sdrReferenceNits: 500.0, hdrPeakNits: 1600.0, currentEDRHeadroom: 3.2, potentialEDRHeadroom: 3.2)
        suite.expect(xdrMetrics.isXDRActive, "identifies active XDR mode when EDR headroom and HDR peak nits exceed SDR")
        suite.expectClose(xdrMetrics.hdrPeakNits / xdrMetrics.sdrReferenceNits, 3.2, "calculates correct XDR brightness ratio")

        let sdrMetrics = BrightnessMetrics(sdrReferenceNits: 160.0, hdrPeakNits: 160.0, currentEDRHeadroom: 1.0, potentialEDRHeadroom: 1.0)
        suite.expect(!sdrMetrics.isXDRActive, "identifies standard SDR mode when peak matches reference")

        // 2. SDR/HDR Color Modes
        let allModes = ColorMode.allCases
        suite.expect(allModes.contains(.displayP3) && allModes.contains(.sRGB) && allModes.contains(.hdrVideoP3ST2084), "includes essential SDR and HDR color modes")

        // 3. Apple Display Presets
        let presets = HDRPolicy.defaultPresets()
        let nativePreset = presets.first(where: { $0.id == "default" })
        let photoPreset = presets.first(where: { $0.id == "photo" })

        suite.expect(nativePreset?.isHDR == true, "native preset supports HDR and XDR headroom")
        suite.expect(photoPreset?.isHDR == false, "photography reference preset restricts to SDR sRGB/P3 without XDR headroom")
        suite.expect(nativePreset?.targetSDRNits == 500.0, "native preset targets 500 nits SDR baseline")
        suite.expect(nativePreset?.maxHDRNits == 1600.0, "native preset reaches 1600 nits peak HDR")

        // Color mode compatibility validation
        if let native = nativePreset, let photo = photoPreset {
            suite.expect(HDRPolicy.validateColorModeCompatibility(preset: native, requestedMode: .displayP3), "compatible color mode allowed for native preset")
            suite.expect(HDRPolicy.validateColorModeCompatibility(preset: native, requestedMode: .hdrVideoP3ST2084), "HDR color mode compatible with XDR preset")
            suite.expect(!HDRPolicy.validateColorModeCompatibility(preset: photo, requestedMode: .hdrVideoP3ST2084), "incompatible HDR mode rejected for photography SDR preset")
            suite.expect(HDRPolicy.validateColorModeCompatibility(preset: photo, requestedMode: .photographyP3D65), "photography color mode compatible with photo preset")
        } else {
            suite.expect(false, "default presets should not be nil")
        }

        // 4. Extra XDR brightness headroom with thermal and comfort advisories
        let basePotential = 3.2
        let normalHeadroom = HDRPolicy.calculateEffectiveHeadroom(potentialHeadroom: basePotential, thermalState: .normal, ambientLightLux: 500)
        let warmHeadroom = HDRPolicy.calculateEffectiveHeadroom(potentialHeadroom: basePotential, thermalState: .warm, ambientLightLux: 500)
        let throttledHeadroom = HDRPolicy.calculateEffectiveHeadroom(potentialHeadroom: basePotential, thermalState: .thermalThrottling, ambientLightLux: 500)
        let criticalHeadroom = HDRPolicy.calculateEffectiveHeadroom(potentialHeadroom: basePotential, thermalState: .critical, ambientLightLux: 500)

        suite.expectClose(normalHeadroom, 3.2, "normal thermal state preserves full headroom")
        suite.expect(warmHeadroom < normalHeadroom, "warm thermal state reduces effective headroom")
        suite.expect(throttledHeadroom < warmHeadroom, "thermal throttling further restricts headroom")
        suite.expect(criticalHeadroom < throttledHeadroom, "critical thermal state imposes strict headroom limit")
        suite.expect(criticalHeadroom >= 1.0, "effective headroom never drops below 1.0 SDR floor")

        // Ambient lighting boost test
        let brightAmbientHeadroom = HDRPolicy.calculateEffectiveHeadroom(potentialHeadroom: basePotential, thermalState: .normal, ambientLightLux: 25000)
        suite.expect(brightAmbientHeadroom >= basePotential, "high ambient lighting provides headroom compensation")

        // Thermal and comfort advisories
        suite.expect(HDRPolicy.generateThermalAdvisory(thermalState: .normal, headroom: 3.2) == nil, "no advisory when thermal state is normal")
        let warmAdvisory = HDRPolicy.generateThermalAdvisory(thermalState: .warm, headroom: 2.7)
        let throttleAdvisory = HDRPolicy.generateThermalAdvisory(thermalState: .thermalThrottling, headroom: 1.9)
        let criticalAdvisory = HDRPolicy.generateThermalAdvisory(thermalState: .critical, headroom: 1.0)

        suite.expect(warmAdvisory != nil && warmAdvisory?.contains("elevated") == true, "generates clear warm temperature advisory")
        suite.expect(throttleAdvisory != nil && throttleAdvisory?.contains("throttling") == true, "generates thermal throttling advisory")
        suite.expect(criticalAdvisory != nil && criticalAdvisory?.contains("critical") == true, "generates critical thermal advisory for user safety and comfort")
    }
}
