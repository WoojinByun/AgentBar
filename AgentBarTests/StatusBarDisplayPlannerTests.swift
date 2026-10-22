import XCTest
import SwiftUI
@testable import AgentBar

final class ServiceTypeColorTests: XCTestCase {
    func testCodexDarkColorIsGray400() {
        let color = ServiceType.codex.defaultDarkColor
        // gray-400: (0.60, 0.63, 0.67)
        let resolved = NSColor(color).usingColorSpace(.sRGB)!
        XCTAssertEqual(resolved.redComponent, 0.60, accuracy: 0.01)
        XCTAssertEqual(resolved.greenComponent, 0.63, accuracy: 0.01)
        XCTAssertEqual(resolved.blueComponent, 0.67, accuracy: 0.01)
    }

    func testAllServicesHaveDistinctDarkColors() {
        let colors = ServiceType.allCases.map { NSColor($0.defaultDarkColor).usingColorSpace(.sRGB)! }
        for i in 0..<colors.count {
            for j in (i + 1)..<colors.count {
                let same = abs(colors[i].redComponent - colors[j].redComponent) < 0.05
                    && abs(colors[i].greenComponent - colors[j].greenComponent) < 0.05
                    && abs(colors[i].blueComponent - colors[j].blueComponent) < 0.05
                XCTAssertFalse(same, "\(ServiceType.allCases[i]) and \(ServiceType.allCases[j]) have nearly identical darkColor")
            }
        }
    }

