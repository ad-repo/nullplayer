import Foundation
import XCTest
@testable import NullPlayer

final class WMPPhase0ArchiveTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin", isDirectory: true)
    }

    func testLockedLimitsMatchDecisionRecord() {
        XCTAssertEqual(WMPPhase0Limits.archiveEntries, 4_096)
        XCTAssertEqual(WMPPhase0Limits.entryUncompressedBytes, 32 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.archiveUncompressedBytes, 128 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.entryCompressionRatio, 200)
        XCTAssertEqual(WMPPhase0Limits.wrapperDirectories, 1)
        XCTAssertEqual(WMPPhase0Limits.xmlDepth, 256)
        XCTAssertEqual(WMPPhase0Limits.xmlNodes, 100_000)
        XCTAssertEqual(WMPPhase0Limits.imageDimension, 8_192)
        XCTAssertEqual(WMPPhase0Limits.imagePixels, 32_000_000)
        XCTAssertEqual(WMPPhase0Limits.scriptBytes, 4 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.expressionDependencyDepth, 128)
        XCTAssertEqual(WMPPhase0Limits.expressionPasses, 256)
        XCTAssertEqual(WMPPhase0Limits.activeTimers, 256)
        XCTAssertEqual(WMPPhase0Limits.minimumTimerPeriodMilliseconds, 8)
        XCTAssertEqual(WMPPhase0Limits.preferenceValueBytes, 64 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.scriptMessageBytes, 1 * 1_024 * 1_024)
        XCTAssertEqual(WMPPhase0Limits.scriptInFlightBytes, 16 * 1_024 * 1_024)
    }

    func testOriginalValidArchivesPassWithoutExtraction() throws {
        for name in ["widgets.wmz", "wrapper-directory.wmz", "two-view.wmz"] {
            XCTAssertNoThrow(try WMPPhase0ArchiveAuditor.audit(url: fixtures.appendingPathComponent(name)), name)
        }
    }

    func testEncodingFixturesCarryExpectedBOMs() throws {
        XCTAssertFalse(try Data(contentsOf: fixtures.appendingPathComponent("utf8.wms")).starts(with: [0xFF, 0xFE]))
        XCTAssertTrue(try Data(contentsOf: fixtures.appendingPathComponent("utf16le.wms")).starts(with: [0xFF, 0xFE]))
        XCTAssertTrue(try Data(contentsOf: fixtures.appendingPathComponent("utf16be.wms")).starts(with: [0xFE, 0xFF]))
    }

    func testHostileArchivesHaveStableTypedFailures() {
        let cases: [(String, WMPPhase0DiagnosticCode)] = [
            ("traversal.wmz", .pathTraversal),
            ("absolute-path.wmz", .absolutePath),
            ("drive-path.wmz", .drivePath),
            ("case-collision.wmz", .caseCollision),
            ("symlink.wmz", .symbolicLink),
            ("wrapper-too-deep.wmz", .wrapperDepthExceeded),
            ("excess-entries.wmz", .tooManyEntries),
            ("excess-ratio.wmz", .compressionRatioExceeded),
            ("excess-entry-bytes.wmz", .entryTooLarge),
            ("excess-archive-bytes.wmz", .archiveTooLarge),
            ("deep-xml.wmz", .xmlDepthExceeded),
            ("excess-xml-nodes.wmz", .xmlNodeLimitExceeded),
            ("oversized-image.wmz", .oversizedImage),
            ("oversized-script.wmz", .oversizedScript),
            ("crc-corrupt.wmz", .crcMismatch),
        ]

        for (name, expectedCode) in cases {
            XCTAssertThrowsError(try WMPPhase0ArchiveAuditor.audit(url: fixtures.appendingPathComponent(name)), name) { error in
                XCTAssertEqual((error as? WMPPhase0Diagnostic)?.code, expectedCode, "wrong diagnostic for \(name): \(error)")
            }
        }
    }
}

