import XCTest
@testable import NullPlayer

final class RipRequestTests: XCTestCase {
    private func profile(_ resolution: RipResolution, _ format: RipVideoFormat) -> StreamRipper.VideoProfile {
        StreamRipper.VideoProfile(resolution: resolution, format: format)
    }

    func testRatesNeverExceedTheSourceBitrate() {
        let hevc4K = profile(.p2160, .hevc)
        let capped = hevc4K.cappedRates(sourceKbps: 14_340)
        XCTAssertEqual(capped.target, 14_340)
        XCTAssertEqual(capped.max, 17_925)
        XCTAssertEqual(capped.buffer, 28_680)
        XCTAssertEqual(hevc4K.cappedRates(sourceKbps: 60_000).target, 20_000)
        XCTAssertEqual(hevc4K.cappedRates(sourceKbps: nil).target, 20_000)
    }

    func testRateTableByFormatAndResolution() {
        XCTAssertEqual(profile(.p1080, .h264).videoKbps, 4000)
        XCTAssertEqual(profile(.p2160, .h264).videoKbps, 35_000)
        XCTAssertEqual(profile(.p1080, .hevc).videoKbps, 6000)
        XCTAssertEqual(profile(.p2160, .original).videoKbps, 20_000, "Original falls back to the HEVC rates")
        XCTAssertEqual(profile(.p2160, .h264).maxVideoKbps, 43_750)
        XCTAssertEqual(profile(.p2160, .h264).videoBufferKbps, 70_000)
    }

    func testOriginalCopiesOnlyWhatA4KChromecastPlays() {
        let original = profile(.p2160, .original)
        XCTAssertTrue(original.copiesSource(codec: "vp9", height: 2160))
        XCTAssertTrue(original.copiesSource(codec: "hevc", height: 2160))
        XCTAssertTrue(original.copiesSource(codec: "h264", height: 1080))
        XCTAssertFalse(original.copiesSource(codec: "h264", height: 2160))
        XCTAssertFalse(original.copiesSource(codec: "av1", height: 2160))
        XCTAssertFalse(original.copiesSource(codec: nil, height: 2160))
        XCTAssertTrue(profile(.p1080, .original).copiesSource(codec: "vp9", height: 1080))
        XCTAssertFalse(profile(.p2160, .hevc).copiesSource(codec: "vp9", height: 2160))
    }

    func testFormatSelectorPrefersVP9AndAACForOriginalAtEveryResolution() {
        XCTAssertEqual(profile(.p2160, .original).ytdlpFormat,
                       "bv*[height<=2160][vcodec^=vp09]+ba[acodec^=mp4a]/bv*[height<=2160][vcodec^=vp09]+ba/"
                       + "bv*[height<=2160]+ba/b[height<=2160]/best[height<=2160]")
        XCTAssertTrue(profile(.p720, .original).ytdlpFormat.hasPrefix("bv*[height<=720][vcodec^=vp09]"))
        XCTAssertEqual(profile(.p1080, .h264).ytdlpFormat, "bv*[height<=1080]+ba/b[height<=1080]/best[height<=1080]")
        XCTAssertEqual(profile(.max, .hevc).ytdlpFormat, "bv*+ba/best")
        XCTAssertTrue(profile(.max, .original).ytdlpFormat.hasPrefix("bv*[vcodec^=vp09]+ba[acodec^=mp4a]"))
    }

    func testRequestRoundTripsForHistoryRetry() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a"))
        let modes: [StreamRipper.Mode] = [.audio(.flac), .audio(.originalOpus), .audio(.mp3(kbps: 192)),
                                          .video(profile(.p2160, .original))]
        let requests = modes.map { RipRequest(url: url, kind: .rip($0, folder: "/tmp")) }
            + [RipRequest(url: url, kind: .youtube(summary: "youtube video"))]
        for request in requests {
            XCTAssertEqual(try JSONDecoder().decode(RipRequest.self, from: JSONEncoder().encode(request)), request)
        }
    }

    /// Tool errors quote the URL and file paths; the log keeps neither.
    func testLogRedactsURLsAndPaths() {
        XCTAssertEqual(StreamRipper.redacted("ERROR: [youtube] https://youtu.be/x?si=tok: /Users/me/Music/A - B.opus: Invalid data"),
                       "ERROR: [youtube] <url> <path>: Invalid data")
    }

    func testAudioChoicesNameTheirDownloadFormat() {
        XCTAssertEqual(RipAudioFormat.originalOpus.format(kbps: 256), .originalOpus)
        XCTAssertEqual(RipAudioFormat.originalAAC.format(kbps: 256), .originalAAC)
        XCTAssertEqual(RipAudioFormat.flac.format(kbps: 192), .flac, "only MP3 takes the bitrate")
        XCTAssertEqual(RipAudioFormat.mp3.format(kbps: 192), .mp3(kbps: 192))
        XCTAssertEqual(StreamRipper.Mode.audio(.mp3(kbps: 192)).description, "audio mp3-192")
        XCTAssertEqual(StreamRipper.Mode.audio(.flac).description, "audio flac")
    }
}

