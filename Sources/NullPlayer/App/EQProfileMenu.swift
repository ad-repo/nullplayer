import AppKit

/// **Assign EQ Profile ▸** — Inherit, Off, each profile, then Equalizer Studio…. Every menu that
/// assigns (library rows, queue rows, radio stations, YouTube videos) builds it here.
@MainActor
enum EQProfileMenu {
    /// A library row, whose tracks are fetched only when an item is chosen. `scopes` is each of its
    /// items' scopes, most specific first, known from the row itself; nil (a playlist, which has no
    /// single level) ticks nothing.
    static func addAssignItem(to menu: NSMenu, level: EQProfileLevel, scopes: [[EQProfileScope]]?,
                              resolve: @escaping @MainActor () async throws -> [Track]) {
        build(into: menu, level: level, current: scopes, resolve: resolve)
    }

    /// Tracks already in hand (a radio station, a downloaded video): what is set at `level` is
    /// ticked — a dash on each setting a mixed selection holds — and a setting inherited from below
    /// is shown on top.
    static func addAssignItem(to menu: NSMenu, level: EQProfileLevel, tracks: [Track]) {
        build(into: menu, level: level, current: tracks.map(\.eqProfileScopes)) { tracks }
    }

    /// The play queue's selected rows, at track level, in queue order; nothing when none is selected.
    static func addAssignItem(to menu: NSMenu, queueRows: Set<Int>) {
        let queue = WindowManager.shared.audioEngine.playlist
        let tracks = queueRows.sorted().filter(queue.indices.contains).map { queue[$0] }
        guard !tracks.isEmpty else { return }
        addAssignItem(to: menu, level: .track, tracks: tracks)
    }

