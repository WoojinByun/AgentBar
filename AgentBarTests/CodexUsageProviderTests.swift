import XCTest
@testable import AgentBar

final class CodexUsageProviderTests: XCTestCase {
    func testWeeklyOnlyResponseUsesServerPercentAndResetCredits() async throws {
        let provider = CodexUsageProvider(readRateLimits: { Self.response(percent: 34) })
        let usage = try await provider.fetchUsage()

        XCTAssertTrue(usage.isAvailable)
        XCTAssertFalse(usage.showsFiveHourUsage)
        XCTAssertEqual(usage.fiveHourUsage.used, 0)
        XCTAssertEqual(usage.weeklyUsage?.unit, .percent)
        XCTAssertEqual(usage.weeklyUsage?.used, 34)
        XCTAssertEqual(usage.weeklyUsage?.total, 100)
        XCTAssertEqual(usage.weeklyUsage?.resetTime, Date(timeIntervalSince1970: 1_789_444_879))
        XCTAssertEqual(usage.resetCredits?.availableCount, 2)
        XCTAssertEqual(usage.resetCredits?.credits?.first?.expiresAt, 1_791_080_828)
    }

    func testLiveZeroReplacesPreviouslyExhaustedUsage() async throws {
        let feed = ResponseFeed([.success(Self.response(percent: 100)), .success(Self.response(percent: 0))])
        let provider = CodexUsageProvider(readRateLimits: { try await feed.next() })
        _ = try await provider.fetchUsage()
        let refreshed = try await provider.fetchUsage()
        XCTAssertEqual(refreshed.weeklyUsage?.used, 0)
        XCTAssertTrue(refreshed.isAvailable)
    }

    func testFailedRefreshKeepsLastObservationAndMarksItStale() async throws {
        let feed = ResponseFeed([.success(Self.response(percent: 100)), .failure(APIError.unauthorized)])
        let provider = CodexUsageProvider(readRateLimits: { try await feed.next() })
        let first = try await provider.fetchUsage()
        let stale = try await provider.fetchUsage()
        XCTAssertEqual(stale.weeklyUsage?.used, 100)
        XCTAssertEqual(stale.lastUpdated, first.lastUpdated)
        XCTAssertFalse(stale.isAvailable)
        XCTAssertNotNil(stale.statusMessage)
    }

    func testInitialFailureDoesNotPresentZeroAsAvailableQuota() async throws {
        let provider = CodexUsageProvider(readRateLimits: { throw APIError.unauthorized })
        let usage = try await provider.fetchUsage()
        XCTAssertFalse(usage.isAvailable)
        XCTAssertFalse(usage.showsFiveHourUsage)
        XCTAssertNil(usage.weeklyUsage)
        XCTAssertNil(usage.resetCredits)
        XCTAssertNotNil(usage.statusMessage)
    }

    func testSelectsCodexBucketWithoutAddingOtherModelLimits() async throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}},"other":{"primary":{"usedPercent":80,"windowDurationMins":300}}}}"#.utf8)
        let provider = CodexUsageProvider(readRateLimits: { data })
        let usage = try await provider.fetchUsage()
        XCTAssertEqual(usage.fiveHourUsage.used, 12)
        XCTAssertEqual(usage.weeklyUsage?.used, 40)
        XCTAssertTrue(usage.showsFiveHourUsage)
    }

    func testUnknownDurationIsNotMislabelledFiveHours() async throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":60}}}"#.utf8)
        let provider = CodexUsageProvider(readRateLimits: { data })
        let usage = try await provider.fetchUsage()
        XCTAssertEqual(usage.primaryLabel, "1h")
        XCTAssertEqual(usage.fiveHourUsage.used, 20)
        XCTAssertNil(usage.weeklyUsage)
    }

    func testMissingQuotaIsUnavailableInsteadOfZero() async throws {
        let provider = CodexUsageProvider(readRateLimits: { Data(#"{"rateLimits":{"primary":null,"secondary":null}}"#.utf8) })
        let usage = try await provider.fetchUsage()
        XCTAssertFalse(usage.isAvailable)
    }

    func testUnknownResetCreditDetailsRemainUnknown() async throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080}},"rateLimitResetCredits":{"availableCount":2,"credits":null}}"#.utf8)
        let provider = CodexUsageProvider(readRateLimits: { data })
        let usage = try await provider.fetchUsage()
        XCTAssertEqual(usage.resetCredits?.availableCount, 2)
        XCTAssertNil(usage.resetCredits?.credits)
    }

    func testStdioHandshakeWaitsForInitializationAndReadsFragmentedResponse() async throws {
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        case "$initialize" in *'"initialize"'*) ;; *) exit 10;; esac
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        case "$initialized" in *'"initialized"'*) ;; *) exit 11;; esac
        IFS= read -r request
        case "$request" in *account*rateLimits*read*) ;; *) exit 12;; esac
        printf '%s\\n' '{"method":"unrelated/notification","params":{}}'
        printf '%s' '{"id":2,"result":{"rateLimits":'
        printf '%s\\n' '{"primary":{"usedPercent":34,"windowDurationMins":10080}}}}'
        IFS= read -r end
        """
        let directory = try makeExecutable(script)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = CodexAppServerClient(executableURL: directory.appendingPathComponent("codex"), timeout: 2)
        let data = try await client.readRateLimits()
        let provider = CodexUsageProvider(readRateLimits: { data })
        let usage = try await provider.fetchUsage()
        XCTAssertEqual(usage.weeklyUsage?.used, 34)
    }

    func testStdioTimeoutTerminatesUnresponsiveProcess() async throws {
        let directory = try makeExecutable("#!/bin/sh\ntrap '' TERM\nwhile IFS= read -r line; do :; done\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        let start = Date()
        let client = CodexAppServerClient(executableURL: directory.appendingPathComponent("codex"), timeout: 0.2)
        do {
            _ = try await client.readRateLimits()
            XCTFail("An unresponsive server must time out.")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        }
    }

    func testStdioServerErrorIsNotAcceptedAsQuota() async throws {
        let directory = try makeExecutable("#!/bin/sh\nread line\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'\nread line\nread line\nprintf '%s\\n' '{\"id\":2,\"error\":{\"code\":-32000,\"message\":\"Not logged in\"}}'\nread line\n")
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = CodexAppServerClient(executableURL: directory.appendingPathComponent("codex"), timeout: 2)
        do {
            _ = try await client.readRateLimits()
            XCTFail("Server errors must not become usage data.")
        } catch {}
    }

    private func makeExecutable(_ script: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("codex")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        return directory
    }

    private static func response(percent: Int) -> Data {
        Data("""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":\(percent),"windowDurationMins":10080,"resetsAt":1789444879},"secondary":null,"planType":"self_serve_business_prolite"},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"test-reset","resetType":"codexRateLimits","status":"available","expiresAt":1791080828,"title":"Full reset"}]}}
        """.utf8)
    }
}

private actor ResponseFeed {
    var responses: [Result<Data, APIError>]
    init(_ responses: [Result<Data, APIError>]) { self.responses = responses }
    func next() throws -> Data { try responses.removeFirst().get() }
}
