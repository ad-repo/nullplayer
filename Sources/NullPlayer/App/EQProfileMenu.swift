import AppKit

/// **Assign EQ Profile ▸** — Inherit, Off, each profile, then Equalizer Studio…. Every menu that
/// assigns (library rows, queue rows, radio stations, YouTube videos) builds it here.
@MainActor
enum EQProfileMenu {
    /// A row whose tracks must be fetched (library albums, artists, playlists): they are resolved
    /// only when an item is chosen, so nothing is ticked.
    static func addAssignItem(to menu: NSMenu, level: EQProfileLevel,
                              resolve: @escaping @MainActor () async throws -> [Track]) {
        build(into: menu, level: level, current: nil, resolve: resolve)
    }

    /// Tracks already in hand (a radio station, a downloaded video): what is set at `level` is
    /// ticked — a dash on each setting a mixed selection holds — and a setting inherited from below
    /// is shown on top.
    static func addAssignItem(to menu: NSMenu, level: EQProfileLevel, tracks: [Track]) {
        build(into: menu, level: level, current: tracks) { tracks }
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

    private static func title(_ level: EQProfileLevel) -> String {
        "Assign EQ Profile (\(level.rawValue.capitalized))"
    }

    private static func build(into menu: NSMenu, level: EQProfileLevel, current: [Track]?,
                              resolve: @escaping @MainActor () async throws -> [Track]) {
        let resolver = EQProfileResolver.shared
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let settings = current?.map { resolver.assignment(at: level, of: $0) } ?? []
        if let current, !current.isEmpty, settings.allSatisfy({ $0 == nil }) {
            let inherited = Set(current.map { resolver.setting(of: $0) })
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
        let studio = NSMenuItem(title: "Equalizer Studio…", action: #selector(MenuTarget.openStudio(_:)), keyEquivalent: "")
        studio.target = MenuTarget.shared
        submenu.addItem(studio)

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
    private final class MenuTarget: NSObject {
        static let shared = MenuTarget()

        @objc func assign(_ sender: NSMenuItem) {
            guard let request = sender.representedObject as? Request else { return }
            Task { @MainActor in
                do {
                    let tracks = try await request.resolve()
                    EQProfileResolver.shared.assign(request.assignment, level: request.level, tracks: tracks)
                } catch is CancellationError {
                } catch {
                    NSLog("[eqprofile] assign failed: %@", error.localizedDescription.redactingSensitiveURLQueryItems)
                }
            }
        }

        @objc func openStudio(_ sender: NSMenuItem) {
            WindowManager.shared.showEqualizerStudio()
        }
    }
}
