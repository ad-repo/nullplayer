import Foundation

/// Runs a `.wmz` scene build on a thread with room for its recursion.
///
/// **`WMPSceneBuilder`'s `walk` recurses once per nesting level, and a debug frame of it is
/// ~110 KB.** The cooperative pool's 544 KB stack overflowed five levels deep — `Compact` as soon as
/// a track played, in the app and in the render harness alike. Same QoS as the detached task this
/// replaced.
enum WMPDeepStack {
    static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let thread = Thread { continuation.resume(with: Result(catching: work)) }
            thread.stackSize = 16 << 20
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }
}
