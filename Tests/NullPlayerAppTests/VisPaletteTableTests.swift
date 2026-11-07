import XCTest
@testable import NullPlayer

/// Fire and EKG pick their colours by `allCases` index into a palette table in the shader, so the
/// table's rows (each preceded by a `// <Style>` comment) must list every style in case order.
final class VisPaletteTableTests: XCTestCase {

    private func paletteRowNames(shader: String, table: String) throws -> [String] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NullPlayer/Visualization/\(shader).metal")
        let source = try String(contentsOf: url, encoding: .utf8)
        let start = try XCTUnwrap(source.range(of: "constant float3 \(table)"))
        let end = try XCTUnwrap(source.range(of: "};", range: start.upperBound..<source.endIndex))
        return source[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("// ") }
            .map { String($0.dropFirst(3)) }
    }

    func testFlamePaletteRowsMatchStyles() throws {
        XCTAssertEqual(try paletteRowNames(shader: "FlameShaders", table: "kFlamePalettes"),
                       FlameStyle.allCases.map(\.rawValue))
    }

    func testEKGPaletteRowsMatchStyles() throws {
        XCTAssertEqual(try paletteRowNames(shader: "EKGShaders", table: "kEKGPalettes"),
                       EKGStyle.allCases.map(\.rawValue))
    }
}
