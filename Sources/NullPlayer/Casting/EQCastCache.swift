import AVFoundation
import Accelerate
import CryptoKit
import Foundation

/// EQ Cast: a track rendered with its resolved EQ profile into a 16-bit FLAC in a user-picked folder,
/// and cast in place of the original. Only the profile is rendered — not the graphic EQ or other DSP.
///
/// The cache never touches the main thread: it resolves profiles on its own store connection, and is
/// handed the tracks to pre-render (CastManager reads the engine). UI updates are pushed, never awaited.
actor EQCastCache {
    static let shared = EQCastCache()
    static let enabledKey = "eqCastEnabled"
    static let folderKey = "eqCastFolder"
    static let metadataName = "eqcast.json"

    /// Output ▸ EQ Cast ▸ Enabled. Off: originals are cast; rendered files are kept.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    static var folder: URL? {
        UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    enum Lookup: Equatable {
        case hit(URL), needsRender, skip
    }

    enum Phase: Sendable {
        case downloading, rendering
    }

    /// What `eqcast.json` holds per file. The curve is stored whole: a profile is edited in place
    /// under the same id, so the id alone would serve stale audio.
    private struct Entry: Codable, Equatable {
        let source: String
        let key: String
        let profileID: UUID
        let curve: EQCurve
    }

    private struct Target {
        let file: URL
        let entry: Entry
    }

    private struct RenderError: Error {
        let reason: String
    }

    private let resolver: EQProfileResolver
    /// Keyed by path, with the entry being rendered: a profile edit keeps the path but changes the entry.
    private var inFlight: [String: (entry: Entry, task: Task<URL?, Never>)] = [:]
    private var listeners: [String: [@Sendable (Phase, Int) -> Void]] = [:]
    /// The last step reported per in-flight path, so progress only climbs.
    private var reported: [String: Int] = [:]
    private var prefetchTask: Task<Void, Never>?
    /// Bumped by `stop()`, so a render waiting out an older curve does not start after it.
    private var stops = 0
    private var usageBytes: Int64?
    private var measuring: URL?

    /// Its own connection to the profile database, so resolving never queues behind the UI's.
    init(store: EQProfileStore = EQProfileStore(busyTimeout: 2)) {
        resolver = EQProfileResolver(store: store)
    }

    /// Cheapest checks first: a track without a profile never pays for the Sonos sample-rate lookup.
    func cached(_ track: Track, device: CastDeviceType) async -> Lookup {
        guard let target = target(for: track) else { return .skip }
        if device == .sonos {
            let sampleRate = await CastManager.resolveSonosSampleRate(for: track)
            guard CastManager.isSonosCompatible(track, sampleRateOverride: sampleRate,
                                                allowUnknownSampleRate: track.url.isFileURL) else { return .skip }
        }
        return isCurrent(target) ? .hit(target.file) : .needsRender
    }

    /// The rendered file, or nil when it could not be made (the original is cast). Callers for the
    /// same file and curve share one render; `progress` gets each 5% step. A render of an older curve
    /// is never joined: it finishes for its own callers, then this one starts.
    func render(_ track: Track, progress: (@Sendable (Phase, Int) -> Void)? = nil) async -> URL? {
        guard let target = target(for: track), let root = Self.folder else { return nil }
        let path = target.file.path, stopsBefore = stops
        while let running = inFlight[path], running.entry != target.entry { _ = await running.task.value }
        guard stops == stopsBefore else { return nil }
        if isCurrent(target) { return target.file }
        if let progress { listeners[path, default: []].append(progress) }
        if let running = inFlight[path] { return await running.task.value }
        let task = Task { await perform(track, target, root: root) }
        inFlight[path] = (target.entry, task)
        return await task.value
    }

    /// Renders `upcoming` in order, one at a time, replacing the previous pass.
    func prefetch(_ upcoming: [Track], device: CastDeviceType) {
        prefetchTask?.cancel()
        prefetchTask = Task {
            for track in upcoming {
                if Task.isCancelled { return }
                if await cached(track, device: device) == .needsRender { _ = await render(track) }
            }
        }
    }

    func stop() {
        stops += 1
        prefetchTask?.cancel()
        prefetchTask = nil
        inFlight.values.forEach { $0.task.cancel() }
    }

    /// Empties the folder except `inUse`, the file being cast: the media server reads it by path.
    func deleteCache(keeping inUse: URL?) async {
        stop()
        for running in inFlight.values { _ = await running.task.value }
        guard let root = Self.folder else { return }
        let keep = inUse.map { [$0, $0.deletingLastPathComponent().appendingPathComponent(Self.metadataName)] }?
            .map { $0.resolvingSymlinksInPath().path } ?? []
        await Task.detached(priority: .utility) { Self.remove(in: root, keeping: Set(keep)) }.value
        usageBytes = nil
        await measureUsage()
    }

    /// Walks the folder once for its size; a render adjusts it from there.
    func measureUsage() async {
        guard let root = Self.folder, measuring != root else { return }
        measuring = root
        publish(nil)
        let total = await Task.detached(priority: .utility) { Self.allocatedSize(of: root) }.value
        if measuring == root { measuring = nil }
        if Self.folder == root { publish(total) }
    }

    // MARK: - Lookup

    /// Where `track`'s render lives and what it must match; nil when EQ Cast does not apply.
    private func target(for track: Track) -> Target? {
        // ponytail: cue tracks are skipped; render the range when cue casting exists.
        guard Self.isEnabled, let root = Self.folder, track.mediaType == .audio,
              track.playHistorySource != .radio, track.cueStartOffset == nil,
              let scope = track.eqProfileScopes.first,
              let profile = resolver.activeProfile(for: track)?.profile else { return nil }
        // `Track` has no track number and `hashValue` changes per launch: a stable hash keeps names unique.
        let hash = SHA256.hash(data: Data("\(scope.source)\0\(scope.key)".utf8))
            .prefix(4).map { String(format: "%02x", $0) }.joined()
        let folder = [scope.source, track.artist ?? "Unknown Artist", track.album ?? "Unknown Album"]
            .reduce(root) { $0.appendingPathComponent(YouTubeManager.sanitizedPathComponent($1), isDirectory: true) }
        let name = "\(YouTubeManager.sanitizedPathComponent(String(track.title.prefix(100)))) [\(hash)].flac"
        return Target(file: folder.appendingPathComponent(name),
                      entry: Entry(source: scope.source, key: scope.key, profileID: profile.id, curve: profile.curve))
    }

    private func isCurrent(_ target: Target) -> Bool {
        FileManager.default.fileExists(atPath: target.file.path)
            && entries(in: target.file.deletingLastPathComponent())[target.file.lastPathComponent] == target.entry
    }

    private func entries(in folder: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.metadataName)) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    /// On the actor, so two renders in one album folder never race on its metadata.
    private func save(_ entry: Entry, for file: URL) {
        let folder = file.deletingLastPathComponent()
        var all = entries(in: folder)
        all[file.lastPathComponent] = entry
        do {
            try JSONEncoder().encode(all).write(to: folder.appendingPathComponent(Self.metadataName), options: .atomic)
        } catch {
            NSLog("[eqcast] metadata write failed: %@", String(describing: error))
        }
    }

    // MARK: - Rendering

    private func perform(_ track: Track, _ target: Target, root: URL) async -> URL? {
        let path = target.file.path
        defer {
            inFlight[path] = nil
            listeners[path] = nil
            reported[path] = nil
        }
        let oldSize = Self.size(of: target.file)
        NSLog("[eqcast] rendering '%@'", track.title)
        let work = Task.detached(priority: listeners[path] == nil ? .utility : .userInitiated) {
            try await Self.produce(track, curve: target.entry.curve, into: target.file, root: root) { phase, fraction in
                await self.report(path, phase, fraction)
            }
        }
        do {
            try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
        } catch {
            NSLog("[eqcast] render of '%@' failed: %@", track.title, String(describing: error))
            return nil
        }
        save(target.entry, for: target.file)
        if let usageBytes { publish(usageBytes + Self.size(of: target.file) - oldSize) }
        NSLog("[eqcast] rendered '%@'", track.title)
        return target.file
    }

    private func report(_ path: String, _ phase: Phase, _ fraction: Double) {
        let percent = min(100, Int(fraction * 20) * 5)
        let rank = (phase == .rendering ? 1000 : 0) + percent
        guard inFlight[path] != nil, rank > reported[path, default: -1] else { return }
        reported[path] = rank
        listeners[path]?.forEach { $0(phase, percent) }
    }

    private func publish(_ bytes: Int64?) {
        usageBytes = bytes
        Task { @MainActor in EQCast.usageBytes = bytes }
    }

    /// Fetches a server track into the cache root, renders `curve` over it, then renames the
    /// finished file into place.
    private static func produce(_ track: Track, curve: EQCurve, into file: URL, root: URL,
                                report: @escaping @Sendable (Phase, Double) async -> Void) async throws {
        let files = FileManager.default
        var source = track.url
        var download: URL?
        defer { if let download { try? files.removeItem(at: download) } }
        if !source.isFileURL {
            let remote = PlexManager.shared.getCastableStreamURL(for: track.url) ?? track.url
            let delegate = DownloadProgress { fraction in Task { await report(.downloading, fraction) } }
            let (temp, response) = try await URLSession.shared.download(from: remote, delegate: delegate)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                try? files.removeItem(at: temp)
                throw RenderError(reason: "HTTP \(status)")
            }
            let ext = response.suggestedFilename.map { URL(fileURLWithPath: $0).pathExtension } ?? ""
            try files.createDirectory(at: root, withIntermediateDirectories: true)
            let moved = root.appendingPathComponent(".download-\(UUID().uuidString)")
                .appendingPathExtension(ext.isEmpty ? "audio" : ext)
            try files.moveItem(at: temp, to: moved)
            download = moved
            source = moved
        }
        // `AVAudioFile` takes the file type from the extension, so the partial file ends in .flac.
        let part = file.deletingPathExtension().appendingPathExtension("part.flac")
        try files.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try await encode(source, curve: curve, to: part) { await report(.rendering, $0) }
        } catch {
            try? files.removeItem(at: part)
            throw error
        }
        guard rename(part.path, file.path) == 0 else { throw RenderError(reason: "rename failed: \(errno)") }
    }

    /// 16-bit FLAC at the source's rate: Sonos S1 decodes only 16-bit FLAC, and any device may play it.
    /// Writing from an Int16 buffer is what makes Core Audio encode 16-bit; Float32 input gives 24.
    private static func encode(_ source: URL, curve: EQCurve, to part: URL,
                               report: (Double) async -> Void) async throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let channels = Int(format.channelCount)
        guard channels <= 2 else { throw RenderError(reason: "\(channels) channels") }
        let output = try AVAudioFile(forWriting: part,
                                     settings: [AVFormatIDKey: kAudioFormatFLAC,
                                                AVSampleRateKey: format.sampleRate,
                                                AVNumberOfChannelsKey: channels],
                                     commonFormat: .pcmFormatInt16, interleaved: false)
        let chunk: AVAudioFrameCount = 32_768
        guard let samples = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk),
              let pcm = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: chunk),
              let float = samples.floatChannelData, let int16 = pcm.int16ChannelData else {
            throw RenderError(reason: "no buffers")
        }
        let kernel = EQProfileKernel(maximumFrames: Int(chunk), sampleRate: format.sampleRate)
        EQProfileCoefficients.design(curve, sampleRate: format.sampleRate)
            .withUnsafeBufferPointer { kernel.reset(with: $0.baseAddress!) }
        // ponytail: hard clip at ±1.0 on hot boosts; add a peak-normalize pass if users hear it.
        var low: Float = -1, high: Float = 1, scale = Float(Int16.max)
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: samples, frameCount: chunk)
            let frames = Int(samples.frameLength)
            guard frames > 0 else { break }
            kernel.process(left: float[0], right: channels == 2 ? float[1] : nil, frames: frames)
            for channel in 0..<channels {
                vDSP_vclip(float[channel], 1, &low, &high, float[channel], 1, vDSP_Length(frames))
                vDSP_vsmul(float[channel], 1, &scale, float[channel], 1, vDSP_Length(frames))
                vDSP_vfixr16(float[channel], 1, int16[channel], 1, vDSP_Length(frames))
            }
            pcm.frameLength = samples.frameLength
            try output.write(from: pcm)
            await report(Double(input.framePosition) / Double(max(1, input.length)))
        }
    }

    // MARK: - Disk

    private static func size(of file: URL) -> Int64 {
        Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }

    private static func allocatedSize(of root: URL) -> Int64 {
        var total: Int64 = 0
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        while let url = walk?.nextObject() as? URL { total += size(of: url) }
        return total
    }

    /// Removes everything under `folder` except the paths in `keep` (symlinks resolved) and the
    /// folders holding them.
    private static func remove(in folder: URL, keeping keep: Set<String>) {
        let files = FileManager.default
        for item in (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let path = item.resolvingSymlinksInPath().path
            if keep.contains(path) { continue }
            if keep.contains(where: { $0.hasPrefix(path + "/") }) {
                remove(in: item, keeping: keep)
            } else {
                try? files.removeItem(at: item)
            }
        }
    }
}

