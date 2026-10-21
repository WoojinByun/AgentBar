import XCTest
@testable import AgentBar

// MARK: - Snapshot parsing and account mapping

final class ClaudeStatusLineSnapshotTests: XCTestCase {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    private func snapshotJSON(
        receivedAt: Int = 2_000_000_000,
        configDir: String = "",
        rateLimits: String = """
        {"five_hour":{"used_percentage":42.5,"resets_at":2000003600},"seven_day":{"used_percentage":7,"resets_at":2000500000}}
        """
    ) -> Data {
        Data("""
        {"version":1,"received_at":\(receivedAt),"config_dir":"\(configDir)","payload":{"session_id":"s-1","cost":{"total_api_duration_ms":1234},"rate_limits":\(rateLimits)}
        }
        """.utf8)
    }

    func testParsesStatusLinePayloadSchema() throws {
        let snapshot = try XCTUnwrap(ClaudeStatusLineSnapshot.parse(snapshotJSON()))

        XCTAssertEqual(snapshot.receivedAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertNil(snapshot.configDir)
        XCTAssertEqual(snapshot.fiveHour?.usedPercentage, 42.5)
        // resets_at is Unix epoch seconds.
        XCTAssertEqual(snapshot.fiveHour?.resetsAt, Date(timeIntervalSince1970: 2_000_003_600))
        XCTAssertEqual(snapshot.sevenDay?.usedPercentage, 7)
        XCTAssertEqual(snapshot.sessionID, "s-1")
        XCTAssertEqual(snapshot.apiDurationMs, 1234)
    }

    func testRejectsSnapshotWithoutAnyKnownWindow() {
        XCTAssertNil(ClaudeStatusLineSnapshot.parse(snapshotJSON(rateLimits: "{}")))
        XCTAssertNil(ClaudeStatusLineSnapshot.parse(Data("not json".utf8)))
    }

    func testDefaultLoginMatchesUnsetOrEmptyConfigDir() throws {
        let snapshot = try XCTUnwrap(ClaudeStatusLineSnapshot.parse(snapshotJSON(configDir: "")))
        XCTAssertTrue(snapshot.belongs(to: .defaultLogin))
        XCTAssertFalse(snapshot.belongs(to: ClaudeAccount(configDir: "~/.claude-2")))
    }

    func testCustomConfigDirMatchesWithAndWithoutTrailingSlash() throws {
        let account = ClaudeAccount(label: "two", configDir: "~/.claude-2")
        let accountWithSlash = ClaudeAccount(label: "two", configDir: "~/.claude-2/")

        for raw in ["\(Self.home)/.claude-2", "\(Self.home)/.claude-2/", "~/.claude-2", "\(Self.home)/./.claude-2"] {
            let snapshot = try XCTUnwrap(ClaudeStatusLineSnapshot.parse(snapshotJSON(configDir: raw)), raw)
            XCTAssertTrue(snapshot.belongs(to: account), raw)
            XCTAssertTrue(snapshot.belongs(to: accountWithSlash), raw)
            XCTAssertFalse(snapshot.belongs(to: .defaultLogin), raw)
        }
    }

    func testStorePicksNewestMatchingSnapshot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try snapshotJSON(receivedAt: 2_000_000_000).write(to: dir.appendingPathComponent("default.json"))
        try snapshotJSON(receivedAt: 2_000_000_500, configDir: "\(Self.home)/.claude-2/")
            .write(to: dir.appendingPathComponent("123.json"))
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("broken.json"))

        let store = ClaudeStatusLineSnapshotStore(directory: dir)
        XCTAssertEqual(store.latestSnapshot(for: .defaultLogin)?.receivedAt, Date(timeIntervalSince1970: 2_000_000_000))
        XCTAssertEqual(
            store.latestSnapshot(for: ClaudeAccount(configDir: "~/.claude-2"))?.receivedAt,
            Date(timeIntervalSince1970: 2_000_000_500)
        )
        XCTAssertNil(store.latestSnapshot(for: ClaudeAccount(configDir: "~/.claude-3")))
    }
}

