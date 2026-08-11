import XCTest
@testable import NullPlayer

/// Tests for `SonosVolumeCoalescer` — single-flight, latest-value-wins volume coalescing (GH #414).
/// The class is `@MainActor`, so the whole suite is too; a continuation-gated stub `send` lets us
/// hold a send "in flight" while newer values are submitted.
@MainActor
final class SonosVolumeCoalescerTests: XCTestCase {

    func testCoalescesToLatestValueWhileSendInFlight() async {
        var sent: [Int] = []
        var started: CheckedContinuation<Void, Never>?
        var gate: CheckedContinuation<Void, Never>?
        var blocked = false

        let coalescer = SonosVolumeCoalescer(
            send: { value in
                sent.append(value)
                if !blocked {                       // block only the first send so it stays in flight
                    blocked = true
                    started?.resume(); started = nil
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gate = c }
                }
                return true
            },
            currentKey: { "device-A" }
        )

        // Start submit(20) — it enters send(20) and suspends on the gate.
        let task = Task { await coalescer.submit(20) }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in started = c }

        // While send(20) is in flight, newer submits overwrite the single pending slot.
        await coalescer.submit(30)
        await coalescer.submit(40)

        gate?.resume()          // let the drain loop resume
        await task.value

        // 30 was superseded by 40 before the loop drained → only 20 and 40 ever hit the wire.
        XCTAssertEqual(sent, [20, 40])
    }

    func testEqualValueIsDeduped() async {
        var sent: [Int] = []
        let coalescer = SonosVolumeCoalescer(
            send: { sent.append($0); return true },
            currentKey: { "device-A" }
        )
        await coalescer.submit(50)
        await coalescer.submit(50)   // equal to lastSent on same key → dropped
        XCTAssertEqual(sent, [50])
    }

    func testFailedSendDoesNotRecordLastSent() async {
        var sent: [Int] = []
        let coalescer = SonosVolumeCoalescer(
            send: { sent.append($0); return false },   // every send fails
            currentKey: { "device-A" }
        )
        await coalescer.submit(50)
        await coalescer.submit(50)   // lastSent never recorded → equal value still sends
        XCTAssertEqual(sent, [50, 50])
    }

    func testStaleCompletionAfterKeyChangeDoesNotPoisonDedupe() async {
        var sent: [Int] = []
        var started: CheckedContinuation<Void, Never>?
        var gate: CheckedContinuation<Void, Never>?
        var blocked = false
        var key: String? = "device-A"

        let coalescer = SonosVolumeCoalescer(
            send: { value in
                sent.append(value)
                if !blocked {
                    blocked = true
                    started?.resume(); started = nil
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gate = c }
                }
                return true
            },
            currentKey: { key }
        )

        let task = Task { await coalescer.submit(10) }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in started = c }

        key = "device-B"        // device switched while send(10) was in flight
        gate?.resume()
        await task.value

        // send(10) completed against the new key → lastSent must NOT have been recorded, so a
        // fresh submit of the same value on device-B still sends.
        await coalescer.submit(10)
        XCTAssertEqual(sent, [10, 10])
    }

    func testResetClearsPendingAndLastSent() async {
        var sent: [Int] = []
        let coalescer = SonosVolumeCoalescer(
            send: { sent.append($0); return true },
            currentKey: { "device-A" }
        )
        await coalescer.submit(50)
        coalescer.reset()
        await coalescer.submit(50)   // dedupe state cleared → sends again
        XCTAssertEqual(sent, [50, 50])
    }

    func testResetInvalidatesInFlightCompletionForSameDeviceKey() async {
        var sent: [Int] = []
        var started: CheckedContinuation<Void, Never>?
        var gate: CheckedContinuation<Void, Never>?
        var blocked = false

        let coalescer = SonosVolumeCoalescer(
            send: { value in
                sent.append(value)
                if !blocked {
                    blocked = true
                    started?.resume(); started = nil
                    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gate = c }
                }
                return true
            },
            currentKey: { "device-A" }
        )

        let task = Task { await coalescer.submit(10) }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in started = c }

        // Teardown resets state while the old session's request is still in flight. A new session
        // to the same UDN submits the same value before that old request completes.
        coalescer.reset()
        await coalescer.submit(10)
        gate?.resume()
        await task.value

        // The stale completion must not repopulate lastSent and suppress the new session's send.
        XCTAssertEqual(sent, [10, 10])
    }

    func testNoSendWhenNoSession() async {
        var sent: [Int] = []
        let coalescer = SonosVolumeCoalescer(
            send: { sent.append($0); return true },
            currentKey: { nil }          // no active session
        )
        await coalescer.submit(50)
        XCTAssertEqual(sent, [])
    }
}
