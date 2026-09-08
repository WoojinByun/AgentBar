import Foundation
import Darwin

actor CodexUsageProvider: UsageProviderProtocol {
    nonisolated let serviceType: ServiceType = .codex
    private let readRateLimits: @Sendable () async throws -> Data
    private var lastSuccessfulUsage: UsageData?

    init(readRateLimits: @escaping @Sendable () async throws -> Data = {
        try await CodexAppServerClient().readRateLimits()
    }) {
        self.readRateLimits = readRateLimits
    }

    func isConfigured() async -> Bool { true }

    func fetchUsage() async throws -> UsageData {
        do {
            let response = try JSONDecoder().decode(CodexLiveRateLimits.self, from: await readRateLimits())
            guard let bucket = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits else {
                throw CodexUsageError.invalidResponse
            }
            let windows = [bucket.primary, bucket.secondary].compactMap { $0 }
            guard !windows.isEmpty,
                  windows.allSatisfy({ $0.usedPercent.isFinite && $0.usedPercent >= 0 && ($0.windowDurationMins ?? 0) > 0 })
            else { throw CodexUsageError.invalidResponse }

            // Slot names are historical; the labels always follow the server's actual duration.
            let weeklyOnly = windows.count == 1 && windows[0].windowDurationMins == 10_080
            let first = weeklyOnly ? nil : windows.first
            let second = weeklyOnly ? windows.first : windows.dropFirst().first
            let usage = UsageData(
                service: .codex,
                fiveHourUsage: first?.metric ?? .zero,
                weeklyUsage: second?.metric,
                lastUpdated: Date(),
                isAvailable: true,
                planName: bucket.displayPlan,
                showsFiveHourUsage: first != nil,
                primaryLabel: first?.label,
                secondaryLabel: second?.label,
                resetCredits: response.rateLimitResetCredits
            )
            lastSuccessfulUsage = usage
            return usage
        } catch {
            return UsageData(
                service: .codex,
                fiveHourUsage: lastSuccessfulUsage?.fiveHourUsage ?? .zero,
                weeklyUsage: lastSuccessfulUsage?.weeklyUsage,
                lastUpdated: lastSuccessfulUsage?.lastUpdated ?? Date(),
                isAvailable: false,
                planName: lastSuccessfulUsage?.planName,
                showsFiveHourUsage: lastSuccessfulUsage?.showsFiveHourUsage ?? false,
                primaryLabel: lastSuccessfulUsage?.primaryLabel,
                secondaryLabel: lastSuccessfulUsage?.secondaryLabel,
                resetCredits: lastSuccessfulUsage?.resetCredits,
                statusMessage: lastSuccessfulUsage == nil
                    ? "Usage unavailable — check Codex login"
                    : "Update failed — showing last known usage"
            )
        }
    }
}

private struct CodexLiveRateLimits: Decodable {
    let rateLimits: CodexLiveBucket?
    let rateLimitsByLimitId: [String: CodexLiveBucket]?
    let rateLimitResetCredits: UsageResetCredits?
}

private struct CodexLiveBucket: Decodable {
    let primary: CodexLiveWindow?
    let secondary: CodexLiveWindow?
    let planType: String?

    var displayPlan: String? {
        guard let planType else { return nil }
        if planType.contains("business") { return "Business" }
        switch planType {
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return nil
        }
    }
}

private struct CodexLiveWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    var metric: UsageMetric {
        UsageMetric(used: usedPercent, total: 100, unit: .percent,
                    resetTime: resetsAt.map { Date(timeIntervalSince1970: $0) })
    }

    var label: String {
        let minutes = windowDurationMins ?? 0
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }
}

enum CodexUsageError: Error {
    case executableMissing
    case timedOut
    case disconnected
    case invalidResponse
    case serverError
}

/// One short-lived stdio connection per refresh; no conversation or model turn is started.
struct CodexAppServerClient: Sendable {
    let executableURL: URL?
    let timeout: TimeInterval

    init(executableURL: URL? = nil, timeout: TimeInterval = 15) {
        self.executableURL = executableURL
        self.timeout = timeout
    }

    func readRateLimits() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try self.readSynchronously()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func readSynchronously() throws -> Data {
        guard let executable = executableURL ?? Self.findExecutable() else {
            throw CodexUsageError.executableMissing
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let ended = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" +
            (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in ended.signal() }
        // A server exiting during a request must produce an error, not SIGPIPE in the menu bar app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        defer {
            try? input.fileHandleForWriting.close()
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning && ended.wait(timeout: .now() + 0.25) == .timedOut {
                process.terminate()
                if ended.wait(timeout: .now() + 0.25) == .timedOut && process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    _ = ended.wait(timeout: .now() + 0.25)
                }
            }
        }
        try process.run()
        try input.fileHandleForReading.close()
        try output.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var buffer = Data()

        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
        }

        func response(id: Int) throws -> Data {
            while ProcessInfo.processInfo.systemUptime < deadline {
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    guard !line.isEmpty else { continue }
                    guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                        throw CodexUsageError.invalidResponse
                    }
                    guard object["id"] as? Int == id else { continue }
                    if object["error"] != nil { throw CodexUsageError.serverError }
                    guard let result = object["result"] as? [String: Any] else {
                        throw CodexUsageError.invalidResponse
                    }
                    return try JSONSerialization.data(withJSONObject: result)
                }
                let remaining = deadline - ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { break }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, Int32(min(remaining * 1_000, 1_000)))
                if ready < 0 {
                    if errno == EINTR { continue }
                    throw CodexUsageError.disconnected
                }
                if ready == 0 { continue }
                var bytes = [UInt8](repeating: 0, count: 8_192)
                let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                guard count > 0 else { throw CodexUsageError.disconnected }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 1_048_576 else { throw CodexUsageError.invalidResponse }
            }
            throw CodexUsageError.timedOut
        }

        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "agentbar", "title": "AgentBar", "version": "1.0"]
        ]])
        _ = try response(id: 1)
        try send(["method": "initialized", "params": [:]])
        try send(["id": 2, "method": "account/rateLimits/read"])
        return try response(id: 2)
    }

    static func findExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        directories += [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        let nodeVersions = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: nodeVersions, includingPropertiesForKeys: nil
        )) ?? []
        directories += versions.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }.map { $0.appendingPathComponent("bin").path }
        for directory in directories {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("codex")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }
}