// MARK: - Wrapper script

final class ClaudeStatusLineWrapperScriptTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private struct RunResult {
        let status: Int32
        let stdout: Data
    }

    private func runWrapper(stdin: Data, originalCommand: String?, configDir: String?) throws -> RunResult {
        let installer = ClaudeStatusLineInstaller(baseDirectory: tempDir.appendingPathComponent("base"))
        try FileManager.default.createDirectory(at: installer.baseDirectory, withIntermediateDirectories: true)
        try ClaudeStatusLineInstaller.wrapperScript.write(to: installer.wrapperURL, atomically: true, encoding: .utf8)

        var arguments = [installer.wrapperURL.path]
        if let originalCommand {
            let originalURL = tempDir.appendingPathComponent("original.cmd")
            try originalCommand.write(to: originalURL, atomically: true, encoding: .utf8)
            arguments.append(originalURL.path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        if let configDir { environment["CLAUDE_CONFIG_DIR"] = configDir }
        environment["CAPTURE_FILE"] = tempDir.appendingPathComponent("captured").path
        process.environment = environment

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(stdin)
        try input.fileHandleForWriting.close()
        let stdout = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(status: process.terminationStatus, stdout: stdout)
    }

    private var snapshotsDir: URL { tempDir.appendingPathComponent("base/snapshots") }

    func testPassesIdenticalStdinThroughAndPreservesStdoutAndExitCode() throws {
        // No trailing newline: the bytes must reach the original command unchanged.
        let payload = Data(#"{"session_id":"abc","rate_limits":{"five_hour":{"used_percentage":12.3,"resets_at":2000003600}}}"#.utf8)
        let result = try runWrapper(
            stdin: payload,
            originalCommand: #"cat > "$CAPTURE_FILE"; printf 'line one\nline two\n'; exit 3"#,
            configDir: "/tmp/agentbar test/.claude-2"
        )

        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "line one\nline two\n")
        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("captured")), payload)

        let files = try FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)
            .filter { $0.hasSuffix(".json") }
        XCTAssertEqual(files.count, 1)
        let snapshot = try XCTUnwrap(ClaudeStatusLineSnapshot.parse(
            Data(contentsOf: snapshotsDir.appendingPathComponent(files[0]))
        ))
        XCTAssertEqual(snapshot.configDir, "/tmp/agentbar test/.claude-2")
        XCTAssertEqual(snapshot.fiveHour?.usedPercentage, 12.3)
        XCTAssertEqual(snapshot.sessionID, "abc")
        XCTAssertLessThan(abs(snapshot.receivedAt.timeIntervalSinceNow), 30)
    }

    func testDefaultLoginSnapshotHasEmptyConfigDir() throws {
        let payload = Data(#"{"rate_limits":{"seven_day":{"used_percentage":50,"resets_at":2000500000}}}"#.utf8)
        let result = try runWrapper(stdin: payload, originalCommand: "cat >/dev/null", configDir: nil)

        XCTAssertEqual(result.status, 0)
        let snapshot = try XCTUnwrap(ClaudeStatusLineSnapshot.parse(
            Data(contentsOf: snapshotsDir.appendingPathComponent("default.json"))
        ))
        XCTAssertNil(snapshot.configDir)
        XCTAssertTrue(snapshot.belongs(to: .defaultLogin))
    }

    func testPayloadWithoutRateLimitsIsNotSavedButStillForwarded() throws {
        let payload = Data(#"{"session_id":"abc"}"#.utf8)
        let result = try runWrapper(
            stdin: payload,
            originalCommand: #"cat > "$CAPTURE_FILE"; echo ok"#,
            configDir: nil
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(data: result.stdout, encoding: .utf8), "ok\n")
        XCTAssertEqual(try Data(contentsOf: tempDir.appendingPathComponent("captured")), payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotsDir.appendingPathComponent("default.json").path))
    }

    func testMissingOriginalCommandExitsCleanlyWithoutOutput() throws {
        let payload = Data(#"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":2000003600}}}"#.utf8)
        let result = try runWrapper(stdin: payload, originalCommand: nil, configDir: nil)

        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotsDir.appendingPathComponent("default.json").path))
    }
}

