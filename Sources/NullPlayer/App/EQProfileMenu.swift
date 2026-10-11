import AppKit

/// **Assign EQ Profile ▸** — Inherit, Off, each profile, then Equalizer Studio…. Every menu that
/// assigns (library rows, queue rows, radio stations, YouTube videos) builds it here.
@MainActor
enum EQProfileMenu {
    /// A row whose tracks must be fetched (library albums, artists, playlists): they are resolved
    /// only when an item is chosen, so nothing is ticked.
    @discardableResult
    static func addAssignItem(to menu: NSMenu, level: EQProfileLevel,
                              resolve: @escaping @MainActor () async throws -> [Track]) -> NSMenuItem {
        build(into: menu, level: level, current: nil, resolve: resolve)
    }

    /// Tracks already in hand (queue rows, a radio station): what is set at `level` is ticked — a dash
    /// on each setting a mixed selection holds — and a setting inherited from below is shown on top.
    @discardableResult
    static func addAssignItem(to menu: NSMenu, level: EQProfileLevel, tracks: [Track]) -> NSMenuItem {
        build(into: menu, level: level, current: tracks) { tracks }
    }

    private static func build(into menu: NSMenu, level: EQProfileLevel, current: [Track]?,
                              resolve: @escaping @MainActor () async throws -> [Track]) -> NSMenuItem {
        let store = EQProfileStore.shared
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let settings = current?.map { store.assignment(at: level, of: $0) } ?? []
        if let current, !current.isEmpty, settings.allSatisfy({ $0 == nil }) {
            let inherited = Set(current.map { store.setting(of: $0) })
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
        let profiles = EQProfileStore.shared.profiles
        if !profiles.isEmpty {
            submenu.addItem(.separator())
            for profile in profiles.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
                add(profile.name, .profile(profile.id))
            }
        }
        submenu.addItem(.separator())
        let studio = NSMenuItem(title: "Equalizer Studio…", action: #selector(MenuTarget.openStudio(_:)), keyEquivalent: "")
        studio.target = MenuTarget.shared
        submenu.addItem(studio)

        let item = NSMenuItem(title: "Assign EQ Profile (\(level.rawValue.capitalized))", action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
        return item
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
                    EQProfileStore.shared.assign(request.assignment, level: request.level, tracks: tracks)
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
