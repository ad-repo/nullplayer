import XCTest
@testable import NullPlayer

final class CLIDisplayTests: XCTestCase {

    // MARK: - Helpers

    /// Redirects stdout to a pipe for the duration of `block`, then returns captured output.
    private func captureOutput(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let saved = dup(STDOUT_FILENO)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(stdout)
        dup2(saved, STDOUT_FILENO)
        close(saved)
        pipe.fileHandleForWriting.closeFile()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    // MARK: - Table Formatting

    func testPrintTableFormatting() {
        // With data
        let headers = ["Title", "Artist"]
        let rows = [["Karma Police", "Radiohead"],
                    ["Exit Music", "Radiohead"]]
        let output = captureOutput {
            CLIDisplay.printTable(headers: headers, rows: rows)
        }

        // Header exists, padded to the widest value in each column
        XCTAssertTrue(output.contains("Title"), "header line missing")
        XCTAssertTrue(output.contains("Artist"), "header line missing")

        // Separator dashes
        XCTAssertTrue(output.contains("---"), "separator row missing")

        // Data rows
        XCTAssertTrue(output.contains("Karma Police"), "first row missing")
        XCTAssertTrue(output.contains("Exit Music"), "second row missing")

        // Footer
        XCTAssertTrue(output.contains("2 result(s)"), "footer count wrong")

        // With empty rows
        let emptyOutput = captureOutput {
            CLIDisplay.printTable(headers: headers, rows: [])
        }
        XCTAssertTrue(emptyOutput.contains("No results found."), "empty-rows fallback missing")
    }

    // MARK: - JSON Encoding

    func testPrintJSONEncoding() {
        struct Song: Codable {
            let artist: String
            let title: String
        }

        let songs = [Song(artist: "Radiohead", title: "Karma Police"),
                     Song(artist: "Björk", title: "Jóga")]
        let output = captureOutput {
            CLIDisplay.printJSON(songs)
        }

        // Must be valid JSON
        let data = output.data(using: .utf8)!
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data), "output is not valid JSON")

        // Pretty-printed (contains newlines and indentation)
        XCTAssertTrue(output.contains("\n"), "expected pretty-printed JSON")

        // Keys are sorted (artist < title alphabetically)
        let artistRange = output.range(of: "\"artist\"")
        let titleRange  = output.range(of: "\"title\"")
        XCTAssertNotNil(artistRange)
        XCTAssertNotNil(titleRange)
        if let a = artistRange, let t = titleRange {
            XCTAssertTrue(a.lowerBound < t.lowerBound, "keys should be sorted: artist before title")
        }

        // Values present
        XCTAssertTrue(output.contains("Radiohead"))
        XCTAssertTrue(output.contains("Karma Police"))
    }
}