// MARK: - Installer

final class ClaudeStatusLineInstallerTests: XCTestCase {
    private var tempDir: URL!
    private var installer: ClaudeStatusLineInstaller!

    private let orcaCommand = #"if [ -f "${HOME-}/.orca/agent-hooks/claude-statusline.sh" ]; then /bin/sh "${HOME-}/.orca/agent-hooks/claude-statusline.sh"; fi"#

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        installer = ClaudeStatusLineInstaller(
            baseDirectory: tempDir.appendingPathComponent("AppSupport/claude-statusline"),
            backupRoot: tempDir.appendingPathComponent("backups"),
            homeDirectory: tempDir.appendingPathComponent("home"),
            now: { Date(timeIntervalSince1970: 2_000_000_000) }
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func writeSettings(_ object: [String: Any], configDir: String?) throws -> URL {
        let url = installer.settingsURL(configDir: configDir)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        return url
    }

    private func readSettings(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    func testDefaultSettingsLiveInHomeDotClaude() {
        XCTAssertEqual(
            installer.settingsURL(configDir: nil).path,
            tempDir.appendingPathComponent("home/.claude/settings.json").path
        )
        XCTAssertEqual(installer.settingsURL(configDir: "/x/.claude-2").path, "/x/.claude-2/settings.json")
    }

    func testInstallUninstallRoundTripRestoresOriginalStatusLine() throws {
        let configDir = tempDir.appendingPathComponent("home/.claude-2").path
        let url = try writeSettings([
            "model": "opus",
            "statusLine": ["type": "command", "command": orcaCommand, "padding": 1]
        ], configDir: configDir)
        XCTAssertEqual(installer.state(configDir: configDir), .notInstalled)

        try installer.install(configDir: configDir)

        let installed = try readSettings(url)
        let statusLine = try XCTUnwrap(installed["statusLine"] as? [String: Any])
        let command = try XCTUnwrap(statusLine["command"] as? String)
        XCTAssertEqual(command, installer.wrapperCommand(configDir: configDir))
        XCTAssertEqual(statusLine["padding"] as? Int, 1, "other statusLine options are kept")
        XCTAssertEqual(installed["model"] as? String, "opus")
        // Orca treats any command naming its agent-hooks script as its own and rewrites it.
        XCTAssertFalse(command.contains("agent-hooks/claude-statusline"))
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: installer.wrapperURL.path))
        XCTAssertEqual(
            try String(contentsOf: installer.originalCommandURL(configDir: configDir), encoding: .utf8),
            orcaCommand
        )
        XCTAssertEqual(installer.state(configDir: configDir), .installed)

        // A backup of the pre-install file exists.
        let backups = FileManager.default.enumerator(atPath: tempDir.appendingPathComponent("backups").path)?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix("settings.json") } ?? []
        XCTAssertEqual(backups.count, 1)

        // Installing twice is a no-op and keeps the real original.
        try installer.install(configDir: configDir)
        XCTAssertEqual(
            try String(contentsOf: installer.originalCommandURL(configDir: configDir), encoding: .utf8),
            orcaCommand
        )

        try installer.uninstall(configDir: configDir)