private final class OrderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var ids: [String] { lock.withLock { stored } }
    func append(_ id: String) { lock.withLock { stored.append(id) } }
}

/// Collects a handle's updates, delivered synchronously for the test.
private final class UpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [RipJobUpdate] = []
    var updates: [RipJobUpdate] { lock.withLock { stored } }
    func handle(id: String) -> RipJobHandle { RipJobHandle(id: id) { [weak self] in self?.record($0) } }
    private func record(_ update: RipJobUpdate) { lock.withLock { stored.append(update) } }
    var fractions: [Double] {
        updates.compactMap { if case .progress(let fraction, _) = $0 { fraction } else { nil } }
    }
    var titles: [String] {
        updates.compactMap { if case .title(let title) = $0 { title } else { nil } }
    }
}

final class RipProgressTests: XCTestCase {
    func testYtDlpProgressAcrossVideoAndAudioStreams() {
        let recorder = UpdateRecorder()
        let handle = recorder.handle(id: "test")
        let reader = YtDlpProgressReader(handle: handle, isVideo: true)
        // yt-dlp's HLS downloader opens each stream with a 100 % line before its first fragment.
        // A split chunk: the 100 % line only completes in the next read.
        reader.consume(Data("[info] noise\n[download] Destination: a.f617.mp4\nNPPROG| 100.0%|NA|Rush Live\n".utf8))
        reader.consume(Data("NPPROG|  0.2%|NA|Rush Live\nNPPROG|  50.0%|120|Rush Live\nNPPROG| 100.0%|0|Rus".utf8))
        reader.consume(Data("h Live\n[download] Destination: a.f140.m4a\nNPPROG| 100.0%|NA|Rush Live\nNPPROG|  10.0%|3|Rush Live\n".utf8))
        XCTAssertEqual(recorder.fractions.count, 4)
        XCTAssertEqual(recorder.fractions[0], 0.0019, accuracy: 0.0001, "the opening 100 % is ignored")
        XCTAssertEqual(recorder.fractions[1], 0.475, accuracy: 0.0001)
        XCTAssertEqual(recorder.fractions[2], 0.95, accuracy: 0.0001)
        XCTAssertEqual(recorder.fractions[3], 0.955, accuracy: 0.0001, "the audio stream starts at 95 %")
        XCTAssertEqual(recorder.titles, ["Rush Live"])
    }

    /// A pipe read can end mid-character; the title still decodes whole.
    func testYtDlpTitleSplitInsideAUTF8Character() {
        let recorder = UpdateRecorder()
        let reader = YtDlpProgressReader(handle: recorder.handle(id: "test"), isVideo: false)
        let line = Data("NPPROG|  5.0%|9|Café Live\n".utf8)
        let cut = line.firstIndex(of: 0xC3)! + 1  // between the two bytes of "é"
        reader.consume(line[..<cut])
        reader.consume(line[cut...])
        XCTAssertEqual(recorder.fractions, [0.05])
        XCTAssertEqual(recorder.titles, ["Café Live"])
    }

    func testFFmpegProgressFractionAndRemaining() {
        let recorder = UpdateRecorder()
        let handle = recorder.handle(id: "test")
        let reader = FFmpegProgressReader(handle: handle, duration: 100)
        reader.consume(Data("out_time_us=25000000\nspeed=2.5x\nprogress=continue\n".utf8))
        XCTAssertEqual(recorder.fractions, [0.25])
        guard case .progress(_, let remaining) = recorder.updates.last else { return XCTFail() }
        XCTAssertEqual(remaining ?? 0, 30, accuracy: 0.001)
    }
}

final class RipHandleTests: XCTestCase {
    func testCancelTerminatesTheRunningProcess() throws {
        let handle = RipJobHandle(id: "test")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sleep")
        task.arguments = ["30"]
        try handle.launch(task)
        handle.cancel()
        task.waitUntilExit()
        XCTAssertEqual(task.terminationReason, .uncaughtSignal)
        XCTAssertTrue(handle.isCancelled)
        let next = Process()
        next.executableURL = URL(fileURLWithPath: "/bin/sleep")
        next.arguments = ["30"]
        XCTAssertThrowsError(try handle.launch(next), "a cancelled job starts nothing new")
    }

