import Darwin
import Foundation

struct WMPScriptRequest: Codable {
    let id: String
    let script: String
    let globalsJSON: String
    let callbackLimit: Int
}

struct WMPScriptResponse: Codable, Equatable {
    let id: String
    let value: String?
    let globalsJSON: String?
    let callbacksJSON: String?
    let error: String?
}

enum WMPScriptEvaluationResult: Equatable {
    case completed(WMPScriptResponse)
    case failed(WMPPhase0Diagnostic)
}

/// Parent-side proof harness for the Phase 0 helper-process architecture.
/// Every evaluation owns a fresh process/realm; a missed deadline terminates that process and the
/// next call starts clean. No instance is wired into a player controller before Phase 5.
final class WMPScriptIsolation {
    let helperURL: URL
    let timeout: TimeInterval
    let terminationGrace: TimeInterval
    private let processLock = NSLock()
    private let terminationLock = NSLock()
    private var activeProcesses: [Int32: Process] = [:]

    init(helperURL: URL, timeout: TimeInterval = 0.25, terminationGrace: TimeInterval = 0.1) {
        self.helperURL = helperURL
        self.timeout = timeout
        self.terminationGrace = terminationGrace
    }

    func evaluate(script: String, globalsJSON: String = "{}",
                  callbackLimit: Int = WMPPhase0Limits.activeTimers) -> WMPScriptEvaluationResult {
        guard script.lengthOfBytes(using: .utf8) <= WMPPhase0Limits.scriptMessageBytes,
              let globalsData = globalsJSON.data(using: .utf8),
              globalsData.count <= WMPPhase0Limits.scriptMessageBytes else {
            return .failed(WMPPhase0Diagnostic(code: .scriptMessageTooLarge, path: nil,
                                               detail: "script/globals exceed 1 MiB"))
        }
        guard (try? JSONSerialization.jsonObject(with: globalsData)) is [String: Any] else {
            return .failed(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                                               detail: "globals must be a JSON object"))
        }
        let request = WMPScriptRequest(id: UUID().uuidString, script: script,
                                       globalsJSON: globalsJSON, callbackLimit: callbackLimit)
        guard let payload = try? JSONEncoder().encode(request),
              payload.count <= WMPPhase0Limits.scriptMessageBytes else {
            return .failed(WMPPhase0Diagnostic(code: .scriptMessageTooLarge, path: nil,
                                               detail: "request exceeds 1 MiB"))
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = helperURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do { try process.run() } catch {
            return .failed(WMPPhase0Diagnostic(code: .scriptCrashed, path: nil,
                                               detail: error.localizedDescription))
        }
        processLock.lock()
        activeProcesses[process.processIdentifier] = process
        processLock.unlock()
        defer {
            processLock.lock()
            activeProcesses.removeValue(forKey: process.processIdentifier)
            processLock.unlock()
        }

        var frame = Data()
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        input.fileHandleForWriting.write(frame)
        try? input.fileHandleForWriting.close()

        let group = DispatchGroup()
        group.enter()
        let responseLock = NSLock()
        var responseData = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = Self.readBounded(output.fileHandleForReading,
                                        limit: WMPPhase0Limits.scriptMessageBytes + 4)
            responseLock.lock()
            responseData = data
            responseLock.unlock()
            group.leave()
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            terminate(process)
            _ = group.wait(timeout: .now() + terminationGrace)
            return .failed(WMPPhase0Diagnostic(code: .scriptTimedOut, path: nil,
                                               detail: "deadline \(timeout)s"))
        }
        responseLock.lock()
        let framedResponse = responseData
        responseLock.unlock()
        guard framedResponse.count <= WMPPhase0Limits.scriptMessageBytes + 4 else {
            terminate(process)
            return .failed(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                                               detail: "response frame exceeds 1 MiB"))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = Self.readBounded(errors.fileHandleForReading, limit: 64 * 1_024)
            let errorText = String(data: errorData,
                                   encoding: .utf8) ?? ""
            return .failed(WMPPhase0Diagnostic(code: .scriptCrashed, path: nil,
                                               detail: "status \(process.terminationStatus) \(errorText)"))
        }
        guard framedResponse.count >= 4 else {
            return .failed(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                                               detail: "missing response frame"))
        }
        let declared = framedResponse.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard declared <= WMPPhase0Limits.scriptMessageBytes,
              framedResponse.count == Int(declared) + 4,
              let response = try? JSONDecoder().decode(WMPScriptResponse.self,
                                                        from: framedResponse.dropFirst(4)),
              response.id == request.id else {
            return .failed(WMPPhase0Diagnostic(code: .scriptProtocolViolation, path: nil,
                                               detail: "invalid response frame"))
        }
        return .completed(response)
    }

    private func terminate(_ process: Process) {
        terminationLock.lock()
        defer { terminationLock.unlock() }
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(terminationGrace)
        while process.isRunning && Date() < deadline { usleep(1_000) }
        if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
    }

    func cancelAll() {
        processLock.lock()
        let processes = Array(activeProcesses.values)
        processLock.unlock()
        processes.forEach(terminate)
    }

    var activeProcessCount: Int {
        processLock.lock()
        defer { processLock.unlock() }
        return activeProcesses.count
    }

    private static func readBounded(_ handle: FileHandle, limit: Int) -> Data {
        var data = Data()
        while data.count <= limit {
            let remaining = limit - data.count + 1
            guard let chunk = try? handle.read(upToCount: min(64 * 1_024, remaining)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
            if data.count > limit {
                try? handle.close()
                break
            }
        }
        return data
    }
}
