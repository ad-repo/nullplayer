import AppKit
import XCTest
@testable import NullPlayer

@MainActor
final class CoverFlowViewTests: XCTestCase {
    private func items(count: Int) -> [CoverFlowItem] {
        (0..<count).map { index in
            CoverFlowItem(
                id: "item-\(index)",
                title: "Item \(index)",
                subtitle: "",
                artwork: { nil },
                loadArtwork: { nil }
            )
        }
    }

    func testDiscreteVerticalWheelMovesCarousel() throws {
        let view = CoverFlowView()
        view.setItems(items(count: 20))

        var centeredIndex: Int?
        view.onCenterChanged = { centeredIndex = $0 }

        let cgEvent = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: -1,
                wheel2: 0,
                wheel3: 0
            )
        )
        let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))

        view.scrollWheel(with: event)

        XCTAssertEqual(centeredIndex, 1)
    }

    func testApproachingEndRequestsOnlyOncePerLoadedItemCount() {
        let view = CoverFlowView()
        view.setItems(items(count: 40))

        var requestCount = 0
        view.onApproachingEnd = { requestCount += 1 }

        view.setCenterIndex(30, animated: false)
        view.setCenterIndex(31, animated: false)
        XCTAssertEqual(requestCount, 1)

        view.setItems(items(count: 60))
        view.setCenterIndex(50, animated: false)
        XCTAssertEqual(requestCount, 2)
    }
}
