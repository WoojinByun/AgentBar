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
