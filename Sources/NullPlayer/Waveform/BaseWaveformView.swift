import AppKit

/// Shared waveform state and interaction helpers used by both classic and modern waveform windows.
class BaseWaveformView: NSView {
    private let waveformConsumerID = "waveformWindow.\(UUID().uuidString)"

    weak var waveformController: WaveformWindowProviding?

    private var loadTask: Task<Void, Never>?
    private var cueLoadTask: Task<Void, Never>?
    private var trackingArea: NSTrackingArea?
    private var tooltipTag: NSView.ToolTipTag = 0
    private var streamWaveformObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var streamingAccumulator: StreamingWaveformAccumulator?
    private var waveformColumnCache: [UInt16] = []
    private var waveformColumnCacheWidth = 0
    private var waveformColumnCacheVersion = -1
    private var waveformDataVersion = 0

    private(set) var currentTrack: Track?
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var snapshot: WaveformSnapshot = .unsupported("No track loaded")
    private(set) var cuePoints: [WaveformCuePoint] = []
    private(set) var dragTimeOverride: TimeInterval?
    private(set) var isDraggingWaveform = false

    var waveformRect: NSRect {
        .zero
    }

    var waveformColors: WaveformRenderColors {
        WaveformRenderColors(
            background: .black,
            backgroundMode: .opaque,
            backgroundOpacity: 1.0,
            contentOpacity: 1.0,
            waveform: .white,
            playedWaveform: .green,
            cuePoint: .lightGray,
            playhead: .white,
            text: .white,
            selection: .white
        )
    }

