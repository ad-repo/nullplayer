import AppKit
import CoreGraphics
import Foundation

/// The MAKI `System` receiver, and the two media receivers that hang off it: the playlist
/// manager, the colour-theme manager, and the file paths a skin is allowed to name. Split
/// out of `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    func invokeSystem(method: String, arguments: [MakiValue], program: MakiProgram) throws -> MakiValue {
        // A script may call a *system* event handler as a method to reuse it, exactly as it may an
        // object's (`System.onEqFreqChanged(freqmode)` in ClassicPro's `eq.m`).
        // `System.onScriptLoaded()` is the one system event a script calls **at itself**, not at the
        // skin: it means "run my startup body again". Broadcast like the others it would re-initialise
        // every program in the archive — 46 of them in Ebonite, each re-creating its timers and its
        // objects — every time a framed window is re-shown. Scoped to the caller it is what the skin
        // asks for: Ebonite's standard frame nulls its frame container on hide and rebuilds it here.
        if method == "onscriptloaded" {
            _ = try dispatch(target: MakiObjectReference(.system), event: method,
                             arguments: arguments, in: [program])
            return .null
        }
        if Self.dispatchableEventArity[method] != nil {
            _ = try dispatchSystem(event: method, arguments: arguments)
            return method == "onaction" ? .integer(0) : .null
        }
        switch method {
        case "getcontainer":
            return objectValue(findRoot(type: "container", xmlID: arguments[0].stringValue))
        case "newdynamiccontainer":
            return objectValue(dynamicContainer(named: arguments[0].stringValue, for: program))
        case "getscriptgroup":
            return objectValue(program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)))
        case "getparam": return .string(program.parameter ?? "")
        case "gettoken":
            let tokens = arguments[0].stringValue.components(separatedBy: arguments[1].stringValue)
            let index = Int(arguments[2].integerValue)
            return .string(tokens.indices.contains(index) ? tokens[index] : "")
        case "getleftvumeter", "getrightvumeter":
            let value = vuValue(left: method == "getleftvumeter")
            if Self.tracesLayerFX { print("FX-TRACE \(method) -> \(value)") }
            return .integer(value)
        case "getvisband":
            return .integer(visBand(channel: arguments[0].integerValue, band: arguments[1].integerValue))
        case "getvolume": return .integer(Int32((host.volume * 255).rounded()))
        case "setvolume":
            let level = max(0, min(255, arguments[0].integerValue))
            host.volume = Double(level) / 255
            // The change is what a skin listens for. Re-entrancy is bounded by the dispatch guard, so
            // a handler that sets the volume again cannot recurse.
            _ = try? dispatchSystem(event: "onvolumechanged", arguments: [.integer(level)])
            return .null
        case "play": host.play(); return .null
        case "pause": host.pause(); return .null
        case "stop": host.stop(); return .null
        // Milliseconds, like `getPosition` and `getPlayItemLength` — see `getposition`.
        case "seekto":
            host.seek(to: TimeInterval(arguments[0].integerValue) / 1000)
            return .null
        case "getplayitemlength": return .integer(Self.milliseconds(host.duration))
        // The number of tracks in the queue, from the same snapshot `PE_Info` is built from, so a
        // skin that shows both cannot disagree with itself. Defix's playlist box reads it directly
        // (`Items: ` + `integerToString(getPlaylistLength())`) rather than parsing the status line —
        // and because the call sat *before* its `a3` write, the missing method aborted the whole
        // `onTimer` and took the readout with it.
        case "getplaylistlength":
            return .integer(Int32(clamping: Int64(playlistSnapshot.trackCount)))
        // The 0-based position of the playing entry — six of the seventeen skins ask for it, the most
        // demanded unimplemented method in the corpus. Winamp's own notifier shows it as
        // `getPlaylistIndex() + 1 + " of " + getPlaylistLength()`, which pins both the base and the
        // pairing. `-1` when nothing is playing, as `currentIndex` already means.
        case "getplaylistindex":
            return .integer(Int32(clamping: Int64(playlistSnapshot.currentIndex)))
        case "getposition":
            // **Milliseconds**, and so are `getPlayItemLength`, `seekTo`, the metadata `length` key
            // and `integerToTime`'s argument — the whole family moves together or a skin's own
            // arithmetic stops agreeing with its own readout.
            //
            // Most of the corpus divides the two into a ratio and cannot tell the difference, so the
            // unit has to be read off the skins that do absolute arithmetic. Two independent ones
            // say milliseconds: Styx's notifier formats the length by hand from
            // `getPlayItemLength()/1000`, and Anexa scales its progress bar with
            // `devby = len/255; setRegionFromMap(map, pos/devby, 1)` — which in seconds truncates to
            // zero for every track under 4:15 and bails out, leaving the bar empty (B64).
            return .integer(Self.milliseconds(host.currentTime))
        case "integertostring": return .string(String(arguments[0].integerValue))
        // The argument is **milliseconds**, matching `getPosition`/`getPlayItemLength` — every corpus
        // caller feeds it one of those directly (micro's `oldTimer` pads the result to `mm:ss`, which
        // is the shape this has to keep).
        case "integertotime":
            let seconds = max(0, Int(arguments[0].integerValue)) / 1000
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        case "floattostring":
            let digits = max(0, min(12, Int(arguments[1].integerValue)))
            return .string(String(format: "%.*f", digits, arguments[0].doubleValue))
        case "stringtointeger": return .integer(Int32(arguments[0].stringValue) ?? 0)
        // The mirror of `floattostring`, and the last method Love is War Miku's notifier preferences
        // reached for. A string that is not a number is 0, as it is on the integer side.
        case "stringtofloat": return .float(Double(arguments[0].stringValue) ?? 0)
        case "integer": return .integer(arguments[0].integerValue)
        case "float": return .float(arguments[0].doubleValue)
        case "string": return .string(arguments[0].stringValue)
        case "boolean": return .boolean(arguments[0].truthy)
        case "strlen": return .integer(Int32(clamping: arguments[0].stringValue.count))
        case "strlower": return .string(arguments[0].stringValue.lowercased())
        case "strupper": return .string(arguments[0].stringValue.uppercased())
        // RFC 3986 unreserved set, everything else escaped. Deliberately stricter than
        // `.urlQueryAllowed`: the argument is one *term* being pasted into a query a skin is
        // assembling, so a `&`, a `?` or a `#` in an album title must not survive as syntax.
        case "urlencode":
            return .string(arguments[0].stringValue
                .addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved) ?? "")
        case "strsearch":
            let range = arguments[0].stringValue.range(of: arguments[1].stringValue)
            return .integer(range.map { Int32(arguments[0].stringValue.distance(from: arguments[0].stringValue.startIndex, to: $0.lowerBound)) } ?? -1)
        case "strleft":
            return .string(String(arguments[0].stringValue.prefix(max(0, Int(arguments[1].integerValue)))))
        case "strright":
            return .string(String(arguments[0].stringValue.suffix(max(0, Int(arguments[1].integerValue)))))
        case "strmid":
            let value = arguments[0].stringValue
            let start = max(0, min(value.count, Int(arguments[1].integerValue)))
            let count = max(0, Int(arguments[2].integerValue))
            let lower = value.index(value.startIndex, offsetBy: start)
            return .string(String(value[lower...].prefix(count)))
        case "getextension":
            // Windows separators as well as POSIX ones: a skin reads these out of playlist entries
            // and Winamp's own paths, and a dot in a *directory* name is not an extension.
            let name = arguments[0].stringValue
                .split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .string("") }
            return .string(String(name[name.index(after: dot)...]))
        case "getpath":
            // The other half of the same split, and the same two separators. The trailing one is
            // dropped, as Winamp drops it: `getPath("C:\Music\a.mp3")` is `C:\Music`. A bare name
            // with no separator at all has no directory, and answers empty.
            let value = arguments[0].stringValue
            guard let separator = value.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
                return .string("")
            }
            return .string(String(value[value.startIndex..<separator]))
        case "removepath":
            let value = arguments[0].stringValue
            guard let separator = value.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
                return .string(value)
            }
            return .string(String(value[value.index(after: separator)...]))
        case "translate": return .string(arguments[0].stringValue)
        case "getprivateint":
            return .integer(loadedSkin.configuration.integer(section: arguments[0].stringValue,
                                                              key: arguments[1].stringValue,
                                                              default: arguments[2].integerValue))
        case "setprivateint":
            loadedSkin.configuration.setInteger(arguments[2].integerValue,
                                                section: arguments[0].stringValue,
                                                key: arguments[1].stringValue)
            return .null
        case "getprivatestring":
            return .string(loadedSkin.configuration.string(section: arguments[0].stringValue,
                                                           key: arguments[1].stringValue,
                                                           default: arguments[2].stringValue))
        case "setprivatestring":
            loadedSkin.configuration.setString(arguments[2].stringValue,
                                               section: arguments[0].stringValue,
                                               key: arguments[1].stringValue)
            return .null
        case "getitem":
            return dynamicValue(role: .configItem(section: arguments[0].stringValue))
        case "getitembyguid":
            // Winamp's config is addressed either by display name or by the owning component's GUID.
            // Both name the same private store here, so the GUID is simply the section key —
            // `loadattribs.maki` and `playlistmenu.maki` reach every attribute they need this way.
            return dynamicValue(role: .configItem(section: arguments[0].stringValue))
        case "newitem":
            let name = arguments[0].stringValue
            let section = arguments[1].stringValue.isEmpty ? name : arguments[1].stringValue
            // The item's own name is the only human-readable label its attributes ever get: the
            // attribute names are the values ("Audio cassette"), the item is the setting
            // ("Visualizer"). Losing it would leave a settings list grouped by raw GUID.
            if !name.isEmpty, configItemNames[section] == nil,
               configItemNames.count < Self.maximumRegisteredSettings {
                configItemNames[section] = name
            }
            return dynamicValue(role: .configItem(section: section))
        // A skin's trace output. Deliberately dropped rather than logged: it is per-frame in some
        // skins, and nothing in NullPlayer consumes it.
        case "debugstring": return .null
        case "getviewportwidth": return .integer(Int32(NSScreen.main?.frame.width ?? 0))
        case "getviewportheight": return .integer(Int32(NSScreen.main?.frame.height ?? 0))
        case "getviewportleft", "getviewporttop", "getviewportleftfromguiobject", "getviewporttopfromguiobject":
            return .integer(0)
        case "getviewportwidthfromguiobject": return .integer(Int32(NSScreen.main?.frame.width ?? 0))
        case "getviewportheightfromguiobject": return .integer(Int32(NSScreen.main?.frame.height ?? 0))
        // The monitor is the whole display containing the skin's player window. Do not derive this
        // from `NSScreen.main`: that is the primary display, not necessarily the one the skin is on.
        // The controller answers in logical screen points so Retina backing pixels never enter MAKI
        // geometry. The direct AppKit lookup is only the headless/unwired fallback.
        case "getmonitorwidth":
            return .integer(Self.screenDimension(monitorSizeRequested?()?.width
                                                  ?? NSScreen.main?.frame.width))
        case "getmonitorheight":
            return .integer(Self.screenDimension(monitorSizeRequested?()?.height
                                                  ?? NSScreen.main?.frame.height))
        case "getmonitorleft", "getmonitortop": return .integer(0)
        case "getcurappleft": return .integer(Self.appFrameDimension(playerWindowFrame?.minX))
        case "getcurapptop": return .integer(Self.appFrameDimension(playerWindowFrame?.minY))
        case "getcurappwidth": return .integer(Self.appFrameDimension(playerWindowFrame?.width))
        case "getcurappheight": return .integer(Self.appFrameDimension(playerWindowFrame?.height))
        case "getmouseposx": return .integer(Int32(clamping: Int((mousePositionRequested?().x ?? 0).rounded())))
        case "getmouseposy": return .integer(Int32(clamping: Int((mousePositionRequested?().y ?? 0).rounded())))
        case "atan": return .float(atan(arguments[0].doubleValue))
        // The rest of MAKI's math library. Every result is guarded against a domain error: a script
        // that asks for `sqrt(-1)` gets 0 rather than a NaN that would then travel into a coordinate
        // and take a whole layer off screen.
        case "sqrt", "pow", "sin", "cos", "tan", "asin", "acos", "atan2", "log", "log10", "exp", "abs":
            let x = arguments[0].doubleValue
            let y = arguments.count > 1 ? arguments[1].doubleValue : 0
            let result: Double
            switch method {
            case "sqrt": result = x < 0 ? 0 : sqrt(x)
            case "pow": result = pow(x, y)
            case "sin": result = sin(x)
            case "cos": result = cos(x)
            case "tan": result = tan(x)
            case "asin": result = asin(min(1, max(-1, x)))
            case "acos": result = acos(min(1, max(-1, x)))
            case "atan2": result = atan2(x, y)
            case "log": result = x > 0 ? log(x) : 0
            case "log10": result = x > 0 ? log10(x) : 0
            case "exp": result = exp(x)
            default: result = abs(x)
            }
            return .double(result.isFinite ? result : 0)
        case "geteq": return .integer((equalizerEnabledRequested?() ?? false) ? 1 : 0)
        case "geteqband":
            return .integer(Int32(clamping: equalizerBandRequested?(Int(arguments[0].integerValue)) ?? 0))
        case "seteqband":
            equalizerBandSetterRequested?(Int(arguments[0].integerValue), Int(arguments[1].integerValue))
            // The change is what a skin listens for, exactly as `setVolume` announces itself. The
            // funnel dispatches only on a real change, so a handler that writes the band it was just
            // told about stops there rather than recursing.
            refreshEqualizerState()
            return .null
        // The preamp is the band before band 0, on the same −127…127 scale. Rika's `eq.xml` reads it
        // while wiring its own equalizer window, and the miss aborted that whole script.
        case "geteqpreamp":
            return .integer(Int32(clamping: equalizerPreampRequested?() ?? 0))
        case "seteqpreamp":
            equalizerPreampSetterRequested?(Int(arguments[0].integerValue))
            refreshEqualizerState()
            return .null
        case "getruntimeversion": return .integer(5)
        case "getskinname": return .string(preferenceNamespace)
        // The player's own settings directory. Winamp answers its install/profile folder and skins
        // build sibling paths from it to sniff for another player's files — Big Bento Modern probes
        // `<settings>/WACUP_Tools/koopa.ini` to decide whether it is running under WACUP. Answering
        // NullPlayer's Application Support folder is the honest reply: the probe misses, the skin
        // takes its "not WACUP" branch, and the handler runs to the end. `File.exists()` is a
        // sandboxed `false` regardless, so nothing here widens what a script can read.
        case "getsettingspath":
            return .string(WinampModernSkinImporter.defaultDestinationDirectory()
                .deletingLastPathComponent().path)
        // The directory the player itself sits in. **The VFS root, not the host's.** The host path is
        // the honest answer to "where is the binary" and the wrong answer to every question a skin
        // asks with it: a skin concatenates onto this and hands the result back to `XmlDoc.load` or
        // `File.exists`, which resolve inside the WAL VFS, where a `/Applications/…` path can never
        // exist. ClassicPro's Web Reader is the case that made it matter — its only route to the
        // provider list it needs is `getApplicationPath() + "\\Plugins\\ClassicPro\\engine\\xui\\…"`,
        // and the engine is mounted at exactly `@WINAMPPATH@\\Plugins\\classicPro\\engine`, so the
        // resolution failed, `initLoadFiles()` returned early, and the reader's own
        // `onSetVisible` handler hid the whole tab (B128).
        //
        // Handing back a string is still not filesystem access: every route onward is sandboxed —
        // `File.load`/`exists` are a no-op and a constant `false`, `System.navigateUrl` is inert, and
        // this answer widens nothing, because the VFS is read-only and already reachable by any
        // `@WINAMPPATH@` a skin writes in its own markup. Probes for Winamp's `/Lang` packs still
        // find nothing and still take their "not installed" branch.
        case "getapplicationpath": return .string(loadedSkin.vfs.winampRoot)
        case "getcolortheme": return .string(activeThemeRequested?() ?? "Default")
        case "setcolortheme":
            _ = themeSwitchRequested?(arguments[0].stringValue)
            return .null
        case "getnumcolorthemes": return .integer(Int32(clamping: themeNamesRequested?().count ?? 0))
        case "enumcolorthemes":
            let themes = themeNamesRequested?() ?? []
            let index = Int(arguments[0].integerValue)
            return .string(themes.indices.contains(index) ? themes[index] : "")
        case "gettimeofday": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000)))
        case "getplayitemdisplaytitle": return .string(host.trackDisplayTitle)
        case "getplayitemstring": return .string(host.trackDisplayTitle)
        // The whole key table lives on the host (`playItemMetadata(forKey:)`) rather than here: a
        // file-info panel asks for eighteen different fields and hides the line for every key that
        // comes back empty, and the harness has to answer them the same way the live host does.
        case "getplayitemmetadatastring":
            return .string(host.playItemMetadata(forKey: arguments[0].stringValue))
        case "getstatus":
            switch host.playbackState {
            case .playing: return .integer(1)
            case .paused: return .integer(-1)
            case .stopped: return .integer(0)
            }
        case "getsonginfotext": return .string(host.songInfoText)
        // The argument names an item, but every call site in the corpus passes the *current* one, and
        // the host only knows what it is decoding now — so the answer is about the playing track.
        case "getdecodername": return .string(host.decoderName)
        case "isvideo", "isvideofullscreen", "iskeydown", "isminimized":
            return .boolean(false)
        // A *component's* window, addressed by GUID. Winamp answers for the plugin windows it has
        // loaded; the only ones we have are the components we put in a holder, so the question is
        // "did anything claim a holder for this GUID". A skin pairs it with the holder's own `hold`
        // param — Big Bento gates its waveform-seeker strip on both — so answering a blanket false
        // kept the strip hidden however the holder was stamped (BB18).
        case "isnamedwindowvisible":
            guard let kind = WinampModernComponentRegistry.kind(for: arguments[0].stringValue) else {
                return .boolean(false)
            }
            return .boolean(claimedComponentKinds.contains(kind))
        // Not in the group above on purpose — see the signature. Under the headless harness there is
        // no `NSApplication` at all, and "the app the skin is running in is in front" is then the
        // honest answer: the alternative reports every probe run as a background app and takes the
        // focus-gated half of a skin's behaviour out of measurement.
        case "isappactive": return .boolean(NSApp?.isActive ?? true)
        case "istransparencyavailable", "istransparencysafe", "islayoutanimationsafe":
            return .boolean(true)
        // **False, unlike the three above.** Desktop alpha is not "can this window be translucent" —
        // it is Winamp asking whether it may run the container on its `desktopalpha="1"` *layout*,
        // which is a second layout built from a second set of artwork. A skin asks once and then
        // addresses that layout for the rest of the session without ever switching to it, because in
        // Winamp the container is already on it. Nothing here activates it, so answering true sent
        // every write to a layout no window shows: Big Bento's notifier laid out `desktopalpha`
        // perfectly — sized to its text, album art in, transport row placed — while the app went on
        // drawing the untouched `normal` layout underneath (BB27). Answer it the way the engine
        // actually behaves and the skin lays out the layout that is on screen.
        case "isdesktopalphaavailable":
            return .boolean(false)
        // No video *component*: a `.wal` video holder gets the neutral backing every unhosted kind
        // gets, so a skin that asks is told the truth and lays itself out without a video tab. Defix
        // asks in the same `onScriptLoaded` that positions its whole tab strip — while the question
        // was refused, the strip was never laid out and its Album Art and Video tabs sat on top of
        // each other at the x both are declared at.
        case "hasvideosupport": return .boolean(false)
        case "getidealvideowidth", "getidealvideoheight": return .integer(0)
        case "lockui", "unlockui", "hidenamedwindow": return .null
        // Winamp's two global navigations, and they are not synonyms: `navigateUrl` means the user's
        // default browser and `navigateUrlBrowser` the player's own. Neither opens anything from
        // here — the request carries a skin-authored string, so it is handed to the window layer,
        // which resolves it through `WinampModernWebNavigationPolicy` (HTTP/HTTPS with a real host,
        // nothing else) and asks the user before the external one leaves the app (B40).
        case "navigateurl":
            globalNavigationRequested?(.defaultBrowser, arguments[0].stringValue)
            return .null
        case "navigateurlbrowser":
            globalNavigationRequested?(.internalBrowser, arguments[0].stringValue)
            return .null
        // The skin's own copy commands — Defix's playlist "Copy … to clipboard" items, the
        // ClassicPro engine's file-info and album-art menus. The string is whatever the script
        // built, so the host writes it as plain text and nothing else; it is an *outbound* seam
        // only, since Winamp has no matching read and a skin that could read the pasteboard would
        // be reading the user's other applications. Refusing it aborted the whole handler, which on
        // Defix is the one that builds the rest of that popup menu (BB13).
        case "setclipboardtext":
            host.setClipboardText(arguments[0].stringValue)
            return .null
        case "newgroup":
            // Wasabi creates the group as a child of the calling script's own group; the script then
            // positions it with `setXmlParam`. This is how Winamp Modern fills a window frame's
            // client area (`content=` → `newGroup` → the whole player UI).
            guard let owner = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)),
                  let instantiate = loadedSkin.runtime.instantiateGroup else { return .null }
            let created = try instantiate(arguments[0].stringValue, owner)
            // The subtree's scripts start on **attachment**, not here: `newGroup` is only the first half
            // of Wasabi's two-step, and a script that runs before its group has been `init`'d into place
            // reads the wrong parent. See `pendingRuntimeGroups`.
            pendingRuntimeGroups.append(created)
            notifyGraphDidMutate()
            return objectValue(created)
        // The same instantiation, but for a groupdef that declares itself a floating window
        // (`owner="main,normal"` + `nodock="1"`): Winamp gives it a borderless layout of its own,
        // owned by that layout. We make it an **overlay child of the owner layout** instead, and the
        // coordinate maths says that is the right answer rather than a compromise — multipass
        // positions the result with `resize(layoutMainNormal.getLeft() + 54, …getTop() + 217, …)`,
        // and `getLeft()`/`getTop()` on a root layout answer 0 here (window-local; see the
        // `clientToScreenX` note), so it lands at (54, 217) — exactly where the author's own
        // commented-out `<group … x="9" y="62"/>` inside drawer.bottom (45,155) → colorthemes (0,0)
        // would have put it.
        //
        // The created object keeps its **group** type. Typing it `layout` would send the `resize`
        // above through `layoutResizeRequested` and resize the *window* to 164×78.
        case "newgroupaslayout":
            guard let instantiate = loadedSkin.runtime.instantiateGroup,
                  let parent = ownerLayout(forGroupDefinition: arguments[0].stringValue, program: program)
            else { return .null }
            // Appended last, so it draws over the drawer background it sits on rather than under it.
            let floated = try instantiate(arguments[0].stringValue, parent)
            pendingRuntimeGroups.append(floated)
            notifyGraphDidMutate()
            return objectValue(floated)
        case "messagebox": return .integer(0) // Sandboxed: skins cannot create modal host UI.
        // ClassicPro version gate + public config (see `reportedWinampBuild`).
        case "getbuildnumber": return .integer(Self.reportedWinampBuild)
        case "getwinampversion": return .string(Self.reportedWinampVersion)
        case "getpublicint":
            return .integer(loadedSkin.configuration.integer(section: "@public",
                                                             key: arguments[0].stringValue,
                                                             default: arguments[1].integerValue))
        case "getpublicstring":
            return .string(loadedSkin.configuration.string(section: "@public",
                                                           key: arguments[0].stringValue,
                                                           default: arguments[1].stringValue))
        case "setpublicstring":
            loadedSkin.configuration.setString(arguments[1].stringValue,
                                               section: "@public", key: arguments[0].stringValue)
            return .null
        case "switchskin":
            // A skin asking the player to load a *different* skin is a host decision, not a script's.
            // The one caller here is ClassicPro's "the plugin is not installed" bail-out, which this
            // runtime does not reach: the engine is mounted or the skin does not load at all.
            return .null
        case "setpublicint":
            loadedSkin.configuration.setInteger(arguments[1].integerValue,
                                                section: "@public", key: arguments[0].stringValue)
            return .null
        case "getdate": return .integer(Int32(truncatingIfNeeded: Int64(Date().timeIntervalSince1970)))
        // Winamp's `random(max)` answers 0…max-1. A non-positive bound has no range to draw from and
        // answers 0 rather than trapping — this is called from animation timers, where a crash would
        // take the skin down. Without it the stock skin's About page aborted at its first statement
        // and drew no text and no shooting stars at all.
        case "random":
            let bound = arguments[0].integerValue
            return .integer(bound > 0 ? Int32.random(in: 0..<bound) : 0)
        case "getdatedoy":
            return .integer(Int32(Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0))
        case "playfile":
            if let url = skinSuppliedMediaURL(arguments[0].stringValue, method: method) {
                componentHost?.playlistAppend(mediaAt: url, play: true)
            }
            return .null
        case "getfilesize":
            // Bounded no-op, for the same reason `findFiles` is one: a script that can stat any path
            // it names has a filesystem-probe capability, which this runtime does not grant. The
            // file-info readout shows 0 bytes rather than the script that draws it aborting.
            return .integer(0)
        case "getlanguageid": return .string("en")
        case "getgroup":
            // One section of Winamp's preferences, keyed by GUID. Backed by the skin's own namespaced
            // configuration store — MAKI never reads or writes real Winamp settings.
            return dynamicValue(role: .configGroup(section: arguments[0].stringValue))
        // Stars, 0–5 — Winamp's unit, and the one NullPlayer's own star rows already use. The host
        // reads a local file's rating straight out of the library and asks the server for anything
        // else, announcing the late answer through `onCurrentTrackRated`.
        case "getcurrenttrackrating":
            return .integer(Int32(clamping: host.currentTrackRating))
        case "setcurrenttrackrating":
            host.currentTrackRating = Int(arguments[0].integerValue)
            return .null
        case "getdateyear":
            // Years since 1900, as C's `tm_year`. Pinned by the engine's own use of it: `cproabout.m`
            // computes an age as `1899 + getDateYear(...) - birthYear` (+1 once the birthday has
            // passed) and leap-year-tests it with `% 4`, both of which are only correct on that scale.
            let date = arguments[0].integerValue > 0
                ? Date(timeIntervalSince1970: TimeInterval(arguments[0].integerValue)) : Date()
            return .integer(Int32(Calendar.current.component(.year, from: date) - 1900))
        default:
            if let value = classicProFileMethod(method, arguments: arguments) { return value }
            throw unsupported(method, program: program)
        }
    }

    /// `MLPlaylists` — Winamp's Media Library playlist manager, the *saved* playlists rather than
    /// the play queue. Answered from the host's own library, so a skin's playlist submenu lists the
    /// same names the Media Library window does.
    ///
    /// Never throws. Every measured caller guards the whole feature on the global being non-null and
    /// on `getNumItems()` being greater than zero (Big Bento's menu builds a "no playlist found"
    /// entry for the empty case), so an empty library is a state the skins already draw — where an
    /// abort would take the rest of the menu with it.
    func invokePlaylistManager(method: String, arguments: [MakiValue]) -> MakiValue {
        let names = componentHost?.savedPlaylistNames() ?? []
        switch method {
        case "getnumitems":
            return .integer(Int32(clamping: names.count))
        case "getitemname":
            let index = Int(arguments[0].integerValue)
            return .string(names.indices.contains(index) ? names[index] : "")
        case "playitem":
            componentHost?.playSavedPlaylist(at: Int(arguments[0].integerValue))
            return .null
        default:
            // Unreachable while `playlistManagerSignatures` and this switch stay in step; recorded
            // rather than silently null so a name added to one and not the other is visible.
            unsupportedMethodCalls[method, default: 0] += 1
            return .null
        }
    }

    /// The sandbox policy for the one kind of value a skin hands *us*: a filesystem path it chose,
    /// through `PlEdit.enqueueFile` and `System.playFile`.
    ///
    /// Everything else on this seam is a path the host gave out first, so those two are the only
    /// methods that could widen what a script can reach. They are deliberately narrow, and narrow in
    /// the same direction the rest of this file already is: `findFiles` answers `-1` and
    /// `getFileSize` answers `0` precisely so a script has no way to *discover* a path. The only
    /// strings it can hold are ones we handed it (`PlEdit.getFileName`,
    /// `System.getPlayItemMetaDataString("filename")`, or one it saved into its own private string
    /// earlier), plus whatever the skin's author or the user typed — which is exactly what the two
    /// real callers do: T800's five `Mem1…Mem5` song slots save the playing file and play it back,
    /// and Big Bento's programmable buttons play a path the *user* enters in the skin's own box.
    ///
    /// So the policy grants **ingest**, not enumeration:
    ///
    /// - an `http`/`https` URL passes straight through — that is the host's existing stream ingest
    ///   and involves no filesystem at all;
    /// - a filesystem path must be absolute, must resolve to an **existing regular file** (not a
    ///   directory, not a fifo or device node that would wedge the audio engine), and must carry an
    ///   extension the player already supports.
    ///
    /// Anything else answers `nil` and the call becomes a silent no-op. It must **not** raise: both
    /// methods are void, Winamp ignores a path it cannot play, and throwing would abandon the rest of
    /// the caller's handler over one bad string — the failure mode `reference/scripting.md` records.
    private func skinSuppliedMediaURL(_ rawPath: String, method: String) -> URL? {
        func refuse(_ reason: String) -> URL? {
            if Self.tracesEveryCall {
                NSLog("WinampModern %@ refused %@: %@", method, rawPath, reason)
            }
            return nil
        }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return refuse("empty path") }
        if let url = URL(string: path), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        // Absolute POSIX only. A relative path has no defined base here (the script's notion of
        // "current directory" is Winamp's, not ours) and a `C:\…` path is a Windows skin's literal
        // that never described this machine.
        guard path.hasPrefix("/") else { return refuse("not an absolute POSIX path") }
        let url = URL(fileURLWithPath: path)
        guard AudioFileValidator.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return refuse("unsupported format")
        }
        guard let isRegularFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
              isRegularFile else {
            return refuse("not an existing regular file")
        }
        return url
    }

    /// `System.newDynamicContainer(id)` — Winamp builds a **fresh instance** of a declared container
    /// so a skin can have several of the same window at once.
    ///
    /// The copy is made **per calling program**, and that is the whole rule. The first program to ask
    /// gets the declared root, exactly as every caller did before B110, so Big Bento's search popups,
    /// MoonLight's four frames and every other single-holder caller behave as they did. A *second*
    /// program asking for the same id is the case that was broken: Ebonite includes
    /// `standardframe.maki` five times, once per framed window, and answering all five with the one
    /// declared root left its playlist, library and frame windows sharing a rect, because every
    /// `frame_layout.resize(…)` wrote to the same container. A program that asks twice — Ebonite does,
    /// on every re-show, since it closes its frame on hide — gets back the copy it already holds
    /// rather than another window.
    ///
    /// A container the skin did not declare `dynamic="1"` is never copied: `dynamic="0"` is the skin
    /// saying this window is a singleton, and a copy of it would be a window nothing can address.
    private func dynamicContainer(named id: String, for program: MakiProgram) -> WasabiObject? {
        let key = id.lowercased()
        let owner = ObjectIdentifier(program)
        if let held = dynamicContainerInstances[key]?[owner],
           let object = loadedSkin.runtime.graph.object(withID: held), !object.isTornDown {
            return object
        }
        guard let declared = findRoot(type: "container", xmlID: id) else { return nil }
        var takenIDs = Set(dynamicContainerInstances[key]?.values ?? [:].values)
        // A NullPlayer-owned window borrowing this skin's frame never takes the **declared**
        // container: that object is the skin's own window's chrome, and the borrowed frame has to be
        // a copy we may adapt without touching it. See `adoptChromeForHostedWindow`.
        let hostedCaller = hostedWindowContainer(of: program)
        if hostedCaller != nil { takenIDs.insert(declared.stableID) }
        let root: WasabiObject
        if !takenIDs.contains(declared.stableID) {
            root = declared
        } else if declared.attributes["dynamic"] == "1",
                  let instance = (try? loadedSkin.runtime.instantiateContainer?(id)) ?? nil {
            // The same two things `start()` does for every declared container, in the same order: the
            // opening layout has to be *realized* before anything else touches the instance, because
            // `getLayout` answers only for realized layouts — and the caller's very next statement is
            // `frame_cont.getLayout("scdef")`. Without it the whole rebuild ran against a null layout
            // and the second framed window came up with no chrome at all.
            let layouts = instance.children.filter {
                $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
            }
            if let opening = layouts.first(where: {
                $0.xmlID?.caseInsensitiveCompare("normal") == .orderedSame
            }) ?? layouts.first {
                markLayoutRealized(opening)
            }
            containerInstanceCreated?(instance)
            // A copy carrying its own `<script>` (a notifier, say) starts it exactly as a runtime
            // group's is started. Ebonite's frame is pure markup and adds none.
            try? startScripts(addedBeneath: instance)
            if let hostedCaller { adoptChromeForHostedWindow(instance, for: hostedCaller) }
            root = instance
        } else {
            // Out of copies (or a singleton container): the declared root is still the right answer —
            // a shared window is a worse result than a working one, and it is what shipped before.
            root = declared
        }
        dynamicContainerInstances[key, default: [:]][owner] = root.stableID
        return root
    }

    /// Whether this `newDynamicContainer` call is coming from the frame script of one of NullPlayer's
    /// own hosted windows. Those subtrees are the only ones synthesis creates, and they are the only
    /// ones `startTrustedHostedWindowScripts` will start, so the source path identifies them exactly.
    private func hostedWindowContainer(of program: MakiProgram) -> WasabiObject? {
        guard let owner = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)),
              let container = ancestor(of: owner, type: "container") ?? (
                  owner.typeName.caseInsensitiveCompare("container") == .orderedSame ? owner : nil),
              container.source.path == WasabiSurfaceSynthesizer.sourcePath
        else { return nil }
        return container
    }

    /// Make a borrowed frame fit a window it was not drawn for.
    ///
    /// A skin's chrome window is drawn for one specific window and can carry that window's own
    /// controls inside the border: Itemskin's thin frame is the one its visualizer and video windows
    /// wear, and `cont.clear.avs` holds `VIS_Prev`, `VIS_Next`, a Random toggle, `Vis_Menu` and a
    /// close button bound to `TOGGLE guid:avs`. Around Cava or Flow every one of those is wrong, and
    /// the close button would shut the skin's visualizer instead of the window it sits on.
    ///
    /// So the controls are hidden in **our copy** and the border artwork is kept. A control is
    /// anything the skin gave an `action` or a `cfgattrib`; layers, including the mover grip, carry
    /// neither and stay. The skin's own window is untouched — it holds the declared container, which
    /// a hosted caller is never given.
    private func adoptChromeForHostedWindow(_ container: WasabiObject, for hosted: WasabiObject) {
        func hideControls(_ object: WasabiObject) {
            for child in object.children {
                if child.attributes["action"] != nil || child.attributes["cfgattrib"] != nil {
                    _ = child.setAttribute("visible", value: "0")
                }
                hideControls(child)
            }
        }
        hideControls(container)
        // …and record the floor the chrome itself will not go below, which is the only reliable
        // statement of how big a window wearing it has to be. It cannot be found in the markup ahead
        // of time: which chrome container a frame script instantiates is the script's decision, made
        // here, and a skin need not size the pair alike (MoonLight's video chrome is 410x281 around a
        // 330x220 window). Read at the one moment it is knowable, and applied by the materializer.
        let layouts = container.children.filter {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
        }
        guard let layout = layouts.first else { return }
        func number(_ names: [String]) -> Double {
            for name in names {
                if let value = layout.attributes[name].flatMap(Double.init) { return value }
            }
            return 0
        }
        let floor = CGSize(width: number(["minimum_w", "w", "default_w"]),
                           height: number(["minimum_h", "h", "default_h"]))
        guard floor.width > 0 || floor.height > 0 else { return }
        hostedChromeFloors[hosted.stableID] = floor
    }

    /// The size floor the chrome a hosted window's frame script built imposes on it, once that script
    /// has run. Nil for a window whose frame draws inline.
    func hostedChromeFloor(of container: WasabiObject) -> CGSize? {
        hostedChromeFloors[container.stableID]
    }

    /// Whether a script has taken this container as a `newDynamicContainer` — a window Winamp creates
    /// **on demand**, whether it turned out to be the declared container (the first caller) or a copy.
    ///
    /// The distinction the window layer needs, and the reason it cannot read `dynamic="1"` instead:
    /// several corpus skins declare their real `Pledit`, `MLibrary` and `AVS` windows `dynamic="1"`,
    /// and those are ordinary skin windows — tiled, snapped to, listed in the menu, remembered. What
    /// makes Ebonite's `sc.alphaframe` different is not the attribute, it is that a script asked for it.
    func isDynamicallyClaimed(_ container: WasabiObjectID) -> Bool {
        dynamicContainerInstances.values.contains { $0.values.contains(container) }
    }

    /// The complete native surface ClassicPro's MAKI invokes (P0B §1): three `ClassicProFile`
    /// filesystem-shell helpers, each routed through the host's intentional reveal/open policy or a
    /// bounded no-op. Returns `nil` when `method` is not one of them.
    func classicProFileMethod(_ method: String, arguments: [MakiValue]) -> MakiValue? {
        switch method {
        case "explorefile":
            host.revealInFinder(arguments[0].stringValue)
            return .null
        case "openfile":
            host.openExternally(arguments[0].stringValue)
            return .null
        case "findfiles":
            // Bounded no-op: report "unavailable" so callers take their early-return path rather than
            // enumerating results. Skins never gain a filesystem-search capability.
            return .integer(-1)
        default:
            return nil
        }
    }

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
    /// **Unknown methods fall through to `System`, and that is not a convenience — it is what keeps
    /// this change from being a regression.** Before `ColorMgr` was bound, the parser seeded a global
    /// of this class with the *System* object, so every call a skin made on it went to
    /// `invokeSystem`. Winamp declares `getColorTheme` / `setColorTheme` / `getNumColorThemes` /
    /// `enumColorThemes` on `ColorMgr` as well, and this runtime answers all four on `System` — so
    /// handling `getGammaSet` alone and returning null for the rest would silently take those four
    /// away from any skin that reaches them through its `ColorMgr` global. Binding a singleton must
    /// only ever *add* to what its receiver could already do.
    func invokeColorManager(method: String, arguments: [MakiValue],
                                    program: MakiProgram) throws -> MakiValue {
        switch method {
        case "getgammaset":
            return dynamicValue(role: .gammaSet(name: arguments[0].stringValue))
        // `ColorMgr.getColor(id)` — a declared colour, as three channels a script can read back.
        // Resolved through the renderer's own path (references followed, gammagroup and the active
        // colour theme applied), so a widget that paints itself from the skin's palette agrees with
        // the palette. ClassicPro's Now Playing widget opens with
        // `Color c = ColorMgr.getColor("wasabi.list.background")` and then feeds `c.getRed()`… into
        // its own background; unimplemented, that call aborted `onScriptLoaded` before every Layer FX
        // wire-up below it and the widget drew as an empty black pane.
        case "getcolor":
            let resolved = WasabiSceneRenderer.resolvedColor(arguments[0].stringValue,
                                                             resources: loadedSkin.runtime.resources,
                                                             themes: loadedSkin.themeCoordinator.catalog)
            let rgb = resolved.usingColorSpace(.deviceRGB) ?? resolved
            return dynamicValue(role: .color(red: Int32((rgb.redComponent * 255).rounded()),
                                             green: Int32((rgb.greenComponent * 255).rounded()),
                                             blue: Int32((rgb.blueComponent * 255).rounded())))
        default:
            return try invokeSystem(method: method, arguments: arguments, program: program)
        }
    }

    /// What every playlist read answers from. The component host is the live queue; the text
    /// provider is the same snapshot under the headless harness, so a probe run and the app agree.
    var playlistSnapshot: WinampModernPlaylistSnapshot {
        componentHost?.playlistSnapshot() ?? WasabiTextMetrics.componentTextProvider?() ?? .empty
    }

    /// `PlEdit`, Winamp's playlist-editor singleton. Every index here is **0-based** and absolute in
    /// the queue; an out-of-range one answers empty or does nothing rather than failing, because a
    /// skin polls this from a timer while the queue is being edited underneath it.
    func invokePlaylistEditor(method: String, arguments: [MakiValue]) -> MakiValue {
        let snapshot = playlistSnapshot
        func row(_ index: Int) -> WinampModernPlaylistRow? {
            snapshot.rows.indices.contains(index) ? snapshot.rows[index] : nil
        }
        switch method {
        case "getcurrentindex": return .integer(Int32(clamping: Int64(snapshot.currentIndex)))
        case "getnumtracks": return .integer(Int32(clamping: Int64(snapshot.trackCount)))
        // The entry's display title — the same string the skin's own playlist draws, so a script that
        // builds a menu from it (ClassicPro's Quick Playlist) cannot disagree with the list beside it.
        case "gettitle": return .string(row(Int(arguments[0].integerValue))?.title ?? "")
        // A *string*, not a number: ClassicPro tests it against `""` before appending it in brackets,
        // and writes it straight into a text object. An unknown duration is empty, which is exactly
        // the case that test exists for.
        case "getlength":
            guard let entry = row(Int(arguments[0].integerValue)), entry.duration > 0 else { return .string("") }
            let seconds = Int(entry.duration)
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        case "getfilename": return .string(row(Int(arguments[0].integerValue))?.filePath ?? "")
        case "getmetadata":
            guard let entry = row(Int(arguments[0].integerValue)) else { return .string("") }
            switch arguments[1].stringValue.lowercased() {
            case "title": return .string(entry.title)
            case "artist": return .string(entry.artist)
            case "album": return .string(entry.album)
            case "filename": return .string(entry.filePath)
            // Milliseconds, the same unit as `System.getPlayItemMetaDataString("length")`, so a
            // panel that reads one and a list that reads the other cannot disagree.
            case "length": return .string(entry.duration > 0 ? String(Self.milliseconds(entry.duration)) : "")
            default: return .string("")
            }
        case "playtrack":
            componentHost?.playlistPlay(row: Int(arguments[0].integerValue))
            return .null
        case "removetrack":
            componentHost?.playlistRemove(row: Int(arguments[0].integerValue))
            return .null
        case "moveto":
            componentHost?.playlistMove(row: Int(arguments[0].integerValue),
                                        to: Int(arguments[1].integerValue))
            return .null
        case "clear":
            componentHost?.playlistClear()
            return .null
        case "enqueuefile":
            if let url = skinSuppliedMediaURL(arguments[0].stringValue, method: method) {
                componentHost?.playlistAppend(mediaAt: url, play: false)
            }
            return .null
        case "showtrack":
            playlistRevealRowRequested?(Int(arguments[0].integerValue))
            return .null
        case "showcurrentlyplayingtrack":
            guard snapshot.currentIndex >= 0 else { return .null }
            playlistRevealRowRequested?(snapshot.currentIndex)
            return .null
        default:
            // Unreachable while `playlistEditorSignatures` and this switch stay in step; recorded
            // rather than silently null so a name added to one and not the other is visible.
            unsupportedMethodCalls[method, default: 0] += 1
            return .null
        }
    }
}