    /// The item, disabled with `reason` as its tooltip, where nothing can be assigned yet.
    static func addUnavailableItem(to menu: NSMenu, level: EQProfileLevel, reason: String) {
        // No submenu and no action: disabled whether or not the menu autoenables.
        let item = NSMenuItem(title: title(level), action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.toolTip = reason
        menu.addItem(item)
    }

    /// Playback Options ▸ **EQ Profiles ▸** — the global toggle and the bulk cleanups. The cleanups
    /// stay enabled while casting: `EQCastCache` re-prefetches on `.eqProfilesDidChange`.
    static func playbackOptionsItem(castingActive: Bool) -> NSMenuItem {
        let store = EQProfileStore.shared
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        // Assigned profiles on or off; assignments are kept either way.
        let enabled = NSMenuItem(title: "Enabled", action: #selector(MenuTarget.toggleEnabled(_:)), keyEquivalent: "")
        enabled.target = MenuTarget.shared
        enabled.state = store.isEnabled ? .on : .off
        if castingActive {
            enabled.isEnabled = false
            enabled.toolTip = "Not available while casting"
        }
        submenu.addItem(enabled)
        submenu.addItem(.separator())

        // Each assigned profile, with what it is assigned to; choosing one asks before removing it everywhere.
        let counts = store.assignmentCounts()
        let profiles = NSMenu()
        profiles.autoenablesItems = false
        for profile in store.sortedProfiles {
            guard let levels = counts[profile.id] else { continue }
            let item = NSMenuItem(title: label(profile, levels), action: #selector(MenuTarget.unassignProfile(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = profile
            profiles.addItem(item)
        }
        let unassign = NSMenuItem(title: "Unassign Profile", action: nil, keyEquivalent: "")
        unassign.submenu = profiles
        unassign.isEnabled = !profiles.items.isEmpty
        submenu.addItem(unassign)
        let removeAll = NSMenuItem(title: "Remove All Assignments…", action: #selector(MenuTarget.removeAllAssignments(_:)), keyEquivalent: "")
        removeAll.target = MenuTarget.shared
        submenu.addItem(removeAll)
        submenu.addItem(.separator())
        submenu.addItem(studioItem())

        let item = NSMenuItem(title: "EQ Profiles", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private static func studioItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Equalizer Studio…", action: #selector(MenuTarget.openStudio(_:)), keyEquivalent: "")
        item.target = MenuTarget.shared
        return item
    }

    /// `Warm — 1 artist, 2 albums, 5 tracks`, most general level first.
    private static func label(_ profile: EQProfile, _ counts: [EQProfileLevel: Int]) -> String {
        let parts = EQProfileLevel.allCases.reversed().compactMap { level -> String? in
            guard let n = counts[level], n > 0 else { return nil }
            return "\(n) \(level.rawValue)\(n == 1 ? "" : "s")"
        }
        return "\(profile.name) — \(parts.joined(separator: ", "))"
    }

    private static func title(_ level: EQProfileLevel) -> String {
        "Assign EQ Profile (\(level.rawValue.capitalized))"
    }

    private static func build(into menu: NSMenu, level: EQProfileLevel, current: [[EQProfileScope]]?,
                              resolve: @escaping @MainActor () async throws -> [Track]) {
        let resolver = EQProfileResolver.shared
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let chains = current?.map { $0.from(level) }
        let settings = chains?.map { $0.first.flatMap(resolver.store.assignment) } ?? []
        if let chains, !chains.isEmpty, settings.allSatisfy({ $0 == nil }) {
            let inherited = Set(chains.map { resolver.setting(of: $0) })
            if inherited.count == 1, let setting = inherited.first.flatMap({ $0 }) {
                let item = NSMenuItem(title: "Inherited: \(setting)", action: nil, keyEquivalent: "")
                item.isEnabled = false
                submenu.addItem(item)
                submenu.addItem(.separator())
            }
        }
        func add(_ title: String, _ assignment: EQProfileAssignment?) {
            let item = NSMenuItem(title: title, action: #selector(MenuTarget.assign(_:)), keyEquivalent: "")
            item.target = MenuTarget.shared
            item.representedObject = Request(assignment: assignment, level: level, resolve: resolve)
            let holding = settings.filter { $0 == assignment }.count
            item.state = settings.isEmpty || holding == 0 ? .off : holding == settings.count ? .on : .mixed
            submenu.addItem(item)
        }
        add("Inherit", nil)
        add("Off", .off)
        let profiles = resolver.store.sortedProfiles
        if !profiles.isEmpty {
            submenu.addItem(.separator())
            for profile in profiles { add(profile.name, .profile(profile.id)) }
        }
        submenu.addItem(.separator())
        submenu.addItem(studioItem())

        let item = NSMenuItem(title: title(level), action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private struct Request {
        let assignment: EQProfileAssignment?
        let level: EQProfileLevel
        let resolve: @MainActor () async throws -> [Track]
    }

    /// `NSMenuItem.target` is weak, so the items share one long-lived target.
    @MainActor
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func assign(_ sender: NSMenuItem) {
            guard let request = sender.representedObject as? Request else { return }
            Task { @MainActor in
                do {
                    let tracks = try await request.resolve()
                    let scopes = EQProfileResolver.shared.assign(request.assignment, level: request.level, tracks: tracks)
                    // A count above one at track level is a menu acting on a multi-row selection.
                    NSLog("[eqprofile] assign %@ at %@ level to %d scope(s) from %d track(s): %@", sender.title,
                          request.level.rawValue, scopes.count, tracks.count,
                          tracks.prefix(3).map(\.title).joined(separator: ", "))
                } catch is CancellationError {
                } catch {
                    NSLog("[eqprofile] assign failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                }
            }
        }

        @objc func toggleEnabled(_ sender: NSMenuItem) {
            EQProfileStore.shared.isEnabled.toggle()
        }

        @objc func unassignProfile(_ sender: NSMenuItem) {
            guard let profile = sender.representedObject as? EQProfile,
                  confirm("Unassign “\(profile.name)”?",
                          "Removes the profile from every track, album and artist it is assigned to. The profile itself is kept. This cannot be undone.",
                          button: "Unassign") else { return }
            NSLog("[eqprofile] unassign %@ from all scopes", sender.title)
            EQProfileStore.shared.unassign(profile.id)
        }

        @objc func removeAllAssignments(_ sender: NSMenuItem) {
            guard confirm("Remove All EQ Profile Assignments?",
                          "Every track, album and artist goes back to no profile, including ones set to Off. The profiles themselves are kept. This cannot be undone.",
                          button: "Remove") else { return }
            NSLog("[eqprofile] remove all assignments")
            EQProfileStore.shared.removeAllAssignments()
        }

        private func confirm(_ message: String, _ info: String, button: String) -> Bool {
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = info
            alert.alertStyle = .warning
            alert.addButton(withTitle: button)
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn
        }

        @objc func openStudio(_ sender: NSMenuItem) {
            WindowManager.shared.showEqualizerStudio()
        }
    }
}