    /// yt-dlp's ffmpeg child must not outlive a cancel: here a shell stands in for yt-dlp.
    func testCancelAlsoTerminatesTheProcessesItStarted() throws {
        let handle = RipJobHandle(id: "tree")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "/bin/sleep 30 & wait"]
        try handle.launch(task)
        var children: [pid_t] = []
        for _ in 0..<50 where children.isEmpty {
            children = ProcessTable.snapshot().descendants(of: task.processIdentifier)
            if children.isEmpty { Thread.sleep(forTimeInterval: 0.05) }
        }
        let child = try XCTUnwrap(children.first, "the shell started its sleep")
        handle.cancel()
        task.waitUntilExit()
        var alive = true
        for _ in 0..<50 where alive {
            alive = kill(child, 0) == 0
            if alive { Thread.sleep(forTimeInterval: 0.05) }
        }
        XCTAssertFalse(alive, "the child process was terminated with its parent")
    }

    /// Waiters get the encoder in the order they asked, which `position(of:)` shows.
    func testEncodeQueueServesWaitersInArrivalOrder() {
        let first = RipJobHandle(id: "q1")
        XCTAssertTrue(RipEncodeQueue.acquire(for: first))
        let order = OrderRecorder()
        let done = expectation(description: "both waiters ran")
        done.expectedFulfillmentCount = 2
        for id in ["q2", "q3"] {
            let handle = RipJobHandle(id: id)
            DispatchQueue.global().async {
                XCTAssertTrue(RipEncodeQueue.acquire(for: handle))
                order.append(id)
                RipEncodeQueue.release()
                done.fulfill()
            }
            // q2 is in line before q3 asks.
            let deadline = Date().addingTimeInterval(5)
            while RipEncodeQueue.position(of: id) == nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
            XCTAssertNotNil(RipEncodeQueue.position(of: id), "\(id) joined the line")
        }
        XCTAssertEqual(RipEncodeQueue.position(of: "q2"), 1)
        XCTAssertEqual(RipEncodeQueue.position(of: "q3"), 2)
        XCTAssertNil(RipEncodeQueue.position(of: "q1"), "the job holding the encoder is not in line")
        RipEncodeQueue.release()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(order.ids, ["q2", "q3"])
    }

    func testEncodeQueueRunsOneAtATimeAndSkipsCancelledWaiters() {
        let first = RipJobHandle(id: "a")
        let waiting = RipJobHandle(id: "b")
        XCTAssertTrue(RipEncodeQueue.acquire(for: first))
        let gaveUp = expectation(description: "cancelled waiter gives up")
        DispatchQueue.global().async {
            XCTAssertFalse(RipEncodeQueue.acquire(for: waiting))
            gaveUp.fulfill()
        }
        waiting.cancel()
        wait(for: [gaveUp], timeout: 3)
        RipEncodeQueue.release()
        let next = RipJobHandle(id: "c")
        XCTAssertTrue(RipEncodeQueue.acquire(for: next), "the slot is free again")
        RipEncodeQueue.release()
    }
}

@MainActor
final class RipJobCenterTests: XCTestCase {
    private var historyURL: URL!

