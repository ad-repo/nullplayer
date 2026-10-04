import XCTest
@testable import NullPlayer

final class PlexFetchAllPagesTests: XCTestCase {
    /// Serves `total` items in pages, keeping only those `keep` allows (as show filtering does).
    private func fetch(total: Int, pageSize: Int, keep: (Int) -> Bool = { _ in true }) async throws -> (items: [Int], requests: [Int]) {
        var requests: [Int] = []
        let items = try await PlexServerClient.fetchAllPages(pageSize: pageSize) { offset, limit in
            requests.append(offset)
            let raw = Array(offset..<min(offset + limit, total))
            return (raw.filter(keep), raw.count)
        }
        return (items, requests)
    }

    func testLoadsEveryPagePastTheFirst() async throws {
        let result = try await fetch(total: 2_350, pageSize: 1_000)
        XCTAssertEqual(result.items, Array(0..<2_350))
        XCTAssertEqual(result.requests, [0, 1_000, 2_000])
    }

    func testExactMultipleEndsOnAnEmptyPage() async throws {
        let result = try await fetch(total: 2_000, pageSize: 1_000)
        XCTAssertEqual(result.items.count, 2_000)
        XCTAssertEqual(result.requests, [0, 1_000, 2_000])
    }

    /// A filtered page is shorter than the page size but is not the last page.
    func testPagesOnRawCountNotKeptCount() async throws {
        let result = try await fetch(total: 25, pageSize: 10) { $0 % 2 == 0 }
        XCTAssertEqual(result.items, Array(stride(from: 0, to: 25, by: 2)))
        XCTAssertEqual(result.requests, [0, 10, 20])
    }
}
