import Foundation

/// The host singletons a script reaches through a global rather than through `System`: `PlEdit`,
/// the playlist editor; `MLPlaylists`, the Media Library's saved playlists; and `ColorMgr`, the
/// colour-theme manager. Each table is the whole of its class (`invokeTraced` routes to them). Split
/// out of `WinampModernScriptRuntimeSystem.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    /// The queue entry at `index`, or nil off either end.
    private func playlistRow(_ index: Int) -> WinampModernPlaylistRow? {
        let rows = playlistSnapshot.rows
        return rows.indices.contains(index) ? rows[index] : nil
    }

    /// The Media Library's saved playlists, by name, in the order `MLPlaylists` indexes them.
    private var savedPlaylistNames: [String] { componentHost?.savedPlaylistNames() ?? [] }

    /// `MLPlaylists` — Winamp's Media Library playlist manager, the *saved* playlists rather than
    /// the play queue. Answered from the host's own library, so a skin's playlist submenu lists the
    /// same names the Media Library window does.
    ///
    /// Never throws. Every measured caller guards the whole feature on the global being non-null and
    /// on `getNumItems()` being greater than zero (Big Bento's menu builds a "no playlist found"
    /// entry for the empty case), so an empty library is a state the skins already draw — where an
    /// abort would take the rest of the menu with it.
    static let playlistManagerMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        table.add("getnumitems", 0, on: MakiClassGUID.playlistManager) { runtime, call in
            .integer(Int32(clamping: runtime.savedPlaylistNames.count))
        }
        table.add("getitemname", 1, on: MakiClassGUID.playlistManager) { runtime, call in
            let names = runtime.savedPlaylistNames
            let index = Int(call.arguments[0].integerValue)
            return .string(names.indices.contains(index) ? names[index] : "")
        }
        table.add("playitem", 1, on: MakiClassGUID.playlistManager) { runtime, call in
            runtime.componentHost?.playSavedPlaylist(at: Int(call.arguments[0].integerValue))
            return .null
        }
        return table
    }()

    /// `ColorMgr`, Winamp's colour-theme manager. The whole surface the corpus reaches is one
    /// method: `getGammaSet(name)` hands back the named theme, and `apply()` on that switches to it.
    ///
    /// The theme itself is not built here. `WasabiColorThemeCatalog` already holds every `<gammaset>`
    /// the skin declared and tracks the active one, and `System.setColorTheme` already routes a
    /// switch through `themeSwitchRequested` — so this is a *binding* job, not a rendering one, and
    /// it deliberately lands on the same route rather than a second one that could disagree with it.
    ///
    /// A name the skin does not ship is answered with the object anyway, and `apply()` on it is a
    /// no-op: the catalog rejects the switch. Refusing here instead would abort the caller's whole
    /// handler over one missing theme.
    /// **Unknown methods fall through to `System` (`invokeTraced`), and that is not a convenience — it is what keeps
    /// this change from being a regression.** Before `ColorMgr` was bound, the parser seeded a global
    /// of this class with the *System* object, so every call a skin made on it went to
    /// `invokeSystem`. Winamp declares `getColorTheme` / `setColorTheme` / `getNumColorThemes` /
    /// `enumColorThemes` on `ColorMgr` as well, and this runtime answers all four on `System` — so
    /// handling `getGammaSet` alone and returning null for the rest would silently take those four
    /// away from any skin that reaches them through its `ColorMgr` global. Binding a singleton must
    /// only ever *add* to what its receiver could already do.
    static let colorManagerMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        table.add("getgammaset", 1, on: MakiClassGUID.colorManager) { runtime, call in
            runtime.dynamicValue(role: .gammaSet(name: call.arguments[0].stringValue))
        }
        // `ColorMgr.getColor(id)` — a declared colour, as three channels a script can read back.
        // Resolved through the renderer's own path (references followed, gammagroup and the active
        // colour theme applied), so a widget that paints itself from the skin's palette agrees with
        // the palette. ClassicPro's Now Playing widget opens with
        // `Color c = ColorMgr.getColor("wasabi.list.background")` and then feeds `c.getRed()`… into
        // its own background; unimplemented, that call aborted `onScriptLoaded` before every Layer FX
        // wire-up below it and the widget drew as an empty black pane.
        table.add("getcolor", 1, on: MakiClassGUID.colorManager) { runtime, call in
            let resolved = WasabiSceneRenderer.resolvedColor(call.arguments[0].stringValue,
                                                             resources: runtime.loadedSkin.runtime.resources,
                                                             themes: runtime.loadedSkin.themeCoordinator.catalog)
            let rgb = resolved.usingColorSpace(.deviceRGB) ?? resolved
            return runtime.dynamicValue(role: .color(red: Int32((rgb.redComponent * 255).rounded()),
                                                     green: Int32((rgb.greenComponent * 255).rounded()),
                                             blue: Int32((rgb.blueComponent * 255).rounded())))
        }
        return table
    }()

    /// `PlEdit`, Winamp's playlist-editor singleton. Every index here is **0-based** and absolute in
    /// the queue; an out-of-range one answers empty or does nothing rather than failing, because a
    /// skin polls this from a timer while the queue is being edited underneath it.
    static let playlistEditorMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        table.add("getcurrentindex", 0, on: MakiClassGUID.playlistEditor) { runtime, call in
            .integer(Int32(clamping: Int64(runtime.playlistSnapshot.currentIndex)))
        }
        table.add("getnumtracks", 0, on: MakiClassGUID.playlistEditor) { runtime, call in
            .integer(Int32(clamping: Int64(runtime.playlistSnapshot.trackCount)))
        }
        // The entry's display title — the same string the skin's own playlist draws, so a script that
        // builds a menu from it (ClassicPro's Quick Playlist) cannot disagree with the list beside it.
        table.add("gettitle", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            .string(runtime.playlistRow(Int(call.arguments[0].integerValue))?.title ?? "")
        }
        // A *string*, not a number: ClassicPro tests it against `""` before appending it in brackets,
        // and writes it straight into a text object. An unknown duration is empty, which is exactly
        // the case that test exists for.
        table.add("getlength", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            guard let entry = runtime.playlistRow(Int(call.arguments[0].integerValue)), entry.duration > 0 else {
                return .string("")
            }
            let seconds = Int(entry.duration)
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        table.add("getfilename", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            .string(runtime.playlistRow(Int(call.arguments[0].integerValue))?.filePath ?? "")
        }
        table.add("getmetadata", 2, on: MakiClassGUID.playlistEditor) { runtime, call in
            guard let entry = runtime.playlistRow(Int(call.arguments[0].integerValue)) else { return .string("") }
            switch call.arguments[1].stringValue.lowercased() {
            case "title": return .string(entry.title)
            case "artist": return .string(entry.artist)
            case "album": return .string(entry.album)
            case "filename": return .string(entry.filePath)
            // Milliseconds, the same unit as `System.getPlayItemMetaDataString("length")`, so a
            // panel that reads one and a list that reads the other cannot disagree.
            case "length":
                return .string(entry.duration > 0 ? String(WinampModernScriptRuntime.milliseconds(entry.duration)) : "")
            default: return .string("")
            }
        }
        table.add("playtrack", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            runtime.componentHost?.playlistPlay(row: Int(call.arguments[0].integerValue))
            return .null
        }
        table.add("removetrack", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            runtime.componentHost?.playlistRemove(row: Int(call.arguments[0].integerValue))
            return .null
        }
        table.add("moveto", 2, on: MakiClassGUID.playlistEditor) { runtime, call in
            runtime.componentHost?.playlistMove(row: Int(call.arguments[0].integerValue),
                                                to: Int(call.arguments[1].integerValue))
            return .null
        }
        table.add(["moveup", "movedown"], 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            let item = Int(call.arguments[0].integerValue)
            runtime.componentHost?.playlistMove(row: item, to: item + (call.method == "moveup" ? -1 : 1))
            return .null
        }
        // Stars, 0–5, the unit `getCurrentTrackRating` answers in.
        table.add("getrating", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            .integer(Int32(runtime.host.rating(ofPlaylistRow: Int(call.arguments[0].integerValue))))
        }
        table.add("setrating", 2, on: MakiClassGUID.playlistEditor) { runtime, call in
            runtime.host.setRating(Int(call.arguments[1].integerValue),
                                   ofPlaylistRow: Int(call.arguments[0].integerValue))
            return .null
        }
        table.add("clear", 0, on: MakiClassGUID.playlistEditor) { runtime, call in
            runtime.componentHost?.playlistClear()
            return .null
        }
        // Arity pinned by ClassicPro's own `extendedbuttons.m`, which ships its source beside the
        // compiled program: `PlEdit.enqueueFile(enqFile)`, one string.
        table.add("enqueuefile", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            if let url = runtime.skinSuppliedMediaURL(call.arguments[0].stringValue, method: call.method) {
                runtime.componentHost?.playlistAppend(mediaAt: url, play: false)
            }
            return .null
        }
        table.add("showtrack", 1, on: MakiClassGUID.playlistEditor) { runtime, call in
            runtime.hooks.playlistRevealRowRequested?(Int(call.arguments[0].integerValue))
            return .null
        }
        table.add("showcurrentlyplayingtrack", 0, on: MakiClassGUID.playlistEditor) { runtime, call in
            let current = runtime.playlistSnapshot.currentIndex
            guard current >= 0 else { return .null }
            runtime.hooks.playlistRevealRowRequested?(current)
            return .null
        }
        return table
    }()
}