    func testCustomColorOverridesDefaultAndResetClearsIt() {
        let suiteName = "AgentBarTests.ServiceColor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(ServiceColorSettings.customColor(for: .claude, defaults: defaults))

        ServiceColorSettings.setCustomColor(Color(red: 1, green: 0, blue: 0), for: .claude, defaults: defaults)
        XCTAssertEqual(ServiceColorSettings.customHex(for: .claude, defaults: defaults), "#FF0000")
        let light = NSColor(ServiceColorSettings.customLightColor(for: .claude, defaults: defaults)!)
            .usingColorSpace(.sRGB)!
        XCTAssertEqual(light.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(light.greenComponent, 0.55, accuracy: 0.01)

        ServiceColorSettings.setCustomColor(nil, for: .claude, defaults: defaults)
        XCTAssertNil(ServiceColorSettings.customHex(for: .claude, defaults: defaults))
    }

    func testRejectsMalformedStoredHex() {
        let suiteName = "AgentBarTests.ServiceColor.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("not-a-color", forKey: ServiceColorSettings.defaultsKey(for: .codex))
        XCTAssertNil(ServiceColorSettings.customColor(for: .codex, defaults: defaults))
    }
}

final class StatusBarDisplayPlannerTests: XCTestCase {
    func testRanksServicesByHighestUsageScoreDescending() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.20, weeklyPct: 0.40),
            makeUsage(service: .codex, fiveHourPct: 0.90, weeklyPct: 0.10),
            makeUsage(service: .gemini, fiveHourPct: 0.50, weeklyPct: 0.60)
        ]

        let ranked = StatusBarDisplayPlanner.rankedServices(from: services)
        XCTAssertEqual(ranked.map(\.service), [.codex, .gemini, .claude])
    }

    func testIgnoresUnavailableServicesWhenRanking() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.8),
            makeUsage(service: .codex, fiveHourPct: 0.7),
            makeUsage(service: .gemini, fiveHourPct: 0.9, available: false)
        ]

        let ranked = StatusBarDisplayPlanner.rankedServices(from: services)
        XCTAssertEqual(ranked.map(\.service), [.claude, .codex])
    }

    func testMaxScrollIndexIsZeroWhenServicesWithinVisibleCount() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.95),
            makeUsage(service: .codex, fiveHourPct: 0.90),
            makeUsage(service: .gemini, fiveHourPct: 0.85)
        ]

        let ranked = StatusBarDisplayPlanner.rankedServices(from: services)
        XCTAssertEqual(StatusBarDisplayPlanner.maxScrollIndex(for: ranked), 0)
    }

    func testMaxScrollIndexEqualsOverflowRowCount() {
        let services = [
            makeUsage(service: .claude, fiveHourPct: 0.99),
            makeUsage(service: .codex, fiveHourPct: 0.98),
            makeUsage(service: .gemini, fiveHourPct: 0.97),
            makeUsage(service: .copilot, fiveHourPct: 0.96),
            makeUsage(service: .cursor, fiveHourPct: 0.95),
            makeUsage(service: .zai, fiveHourPct: 0.94),
            makeUsage(service: .claude, fiveHourPct: 0.93)
        ]

        let ranked = StatusBarDisplayPlanner.rankedServices(from: services)
        XCTAssertEqual(StatusBarDisplayPlanner.maxScrollIndex(for: ranked), 4)
    }

    func testTieBreakUsesServiceOrder() {
        let services = [
            makeUsage(service: .zai, fiveHourPct: 0.50),
            makeUsage(service: .codex, fiveHourPct: 0.50),
            makeUsage(service: .claude, fiveHourPct: 0.50)
        ]

        let ranked = StatusBarDisplayPlanner.rankedServices(from: services)
        XCTAssertEqual(ranked.map(\.service), [.claude, .codex, .zai])
    }

    func testTopPriorityHoldIsLongerThanStepHold() {
        XCTAssertGreaterThan(
            StatusBarDisplayPlanner.topPriorityHoldSeconds,
            StatusBarDisplayPlanner.scrollStepHoldSeconds
        )
    }

    func testRowFramesFillViewportHeightForOneTwoAndThreeRows() {
        let viewport = StatusBarDisplayPlanner.viewportHeight
        for count in 1...3 {
            let frames = StatusBarDisplayPlanner.rowFrames(forVisibleRowCount: count)
            XCTAssertEqual(frames.count, count)
            XCTAssertEqual(frames.first?.minY ?? -1, 0, accuracy: 0.0001, "\(count) rows: top gap")
            XCTAssertEqual(frames.last?.maxY ?? -1, viewport, accuracy: 0.0001, "\(count) rows: bottom gap")
            for (upper, lower) in zip(frames, frames.dropFirst()) {
                XCTAssertEqual(lower.minY - upper.maxY, StatusBarDisplayPlanner.rowSpacing, accuracy: 0.0001)
            }
            XCTAssertEqual(Set(frames.map(\.height)).count, 1, "rows share one height")
        }
    }

    func testClaudePlusCodexUsesTwoFullHeightRows() {
        // StackedBarView sizes rows by the ranked service count.
        let ranked = StatusBarDisplayPlanner.rankedServices(from: [
            makeUsage(service: .claude, fiveHourPct: 0.4),
            makeUsage(service: .codex, fiveHourPct: 0.2)
        ])
        XCTAssertEqual(ranked.count, 2)
        let frames = StatusBarDisplayPlanner.rowFrames(forVisibleRowCount: ranked.count)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].height, 9.5, accuracy: 0.0001)
        XCTAssertEqual(frames[0].minY, 0, accuracy: 0.0001)
        XCTAssertEqual(frames[1].maxY, StatusBarDisplayPlanner.viewportHeight, accuracy: 0.0001)
    }

    func testRowHeightSplitsViewportEvenly() {
        XCTAssertEqual(StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 1).rowHeight, 20, accuracy: 0.0001)
        XCTAssertEqual(StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 2).rowHeight, 9.5, accuracy: 0.0001)
        XCTAssertEqual(StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 3).rowHeight, 6, accuracy: 0.0001)
    }

    func testThreeRowLayoutKeepsOriginalLook() {
        let layout = StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 3)
        XCTAssertEqual(layout.spacing, 1)
        XCTAssertEqual(layout.labelFontSize, 6)
        XCTAssertEqual(layout.labelWidth, 14)
        XCTAssertEqual(layout.cornerRadius, 1.5)
    }

    func testRowCountIsClampedToVisibleRange() {
        XCTAssertEqual(
            StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 0),
            StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 1)
        )
        XCTAssertEqual(
            StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 7),
            StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: 3)
        )
    }

    func testLabelFontGrowsAsRowsGetTaller() {
        let sizes = (1...3).map { StatusBarDisplayPlanner.rowLayout(forVisibleRowCount: $0).labelFontSize }
        XCTAssertGreaterThan(sizes[0], sizes[1])
        XCTAssertGreaterThan(sizes[1], sizes[2])
    }


    private func makeUsage(
        service: ServiceType,
        fiveHourPct: Double,
        weeklyPct: Double = 0,
        available: Bool = true
    ) -> UsageData {
        UsageData(
            service: service,
            fiveHourUsage: UsageMetric(
                used: fiveHourPct * 100,
                total: 100,
                unit: .percent,
                resetTime: nil
            ),
            weeklyUsage: UsageMetric(
                used: weeklyPct * 100,
                total: 100,
                unit: .percent,
                resetTime: nil
            ),
            lastUpdated: Date(),
            isAvailable: available
        )
    }
}
