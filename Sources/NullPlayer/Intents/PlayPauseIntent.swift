import AppIntents

/// Toggles playback, as the Play/Pause media key does (`NowPlayingManager`).
///
/// Phase 0 spike payload: it proves the App Intents metadata pipeline end to end. The typed
/// `AppCommands` facade replaces the direct engine call in Phase 1.
struct PlayPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Play/Pause"
    static let description = IntentDescription("Plays or pauses the current track in NullPlayer.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = WindowManager.shared.audioEngine
        if engine.state == .playing {
            engine.pause()
        } else {
            engine.play()
        }
        return .result()
    }
}
