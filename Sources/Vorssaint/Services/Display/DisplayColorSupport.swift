// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ColorSync

struct DisplayColorSupport {
    struct ColorProfile: Identifiable, Equatable {
        let id: String
        let name: String
    }
    
    struct SoftwareAdjustments: Equatable {
        var temperature: Double
        var hue: Double
        var saturation: Double
        var contrast: Double
        
        static func `default`() -> SoftwareAdjustments {
            SoftwareAdjustments(temperature: 6500, hue: 0.0, saturation: 1.0, contrast: 1.0)
        }
        
        mutating func reset() {
            self = .default()
        }
    }
    
    static func getAvailableColorProfiles() -> [ColorProfile] {
        // Mocking for now, as proper ColorSync might require complex setup
        return [
            ColorProfile(id: "sRGB", name: "sRGB IEC61966-2.1"),
            ColorProfile(id: "DisplayP3", name: "Display P3")
        ]
    }
}
