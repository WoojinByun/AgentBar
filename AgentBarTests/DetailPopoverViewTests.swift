import XCTest
import AppKit
import SwiftUI
@testable import AgentBar

@MainActor
final class DetailPopoverViewTests: XCTestCase {

    func testDetailPopoverScrollsWhenUsageRowsOverflow() {
        let viewModel = UsageViewModel(providers: [])
        viewModel.usageData = makeUsageRows(count: 36)

        let rendered = renderPopover(viewModel: viewModel)
        let scrollView = waitForScrollViewLayout(in: rendered.hostingView)

        XCTAssertNotNil(scrollView, "Expected a scroll view when usage data is present.")
        guard let scrollView else { return }

        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = scrollView.documentView?.bounds.height ?? 0
        let viewportWidth = scrollView.contentView.bounds.width
        let documentWidth = scrollView.documentView?.bounds.width ?? 0

        XCTAssertGreaterThan(
            documentHeight,
            viewportHeight,
            "Expected overflow rows to exceed the viewport so content is scrollable."
        )
        XCTAssertGreaterThan(viewportWidth, 0, "Expected a non-zero scroll viewport width.")
        XCTAssertEqual(
            documentWidth,
            viewportWidth,
            accuracy: 2.0,
            "Expected usage rows to expand to the full scroll viewport width."
        )

        withExtendedLifetime(rendered.window) {}
    }

    func testDetailPopoverReservesSpaceOutsideScrollRegionForFooter() {
        let viewModel = UsageViewModel(providers: [])
        viewModel.usageData = makeUsageRows(count: 36)

        let rendered = renderPopover(viewModel: viewModel)
        let scrollView = waitForScrollViewLayout(in: rendered.hostingView)

        XCTAssertNotNil(scrollView, "Expected a scroll view when usage data is present.")
        guard let scrollView else { return }

        let scrollFrame = scrollView.convert(scrollView.bounds, to: rendered.hostingView)
        XCTAssertGreaterThan(scrollFrame.height, 0, "Expected a non-zero scroll region height after layout.")
        let nonScrollHeight = rendered.hostingView.bounds.height - scrollFrame.height
        XCTAssertGreaterThan(
            nonScrollHeight,
            80,
            "Expected fixed header/footer chrome to remain visible outside the scroll region."
        )

        withExtendedLifetime(rendered.window) {}
    }

    func testBuyMeACoffeeActionOpensExpectedURL() {
        withBuyMeACoffeeHidden(false) {
            let viewModel = UsageViewModel(providers: [])
            var openedURLs: [URL] = []

            let view = DetailPopoverView(viewModel: viewModel) { url in
                openedURLs.append(url)
            }
            view.triggerBMCForTesting()

            XCTAssertEqual(
                openedURLs.first?.absoluteString,
                "https://buymeacoffee.com/_scari",
                "Expected tapping Buy Me a Coffee to attempt opening the BMC support URL."
            )
        }
    }

    func testBuyMeACoffeeButtonCanBeHiddenFromSettings() {
        withBuyMeACoffeeHidden(true) {
            let viewModel = UsageViewModel(providers: [])
            let view = DetailPopoverView(viewModel: viewModel)
            XCTAssertFalse(view.isBMCButtonVisibleForTesting())
        }
    }

    func testBuyMeACoffeeButtonVisibleWhenNotHidden() {
        withBuyMeACoffeeHidden(false) {
            let viewModel = UsageViewModel(providers: [])
            let view = DetailPopoverView(viewModel: viewModel)
            XCTAssertTrue(view.isBMCButtonVisibleForTesting())
        }
    }

    func testSortedForDisplayOrdersByHighestUsageDescending() {
        let input = [
            UsageData.mock(service: .claude, fiveHourPct: 0.20, weeklyPct: 0.40),
            UsageData.mock(service: .codex, fiveHourPct: 0.90, weeklyPct: 0.10),
            UsageData.mock(service: .gemini, fiveHourPct: 0.50, weeklyPct: 0.60)
        ]

        let sorted = DetailPopoverView.sortedForDisplay(input)

        XCTAssertEqual(sorted.map(\.service), [.codex, .gemini, .claude])
    }

    func testSortedForDisplayUsesServiceOrderAsTieBreaker() {
        let input = [
            UsageData.mock(service: .zai, fiveHourPct: 0.50, weeklyPct: 0.50),
            UsageData.mock(service: .codex, fiveHourPct: 0.50, weeklyPct: 0.50),
            UsageData.mock(service: .claude, fiveHourPct: 0.50, weeklyPct: 0.50)
        ]

        let sorted = DetailPopoverView.sortedForDisplay(input)

        XCTAssertEqual(sorted.map(\.service), [.claude, .codex, .zai])
    }

