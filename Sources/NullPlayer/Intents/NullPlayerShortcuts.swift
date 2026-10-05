import AppIntents

/// The App Shortcuts NullPlayer offers in Siri and Spotlight with no setup.
struct NullPlayerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayPauseIntent(),
            phrases: [
                "Play/Pause \(.applicationName)",
                "Play or pause \(.applicationName)",
            ],
            shortTitle: "Play/Pause",
            systemImageName: "playpause"
        )
    }
}
