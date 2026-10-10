// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages BD-18 Picture-in-picture, display streaming and selected-window streaming:
/// creating floating PIP preview windows for displays, virtual displays, or selected windows.
final class DisplayPIPService: ObservableObject {
    static let shared = DisplayPIPService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-pip")

    enum CaptureSourceType: String, Codable {
        case fullDisplay
        case virtualDisplay
        case selectedWindow
    }

    struct PIPSession: Codable, Equatable, Identifiable {
        let id: UUID
        var title: String
        var sourceType: CaptureSourceType
        var targetID: UInt32
        var frameRate: Int
        var isFloating: Bool
        var isRotated: Bool
        var isFlipped: Bool
        var isStreaming: Bool
    }

    @Published private(set) var activeSessions: [PIPSession] = []
    @Published var hasScreenRecordingPermission: Bool = true

    private init() {}

    /// Starts a picture-in-picture streaming session.
    func startPIPSession(title: String, sourceType: CaptureSourceType, targetID: UInt32, frameRate: Int = 60) -> PIPSession? {
        guard hasScreenRecordingPermission else {
            Self.log.error("PIP session creation failed: Screen recording permission is denied.")
            return nil
        }

        let validFrameRate = max(15, min(120, frameRate))
        let session = PIPSession(
            id: UUID(),
            title: title,
            sourceType: sourceType,
            targetID: targetID,
            frameRate: validFrameRate,
            isFloating: true,
            isRotated: false,
            isFlipped: false,
            isStreaming: true
        )

        activeSessions.append(session)
        Self.log.log("Started PIP streaming session '\(title)' (\(sourceType.rawValue), target: \(targetID) @ \(validFrameRate)fps)")
        return session
    }

    /// Stops a picture-in-picture streaming session.
    func stopPIPSession(id: UUID) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        let session = activeSessions[index]
        activeSessions.remove(at: index)
        Self.log.log("Stopped PIP session '\(session.title)'")
    }

    /// Updates session transformations (rotation / mirror flip).
    func updateSessionTransforms(id: UUID, isRotated: Bool, isFlipped: Bool) {
        guard let index = activeSessions.firstIndex(where: { $0.id == id }) else { return }
        activeSessions[index].isRotated = isRotated
        activeSessions[index].isFlipped = isFlipped
        Self.log.log("Updated PIP session '\(self.activeSessions[index].title)' transforms (rotated: \(isRotated), flipped: \(isFlipped))")
    }
}
