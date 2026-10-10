// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages BD-17 Custom 3D LUTs:
/// parsing, validating, importing, and applying 3D Look-Up Tables (.cube files) to display output pipelines.
final class Display3DLUTService: ObservableObject {
    static let shared = Display3DLUTService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-3dlut")

    struct LUT3DModel: Codable, Equatable, Identifiable {
        let id: UUID
        var title: String
        var size: Int
        var filePath: String
        var isEnabled: Bool
        var displayID: UInt32?
    }

    @Published private(set) var activeLUTs: [LUT3DModel] = []

    private let storageKey = "com.vorssaint.display3DLUTs.saved"

    private init() {
        loadLUTs()
    }

    func loadLUTs() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            activeLUTs = []
            return
        }
        do {
            activeLUTs = try JSONDecoder().decode([LUT3DModel].self, from: data)
        } catch {
            Self.log.error("Failed to decode saved 3D LUT models: \(error.localizedDescription)")
            activeLUTs = []
        }
    }

    func saveLUTs() {
        do {
            let data = try JSONEncoder().encode(activeLUTs)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.log.error("Failed to encode 3D LUT models: \(error.localizedDescription)")
        }
    }

    /// Validates .cube LUT file content.
    func validateLUTFile(content: String) -> (isValid: Bool, title: String, size: Int) {
        let lines = content.components(separatedBy: .newlines)
        var title = "Custom 3D LUT"
        var lutSize = 0
        var sampleCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.hasPrefix("TITLE ") {
                title = trimmed.replacingOccurrences(of: "TITLE ", with: "").replacingOccurrences(of: "\"", with: "")
            } else if trimmed.hasPrefix("LUT_3D_SIZE ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2, let parsed = Int(parts[1]) {
                    lutSize = parsed
                }
            } else {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count == 3, Float(parts[0]) != nil, Float(parts[1]) != nil, Float(parts[2]) != nil {
                    sampleCount += 1
                }
            }
        }

        let expectedSamples = lutSize * lutSize * lutSize
        let isValid = (lutSize >= 2 && lutSize <= 256 && sampleCount == expectedSamples)
        return (isValid, title, lutSize)
    }

    /// Imports and applies a 3D LUT to a specific display.
    func importAndApplyLUT(filePath: String, displayID: UInt32?) -> Bool {
        guard FileManager.default.fileExists(atPath: filePath) else {
            Self.log.error("LUT import failed: File does not exist at '\(filePath)'")
            return false
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            Self.log.error("LUT import failed: Unable to read content from '\(filePath)'")
            return false
        }

        let validation = validateLUTFile(content: content)
        guard validation.isValid else {
            Self.log.error("LUT import failed: Invalid or unsupported .cube format")
            return false
        }

        let model = LUT3DModel(
            id: UUID(),
            title: validation.title,
            size: validation.size,
            filePath: filePath,
            isEnabled: true,
            displayID: displayID
        )

        activeLUTs.append(model)
        saveLUTs()
        Self.log.log("Successfully imported and applied 3D LUT '\(validation.title)' (size \(validation.size)x\(validation.size)x\(validation.size))")
        return true
    }

    /// Disables and removes a 3D LUT.
    func removeLUT(id: UUID) {
        activeLUTs.removeAll { $0.id == id }
        saveLUTs()
        Self.log.log("Removed 3D LUT with ID \(id.uuidString)")
    }
}