/// A download's progress, from its task's `Progress`. KVO fires on the session's serial delegate
/// queue, so `lastStep` has one writer.
private final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onChange: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastStep = -1

    init(_ onChange: @escaping @Sendable (Double) -> Void) {
        self.onChange = onChange
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let step = Int(progress.fractionCompleted * 20)
            guard step != lastStep else { return }
            lastStep = step
            onChange(progress.fractionCompleted)
        }
    }
}

/// The one seam CastManager calls, on main: which file to cast, the render's progress in the
/// ActivityCenter, and the upcoming tracks to pre-render.
@MainActor
enum EQCast {
    /// The cache folder's size; nil while it is measured. Pushed by the cache.
    static var usageBytes: Int64?
    /// The rendered file being cast now, which Delete Cache keeps.
    private(set) static var castingFile: URL?
    /// The last pre-render list; nil until the session's first, so the first cast says it takes a moment.
    private static var upcoming: (tracks: [Track], device: CastDeviceType)?
    /// The render whose progress the row shows. Progress hops to main in its own Task, so one can
    /// land after `hide`; without this check it would re-create a row nothing removes.
    private static var activity: UUID?
    private static let renderActivityID = "eqcast-render"

    /// A profile edit re-renders what is coming up.
    private static let profileObserver = NotificationCenter.default.addObserver(
        forName: .eqProfilesDidChange, object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            guard let upcoming else { return }
            Task { await EQCastCache.shared.prefetch(upcoming.tracks, device: upcoming.device) }
        }
    }

    /// The rendered file to cast instead of `track`, or nil to cast the original. A render shows on
    /// the ActivityCenter; `generation` false means the request was superseded and nothing renders.
    static func castableFile(for track: Track, device: CastDeviceType, generation: @MainActor () -> Bool) async -> URL? {
        let cache = EQCastCache.shared
        var file: URL?
        switch await cache.cached(track, device: device) {
        case .skip:
            break
        case .hit(let url):
            NSLog("[eqcast] reusing render of '%@'", track.title)
            file = url
        case .needsRender:
            guard generation() else { return nil }
            let token = UUID(), title = track.title, first = upcoming == nil
            activity = token
            ActivityCenter.shared.show(id: renderActivityID, message: line(title, track.url.isFileURL ? .rendering : .downloading, 0, first: first))
            file = await cache.render(track) { phase, percent in
                Task { @MainActor in
                    if activity == token { ActivityCenter.shared.show(id: renderActivityID, message: line(title, phase, percent, first: first)) }
                }
            }
            if activity == token {
                activity = nil
                ActivityCenter.shared.hide(id: renderActivityID)
            }
        }
        return file
    }

    /// How many of the tracks that play next are pre-rendered after each cast.
    private static let lookahead = 3

    /// After a successful cast: `file` is the render now playing (nil for an original), which Delete
    /// Cache keeps; then the next `lookahead` tracks in play order are pre-rendered.
    static func didCast(_ file: URL?, from engine: AudioEngine, device: CastDeviceType) {
        castingFile = file
        guard EQCastCache.isEnabled else { return }
        _ = profileObserver
        let tracks = engine.upcomingIndices.prefix(lookahead).map { engine.playlist[$0] }
        upcoming = (tracks, device)
        Task { await EQCastCache.shared.prefetch(tracks, device: device) }
    }

    /// Casting ended, or EQ Cast was turned off: stop pre-rendering. Rendered files are kept.
    static func stop() {
        upcoming = nil
        castingFile = nil
        Task { await EQCastCache.shared.stop() }
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: EQCastCache.enabledKey)
        if enabled { measureUsage() } else { stop() }
    }

    /// The old folder's files stay where they are.
    static func setFolder(_ folder: URL) {
        UserDefaults.standard.set(folder.path, forKey: EQCastCache.folderKey)
        usageBytes = nil
        measureUsage()
    }

    static func measureUsage() {
        Task { await EQCastCache.shared.measureUsage() }
    }

    private static func line(_ title: String, _ phase: EQCastCache.Phase, _ percent: Int, first: Bool) -> String {
        switch phase {
        case .downloading: return "EQ Cast: downloading \(title) \(percent)%"
        case .rendering where first: return "EQ Cast: preparing \(title) — first track takes a moment… \(percent)%"
        case .rendering: return "EQ Cast: rendering \(title) \(percent)%"
        }
    }
}
