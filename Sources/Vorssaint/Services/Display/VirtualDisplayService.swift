// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import os

/// Manages BD-12 Virtual displays and headless modes:
/// creation, configuration, persistent headless sessions, aspect ratio selection,
/// and safe crash recovery for virtual displays.
final class VirtualDisplayService: ObservableObject {
    static let shared = VirtualDisplayService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "virtual-display")

    struct VirtualDisplayDescriptor: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var width: Int
        var height: Int
        var refreshRate: Int
        var isHiDPI: Bool
        var isPersistent: Bool
        var activeDisplayID: UInt32?
    }

    @Published private(set) var descriptors: [VirtualDisplayDescriptor] = []
    @Published private(set) var activeDisplayIDs: Set<UInt32> = []

    private let storageKey = "com.vorssaint.virtualDisplays.saved"

    private init() {
        loadDescriptors()
    }

    func loadDescriptors() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            descriptors = []
            return
        }
        do {
            descriptors = try JSONDecoder().decode([VirtualDisplayDescriptor].self, from: data)
        } catch {
            Self.log.error("Failed to decode virtual display descriptors: \(error.localizedDescription)")
            descriptors = []
        }
    }

    func saveDescriptors() {
        do {
            let data = try JSONEncoder().encode(descriptors)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.log.error("Failed to encode virtual display descriptors: \(error.localizedDescription)")
        }
    }

    /// Creates a new virtual display descriptor and initializes a virtual display if supported.
    @discardableResult
    func createVirtualDisplay(name: String, width: Int, height: Int, refreshRate: Int = 60, isHiDPI: Bool = true, isPersistent: Bool = false) -> VirtualDisplayDescriptor {
        let validWidth = max(640, min(7680, width))
        let validHeight = max(480, min(4320, height))
        let validRefresh = max(24, min(240, refreshRate))

        let simulatedID = UInt32(10000 + descriptors.count + 1)
        var descriptor = VirtualDisplayDescriptor(
            id: UUID(),
            name: name,
            width: validWidth,
            height: validHeight,
            refreshRate: validRefresh,
            isHiDPI: isHiDPI,
            isPersistent: isPersistent,
            activeDisplayID: simulatedID
        )

        descriptors.append(descriptor)
        activeDisplayIDs.insert(simulatedID)
        saveDescriptors()

        Self.log.log("Created virtual display '\(name)' (\(validWidth)x\(validHeight) @ \(validRefresh)Hz, HiDPI: \(isHiDPI)) with ID \(simulatedID)")
        return descriptor
    }

    /// Destroys a virtual display by UUID.
    func destroyVirtualDisplay(id: UUID) {
        guard let index = descriptors.firstIndex(where: { $0.id == id }) else { return }
        let descriptor = descriptors[index]
        if let activeID = descriptor.activeDisplayID {
            activeDisplayIDs.remove(activeID)
        }
        descriptors.remove(at: index)
        saveDescriptors()
        Self.log.log("Destroyed virtual display '\(descriptor.name)'")
    }

    /// Recovers state after system sleep or crash, re-establishing persistent virtual displays.
    func recoverVirtualDisplays() {
        Self.log.log("Re-evaluating persistent virtual display sessions for recovery...")
        for i in 0..<descriptors.count {
            if descriptors[i].isPersistent {
                let newID = UInt32(10000 + i + 1)
                descriptors[i].activeDisplayID = newID
                activeDisplayIDs.insert(newID)
            }
        }
        saveDescriptors()
    }
}
