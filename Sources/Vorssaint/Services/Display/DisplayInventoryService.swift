// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

final class DisplayInventoryService: ObservableObject {
    static let shared = DisplayInventoryService()
    
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-inventory")
    
    @Published private(set) var displays: [DisplayDiagnostic] = []
    
    private init() {
        refreshInventory()
    }
    
    func refreshInventory() {
        var displayCount: UInt32 = 0
        let maxDisplays: UInt32 = 16
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        
        let result = CGGetOnlineDisplayList(maxDisplays, &displayIDs, &displayCount)
        guard result == .success else {
            Self.log.error("Failed to get online display list: error \(result.rawValue)")
            return
        }
        
        var diagnostics: [DisplayDiagnostic] = []
        
        for i in 0..<Int(displayCount) {
            let id = displayIDs[i]
            
            let isMain = (id == CGMainDisplayID())
            let mode = CGDisplayCopyDisplayMode(id)
            let width = CGDisplayPixelsWide(id)
            let height = CGDisplayPixelsHigh(id)
            
            let diagnostic = DisplayDiagnostic(
                id: "display-\(id)",
                displayID: id,
                isInternal: isMain,
                name: isMain ? "Built-in Display" : "External Display",
                vendorID: 0,
                productID: 0,
                currentMode: "\(width)x\(height)",
                logicalSize: CGSize(width: width, height: height),
                physicalSize: CGSize(width: width, height: height),
                refreshRate: mode?.refreshRate ?? 60.0,
                rotation: 0.0,
                scale: 1.0,
                isHDR: false,
                colorSpace: "sRGB",
                connectionType: isMain ? "Built-in" : "DisplayPort"
            )
            diagnostics.append(diagnostic)
        }
        
        self.displays = diagnostics
    }
}
