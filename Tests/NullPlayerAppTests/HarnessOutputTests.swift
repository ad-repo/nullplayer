import Foundation
import XCTest
@testable import NullPlayer

/// Proves `HarnessOutput`, the emitter every family's harness writes through.
final class HarnessOutputTests: XCTestCase {
    /// W35 lost 5,087 bytes of one skin's measurements mid-line in a 180-archive sweep, and the
    /// only reason anyone knew is that the collision left a visible splice for the census to flag.
    /// A loss that had landed on a line boundary would have read as a skin that simply drew less.
    /// So: many writers, lines longer than any stdio buffer, and every line has to come back whole
    /// and exactly once.
    func testEmitsEveryLineWholeUnderConcurrentWriters() throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harness-emit-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let writers = 8, perWriter = 200
        DispatchQueue.concurrentPerform(iterations: writers) { writer in
            for index in 0..<perWriter {
                // Every fourth line is 9 KB — past any stdio buffer, so a line that survives whole
                // proves the partial-write loop and not just that the line happened to fit.
                let padding = index % 4 == 0 ? String(repeating: "x", count: 9_000) : "value"
                HarnessOutput.emit("CALL writer\(writer) line\(index) \(padding)",
                                      to: handle.fileDescriptor)
            }
        }
        try handle.close()

        let lines = try String(contentsOf: file, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, writers * perWriter, "lines were lost or split")
        var seen = Set<String>()
        for line in lines {
            XCTAssertTrue(line.hasPrefix("CALL writer"), "a line was spliced: \(line.prefix(60))")
            let identity = line.split(separator: " ").prefix(3).joined(separator: " ")
            XCTAssertTrue(seen.insert(identity).inserted, "duplicated: \(identity)")
        }
        XCTAssertEqual(seen.count, writers * perWriter)
    }
}
