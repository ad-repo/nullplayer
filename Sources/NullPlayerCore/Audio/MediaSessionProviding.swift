import Foundation

public protocol MediaSessionProviding: AnyObject {
    associatedtype SessionTrack

    func setup()
    func updateNowPlaying(track: SessionTrack?)
    func updatePlaybackState(_ state: PlaybackState)
    func updateElapsedTime(_ elapsedTime: TimeInterval)
}
