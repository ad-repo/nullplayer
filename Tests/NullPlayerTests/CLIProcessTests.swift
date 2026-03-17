import XCTest

/// Integration tests that spawn the real NullPlayer binary with --cli and assert on
/// exit code + output. Remote sources auto-skip when not configured.
final class CLIProcessTests: XCTestCase {

    // MARK: - Shared helpers

    /// Locates the NullPlayer binary next to the test runner executable.
    static func nullPlayerBinary() throws -> URL {
        let testBinary = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let binary = testBinary.deletingLastPathComponent().appendingPathComponent("NullPlayer")
        guard FileManager.default.fileExists(atPath: binary.path) else {
            throw XCTSkip("NullPlayer binary not found at \(binary.path) — build the app first")
        }
        return binary
    }

    /// Runs NullPlayer with `args`, capturing stdout + stderr. Returns `(stdout, stderr, exitCode)`.
    @discardableResult
    func run(_ args: [String], timeout: TimeInterval = 15) throws -> (out: String, err: String, code: Int32) {
        let binary = try Self.nullPlayerBinary()

        let outPipe = Pipe()
        let errPipe = Pipe()
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Drain pipes on background threads to prevent deadlock on large output
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        process.waitUntilExit()
        group.wait()

        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""
        return (out, err, process.terminationStatus)
    }

    // MARK: - Tests

    func testHelp() throws {
        let (out, _, code) = try run(["--cli", "--help"])
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("USAGE:"), "help missing USAGE section")
        XCTAssertTrue(out.contains("PLAYBACK:"), "help missing PLAYBACK section")
        XCTAssertTrue(out.contains("KEYBOARD CONTROLS"), "help missing KEYBOARD CONTROLS section")
    }

    func testVersion() throws {
        let (out, _, code) = try run(["--cli", "--version"])
        XCTAssertEqual(code, 0)
        // e.g. "NullPlayer 0.17.3"
        let versionPattern = #"NullPlayer \d+\.\d+"#
        XCTAssertTrue(out.range(of: versionPattern, options: .regularExpression) != nil,
                      "version output '\(out.trimmingCharacters(in: .whitespacesAndNewlines))' doesn't match expected pattern")
    }

    func testListEQAndOutputs() throws {
        for flag in ["--list-eq", "--list-outputs"] {
            let (out, _, code) = try run(["--cli", flag])
            XCTAssertEqual(code, 0, "\(flag) exited non-zero")
            XCTAssertTrue(out.contains("---"), "\(flag) output has no table separator")
            // At least one non-empty data row should follow the separator
            let lines = out.components(separatedBy: "\n")
            let separatorIdx = lines.firstIndex(where: { $0.contains("---") })
            XCTAssertNotNil(separatorIdx, "\(flag): separator line not found")
            if let idx = separatorIdx {
                let dataLines = lines[(idx + 1)...].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.contains("result(s)") }
                XCTAssertFalse(dataLines.isEmpty, "\(flag): no data rows after separator")
            }
        }
    }

    func testListSources() throws {
        let (out, _, code) = try run(["--cli", "--list-sources"])
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("---"), "--list-sources output has no table separator")
    }

    func testListStations() throws {
        // Table format
        let (tableOut, _, tableCode) = try run(["--cli", "--list-stations"])
        XCTAssertEqual(tableCode, 0, "--list-stations (table) exited non-zero")

        // JSON format
        let (jsonOut, _, jsonCode) = try run(["--cli", "--list-stations", "--json"])
        XCTAssertEqual(jsonCode, 0, "--list-stations --json exited non-zero")
        let jsonData = jsonOut.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: jsonData)
        XCTAssertNotNil(parsed, "--list-stations --json output is not valid JSON:\n\(jsonOut)")

        // Folder filter: result count should be ≤ unfiltered count
        let (filteredOut, _, filteredCode) = try run(["--cli", "--list-stations", "--folder", "genre"])
        XCTAssertEqual(filteredCode, 0, "--list-stations --folder exited non-zero")

        func rowCount(_ output: String) -> Int {
            let lines = output.components(separatedBy: "\n")
            guard let sepIdx = lines.firstIndex(where: { $0.contains("---") }) else { return 0 }
            return lines[(sepIdx + 1)...].filter {
                let t = $0.trimmingCharacters(in: .whitespaces)
                return !t.isEmpty && !t.contains("result(s)")
            }.count
        }

        let totalRows    = rowCount(tableOut)
        let filteredRows = rowCount(filteredOut)
        XCTAssertLessThanOrEqual(filteredRows, totalRows,
                                 "filtered station list (\(filteredRows)) should be ≤ total (\(totalRows))")
    }

    func testErrorCases() throws {
        // Mutually exclusive flags
        let (_, err1, code1) = try run(["--cli", "--repeat-all", "--repeat-one"])
        XCTAssertEqual(code1, 1, "--repeat-all --repeat-one should exit 1")
        XCTAssertTrue(err1.contains("Error:"), "expected Error: message on stderr")

        // Unknown flag
        let (_, err2, code2) = try run(["--cli", "--unknown-flag"])
        XCTAssertEqual(code2, 1, "--unknown-flag should exit 1")
        XCTAssertTrue(err2.contains("Error:"), "expected Error: message on stderr for unknown flag")
    }

    func testLocalSourceQueries() throws {
        // Check if local library has any artists; skip if empty
        let (artistOut, _, artistCode) = try run(["--cli", "--source", "local", "--list-artists"])
        XCTAssertEqual(artistCode, 0, "--source local --list-artists exited non-zero")

        if artistOut.contains("No results found.") {
            throw XCTSkip("Local library is empty — skipping local source query tests")
        }

        let queries: [[String]] = [
            ["--source", "local", "--list-albums"],
            ["--source", "local", "--list-genres"],
            ["--source", "local", "--list-tracks"],
            ["--source", "local", "--list-playlists"],
            ["--source", "local", "--search", "a"],
        ]

        for args in queries {
            let (_, _, code) = try run(["--cli"] + args)
            XCTAssertEqual(code, 0, "local query \(args.joined(separator: " ")) exited non-zero")
        }
    }

    func testRemoteSourceQueries() throws {
        let sources = ["plex", "subsonic", "jellyfin", "emby"]

        for source in sources {
            let (out, err, code) = try run(["--cli", "--source", source, "--list-artists"])

            if code == 0 {
                // Server is configured and responded — assert tabular output
                XCTAssertTrue(out.contains("---") || out.contains("No results found."),
                              "\(source): unexpected output format")
            } else if err.lowercased().contains("not configured") || err.lowercased().contains("not connected") {
                // Source not set up in this environment — acceptable
                continue
            } else {
                XCTFail("\(source) --list-artists failed unexpectedly (exit \(code)):\n\(err)")
            }
        }
    }
}
