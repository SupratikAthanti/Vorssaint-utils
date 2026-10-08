// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MainIconTemperatureReadoutTests {
    static func run(_ suite: TestSuite) {
        testDefaults(suite)
        testRenderingFormats(suite)
        testStatusItemClickBehavior(suite)
    }

    private static func testDefaults(_ suite: TestSuite) {
        let defaults = UserDefaults.standard

        // Check defaults registration
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
        var snapshot = SystemSnapshot()
        snapshot.cpuTemperature = 45.0
        snapshot.gpuTemperature = 42.0
        snapshot.batteryTemperature = 33.0

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
        defaults.set("stacked", forKey: DefaultsKey.menuBarMainIconTemperatureLayout)
        defaults.set(MenuBarMetric.cpuTemperature.rawValue, forKey: DefaultsKey.menuBarMainIconTopMetric)
        defaults.set(MenuBarMetric.gpuTemperature.rawValue, forKey: DefaultsKey.menuBarMainIconBottomMetric)

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

        // Reset defaults
        defaults.removeObject(forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
        defaults.removeObject(forKey: DefaultsKey.menuBarMainIconTemperatureLayout)
        defaults.removeObject(forKey: DefaultsKey.menuBarMainIconTopMetric)
        defaults.removeObject(forKey: DefaultsKey.menuBarMainIconBottomMetric)
    }

    private static func testStatusItemClickBehavior(_ suite: TestSuite) {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)

        var mainPanelOpened = false
        let controller = StatusItemController()
        controller.onLeftClick = {
            mainPanelOpened = true
        }

        // Simulate click
        controller.onLeftClick?()
        suite.expect(mainPanelOpened, "Clicking status item opens main homepage/panel when icon is replaced with temperatures")

        defaults.removeObject(forKey: DefaultsKey.menuBarReplaceMainIconWithTemperature)
    }
}