final class WMPScriptIsolationTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/WMPSkin", isDirectory: true)
    }

    private var helperURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/debug/WMPScriptIsolationHelper")
    }

    private func script(_ name: String) throws -> String {
        try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    func testNormalHostCallbackSyntaxRecursionAndTimerCases() throws {
        let runtime = WMPScriptIsolation(helperURL: helperURL, timeout: 0.5)

        let normal = try completed(runtime.evaluate(script: script("normal-return.js")))
        XCTAssertEqual(normal.value, "42")
        XCTAssertNil(normal.error)

        let host = try completed(runtime.evaluate(
            script: script("host-read-write.js"),
            globalsJSON: #"{"player":{"settings":{"volume":0.25}}}"#
        ))
        XCTAssertEqual(host.value, "0.75")
        XCTAssertTrue(host.globalsJSON?.contains("0.75") == true)

        let callback = try completed(runtime.evaluate(script: script("callback.js")))
        XCTAssertEqual(callback.callbacksJSON, #"["ready"]"#)

        let ambient = try completed(runtime.evaluate(
            script: "[typeof fetch, typeof require, typeof XMLHttpRequest, typeof WebSocket, typeof ObjC].join(',')"
        ))
        XCTAssertEqual(ambient.value, "undefined,undefined,undefined,undefined,undefined")

        let syntax = try completed(runtime.evaluate(script: script("syntax-error.js")))
        XCTAssertNotNil(syntax.error)

        let recursion = try completed(runtime.evaluate(script: script("recursion.js")))
        XCTAssertNotNil(recursion.error)

        let timers = try completed(runtime.evaluate(script: script("timer-storm.js")))
        let callbackData = try XCTUnwrap(timers.callbacksJSON?.data(using: .utf8))
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: callbackData) as? [String])
        XCTAssertEqual(values.count, WMPPhase0Limits.activeTimers)
    }

    func testAllocationPressureCannotHoldTheTestRunner() throws {
        let runtime = WMPScriptIsolation(helperURL: helperURL, timeout: 0.5)
        let start = Date()
        let result = runtime.evaluate(script: try script("allocation-pressure.js"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5)
        switch result {
        case .failed(let diagnostic):
            XCTAssertTrue([.scriptTimedOut, .scriptCrashed].contains(diagnostic.code))
        case .completed(let response):
            XCTAssertNotNil(response.error)
        }
    }

    func testInfiniteLoopHardStopAndCleanRestartForOneHundredCycles() throws {
        let runtime = WMPScriptIsolation(helperURL: helperURL, timeout: 0.05, terminationGrace: 0.05)
        let loop = "var priorState = 123; " + (try script("infinite-loop.js"))
        let start = Date()

        for cycle in 0..<100 {
            guard case .failed(let failure) = runtime.evaluate(script: loop) else {
                return XCTFail("cycle \(cycle) did not terminate the spinning realm")
            }
            XCTAssertEqual(failure.code, .scriptTimedOut, "cycle \(cycle)")

            let clean = try completed(runtime.evaluate(script: "typeof priorState"))
            XCTAssertEqual(clean.value, "undefined", "state survived cycle \(cycle)")
            XCTAssertNil(clean.error)
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 60, "kill/restart proof exceeded its fixed outer deadline")
    }

    func testOversizedProtocolMessageIsRejectedBeforeLaunch() {
        let runtime = WMPScriptIsolation(helperURL: helperURL)
        let result = runtime.evaluate(script: String(repeating: "x", count: WMPPhase0Limits.scriptMessageBytes))
        guard case .failed(let failure) = result else { return XCTFail("oversized request was accepted") }
        XCTAssertEqual(failure.code, .scriptMessageTooLarge)
    }

    private func completed(_ result: WMPScriptEvaluationResult, file: StaticString = #filePath,
                           line: UInt = #line) throws -> WMPScriptResponse {
        switch result {
        case .completed(let response): return response
        case .failed(let failure):
            XCTFail("evaluation failed: \(failure)", file: file, line: line)
            throw failure
        }
    }
}