    override func setUp() {
        historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("rip-history-\(UUID().uuidString).json")
        UserDefaults.standard.removeObject(forKey: RipJobCenter.showsActivityNotificationsKey)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: historyURL)
        UserDefaults.standard.removeObject(forKey: RipJobCenter.showsActivityNotificationsKey)
    }

    private func makeCenter() -> RipJobCenter {
        RipJobCenter(history: RipHistoryStore(fileURL: historyURL), presentsFailures: false)
    }

    func testJobsRunTogetherAndFinishIntoHistory() throws {
        let center = makeCenter()
        let url = try XCTUnwrap(URL(string: "https://example.com/a"))
        let handles = (0..<3).map { _ in center.beginExternal(url: url, summary: "youtube video") }
        XCTAssertEqual(center.runningCount, 3)
        handles[1].cancel()
        center.finish(handles[1], outputPath: nil, sizeBytes: nil, error: "terminated")
        center.finish(handles[0], outputPath: nil, sizeBytes: nil, error: "HTTP 403")
        XCTAssertEqual(center.runningCount, 1, "ending two leaves the third running")
        center.finish(handles[2], outputPath: "/tmp/x.mp4", sizeBytes: nil, error: nil)
        XCTAssertEqual(center.runningCount, 0)
        XCTAssertEqual(center.history.entries.map(\.outcome), [.done, .failed, .cancelled])
        XCTAssertEqual(center.history.entries[1].error, "HTTP 403")
        XCTAssertNil(center.history.entries[2].error, "a cancel is not a failure")
        XCTAssertFalse(center.showsActivityNotifications, "the notification panel is off by default")
    }

    /// A failed row names yt-dlp's error, not the warnings printed before it.
    @MainActor
    func testErrorSummaryPrefersTheErrorOverWarnings() {
        let stderr = """
        https://example.com/x

        WARNING: Your yt-dlp version (2026.08.19) is older than 90 days!
        It is strongly recommended to always use the latest version.
        ERROR: [generic] x: Unable to download webpage: HTTP Error 404: Not Found
        """
        XCTAssertEqual(RipWindowView.errorSummary(stderr), "ERROR: [generic] x: Unable to download webpage: HTTP Error 404: Not Found")
        XCTAssertEqual(RipWindowView.errorSummary("WARNING: old\nffmpeg exited with code 1"), "ffmpeg exited with code 1")
        XCTAssertEqual(RipWindowView.errorSummary("Could not create a temporary download folder"), "Could not create a temporary download folder")
        XCTAssertEqual(RipWindowView.errorSummary(nil), "")
    }

    /// Jobs saving the same name at once each keep their own file; neither deletes the other's.
    func testConcurrentTransfersToOneNameKeepEveryFile() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("rip-transfer-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("dest")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let count = 8
        let staged = try (0..<count).map { index -> URL in
            let url = root.appendingPathComponent("staged-\(index).opus")
            try Data(repeating: UInt8(index), count: 2_000_000).write(to: url)
            return url
        }
        let desired = folder.appendingPathComponent("Album.opus")
        let errors = OrderRecorder()
        DispatchQueue.concurrentPerform(iterations: count) { index in
            do { try StreamRipper.transferStagedFile(from: staged[index], to: desired) }
            catch { errors.append("\(error)") }
        }
        XCTAssertEqual(errors.ids, [])
        let saved = try fm.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(saved.count, count, "every job's file survives: \(saved.sorted())")
        let firstBytes = Set(try saved.map { try Data(contentsOf: folder.appendingPathComponent($0)).first })
        XCTAssertEqual(firstBytes.count, count, "each saved file is a different job's")
    }

    func testDuplicateMatchesOnlyARunningJobWithTheSameChoices() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/a"))
        let mode = StreamRipper.Mode.video(.init(resolution: .p2160, format: .original))
        let request = RipRequest(url: url, kind: .rip(mode, folder: "/tmp"))
        let job = RipJob(handle: RipJobHandle(id: "dup"), request: request)
        XCTAssertTrue(job.duplicates(request))
        XCTAssertFalse(job.duplicates(RipRequest(url: url, kind: .rip(.video(.init(resolution: .p1080, format: .original)), folder: "/tmp"))))
        XCTAssertFalse(job.duplicates(RipRequest(url: url, kind: .rip(mode, folder: "/Volumes/NAS"))),
                       "the same rip into another folder is a new rip")
        let youtube = RipRequest(url: url, kind: .youtube(summary: "youtube video"))
        XCTAssertFalse(RipJob(handle: RipJobHandle(id: "yt"), request: youtube).duplicates(youtube),
                       "a YouTube download is never a rip's duplicate")
        job.phase = .done
        XCTAssertFalse(job.duplicates(request))
    }

    func testHistoryPersistsCapsAndSurvivesACorruptFile() throws {
        let store = RipHistoryStore(fileURL: historyURL)
        let url = try XCTUnwrap(URL(string: "https://example.com/a"))
        for index in 0..<(RipHistoryStore.limit + 2) {
            store.append(RipHistoryEntry(id: "\(index)", request: RipRequest(url: url, kind: .rip(.audio(.mp3(kbps: 256)), folder: "/tmp")),
                                         title: "t\(index)", outcome: .done, startedAt: Date(),
                                         finishedAt: Date(), outputPath: nil, sizeBytes: nil, error: nil))
        }
        let reloaded = RipHistoryStore(fileURL: historyURL)
        XCTAssertEqual(reloaded.entries.count, RipHistoryStore.limit)
        XCTAssertEqual(reloaded.entries.first?.id, "\(RipHistoryStore.limit + 1)", "newest first")
        XCTAssertEqual(reloaded.entries.first?.request.kind, .rip(.audio(.mp3(kbps: 256)), folder: "/tmp"))
        reloaded.remove(id: "\(RipHistoryStore.limit + 1)")
        XCTAssertEqual(RipHistoryStore(fileURL: historyURL).entries.count, RipHistoryStore.limit - 1)
        reloaded.clear()
        XCTAssertTrue(RipHistoryStore(fileURL: historyURL).entries.isEmpty)
        try Data("not json".utf8).write(to: historyURL)
        XCTAssertTrue(RipHistoryStore(fileURL: historyURL).entries.isEmpty)
    }
}
