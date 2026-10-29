import Foundation

/// Main-thread transport intent while a local file is being prepared. A deferred transport
/// load rejoins loadTrack with its original skip bound and Play Now rollback policy.
struct DeferredLocalLoadIntent {
    struct Transport {
        let lastSkippable: Int?
        let playNow: PlayNowRequest?
        let firstFailure: TrackLoadFailure?
    }

    var shouldPlay: Bool
    let transport: Transport?
}
