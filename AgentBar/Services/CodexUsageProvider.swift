import Foundation
import Darwin

private final class CodexAppServerResponseBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let responseSignal = DispatchSemaphore(value: 0)
    private var bufferedData = Data()
    private var response: String?

    func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        bufferedData.append(data)
        while let newline = bufferedData.firstRange(of: Data([0x0A])) {
            let lineData = bufferedData[..<newline.lowerBound]
            bufferedData.removeSubrange(...newline.lowerBound)
            guard response == nil,
                  let line = String(data: lineData, encoding: .utf8),
                  let payload = try? JSONDecoder().decode(CodexAppServerResponse.self, from: lineData),
                  payload.id == 2 else { continue }
            response = line
            responseSignal.signal()
        }
    }

    func wait(timeout: TimeInterval) -> String? {
        _ = responseSignal.wait(timeout: .now() + timeout)
        lock.lock()
        defer { lock.unlock() }
        return response
    }

    func finish() {
        responseSignal.signal()
    }
}

// MARK: - Codex Session Record Models (matches actual ~/.codex/sessions/ JSONL)

struct CodexSessionRecord: Decodable, Sendable {
    let timestamp: String?
    let type: String?
    let payload: CodexPayload?
}

struct CodexPayload: Decodable, Sendable {
    let type: String?
    let info: CodexTokenInfo?
    let rate_limits: CodexRateLimits?
}

struct CodexTokenInfo: Decodable, Sendable {
    let total_token_usage: CodexTokenUsage?
    let last_token_usage: CodexTokenUsage?
}

struct CodexTokenUsage: Decodable, Sendable {
    let input_tokens: Int?
    let output_tokens: Int?
    let cached_input_tokens: Int?
    let reasoning_output_tokens: Int?
    let total_tokens: Int?

    var totalTokens: Int {
        (input_tokens ?? 0) +
        (cached_input_tokens ?? 0) +
        (output_tokens ?? 0) +
        (reasoning_output_tokens ?? 0)
    }
}

struct CodexRateLimits: Decodable, Sendable {
    let limit_id: String?
    let primary: CodexRateWindow?
    let secondary: CodexRateWindow?
}

struct CodexRateWindow: Decodable, Sendable {
    let used_percent: Double?
    let window_minutes: Int?
    let resets_at: Int?
}

struct CodexAppServerResponse: Decodable, Sendable {
    let id: Int?
    let result: CodexAppServerResult?
}

struct CodexAppServerResult: Decodable, Sendable {
    let rateLimits: CodexAppServerRateLimits?
    let rateLimitsByLimitId: [String: CodexAppServerRateLimits]?
}

struct CodexAppServerRateLimits: Decodable, Sendable {
    let limitId: String?
    let primary: CodexAppServerRateWindow?
    let secondary: CodexAppServerRateWindow?

    var sessionRateLimits: CodexRateLimits {
        CodexRateLimits(
            limit_id: limitId,
            primary: primary?.sessionRateWindow,
            secondary: secondary?.sessionRateWindow
        )
    }
}

struct CodexAppServerRateWindow: Decodable, Sendable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Int?

    var sessionRateWindow: CodexRateWindow {
        CodexRateWindow(
            used_percent: usedPercent,
            window_minutes: windowDurationMins,
            resets_at: resetsAt
        )
    }
}

// MARK: - Provider

final class CodexUsageProvider: UsageProviderProtocol, @unchecked Sendable {
    let serviceType: ServiceType = .codex
    private static let appServerTimeout: TimeInterval = 5

    private let sessionsDir: URL
    private let fiveHourTokenLimit: Double
    private let weeklyTokenLimit: Double
    private let defaults: UserDefaults
    private let appServerResponseProvider: @Sendable () -> String?
    private let hasAppServerSource: Bool

