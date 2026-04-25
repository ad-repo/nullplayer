import AppKit
import Foundation

extension Notification.Name {
    static let youTubeMusicStateChanged = Notification.Name("youTubeMusicStateChanged")
    static let youTubeMusicTrackChanged = Notification.Name("youTubeMusicTrackChanged")
}

enum YouTubeMusicPlaybackState: String, Sendable {
    case stopped
    case playing
    case paused
    case buffering
    case ended
}

final class YouTubeMusicController {
    static let shared = YouTubeMusicController()

    private(set) var queue: [YouTubeMusicTrack] = []
    private(set) var currentIndex: Int = -1
    private(set) var state: YouTubeMusicPlaybackState = .stopped {
        didSet {
            NotificationCenter.default.post(
                name: .youTubeMusicStateChanged,
                object: self,
                userInfo: ["state": state.rawValue]
            )
        }
    }

    weak var playerView: YouTubeMusicPlayerView?

    var isActive: Bool {
        state != .stopped && currentIndex >= 0 && currentIndex < queue.count
    }

    var currentTrack: YouTubeMusicTrack? {
        guard currentIndex >= 0 && currentIndex < queue.count else { return nil }
        return queue[currentIndex]
    }

    private init() {}

    func load(rawSource: String, autoplay: Bool = true) {
        guard let track = YouTubeMusicURLParser.makeTrack(from: rawSource) else {
            NSSound.beep()
            return
        }
        load(queue: [track], startIndex: 0, autoplay: autoplay)
    }

    func load(queue nextQueue: [YouTubeMusicTrack], startIndex: Int = 0, autoplay: Bool = true) {
        guard nextQueue.indices.contains(startIndex) else { return }
        queue = nextQueue
        currentIndex = startIndex
        state = .buffering
        NotificationCenter.default.post(name: .youTubeMusicTrackChanged, object: self)
        playerView?.load(track: nextQueue[startIndex], autoplay: autoplay)
    }

    func playPause() {
        switch state {
        case .playing:
            pause()
        default:
            play()
        }
    }

    func play() {
        ensurePlayerWindowVisible()
        playerView?.play()
        state = .playing
    }

    func pause() {
        playerView?.pause()
        state = .paused
    }

    func stop() {
        playerView?.stop()
        state = .stopped
    }

    func next() {
        guard !queue.isEmpty else { return }
        if currentIndex + 1 < queue.count {
            currentIndex += 1
        } else {
            currentIndex = 0
        }
        state = .buffering
        NotificationCenter.default.post(name: .youTubeMusicTrackChanged, object: self)
        playerView?.load(track: queue[currentIndex], autoplay: true)
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            currentIndex = queue.count - 1
        }
        state = .buffering
        NotificationCenter.default.post(name: .youTubeMusicTrackChanged, object: self)
        playerView?.load(track: queue[currentIndex], autoplay: true)
    }

    func seek(to seconds: TimeInterval) {
        playerView?.seek(to: seconds)
    }

    func seek(by seconds: TimeInterval) {
        playerView?.seek(by: seconds)
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        playerView?.setVolume(Int(clamped * 100))
    }

    func handlePlayerState(_ rawState: Int) {
        switch rawState {
        case -1, 3:
            state = .buffering
        case 0:
            state = .ended
            next()
        case 1:
            state = .playing
        case 2:
            state = .paused
        default:
            break
        }
    }

    private func ensurePlayerWindowVisible() {
        WindowManager.shared.showYouTubeMusicPlayer()
    }
}