    func testSortedForDisplayKeepsUnavailableRows() {
        let unavailable = UsageData(
            service: .claude,
            fiveHourUsage: UsageMetric(used: 1, total: 100, unit: .percent, resetTime: nil),
            weeklyUsage: nil,
            lastUpdated: Date(),
            isAvailable: false
        )
        let available = UsageData.mock(service: .codex, fiveHourPct: 0.30, weeklyPct: 0.30)

        let sorted = DetailPopoverView.sortedForDisplay([unavailable, available])

        XCTAssertEqual(sorted.count, 2)
        XCTAssertTrue(sorted.contains { $0.service == .claude && !$0.isAvailable })
    }

    func testResolvedVersionStringPrefersTagOverCommitHash() {
        let version = DetailPopoverView.resolvedVersionString(from: [
            "GitVersionTag": "v1.2.3",
            "GitCommitHash": "abc1234",
            "CFBundleShortVersionString": "1.0"
        ])

        XCTAssertEqual(version, "v1.2.3")
    }

    func testResolvedVersionStringUsesCommitHashWithoutTag() {
        let version = DetailPopoverView.resolvedVersionString(from: [
            "GitVersionTag": "   ",
            "GitCommitHash": "abc1234",
            "CFBundleShortVersionString": "1.0"
        ])

        XCTAssertEqual(version, "abc1234")
    }

    func testResolvedVersionStringFallsBackToBundleVersionWhenTagAndHashMissing() {
        let version = DetailPopoverView.resolvedVersionString(from: [
            "CFBundleShortVersionString": "1.0"
        ])

        XCTAssertEqual(version, "1.0")
    }

    func testResolvedVersionStringReturnsUnknownWhenAllValuesMissing() {
        XCTAssertEqual(DetailPopoverView.resolvedVersionString(from: nil), "unknown")
        XCTAssertEqual(DetailPopoverView.resolvedVersionString(from: [:]), "unknown")
    }

    func testResetTimestampTextShowsLocalDateAndTimeWithoutLabel() {
        let resetTime = Date(timeIntervalSince1970: 1_788_873_180)

        let text = MetricRow.resetTimestampText(for: resetTime, timeZone: TimeZone(secondsFromGMT: 0)!)

        XCTAssertEqual(text, "09/08 13:13")
    }

    private func makeUsageRows(count: Int) -> [UsageData] {
        let services = ServiceType.allCases
        return (0..<count).map { index in
            UsageData.mock(service: services[index % services.count])
        }
    }

    private func renderPopover(
        viewModel: UsageViewModel,
        openExternalURL: @escaping (URL) -> Void = { _ in }
    ) -> (window: NSWindow, hostingView: NSHostingView<DetailPopoverView>) {
        let rootView = DetailPopoverView(viewModel: viewModel, openExternalURL: openExternalURL)
        let hostingView = NSHostingView(rootView: rootView)
        let frame = NSRect(x: 0, y: 0, width: 320, height: 480)
        hostingView.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.contentView = hostingView
        window.layoutIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        return (window, hostingView)
    }

    private func waitForScrollViewLayout(
        in hostingView: NSView,
        timeout: TimeInterval = 1.0
    ) -> NSScrollView? {
        let deadline = Date().addingTimeInterval(timeout)
        var previousSizes: (viewport: CGSize, document: CGSize)?

        while Date() < deadline {
            hostingView.layoutSubtreeIfNeeded()

            if let scrollView = findFirstScrollView(in: hostingView),
               let documentView = scrollView.documentView {
                let viewportSize = scrollView.contentView.bounds.size
                let documentSize = documentView.bounds.size

                if viewportSize.width > 0, viewportSize.height > 0,
                   documentSize.width > 0, documentSize.height > 0 {
                    if let previousSizes,
                       abs(previousSizes.viewport.width - viewportSize.width) < 0.5,
                       abs(previousSizes.viewport.height - viewportSize.height) < 0.5,
                       abs(previousSizes.document.width - documentSize.width) < 0.5,
                       abs(previousSizes.document.height - documentSize.height) < 0.5 {
                        return scrollView
                    }
                    previousSizes = (viewportSize, documentSize)
                }
            }

            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        XCTFail("Timed out waiting for scroll view layout to stabilize with non-zero dimensions.")
        return nil
    }

    private func findFirstScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for child in view.subviews {
            if let match = findFirstScrollView(in: child) {
                return match
            }
        }
        return nil
    }

    private func withBuyMeACoffeeHidden(
        _ isHidden: Bool,
        testBody: () -> Void
    ) {
        let defaults = UserDefaults.standard
        let key = BuyMeACoffeeSettings.hideButtonKey
        let previousValue = defaults.object(forKey: key)
        defaults.set(isHidden, forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        testBody()
    }

}
