// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum MainIconTemperatureReadoutTests {
    static func run(_ suite: TestSuite) {
        testDefaults(suite)
        testRenderingFormats(suite)
        testStatusItemClickBehavior(suite)
    }

    private static func testDefaults(_ suite: TestSuite) {
        let suiteName = "vorss.tests.mainicon.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "Failed to create isolated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults.register(defaults: [
            DefaultsKey.menuBarReplaceMainIconWithTemperature: false,
            DefaultsKey.menuBarMainIconTemperatureLayout: MainIconTemperatureLayout.defaultLayout.rawValue,
            DefaultsKey.menuBarMainIconTopMetric: MenuBarMetric.cpuTemperature.rawValue,
            DefaultsKey.menuBarMainIconBottomMetric: MenuBarMetric.gpuTemperature.rawValue,
        ])

        let replaceIcon = defaults.bool(forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
        suite.expect(replaceIcon == false, "Main icon replacement default is off")

        let layout = defaults.string(forKey: DefaultsKey.menuBarMainIconTemperatureLayout)
            ?? MainIconTemperatureLayout.defaultLayout.rawValue
        suite.expect(layout == "stacked", "Main icon temperature layout default is stacked")

        let topMetric = defaults.string(forKey: DefaultsKey.menuBarMainIconTopMetric)
            ?? MenuBarMetric.cpuTemperature.rawValue
        suite.expect(topMetric == MenuBarMetric.cpuTemperature.rawValue, "Top metric default is cpuTemperature")

        let bottomMetric = defaults.string(forKey: DefaultsKey.menuBarMainIconBottomMetric)
            ?? MenuBarMetric.gpuTemperature.rawValue
        suite.expect(bottomMetric == MenuBarMetric.gpuTemperature.rawValue, "Bottom metric default is gpuTemperature")
    }

    private static func testRenderingFormats(_ suite: TestSuite) {
        let suiteName = "vorss.tests.mainicon.rendering.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            suite.expect(false, "Failed to create isolated defaults suite")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        defaults.set(TemperatureUnit.celsius.rawValue, forKey: DefaultsKey.temperatureUnit)
        defaults.set(true, forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
        defaults.set("stacked", forKey: DefaultsKey.menuBarMainIconTemperatureLayout)
        defaults.set(MenuBarMetric.cpuTemperature.rawValue, forKey: DefaultsKey.menuBarMainIconTopMetric)
        defaults.set(MenuBarMetric.gpuTemperature.rawValue, forKey: DefaultsKey.menuBarMainIconBottomMetric)

        var snapshot = SystemSnapshot()
        snapshot.cpuTemperature = 45.0
        snapshot.gpuTemperature = 42.0
        snapshot.batteryTemperature = 33.0

        // Test stacked rendering string helper
        let stackedSegments = MenuBarRenderer.mainIconTemperatureSegments(for: snapshot, in: defaults)
        suite.expect(!stackedSegments.isEmpty, "Stacked main icon temperature segments generated")

        let stackedText = stackedSegments.compactMap { segment -> String? in
            if case let .text(str) = segment { return str }
            if case let .metricBlock(_, value, _, _, _) = segment { return value }
            return nil
        }.joined()

        suite.expect(stackedText.contains("45°"), "Stacked text contains top temperature 45°")
        suite.expect(stackedText.contains("42°"), "Stacked text contains bottom temperature 42°")

        // Test side-by-side rendering string helper
        defaults.set("sideBySide", forKey: DefaultsKey.menuBarMainIconTemperatureLayout)
        let sideSegments = MenuBarRenderer.mainIconTemperatureSegments(for: snapshot, in: defaults)
        suite.expect(!sideSegments.isEmpty, "Side-by-side main icon temperature segments generated")

        let sideText = sideSegments.compactMap { segment -> String? in
            if case let .text(str) = segment { return str }
            if case let .metricBlock(_, value, _, _, _) = segment { return value }
            return nil
        }.joined()

        suite.expect(sideText.contains("45°") && sideText.contains("42°"), "Side-by-side text contains both 45° and 42°")
    }

    private static func testStatusItemClickBehavior(_ suite: TestSuite) {
        let previousReplace = UserDefaults.standard.object(forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
        defer {
            if let previousReplace {
                UserDefaults.standard.set(previousReplace, forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
            } else {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
            }
        }

        UserDefaults.standard.set(true, forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)

        var mainPanelOpened = false
        let controller = StatusItemController()
        controller.onLeftClick = {
            mainPanelOpened = true
        }

        guard let button = controller.button,
              let target = button.target,
              let action = button.action else {
            suite.expect(false, "Status item button, target, or action missing")
            return
        }

        suite.expect(target === controller, "Status item button target is controller")

        // Perform actual action on button target
        _ = (target as AnyObject).perform(action, with: button)
        suite.expect(mainPanelOpened, "Status item button action triggers onLeftClick callback to open main panel")
    }
}
