import Foundation

/// What the source bar shows after "Source:", for both views to lay out in their own way.
extension LibraryBrowserModel {

    enum SourceBarContent {
        /// Local Files, Internet Radio or YouTube: the name with its count, then +ADD.
        case builtIn(name: String)
        /// A configured server: its name, then its library.
        case server(name: String, library: String)
        /// A server source with nothing configured: a centred prompt, and no right-side buttons.
        case unconfigured(prompt: String)
    }

    var sourceBarContent: SourceBarContent {
        switch currentSource {
        case .local:
            return .builtIn(name: "Local Files")
        case .radio:
            return .builtIn(name: "Internet Radio")
        case .youtube:
            return .builtIn(name: "YouTube")
        case .plex(let serverId):
            let manager = PlexManager.shared
            let server = manager.servers.first(where: { $0.id == serverId })
            guard server != nil || manager.isLinked else {
                return .unconfigured(prompt: "Click to link your Plex account")
            }
            return .server(name: server?.name ?? "Select Server", library: manager.currentLibrary?.title ?? "Select")
        case .subsonic(let serverId):
            let manager = SubsonicManager.shared
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                return .unconfigured(prompt: "Click to add a Subsonic server")
            }
            return .server(name: server.name, library: manager.currentMusicFolder?.name ?? "All")
        case .jellyfin(let serverId):
            let manager = JellyfinManager.shared
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                return .unconfigured(prompt: "Click to add a Jellyfin server")
            }
            let library = browseMode == .movies ? manager.currentMovieLibrary?.name
                : browseMode == .shows ? manager.currentShowLibrary?.name : manager.currentMusicLibrary?.name
            return .server(name: server.name, library: library ?? "All")
        case .emby(let serverId):
            let manager = EmbyManager.shared
            guard let server = manager.servers.first(where: { $0.id == serverId }) else {
                return .unconfigured(prompt: "Click to add an Emby server")
            }
            let library = browseMode == .movies ? manager.currentMovieLibrary?.name
                : browseMode == .shows ? manager.currentShowLibrary?.name : manager.currentMusicLibrary?.name
            return .server(name: server.name, library: library ?? "All")
        }
    }
}
