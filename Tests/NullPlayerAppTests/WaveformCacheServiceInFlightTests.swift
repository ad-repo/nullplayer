import XCTest
@testable import NullPlayer

/// `loadSnapshot` shares one generation per cache key and cancels it only when a different track is
/// loaded. The decode is replaced by a generator the test holds open, so each case is deterministic.
final class WaveformCacheServiceInFlightTests: XCTestCase {

    /// Records which sources were generated and holds a generation open until released.
    private actor Generations {
        private(set) var started: [String] = []
        private var released = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func start(_ url: URL) -> Int {
            started.append(url.lastPathComponent)
            return started.filter { $0 == url.lastPathComponent }.count
        }

        func count(of name: String) -> Int { started.filter { $0 == name }.count }

        /// Waits until `release()`, ignoring cancellation, like a decode between cancellation checks.
        func waitForRelease() async {
            if released { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func release() {
            released = true
            waiters.forEach { $0.resume() }
            waiters = []
        }
    }

    private actor ResultBox {
        private(set) var value: WaveformSnapshot?
        func set(_ value: WaveformSnapshot) { self.value = value }
    }

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("np-waveform-inflight-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func track(_ name: String) throws -> Track {
        let url = directory.appendingPathComponent(name)
        try Data([0]).write(to: url)
        return Track(lightweightURL: url)
    }

    private func service(_ generate: @escaping @Sendable (URL) async throws -> WaveformSnapshot) -> WaveformCacheService {
        WaveformCacheService(cacheDirectoryURL: directory.appendingPathComponent("cache", isDirectory: true),
                             generatorOverride: generate)
    }

    private static func ready(_ url: URL) -> WaveformSnapshot {
        WaveformSnapshot(sourcePath: url.path, duration: 1, samples: [1], state: .ready, message: nil,
                         cacheKey: nil, allowsSeeking: true, isStreaming: false)
    }

    private func waitUntil(_ condition: @escaping () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for condition", file: file, line: line)
    }

    /// The load's result, or nil after a timeout — so a load stuck behind a generation that never
    /// ends fails the test instead of hanging it.
    private func result(of load: Task<WaveformSnapshot, Never>, file: StaticString = #filePath, line: UInt = #line) async -> WaveformSnapshot? {
        let box = ResultBox()
        Task { await box.set(await load.value) }
        await waitUntil({ await box.value != nil }, file: file, line: line)
        return await box.value
    }

    /// Skipping to another track stops the old generation instead of letting it run to the end.
    func testLoadingAnotherTrackCancelsTheRunningGeneration() async throws {
        let generations = Generations()
        let service = service { url in
            _ = await generations.start(url)
            if url.lastPathComponent == "a.wav" {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
            return Self.ready(url)
        }
        let a = try track("a.wav"), b = try track("b.wav")

        let loadA = Task { await service.loadSnapshot(for: a) }
        await waitUntil { await generations.count(of: "a.wav") == 1 }

        let resultB = await service.loadSnapshot(for: b)
        let finishedA = await result(of: loadA)
        let resultA = try XCTUnwrap(finishedA, "a.wav's generation ran on instead of being cancelled")

        XCTAssertEqual(resultB.state, .ready)
        XCTAssertEqual(resultA.state, .failed)
        XCTAssertEqual(resultA.message, "Waveform generation cancelled")
    }

    /// Reloads of the same track (a skin switch, reopening the window) join the running generation.
    func testLoadsOfTheSameTrackShareOneGeneration() async throws {
        let generations = Generations()
        let service = service { url in
            _ = await generations.start(url)
            await generations.waitForRelease()
            return Self.ready(url)
        }
        let a = try track("a.wav")

        let first = Task { await service.loadSnapshot(for: a) }
        await waitUntil { await generations.count(of: "a.wav") == 1 }
        let second = Task { await service.loadSnapshot(for: a) }
        try await Task.sleep(nanoseconds: 100_000_000)
        await generations.release()

        let results = await [first.value, second.value]
        XCTAssertEqual(results.map(\.state), [.ready, .ready])
        let count = await generations.count(of: "a.wav")
        XCTAssertEqual(count, 1)
    }

    /// A caller that goes away (the old window during a rebuild) does not cancel the shared work.
    func testCancelledCallerDoesNotCancelTheSharedGeneration() async throws {
        let generations = Generations()
        let service = service { url in
            _ = await generations.start(url)
            await generations.waitForRelease()
            try Task.checkCancellation()
            return Self.ready(url)
        }
        let a = try track("a.wav")

        let abandoned = Task { await service.loadSnapshot(for: a) }
        await waitUntil { await generations.count(of: "a.wav") == 1 }
        abandoned.cancel()
        let second = Task { await service.loadSnapshot(for: a) }
        try await Task.sleep(nanoseconds: 100_000_000)
        await generations.release()

        let result = await second.value
        XCTAssertEqual(result.state, .ready)
        let count = await generations.count(of: "a.wav")
        XCTAssertEqual(count, 1)
    }

    /// Going back to a track whose cancelled generation is still winding down starts a fresh one
    /// rather than joining the cancelled one and reporting it as a failure.
    func testReloadingATrackWhoseGenerationWasCancelledStartsAFreshOne() async throws {
        let generations = Generations()
        let service = service { url in
            let call = await generations.start(url)
            if url.lastPathComponent == "a.wav", call == 1 {
                await generations.waitForRelease()
            }
            return Self.ready(url)
        }
        let a = try track("a.wav"), b = try track("b.wav")

        let firstA = Task { await service.loadSnapshot(for: a) }
        await waitUntil { await generations.count(of: "a.wav") == 1 }
        _ = await service.loadSnapshot(for: b)

        let reloadA = await result(of: Task { await service.loadSnapshot(for: a) })
        let count = await generations.count(of: "a.wav")
        await generations.release()
        _ = await firstA.value

        XCTAssertEqual(reloadA?.state, .ready, "the reload joined the cancelled generation")
        XCTAssertEqual(count, 2)
    }
}