        let restored = try readSettings(url)
        let restoredLine = try XCTUnwrap(restored["statusLine"] as? [String: Any])
        XCTAssertEqual(restoredLine["command"] as? String, orcaCommand)
        XCTAssertEqual(restoredLine["padding"] as? Int, 1)
        XCTAssertEqual(restored["model"] as? String, "opus")
        XCTAssertEqual(installer.state(configDir: configDir), .notInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.originalCommandURL(configDir: configDir).path))
    }

    func testInstallWithoutExistingStatusLineAndUninstallRemovesIt() throws {
        let url = try writeSettings(["theme": "dark"], configDir: nil)

        try installer.install(configDir: nil)
        XCTAssertNotNil(try readSettings(url)["statusLine"])
        XCTAssertEqual(installer.state(configDir: nil), .installed)

        try installer.uninstall(configDir: nil)
        let restored = try readSettings(url)
        XCTAssertNil(restored["statusLine"])
        XCTAssertEqual(restored["theme"] as? String, "dark")
    }

    func testDetectsWhenAnotherToolReplacedTheWrapper() throws {
        let url = try writeSettings(["statusLine": ["type": "command", "command": orcaCommand]], configDir: nil)
        try installer.install(configDir: nil)

        // Orca (or the user) writes its own command back.
        var settings = try readSettings(url)
        settings["statusLine"] = ["type": "command", "command": orcaCommand]
        try JSONSerialization.data(withJSONObject: settings).write(to: url)

        XCTAssertEqual(installer.state(configDir: nil), .replaced)

        // Reinstalling wraps the new command again.
        try installer.install(configDir: nil)
        XCTAssertEqual(installer.state(configDir: nil), .installed)

        // Uninstalling while replaced leaves the other tool's command alone.
        settings = try readSettings(url)
        settings["statusLine"] = ["type": "command", "command": "echo other"]
        try JSONSerialization.data(withJSONObject: settings).write(to: url)
        try installer.uninstall(configDir: nil)
        XCTAssertEqual((try readSettings(url)["statusLine"] as? [String: Any])?["command"] as? String, "echo other")
        XCTAssertEqual(installer.state(configDir: nil), .notInstalled)
    }

    func testSymlinkedSettingsAreWrappedOnceAndLinkIsKept() throws {
        // ~/.claude-2/settings.json -> ~/.claude/settings.json, as on the user's machine.
        let url = try writeSettings(["statusLine": ["type": "command", "command": orcaCommand]], configDir: nil)
        let second = tempDir.appendingPathComponent("home/.claude-2").path
        let link = installer.settingsURL(configDir: second)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)

        try installer.install(configDir: nil)
        try installer.install(configDir: second)

        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "symlink must survive")
        XCTAssertEqual(installer.state(configDir: nil), .installed)
        XCTAssertEqual(installer.state(configDir: second), .installed)
        XCTAssertEqual(
            try String(contentsOf: installer.originalCommandURL(configDir: second), encoding: .utf8),
            orcaCommand,
            "the wrapper must not wrap itself"
        )

        try installer.uninstall(configDir: second)
        try installer.uninstall(configDir: nil)
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))
        XCTAssertEqual((try readSettings(url)["statusLine"] as? [String: Any])?["command"] as? String, orcaCommand)
    }

    func testCheckerReportsStatusLineStateForAccounts() throws {
        _ = try writeSettings(["statusLine": ["type": "command", "command": orcaCommand]], configDir: nil)
        let second = tempDir.appendingPathComponent("home/.claude-2").path
        _ = try writeSettings([:], configDir: second)
        try installer.install(configDir: nil)

        let checker = AgentHookConfigurationChecker(
            codexConfigURL: tempDir.appendingPathComponent("none.toml"),
            claudeConfigURLs: [],
            statusLineInstaller: installer,
            claudeAccounts: [.defaultLogin, ClaudeAccount(configDir: second)]
        )
        let partial = checker.check().claudeStatusLine
        XCTAssertFalse(partial.isConfigured)
        XCTAssertTrue(partial.detail.contains("not installed"), partial.detail)

        try installer.install(configDir: second)
        XCTAssertTrue(checker.check().claudeStatusLine.isConfigured)
    }
}
