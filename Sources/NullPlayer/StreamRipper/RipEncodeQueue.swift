import Foundation

/// The one hardware video encoder, shared by every rip: encodes run one at a time, first come
/// first served, and a job waiting its turn shows as *Queued for encode · #N in line*. Waits on a
/// background queue.
enum RipEncodeQueue {
    private static let lock = NSLock()
    private static var busy = false
    /// Waiting jobs' ids, in arrival order: `RipJobCenter.encodeQueuePosition` counts the same order.
    private static var waiting: [String] = []

    /// Blocks until the encoder is free and this job is first in line; false if `handle` is
    /// cancelled while waiting.
    static func acquire(for handle: RipJobHandle) -> Bool {
        lock.withLock { waiting.append(handle.id) }
        while true {
            let state: Bool? = lock.withLock {
                if handle.isCancelled {
                    waiting.removeAll { $0 == handle.id }
                    return false
                }
                guard !busy, waiting.first == handle.id else { return nil }
                waiting.removeFirst()
                busy = true
                return true
            }
            if let state { return state }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    static func release() { lock.withLock { busy = false } }
}
