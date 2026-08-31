import AppKit

protocol ReeltoneComponentBridging: AnyObject {
    var playbackState: PlaybackState { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    var volume: Float { get set }
    var shuffleEnabled: Bool { get set }
    var repeatEnabled: Bool { get set }
    var currentTrack: Track? { get }

    func play()
    func pause()
    func stop()
    func previous()
    func next()
    func seek(to time: TimeInterval)
}

final class ReeltoneComponentBridge: ReeltoneComponentBridging {
    private var engine: AudioEngine { WindowManager.shared.audioEngine }

    var playbackState: PlaybackState { engine.state }
    var currentTime: TimeInterval { engine.currentTime }
    var duration: TimeInterval { engine.duration }
    var volume: Float {
        get { engine.volume }
        set { engine.volume = min(1, max(0, newValue)) }
    }
    var shuffleEnabled: Bool {
        get { engine.shuffleEnabled }
        set { engine.shuffleEnabled = newValue }
    }
    var repeatEnabled: Bool {
        get { engine.repeatEnabled }
        set { engine.repeatEnabled = newValue }
    }
    var currentTrack: Track? { engine.currentTrack }

    func play() { engine.play() }
    func pause() { engine.pause() }
    func stop() { engine.stop() }
    func previous() { engine.previous() }
    func next() { engine.next() }
    func seek(to time: TimeInterval) { engine.seek(to: time) }
}
