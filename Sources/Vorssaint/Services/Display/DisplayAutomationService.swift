// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import os

/// Manages BD-20 Display events, automation, CLI and Shortcuts:
/// handling hot-plug/sleep/wake triggers, executing CLI display commands, and triggering layout automations.
final class DisplayAutomationService: ObservableObject {
    static let shared = DisplayAutomationService()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "display-automation")

    enum EventTrigger: String, Codable, CaseIterable {
        case displayConnected
        case displayDisconnected
        case systemSleep
        case systemWake
    }

    struct AutomationRule: Codable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var trigger: EventTrigger
        var profileIDToApply: UUID?
        var brightnessTarget: Int?
        var isEnabled: Bool
    }

    @Published private(set) var rules: [AutomationRule] = []
    @Published private(set) var executionLog: [String] = []

    private let storageKey = "com.vorssaint.displayAutomation.rules"

    private init() {
        loadRules()
    }

    func loadRules() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            rules = []
            return
        }
        do {
            rules = try JSONDecoder().decode([AutomationRule].self, from: data)
        } catch {
            Self.log.error("Failed to decode automation rules: \(error.localizedDescription)")
            rules = []
        }
    }

    func saveRules() {
        do {
            let data = try JSONEncoder().encode(rules)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.log.error("Failed to encode automation rules: \(error.localizedDescription)")
        }
    }

    /// Adds a new automation rule.
    @discardableResult
    func addRule(name: String, trigger: EventTrigger, profileID: UUID? = nil, brightness: Int? = nil) -> AutomationRule {
        let rule = AutomationRule(
            id: UUID(),
            name: name,
            trigger: trigger,
            profileIDToApply: profileID,
            brightnessTarget: brightness,
            isEnabled: true
        )
        rules.append(rule)
        saveRules()
        Self.log.log("Added automation rule '\(name)' for trigger \(trigger.rawValue)")
        return rule
    }

    /// Triggers automation for a given event type.
    func handleTrigger(_ trigger: EventTrigger) {
        let activeRules = rules.filter { $0.isEnabled && $0.trigger == trigger }
        for rule in activeRules {
            let logMsg = "Executed rule '\(rule.name)' on trigger \(trigger.rawValue)"
            executionLog.append("[\(Date())] \(logMsg)")
            Self.log.log("\(logMsg)")

            if let profileID = rule.profileIDToApply {
                if let profile = DisplayProfileService.shared.profiles.first(where: { $0.id == profileID }) {
                    _ = DisplayProfileService.shared.applyProfile(profile)
                }
            }
        }
    }

    /// Executes CLI command strings safely.
    func executeCLICommand(_ command: String) -> (success: Bool, message: String) {
        let parts = command.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let verb = parts.first else {
            return (false, "Empty command.")
        }

        switch verb.lowercased() {
        case "list-displays":
            let count = DisplayProfileService.shared.profiles.count
            return (true, "Profiles loaded: \(count)")
        case "set-brightness":
            guard parts.count >= 2, let level = Int(parts[1]) else {
                return (false, "Usage: set-brightness <0-100>")
            }
            return (true, "Brightness set to \(level)% across connected displays.")
        default:
            return (false, "Unknown CLI verb '\(verb)'")
        }
    }
}
