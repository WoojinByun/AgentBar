import XCTest
@testable import AgentBar

final class CodexUsageProviderTests: XCTestCase {

    var tempDir: URL!
    var testDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        suiteName = "CodexUsageProviderTests.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Directory Traversal

    func testFindsFilesInDateSubdirectories() async throws {
        // Create YYYY/MM/DD/ structure
        let dateDir = tempDir.appendingPathComponent("2026/02/13")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":200,"reasoning_output_tokens":100},"total_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":200,"reasoning_output_tokens":100}},"rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":\(Int(Date().addingTimeInterval(3600).timeIntervalSince1970))},"secondary":{"used_percent":2.0,"window_minutes":10080,"resets_at":\(Int(Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970))}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-2026-02-13T00-00-00-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.service, .codex)
        XCTAssertTrue(usage.isAvailable)
        // 5% of 10M = 500,000
        XCTAssertEqual(usage.fiveHourUsage.used, 500_000, accuracy: 1)
        // 2% of 100M = 2,000,000
        XCTAssertEqual(usage.weeklyUsage!.used, 2_000_000, accuracy: 1)
        XCTAssertEqual(usage.fiveHourUsage.unit, .tokens)
    }

    // MARK: - Rate Limits Parsing

    func testUsesLatestRateLimitsFromMostRecentFile() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/13")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let futureReset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let weeklyReset = Int(Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970)