    init(
        sessionsDir: URL? = nil,
        fiveHourTokenLimit: Double = 10_000_000,
        weeklyTokenLimit: Double = 100_000_000,
        defaults: UserDefaults = .standard,
        appServerResponseProvider: (@Sendable () -> String?)? = nil,
        codexExecutableProvider: (@Sendable () -> URL?)? = nil
    ) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.sessionsDir = sessionsDir ?? home.appendingPathComponent(".codex/sessions")
        self.fiveHourTokenLimit = fiveHourTokenLimit
        self.weeklyTokenLimit = weeklyTokenLimit
        self.defaults = defaults

        if let appServerResponseProvider {
            self.appServerResponseProvider = appServerResponseProvider
            self.hasAppServerSource = true
        } else if sessionsDir == nil || codexExecutableProvider != nil {
            let executableURL: URL?
            if let codexExecutableProvider {
                executableURL = codexExecutableProvider()
            } else {
                executableURL = Self.findCodexExecutable(
                    environment: ProcessInfo.processInfo.environment,
                    homeDirectory: home
                )
            }
            self.appServerResponseProvider = {
                guard let executableURL else { return nil }
                return Self.runAppServer(
                    executableURL: executableURL,
                    timeout: Self.appServerTimeout
                )
            }
            self.hasAppServerSource = executableURL != nil
        } else {
            self.appServerResponseProvider = { nil }
            self.hasAppServerSource = false
        }
    }

    func isConfigured() async -> Bool {
        hasAppServerSource || FileManager.default.fileExists(atPath: sessionsDir.path)
    }

    func fetchUsage() async throws -> UsageData {
        let now = Date()

        let liveRateLimits = appServerResponseProvider()
            .flatMap(Self.parseAppServerRateLimits)
        let latestRateLimits = liveRateLimits ?? findLatestRateLimits(now: now)

        let fiveHourMetric: UsageMetric
        let weeklyMetric: UsageMetric
        var showsFiveHourUsage = true

        if let rateLimits = latestRateLimits {
            let primaryWindows = rateLimits.compactMap(\.primary)
            let secondaryWindows = rateLimits.compactMap(\.secondary)
            let allWindows = primaryWindows + secondaryWindows
            let explicitFiveHourWindows = allWindows.filter { $0.window_minutes == 5 * 60 }
            let explicitWeeklyWindows = allWindows.filter { $0.window_minutes == 7 * 24 * 60 }
            let fiveHourWindows = explicitFiveHourWindows.isEmpty
                ? primaryWindows.filter { $0.window_minutes == nil }
                : explicitFiveHourWindows
            let weeklyWindows = explicitWeeklyWindows.isEmpty
                ? secondaryWindows.filter { $0.window_minutes == nil }
                : explicitWeeklyWindows
            showsFiveHourUsage = !fiveHourWindows.isEmpty

            if liveRateLimits != nil {
                fiveHourMetric = resolvePercentMetric(
                    windows: fiveHourWindows,
                    cacheKey: "codexUsageCache.fiveHour",
                    now: now
                )
                weeklyMetric = resolvePercentMetric(
                    windows: weeklyWindows,
                    cacheKey: "codexUsageCache.weekly",
                    now: now
                )
            } else {
                fiveHourMetric = resolveTokenRateMetric(
                    windows: fiveHourWindows,
                    tokenLimit: fiveHourTokenLimit,
                    cacheKey: "codexUsageCache.fiveHour",
                    now: now
                )
                weeklyMetric = resolveTokenRateMetric(
                    windows: weeklyWindows,
                    tokenLimit: weeklyTokenLimit,
                    cacheKey: "codexUsageCache.weekly",
                    now: now
                )
            }
        } else {
            // Fallback: sum tokens from session files
            let (fiveHour, weekly) = sumTokensFromSessions(now: now)
            fiveHourMetric = resolveMetric(
                used: Double(fiveHour), total: fiveHourTokenLimit,
                unit: .tokens, resetTime: nil,
                cacheKey: "codexUsageCache.fiveHour", now: now
            )
            weeklyMetric = resolveMetric(
                used: Double(weekly), total: weeklyTokenLimit,
                unit: .tokens, resetTime: nil,
                cacheKey: "codexUsageCache.weekly", now: now
            )
        }

        let planName = (defaults.string(forKey: "codexPlan")
            .flatMap { CodexPlan(rawValue: $0) } ?? .pro).rawValue

        return UsageData(
            service: .codex,
            fiveHourUsage: fiveHourMetric,
            weeklyUsage: weeklyMetric,
            lastUpdated: now,
            isAvailable: true,
            planName: planName,
            showsFiveHourUsage: showsFiveHourUsage
        )
    }

    static func parseAppServerRateLimits(_ output: String) -> [CodexRateLimits]? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            guard let data = String(line).data(using: .utf8),
                  let response = try? JSONDecoder().decode(CodexAppServerResponse.self, from: data),
                  response.id == 2,
                  let result = response.result else { continue }

            if let byLimitID = result.rateLimitsByLimitId, !byLimitID.isEmpty {
                return byLimitID.values.map(\.sessionRateLimits)
            }
            if let rateLimits = result.rateLimits {
                return [rateLimits.sessionRateLimits]
            }
        }
        return nil
    }

    static func runAppServer(executableURL: URL, timeout: TimeInterval) -> String? {
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let outputHandle = outputPipe.fileHandleForReading
        let responseBuffer = CodexAppServerResponseBuffer()
        let terminationSignal = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            responseBuffer.finish()
            terminationSignal.signal()
        }
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                responseBuffer.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            inputPipe.fileHandleForWriting.closeFile()
            outputHandle.closeFile()
            return nil
        }

        let requests = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"agentbar","title":"AgentBar","version":"1.0"}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":2}"#,
        ].joined(separator: "\n") + "\n"
        guard writeAppServerRequests(
            Data(requests.utf8),
            to: inputPipe.fileHandleForWriting.fileDescriptor
        ) else {
            inputPipe.fileHandleForWriting.closeFile()
            outputHandle.readabilityHandler = nil
            terminateProcessTree(process, terminationSignal: terminationSignal)
            outputHandle.closeFile()
            return nil
        }

        let response = responseBuffer.wait(timeout: timeout)
        inputPipe.fileHandleForWriting.closeFile()
        outputHandle.readabilityHandler = nil

        terminateProcessTree(process, terminationSignal: terminationSignal)
        outputHandle.closeFile()
        return response
    }

    static func writeAppServerRequests(_ data: Data, to fileDescriptor: Int32) -> Bool {
        guard fcntl(fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else { return false }

        return data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return true }
            var bytesWritten = 0

            while bytesWritten < buffer.count {
                let result = Darwin.write(
                    fileDescriptor,
                    baseAddress.advanced(by: bytesWritten),
                    buffer.count - bytesWritten
                )
                if result > 0 {
                    bytesWritten += result
                } else if result == -1, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private static func terminateProcessTree(
        _ process: Process,
        terminationSignal: DispatchSemaphore
    ) {
        let rootPID = process.processIdentifier
        let descendants = descendantProcessIdentifiers(of: rootPID)
        descendants.reversed().forEach { _ = kill($0, SIGTERM) }

        if process.isRunning {
            process.terminate()
        }

        _ = terminationSignal.wait(timeout: .now() + 0.25)

        let graceDeadline = Date().addingTimeInterval(0.25)
        while descendants.contains(where: processExists), Date() < graceDeadline {
            usleep(10_000)
        }

        let remaining = Set(descendants + descendantProcessIdentifiers(of: rootPID))
        remaining.filter(processExists).forEach { _ = kill($0, SIGKILL) }
        if process.isRunning {
            _ = kill(rootPID, SIGKILL)
            _ = terminationSignal.wait(timeout: .now() + 0.25)
        }

        let reapDeadline = Date().addingTimeInterval(0.5)
        while remaining.contains(where: processExists), Date() < reapDeadline {
            usleep(10_000)
        }
    }

    private static func processExists(_ processIdentifier: pid_t) -> Bool {
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private static func descendantProcessIdentifiers(of rootPID: pid_t) -> [pid_t] {
        guard rootPID > 0 else { return [] }

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return [] }

        var processes = [kinfo_proc](
            repeating: kinfo_proc(),
            count: size / MemoryLayout<kinfo_proc>.stride
        )
        guard sysctl(&mib, 4, &processes, &size, nil, 0) == 0 else { return [] }

        var childrenByParent: [pid_t: [pid_t]] = [:]
        for process in processes {
            childrenByParent[process.kp_eproc.e_ppid, default: []]
                .append(process.kp_proc.p_pid)
        }

        var descendants: [pid_t] = []
        var pending = childrenByParent[rootPID] ?? []
        while let child = pending.popLast() {
            descendants.append(child)
            pending.append(contentsOf: childrenByParent[child] ?? [])
        }
        return descendants
    }

    static func findCodexExecutable(
        environment: [String: String], homeDirectory: URL
    ) -> URL? {
        let fm = FileManager.default
        let supersetExecutable = homeDirectory.appendingPathComponent(".superset/bin/codex")
        var candidates = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") }
            .filter { $0.standardizedFileURL != supersetExecutable.standardizedFileURL }
        candidates += [
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".bun/bin/codex"),
            homeDirectory.appendingPathComponent(".volta/bin/codex"),
            homeDirectory.appendingPathComponent(".asdf/shims/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]

        let nvmVersions = homeDirectory.appendingPathComponent(".nvm/versions/node")
        if let versions = try? fm.contentsOfDirectory(
            at: nvmVersions,
            includingPropertiesForKeys: nil
        ) {
            candidates += versions
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
                .map { $0.appendingPathComponent("bin/codex") }
        }
        candidates.append(supersetExecutable)

        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    // MARK: - Metric Caching

    private func resolveMetric(
        used: Double, total: Double, unit: UsageUnit, resetTime: Date?,
        cacheKey: String, now: Date, preserveCachedZero: Bool = true
    ) -> UsageMetric {
        let cached = validCachedMetric(forKey: cacheKey, unit: unit, total: total, now: now)
        let incoming = UsageMetric(used: used, total: total, unit: unit, resetTime: resetTime)

        if shouldPreferCachedMetric(
            cached,
            over: incoming,
            now: now,
            preserveCachedZero: preserveCachedZero
        ) {
            return cached!
        }

        if incoming.used > 0 || incoming.resetTime != nil {
            saveMetricCache(incoming, forKey: cacheKey)
        } else {
            clearMetricCache(forKey: cacheKey)
        }
        return incoming
    }

    private func resolvePercentMetric(
        windows: [CodexRateWindow], cacheKey: String, now: Date
    ) -> UsageMetric {
        guard !windows.isEmpty else {
            clearMetricCache(forKey: cacheKey)
            return UsageMetric(used: 0, total: 100, unit: .percent, resetTime: nil)
        }

        let (used, resetTime) = resolveAggregatedWindow(windows: windows, now: now)
        return resolveMetric(
            used: used, total: 100, unit: .percent, resetTime: resetTime,
            cacheKey: cacheKey, now: now, preserveCachedZero: false
        )
    }

    private func resolveTokenRateMetric(
        windows: [CodexRateWindow], tokenLimit: Double, cacheKey: String, now: Date
    ) -> UsageMetric {
        guard !windows.isEmpty else {
            clearMetricCache(forKey: cacheKey)
            return UsageMetric(used: 0, total: tokenLimit, unit: .tokens, resetTime: nil)
        }

        let (usedPercent, resetTime) = resolveAggregatedWindow(windows: windows, now: now)
        return resolveMetric(
            used: tokenLimit * usedPercent / 100,
            total: tokenLimit,
            unit: .tokens,
            resetTime: resetTime,
            cacheKey: cacheKey,
            now: now
        )
    }

    private func shouldPreferCachedMetric(
        _ cached: UsageMetric?, over incoming: UsageMetric, now: Date,
        preserveCachedZero: Bool
    ) -> Bool {
        guard let cached, cached.used > 0 else { return false }
        guard let cachedReset = cached.resetTime, cachedReset > now else { return false }
        guard incoming.used <= 0 else { return false }
        if preserveCachedZero { return true }
        guard let incomingReset = incoming.resetTime else { return true }
        return abs(incomingReset.timeIntervalSince(cachedReset)) < 1
    }

    private func validCachedMetric(
        forKey key: String, unit: UsageUnit, total: Double, now: Date
    ) -> UsageMetric? {
        guard let cached = loadMetricCache(forKey: key, unit: unit, defaultTotal: total) else {
            return nil
        }

        guard cached.unit == unit, abs(cached.total - total) < 1 else {
            clearMetricCache(forKey: key)
            return nil
        }

        if let reset = cached.resetTime, reset <= now {
            clearMetricCache(forKey: key)
            return nil
        }

        if cached.used <= 0, cached.resetTime == nil {
            clearMetricCache(forKey: key)
            return nil
        }

        return cached
    }

    private func saveMetricCache(_ metric: UsageMetric, forKey key: String) {
        defaults.set(metric.used, forKey: "\(key).used")
        defaults.set(metric.total, forKey: "\(key).total")
        defaults.set(metric.unit.rawValue, forKey: "\(key).unit")
        defaults.set(metric.resetTime?.timeIntervalSince1970, forKey: "\(key).resetTime")
    }

    private func loadMetricCache(
        forKey key: String, unit: UsageUnit, defaultTotal: Double
    ) -> UsageMetric? {
        guard defaults.object(forKey: "\(key).used") != nil else { return nil }
        let used = defaults.double(forKey: "\(key).used")
        let total = defaults.object(forKey: "\(key).total") != nil
            ? defaults.double(forKey: "\(key).total") : defaultTotal
        let storedUnit = defaults.string(forKey: "\(key).unit")
            .flatMap(UsageUnit.init(rawValue:)) ?? unit
        let resetTimestamp = defaults.object(forKey: "\(key).resetTime") as? Double
        let resetTime = resetTimestamp.map { Date(timeIntervalSince1970: $0) }
        return UsageMetric(used: used, total: total, unit: storedUnit, resetTime: resetTime)
    }

    private func clearMetricCache(forKey key: String) {
        defaults.removeObject(forKey: "\(key).used")
        defaults.removeObject(forKey: "\(key).total")
        defaults.removeObject(forKey: "\(key).unit")
        defaults.removeObject(forKey: "\(key).resetTime")
    }

    // MARK: - Window Resolution

    /// Resolve a rate window: advance stale resets_at by window_minutes until future.
    private func resolveWindow(
        window: CodexRateWindow, now: Date
    ) -> (used: Double, resetTime: Date?) {
        let usedPercent = window.used_percent ?? 0

        guard let resetsAt = window.resets_at else {
            return (usedPercent, nil)
        }

        var resetDate = Date(timeIntervalSince1970: TimeInterval(resetsAt))

        if resetDate > now {
            return (usedPercent, resetDate)
        }

        // resets_at is stale — advance by window intervals to find next reset
        if let windowMinutes = window.window_minutes, windowMinutes > 0 {
            let windowSeconds = TimeInterval(windowMinutes) * 60
            while resetDate <= now {
                resetDate = resetDate.addingTimeInterval(windowSeconds)
            }
            // Window has rolled over; usage from the old window is stale
            return (0, resetDate)
        }

        // No window_minutes to advance with — window has reset
        return (0, nil)
    }

    /// Resolve multiple windows independently and aggregate active usage.
    private func resolveAggregatedWindow(
        windows: [CodexRateWindow], now: Date
    ) -> (used: Double, resetTime: Date?) {
        guard !windows.isEmpty else { return (0, nil) }

        var totalUsed: Double = 0
        var earliestActiveReset: Date?
        var earliestAnyReset: Date?

        for window in windows {
            let (used, resetTime) = resolveWindow(window: window, now: now)
            totalUsed += used

            if let resetTime {
                if let current = earliestAnyReset {
                    earliestAnyReset = min(current, resetTime)
                } else {
                    earliestAnyReset = resetTime
                }

                if used > 0 {
                    if let current = earliestActiveReset {
                        earliestActiveReset = min(current, resetTime)
                    } else {
                        earliestActiveReset = resetTime
                    }
                }
            }
        }

        return (totalUsed, earliestActiveReset ?? earliestAnyReset)
    }

    // MARK: - Rate Limits Extraction

    private func findLatestRateLimits(now: Date) -> [CodexRateLimits]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return nil }

        let recentFiles = findSessionFiles(within: 7 * 24 * 3600, relativeTo: now)
        guard !recentFiles.isEmpty else { return nil }

        // Check the most recent file first (sorted by path descending = most recent date first)
        let sorted = recentFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }

        for file in sorted {
            if let rateLimits = extractLatestRateLimits(from: file) {
                return rateLimits
            }
        }

        return nil
    }

    private func extractLatestRateLimits(from file: URL) -> [CodexRateLimits]? {
        guard let records = try? JSONLParser.parseFile(file, as: CodexSessionRecord.self) else {
            return nil
        }

        // Track the latest rate_limits per limit_id.
        // Codex sessions may interleave multiple limit_ids (e.g. "codex",
        // "codex_bengalfox") with independent usage counters, so we keep each
        // limit_id's latest entry and resolve/aggregate windows afterward.
        var latestByLimitID: [String: CodexRateLimits] = [:]
        for record in records {
            guard record.type == "event_msg",
                  record.payload?.type == "token_count",
                  let rl = record.payload?.rate_limits else { continue }
            let key = rl.limit_id ?? ""
            latestByLimitID[key] = rl
        }

        guard !latestByLimitID.isEmpty else { return nil }
        return Array(latestByLimitID.values)
    }

    // MARK: - Token Summing Fallback

    private func sumTokensFromSessions(now: Date) -> (fiveHour: Int, weekly: Int) {
        let fiveHourCutoff = DateUtils.fiveHourWindowStart(relativeTo: now)
        let weeklyCutoff = DateUtils.weeklyWindowStart(relativeTo: now)

        let files = findSessionFiles(within: 7 * 24 * 3600, relativeTo: now)
        var fiveHourTotal = 0
        var weeklyTotal = 0

        for file in files {
            let records = (try? JSONLParser.parseFile(file, as: CodexSessionRecord.self)) ?? []
            for record in records {
                guard record.type == "event_msg",
                      record.payload?.type == "token_count",
                      let info = record.payload?.info,
                      let lastUsage = info.last_token_usage,
                      let ts = record.timestamp,
                      let date = DateUtils.parseISO8601(ts) else { continue }

                let tokens = lastUsage.totalTokens
                if date >= fiveHourCutoff && date <= now {
                    fiveHourTotal += tokens
                }
                if date >= weeklyCutoff && date <= now {
                    weeklyTotal += tokens
                }
            }
        }

        return (fiveHourTotal, weeklyTotal)
    }

    // MARK: - Directory Traversal

    private func findSessionFiles(within seconds: TimeInterval, relativeTo now: Date) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsDir.path) else { return [] }

        let cutoff = now.addingTimeInterval(-seconds)
        var results: [URL] = []

        // Recursively enumerate through YYYY/MM/DD/ subdirectories
        guard let enumerator = fm.enumerator(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            // Skip files not modified recently
            if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
               let modDate = attrs[.modificationDate] as? Date,
               modDate < cutoff {
                continue
            }

            results.append(fileURL)
        }

        return results
    }
}
