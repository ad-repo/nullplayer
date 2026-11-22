import Foundation

/// The one hardware video encoder, shared by every rip: encodes run one at a time, first come
/// first served, and a job waiting its turn shows as *Queued for encode · #N in line*. The line
/// lives here alone; the window reads a job's place from `position(of:)`. Waits on a background
/// queue.
enum RipEncodeQueue {
    private static let condition = NSCondition()
    private static var busy = false
    /// Waiting jobs' ids, in arrival order.
    private static var waiting: [String] = []

    /// Joins the line, reporting `.queuedForEncode`, and blocks until the encoder is free and
    /// this job is first; false if `handle` is cancelled while waiting.
    static func acquire(for handle: RipJobHandle) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        waiting.append(handle.id)
        handle.report(.phase(.queuedForEncode))
        while true {
            if handle.isCancelled {
                waiting.removeAll { $0 == handle.id }
                condition.broadcast()
                return false
            }
            if !busy, waiting.first == handle.id {
                waiting.removeFirst()
                busy = true
                return true
            }
            condition.wait()
        }
    }

    static func release() {
        condition.withLock {
            busy = false
            condition.broadcast()
        }
    }

    /// Wakes every waiter, so a cancelled one leaves the line.
    static func wakeWaiters() { condition.withLock { condition.broadcast() } }

    /// The job's place in line (1 = next), or nil when it is not waiting.
    static func position(of jobID: String) -> Int? {
        condition.withLock { waiting.firstIndex(of: jobID).map { $0 + 1 } }
    }
}