        // First event: 1%
        // Second event: 3% (latest)
        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":\(futureReset)},"secondary":{"used_percent":0.5,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"output_tokens":200},"total_token_usage":{"input_tokens":500,"output_tokens":200}},"rate_limits":{"primary":{"used_percent":3.0,"window_minutes":300,"resets_at":\(futureReset)},"secondary":{"used_percent":1.5,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Should use the latest (3%)
        XCTAssertEqual(usage.fiveHourUsage.used, 300_000, accuracy: 1)
        XCTAssertEqual(usage.weeklyUsage!.used, 1_500_000, accuracy: 1)
    }

    func testTreats10080MinutePrimaryWindowAsWeeklyOnly() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/09/08")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let weeklyReset = Int(Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970)
        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        XCTAssertFalse(usage.showsFiveHourUsage)
        guard let weeklyUsage = usage.weeklyUsage else {
            return XCTFail("Expected the 7-day Codex window to be displayed.")
        }
        guard let resetTime = weeklyUsage.resetTime else {
            return XCTFail("Expected the 7-day Codex window to include a reset time.")
        }
        XCTAssertEqual(weeklyUsage.used, 1_000_000, accuracy: 1)
        XCTAssertEqual(resetTime.timeIntervalSince1970, Double(weeklyReset), accuracy: 1)
    }

    func testResetWindowMeansZeroUsage() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/13")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        // resets_at is in the past = window has already reset
        let pastReset = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970)

        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":50.0,"window_minutes":300,"resets_at":\(pastReset)},"secondary":{"used_percent":25.0,"window_minutes":10080,"resets_at":\(pastReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Past resets_at means usage has reset to 0
        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.weeklyUsage!.used, 0)
    }

    // MARK: - Event Type Filtering

    func testFiltersOnlyEventMsgTokenCount() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/14")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let futureReset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)

        let content = """
        {"timestamp":"\(now)","type":"session_meta","payload":{"id":"test"}}
        {"timestamp":"\(now)","type":"response_item","payload":{"type":"message"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"user_message"}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"output_tokens":50},"total_token_usage":{"input_tokens":100,"output_tokens":50}},"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":\(futureReset)},"secondary":{"used_percent":0.5,"window_minutes":10080,"resets_at":\(futureReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Only the token_count event_msg should be processed
        XCTAssertEqual(usage.fiveHourUsage.used, 100_000, accuracy: 1)
    }

    // MARK: - Token Summing Fallback

    func testFallsBackToTokenSummingWithoutRateLimits() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/14")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())

        // event_msg with token_count but no rate_limits
        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":200,"reasoning_output_tokens":100},"total_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":200,"reasoning_output_tokens":100}}}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"output_tokens":800,"cached_input_tokens":300,"reasoning_output_tokens":150},"total_token_usage":{"input_tokens":3000,"output_tokens":1300,"cached_input_tokens":500,"reasoning_output_tokens":250}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Fallback: sum last_token_usage from both events
        // Event 1: 1000+500+200+100 = 1800
        // Event 2: 2000+800+300+150 = 3250
        // Total: 5050
        XCTAssertEqual(usage.fiveHourUsage.used, 5050)
        XCTAssertEqual(usage.weeklyUsage!.used, 5050)
    }

    // MARK: - Multiple limit_id Merging

    func testMergesMultipleLimitIDs() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/15")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let futureReset1 = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let futureReset2 = Int(Date().addingTimeInterval(7200).timeIntervalSince1970)
        let weeklyReset = Int(Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970)

        // Two different limit_ids interleaved in the same session
        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":12.0,"window_minutes":300,"resets_at":\(futureReset1)},"secondary":{"used_percent":6.0,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":3.0,"window_minutes":300,"resets_at":\(futureReset2)},"secondary":{"used_percent":1.0,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Should sum: 12% + 3% = 15% of 10M = 1,500,000
        XCTAssertEqual(usage.fiveHourUsage.used, 1_500_000, accuracy: 1)
        // Should sum: 6% + 1% = 7% of 100M = 7,000,000
        XCTAssertEqual(usage.weeklyUsage!.used, 7_000_000, accuracy: 1)
        // Reset time should be the earliest (most conservative)
        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        XCTAssertEqual(
            usage.fiveHourUsage.resetTime!.timeIntervalSince1970,
            Double(futureReset1),
            accuracy: 1
        )
    }

    func testMergedLimitIDsKeepActiveUsageWhenOnePrimaryWindowIsStale() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/15")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let staleReset = Int(Date().addingTimeInterval(-3600).timeIntervalSince1970)
        let activeReset = Int(Date().addingTimeInterval(7200).timeIntervalSince1970)

        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":12.0,"window_minutes":300,"resets_at":\(staleReset)}}}}
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex_bengalfox","primary":{"used_percent":3.0,"window_minutes":300,"resets_at":\(activeReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Stale window should resolve to 0, while active window is still counted.
        XCTAssertEqual(usage.fiveHourUsage.used, 300_000, accuracy: 1)
        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        XCTAssertEqual(
            usage.fiveHourUsage.resetTime!.timeIntervalSince1970,
            Double(activeReset),
            accuracy: 1
        )
    }

    func testSingleLimitIDNotAffectedByMerge() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/15")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let futureReset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let weeklyReset = Int(Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970)

        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"codex","primary":{"used_percent":10.0,"window_minutes":300,"resets_at":\(futureReset)},"secondary":{"used_percent":4.0,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Single limit_id: 10% of 10M = 1,000,000
        XCTAssertEqual(usage.fiveHourUsage.used, 1_000_000, accuracy: 1)
        XCTAssertEqual(usage.weeklyUsage!.used, 4_000_000, accuracy: 1)
    }

    // MARK: - Edge Cases

    func testHandlesMissingDirectory() async {
        let provider = CodexUsageProvider(
            sessionsDir: URL(fileURLWithPath: "/nonexistent/path"),
            defaults: testDefaults
        )
        let isConfigured = await provider.isConfigured()
        XCTAssertFalse(isConfigured)
    }

    func testHandlesEmptyDirectory() async throws {
        let provider = CodexUsageProvider(sessionsDir: tempDir, defaults: testDefaults)
        let usage = try await provider.fetchUsage()

        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.weeklyUsage!.used, 0)
        XCTAssertTrue(usage.isAvailable)
    }

    // MARK: - Idle Session Caching

    func testPrefersCachedUsageWhenWindowBecomesStale() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/14")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let futureReset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)
        let weeklyReset = Int(Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970)

        // First fetch: active session with 10% usage
        let activeContent = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":\(futureReset)},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":\(weeklyReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try activeContent.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let firstUsage = try await provider.fetchUsage()
        XCTAssertEqual(firstUsage.fiveHourUsage.used, 1_000_000, accuracy: 1)

        // Second fetch: rewrite with stale resets_at but same future reset (simulates idle)
        // The window rolled over, resolveWindow returns 0, but cache should preserve value
        let staleReset = Int(Date().addingTimeInterval(-60).timeIntervalSince1970)
        let staleContent = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":\(staleReset)},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":\(staleReset)}}}}
        """
        try staleContent.write(to: file, atomically: true, encoding: .utf8)

        let secondUsage = try await provider.fetchUsage()

        // Cache should preserve the non-zero 5h value (reset time still in the future)
        XCTAssertEqual(secondUsage.fiveHourUsage.used, 1_000_000, accuracy: 1)
        XCTAssertNotNil(secondUsage.fiveHourUsage.resetTime)
    }

    func testCacheExpiredWhenResetTimePasses() async throws {
        // Pre-seed cache with usage that has an already-expired reset time
        let pastReset = Date().addingTimeInterval(-60)
        testDefaults.set(Double(500_000), forKey: "codexUsageCache.fiveHour.used")
        testDefaults.set(Double(10_000_000), forKey: "codexUsageCache.fiveHour.total")
        testDefaults.set(pastReset.timeIntervalSince1970, forKey: "codexUsageCache.fiveHour.resetTime")

        let provider = CodexUsageProvider(
            sessionsDir: tempDir,
            fiveHourTokenLimit: 10_000_000,
            weeklyTokenLimit: 100_000_000,
            defaults: testDefaults
        )
        let usage = try await provider.fetchUsage()

        // Cache expired → should return 0, not cached value
        XCTAssertEqual(usage.fiveHourUsage.used, 0)
    }

    func testResetTimeFromRateLimits() async throws {
        let dateDir = tempDir.appendingPathComponent("2026/02/14")
        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let now = ISO8601DateFormatter().string(from: Date())
        let futureReset = Int(Date().addingTimeInterval(3600).timeIntervalSince1970)

        let content = """
        {"timestamp":"\(now)","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":1.0,"window_minutes":300,"resets_at":\(futureReset)},"secondary":{"used_percent":0.5,"window_minutes":10080,"resets_at":\(futureReset)}}}}
        """
        let file = dateDir.appendingPathComponent("rollout-test.jsonl")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let provider = CodexUsageProvider(sessionsDir: tempDir, defaults: testDefaults)
        let usage = try await provider.fetchUsage()

        XCTAssertNotNil(usage.fiveHourUsage.resetTime)
        XCTAssertNotNil(usage.weeklyUsage?.resetTime)
    }
}
