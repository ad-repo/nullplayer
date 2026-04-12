import Foundation

public extension Notification.Name {
    /// Posted when new PCM audio data is available for visualization
    /// userInfo contains: "pcm" ([Float]), "sampleRate" (Double)
    static let audioPCMDataUpdated = Notification.Name("audioPCMDataUpdated")

    /// Posted when new spectrum data is available for visualization
    /// userInfo contains: "spectrum" ([Float]) - 75 bands normalized 0-1
    static let audioSpectrumDataUpdated = Notification.Name("audioSpectrumDataUpdated")

    /// Posted when playback state changes (playing, paused, stopped)
    /// userInfo contains: "state" (PlaybackState)
    static let audioPlaybackStateChanged = Notification.Name("audioPlaybackStateChanged")

    /// Posted when playback option state changes (repeat, shuffle, gapless, normalization, crossfade)
    static let audioPlaybackOptionsChanged = Notification.Name("audioPlaybackOptionsChanged")

    /// Posted when the current track changes
    /// userInfo contains: "track" (Track?) - may be nil when playback stops
    static let audioTrackDidChange = Notification.Name("audioTrackDidChange")

    /// Posted when a track fails to load
    /// userInfo contains: "track" (Track), "error" (Error), "message" (String)
    static let audioTrackDidFailToLoad = Notification.Name("audioTrackDidFailToLoad")

    /// Posted when BPM detection updates
    /// userInfo contains: "bpm" (Int) - 0 means no confident reading
    static let bpmUpdated = Notification.Name("bpmUpdated")
}