    var isTooltipHidden: Bool {
        get {
            if UserDefaults.standard.object(forKey: "waveformHideTooltip") == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: "waveformHideTooltip")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "waveformHideTooltip")
            refreshToolTips()
        }
    }

    var showsCuePoints: Bool {
        get { UserDefaults.standard.bool(forKey: "waveformShowCuePoints") }
        set {
            UserDefaults.standard.set(newValue, forKey: "waveformShowCuePoints")
            requestCuePoints(for: currentTrack)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newArea)
        trackingArea = newArea
        refreshToolTips()
    }

    func startAppearanceObservation() {
        guard appearanceObserver == nil else { return }
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: .waveformAppearanceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWaveformAppearanceChanged()
        }
    }

    func stopAppearanceObservation() {
        if let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
            self.appearanceObserver = nil
        }
    }

    func drawWaveform(in context: CGContext) {
        let columnAmplitudes = cachedColumnAmplitudes()
        WaveformDrawing.draw(
            snapshot: snapshot,
            columnAmplitudes: columnAmplitudes,
            cuePoints: cuePoints,
            showCuePoints: showsCuePoints,
            currentTime: currentTime,
            dragTime: dragTimeOverride,
            in: waveformRect,
            colors: waveformColors,
            context: context
        )
    }

    func updateTrack(_ track: Track?) {
        ensureStreamingObserver()

        if shouldPreservePrerender(for: track) {
            currentTrack = track
            if let track {
                duration = track.duration ?? duration
            }
            needsDisplay = true
            return
        }

        currentTrack = track
        currentTime = 0
        dragTimeOverride = nil
        cuePoints = []
        requestCuePoints(for: track)
        streamingAccumulator = nil
        updateWaveformConsumerRegistration(enabled: false)

        guard let track else {
            setSnapshot(.unsupported("No track loaded"))
            duration = 0
            needsDisplay = true
            return
        }

        duration = track.duration ?? 0
        if track.mediaType != .audio {
            setSnapshot(.unsupported("Waveform unavailable for video"))
            needsDisplay = true
            return
        }
        reloadWaveform(force: false)
    }

    private func shouldPreservePrerender(for nextTrack: Track?) -> Bool {
        guard let currentTrack,
              let nextTrack,
              snapshot.state == .ready,
              !snapshot.samples.isEmpty else {
            return false
        }

        if let currentIdentity = currentTrack.streamingServiceIdentity,
           currentIdentity == nextTrack.streamingServiceIdentity,
           snapshot.sourcePath?.hasPrefix("service:") == true {
            return true
        }

        if currentTrack.url.isFileURL,
           nextTrack.url.isFileURL,
           currentTrack.url.resolvingSymlinksInPath().standardizedFileURL ==
            nextTrack.url.resolvingSymlinksInPath().standardizedFileURL {
            return true
        }

        return false
    }

    func updateTime(current: TimeInterval, duration: TimeInterval) {
        let previousDuration = self.duration
        currentTime = current
        self.duration = duration
        var shouldRedraw = true
        if let track = currentTrack, !track.url.isFileURL {
            let effectiveDuration = duration > 0 ? duration : track.duration
            let hasLockedServicePrerender = snapshot.state == .ready &&
                snapshot.isStreaming &&
                snapshot.allowsSeeking &&
                snapshot.sourcePath?.hasPrefix("service:") == true &&
                streamingAccumulator == nil

            if hasLockedServicePrerender {
                if let effectiveDuration, effectiveDuration > 0,
                   abs(snapshot.duration - effectiveDuration) > 0.001 {
                    var next = snapshot
                    next.duration = effectiveDuration
                    setSnapshot(next)
                }
            } else {
            let previousAllowsSeeking = snapshot.allowsSeeking
            let previousSnapshotDuration = snapshot.duration

            streamingAccumulator?.updateDuration(effectiveDuration)
            if snapshot.state == .ready {
                let nextAllowsSeeking = (effectiveDuration ?? 0) > 0
                if previousAllowsSeeking != nextAllowsSeeking ||
                    (nextAllowsSeeking && previousSnapshotDuration != (effectiveDuration ?? 0)) {
                    setSnapshot(streamingAccumulator?.snapshot(sourcePath: track.url.absoluteString, currentTime: current) ?? .loadingStream)
                }
            }
            }

            if snapshot.isStreaming && !snapshot.allowsSeeking && previousDuration == duration && !isDraggingWaveform {
                shouldRedraw = false
            }
        }
        if shouldRedraw {
            setNeedsDisplay(waveformRect)
        }
    }

    func reloadWaveform(force: Bool) {
        loadTask?.cancel()

        guard let track = currentTrack, track.mediaType == .audio else {
            needsDisplay = true
            return
        }

        if !track.url.isFileURL {
            streamingAccumulator = StreamingWaveformAccumulator(duration: duration > 0 ? duration : track.duration)
            setSnapshot(.loadingStream)
            updateWaveformConsumerRegistration(enabled: window?.isVisible ?? true)
            needsDisplay = true

            // Service-backed streams can prerender in the background; live updates remain active.
            loadTask = Task { [weak self] in
                let result = await WaveformCacheService.shared.loadSnapshot(for: track, forceRegeneration: force)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.currentTrack == track else { return }
                    guard result.state == .ready, !result.samples.isEmpty else {
                        if result.state != .ready {
                            NSLog(
                                "BaseWaveformView: Stream prerender unavailable for '%@': %@",
                                track.title,
                                result.message ?? result.state.rawValue
                            )
                        }
                        return
                    }
                    self.setSnapshot(result)
                    if result.isStreaming && result.allowsSeeking {
                        // Service prerender is ready; stop live chunk accumulation so the
                        // prerendered full-track snapshot remains visible.
                        self.streamingAccumulator = nil
                        self.updateWaveformConsumerRegistration(enabled: false)
                    }
                    if self.duration <= 0 {
                        self.duration = result.duration
                    }
                    self.needsDisplay = true
                }
            }
            return
        }

        setSnapshot(.loading)
        needsDisplay = true

        loadTask = Task { [weak self] in
            let result = await WaveformCacheService.shared.loadSnapshot(for: track, forceRegeneration: force)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.currentTrack == track else { return }
                self.setSnapshot(result)
                if self.duration <= 0 {
                    self.duration = result.duration
                }
                self.needsDisplay = true
            }
        }
    }

    func stopLoadingForHide() {
        loadTask?.cancel()
        cueLoadTask?.cancel()
        isDraggingWaveform = false
        dragTimeOverride = nil
        updateWaveformConsumerRegistration(enabled: false)
    }

    func clearCurrentCacheAndReload() {
        let track = currentTrack
        loadTask?.cancel()
        if let track, !track.url.isFileURL {
            streamingAccumulator = StreamingWaveformAccumulator(duration: duration > 0 ? duration : track.duration)
            setSnapshot(.loadingStream)
            updateWaveformConsumerRegistration(enabled: window?.isVisible ?? true)
            needsDisplay = true
        }
        loadTask = Task { [weak self] in
            await WaveformCacheService.shared.clearCache(for: track)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.reloadWaveform(force: false)
            }
        }
    }

    func beginWaveformDrag(at point: NSPoint) {
        guard snapshot.isInteractive, waveformRect.contains(point) else { return }
        isDraggingWaveform = true
        dragTimeOverride = time(for: point)
        setNeedsDisplay(waveformRect)
    }

    func continueWaveformDrag(at point: NSPoint) {
        guard isDraggingWaveform else { return }
        dragTimeOverride = time(for: point)
        setNeedsDisplay(waveformRect)
    }

    func endWaveformDrag(at point: NSPoint) {
        guard isDraggingWaveform else { return }
        let targetTime = time(for: point)
        isDraggingWaveform = false
        dragTimeOverride = nil
        if WindowManager.shared.isVideoActivePlayback {
            WindowManager.shared.seekVideo(to: targetTime)
        } else {
            WindowManager.shared.audioEngine.seek(to: targetTime)
        }
        currentTime = targetTime
        setNeedsDisplay(waveformRect)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = ContextMenuBuilder.buildWaveformWindowContextMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let cursor = snapshot.isInteractive ? NSCursor.pointingHand : NSCursor.arrow
        addCursorRect(waveformRect, cursor: cursor)
    }

    private func refreshToolTips() {
        if tooltipTag != 0 {
            removeToolTip(tooltipTag)
            tooltipTag = 0
        }

        guard !isTooltipHidden else { return }
        tooltipTag = addToolTip(waveformRect, owner: self, userData: nil)
    }

    private func handleWaveformAppearanceChanged() {
        setNeedsDisplay(waveformRect)
    }

    private func requestCuePoints(for track: Track?) {
        cueLoadTask?.cancel()

        guard showsCuePoints, let track else {
            cuePoints = []
            setNeedsDisplay(waveformRect)
            return
        }

        let expectedTrackID = track.id
        cueLoadTask = Task { [weak self] in
            let parseTask = Task.detached(priority: .utility) {
                WaveformCueSheetParser.parse(for: track)
            }
            let points = await withTaskCancellationHandler {
                await parseTask.value
            } onCancel: {
                parseTask.cancel()
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      self.showsCuePoints,
                      self.currentTrack?.id == expectedTrackID else { return }
                self.cuePoints = points
                self.setNeedsDisplay(self.waveformRect)
            }
        }
    }

    private func time(for point: NSPoint) -> TimeInterval {
        guard duration > 0 else { return 0 }
        let fraction = min(max((point.x - waveformRect.minX) / max(waveformRect.width, 1), 0), 1)
        return duration * TimeInterval(fraction)
    }

    private func ensureStreamingObserver() {
        guard streamWaveformObserver == nil else { return }
        streamWaveformObserver = NotificationCenter.default.addObserver(
            forName: .audioWaveform576DataUpdated,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Avoid blocking the real-time audio callback thread while waiting on
            // OperationQueue.main delivery, which can deadlock during cast handoff.
            DispatchQueue.main.async { [weak self] in
                self?.handleStreamingWaveformNotification(notification)
            }
        }
    }

    private func handleStreamingWaveformNotification(_ notification: Notification) {
        guard let track = currentTrack,
              track.mediaType == .audio,
              !track.url.isFileURL,
              let userInfo = notification.userInfo,
              let left = userInfo["left"] as? [UInt8],
              let right = userInfo["right"] as? [UInt8],
              let sampleRate = userInfo["sampleRate"] as? Double else {
            return
        }

        // Once a service-backed prerender is ready, keep it stable and ignore live
        // waveform chunks so the window remains fully preloaded.
        if snapshot.state == .ready,
           snapshot.allowsSeeking,
           snapshot.isStreaming,
           snapshot.sourcePath?.hasPrefix("service:") == true {
            return
        }

        if streamingAccumulator == nil {
            streamingAccumulator = StreamingWaveformAccumulator(duration: duration > 0 ? duration : track.duration)
        }

        let playbackTime = WindowManager.shared.audioEngine.currentTime
        streamingAccumulator?.updateDuration(duration > 0 ? duration : track.duration)
        streamingAccumulator?.append(left: left, right: right, sampleRate: sampleRate, currentTime: playbackTime)
        setSnapshot(streamingAccumulator?.snapshot(sourcePath: track.url.absoluteString, currentTime: playbackTime) ?? .loadingStream)
        needsDisplay = true
    }

    private func cachedColumnAmplitudes() -> [UInt16] {
        let width = max(1, Int(waveformRect.width))
        guard !snapshot.samples.isEmpty else { return [] }
        if waveformColumnCacheWidth == width, waveformColumnCacheVersion == waveformDataVersion {
            return waveformColumnCache
        }

        waveformColumnCache = WaveformDrawing.makeColumnAmplitudes(samples: snapshot.samples, pixelWidth: width)
        waveformColumnCacheWidth = width
        waveformColumnCacheVersion = waveformDataVersion
        return waveformColumnCache
    }

    private func setSnapshot(_ snapshot: WaveformSnapshot) {
        self.snapshot = snapshot
        waveformDataVersion &+= 1
    }

    private func updateWaveformConsumerRegistration(enabled: Bool) {
        guard let track = currentTrack, track.mediaType == .audio, !track.url.isFileURL else {
            WindowManager.shared.audioEngine.removeWaveformConsumer(waveformConsumerID)
            return
        }
        if enabled {
            WindowManager.shared.audioEngine.addWaveformConsumer(waveformConsumerID)
        } else {
            WindowManager.shared.audioEngine.removeWaveformConsumer(waveformConsumerID)
        }
    }

    deinit {
        loadTask?.cancel()
        cueLoadTask?.cancel()
        WindowManager.shared.audioEngine.removeWaveformConsumer(waveformConsumerID)
        if let streamWaveformObserver {
            NotificationCenter.default.removeObserver(streamWaveformObserver)
        }
    }
}

extension BaseWaveformView: NSViewToolTipOwner {
    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard !isTooltipHidden,
              waveformRect.contains(point) else {
            return ""
        }

        let fraction = (point.x - waveformRect.minX) / max(waveformRect.width, 1)
        return WaveformDrawing.tooltipText(at: fraction, snapshot: snapshot, cuePoints: cuePoints) ?? ""
    }
}
