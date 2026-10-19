import Foundation
import Darwin

protocol UsageProviderProtocol: Sendable {
    var serviceType: ServiceType { get }
    /// Account identity for services with several accounts; nil for single-account providers.
    var accountLabel: String? { get }
    var accountIndex: Int? { get }
    func isConfigured() async -> Bool
    func fetchUsage() async throws -> UsageData
}

extension UsageProviderProtocol {
    var accountLabel: String? { nil }
    var accountIndex: Int? { nil }
}

struct CLIProcessRuntime {
    let run: () throws -> Void
    let waitForTermination: (TimeInterval) -> DispatchTimeoutResult
    let isRunning: () -> Bool
    let terminate: () -> Void
    let forceTerminate: () -> Void
    let terminationStatus: () -> Int32
    let readOutput: () -> Data
    let cleanupAfterRunFailure: () -> Void
    let cleanupAfterTimeout: () -> Void

    init(
        run: @escaping () throws -> Void,
        waitForTermination: @escaping (TimeInterval) -> DispatchTimeoutResult,
        isRunning: @escaping () -> Bool,
        terminate: @escaping () -> Void,
        forceTerminate: @escaping () -> Void = {},
        terminationStatus: @escaping () -> Int32,
        readOutput: @escaping () -> Data,
        cleanupAfterRunFailure: @escaping () -> Void = {},
        cleanupAfterTimeout: @escaping () -> Void = {}
    ) {
        self.run = run
        self.waitForTermination = waitForTermination
        self.isRunning = isRunning
        self.terminate = terminate
        self.forceTerminate = forceTerminate
        self.terminationStatus = terminationStatus
        self.readOutput = readOutput
        self.cleanupAfterRunFailure = cleanupAfterRunFailure
        self.cleanupAfterTimeout = cleanupAfterTimeout
    }
}

enum CLIProcessExecutor {
    private static let terminateGracePeriod: TimeInterval = 0.25
    private final class LockedDataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func set(_ newData: Data) {
            lock.lock()
            data = newData
            lock.unlock()
        }

        func get() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    static func executeCommand(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) -> String? {
        let process = Process()
        let pipe = Pipe()
        let outputHandle = pipe.fileHandleForReading
        let terminationSignal = DispatchSemaphore(value: 0)
        let outputData = LockedDataBox()
        let outputReadSignal = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        let runtime = CLIProcessRuntime(
            run: {
                try process.run()
                // Close the parent write-end so EOF is observed when the child exits.
                pipe.fileHandleForWriting.closeFile()

                // Drain stdout while the process is running to avoid pipe backpressure deadlocks.
                DispatchQueue.global(qos: .utility).async {
                    let data = outputHandle.readDataToEndOfFile()
                    outputData.set(data)
                    outputReadSignal.signal()
                }
            },
            waitForTermination: { waitTimeout in
                terminationSignal.wait(timeout: .now() + waitTimeout)
            },
            isRunning: { process.isRunning },
            terminate: { process.terminate() },
            forceTerminate: {
                if process.processIdentifier > 0 {
                    _ = kill(process.processIdentifier, SIGKILL)
                }
            },
            terminationStatus: { process.terminationStatus },
            readOutput: {
                _ = outputReadSignal.wait(timeout: .distantFuture)
                return outputData.get()
            },
            cleanupAfterRunFailure: {
                pipe.fileHandleForWriting.closeFile()
                outputHandle.closeFile()
            },
            cleanupAfterTimeout: {
                outputHandle.closeFile()
                _ = outputReadSignal.wait(timeout: .now() + terminateGracePeriod)
            }
        )

        return executeCommand(timeout: timeout, runtime: runtime)
    }

    static func executeCommand(timeout: TimeInterval, runtime: CLIProcessRuntime) -> String? {
        do {
            try runtime.run()
        } catch {
            runtime.cleanupAfterRunFailure()
            return nil
        }

        let waitResult = runtime.waitForTermination(timeout)
        if waitResult == .timedOut {
            if runtime.isRunning() {
                runtime.terminate()
                _ = runtime.waitForTermination(terminateGracePeriod)
                if runtime.isRunning() {
                    runtime.forceTerminate()
                    _ = runtime.waitForTermination(terminateGracePeriod)
                }
            }
            runtime.cleanupAfterTimeout()
            return nil
        }

        guard runtime.terminationStatus() == 0 else { return nil }

        let output = String(data: runtime.readOutput(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == true ? nil : output
    }
}
