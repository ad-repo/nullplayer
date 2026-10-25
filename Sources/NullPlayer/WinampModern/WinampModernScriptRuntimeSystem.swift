import AppKit
import CoreGraphics
import Foundation

/// The MAKI `System` receiver and the file paths a skin is allowed to name. The singletons a script
/// reaches through a global (`PlEdit`, `MLPlaylists`, `ColorMgr`) are in `…RuntimeSingletons.swift`.
/// Split out of `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    /// `newGroup`, `newGroupAsLayout` and `GroupList.instantiate` for a group the skin never defined:
    /// Winamp answers NULL and the script carries on. 19 skins ask for one (machina's frames name a
    /// `component.content.group` it dropped), and a throw aborted the rest of each handler.
    func instantiateOrNull(_ identifier: String, _ parent: WasabiObject, program: MakiProgram) throws -> WasabiObject? {
        guard let instantiate = loadedSkin.runtime.instantiateGroup else { return nil }
        do {
            return try instantiate(identifier, parent)
        } catch let failure as WalFailure
            where failure.diagnostics.allSatisfy({ $0.code == .missingGroupDefinition }) {
            report(WalDiagnostic(.missingGroupDefinition,
                                 "Script requested unknown group '\(identifier)'; it answered null.",
                                 severity: .warning, location: program.source))
            return nil
        }
    }

    private var playItemString: String { host.trackPath.isEmpty ? host.trackDisplayTitle : host.trackPath }

    /// Whether any container opens on its `desktopalpha` layout — `isDesktopAlphaAvailable()`.
    private var opensDesktopAlphaLayout: Bool {
        loadedSkin.runtime.graph.roots.contains { root in
            root.tag.is(.container) && WasabiSceneRenderer.primaryLayout(of: root)?.xmlID?
                .caseInsensitiveCompare(WasabiSceneRenderer.desktopAlphaLayoutID) == .orderedSame
        }
    }

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
        if WinampModernScriptSignatures.dispatchableEventArity[method] != nil {
            _ = try dispatchSystem(event: method, arguments: arguments)
            return method == "onaction" ? .integer(0) : .null
        }
        let call = MakiCall(method: method, receiver: (), arguments: arguments, program: program)
        for family in Self.systemFamilies {
            if let value = try answer(family, call) { return value }
        }
        throw unsupported(method, program: program)
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
    func skinSuppliedMediaURL(_ rawPath: String, method: String) -> URL? {
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
        guard let declared = findRoot(type: .container, xmlID: id) else { return nil }
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
            if let opening = WasabiSceneRenderer.primaryLayout(of: instance) {
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
              let container = ancestor(of: owner, type: .container) ?? (
                  owner.tag.is(.container) ? owner : nil),
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
    ///
    /// A strip that held nothing but those controls is then dropped (B159).
    private func adoptChromeForHostedWindow(_ container: WasabiObject, for hosted: WasabiObject) {
        var hidden: [WasabiObject] = []
        func hideControls(_ object: WasabiObject) {
            for child in object.children {
                if child.attributes["action"] != nil || child.attributes["cfgattrib"] != nil {
                    _ = child.setAttribute("visible", value: "0")
                    hidden.append(child)
                }
                hideControls(child)
            }
        }
        hideControls(container)
        liftHostedClient(into: container, for: hosted, pastHiddenControls: hidden)
        // …and record the floor the chrome itself will not go below, which is the only reliable
        // statement of how big a window wearing it has to be. It cannot be found in the markup ahead
        // of time: which chrome container a frame script instantiates is the script's decision, made
        // here, and a skin need not size the pair alike (MoonLight's video chrome is 410x281 around a
        // 330x220 window). Read at the one moment it is knowable, and applied by the materializer.
        let layouts = container.children.filter {
            $0.tag.is(.layout)
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

    /// Drop the top strip a hosted window's borrowed chrome kept for controls we hid.
    ///
    /// Itemskin's visualizer frame is 26pt thick on three sides and 40pt on top, where its own window
    /// puts `VIS_Prev`, `VIS_Next`, Random, `Vis_Menu` and a close button, and its bitmap is solid
    /// black there. With the controls hidden, every NullPlayer window wearing it showed a 13pt black
    /// bar above its contents. So when every hidden control sat in that strip and nothing still drawn
    /// starts inside it, the top border becomes as thick as the thickest of the other three sides.
    /// Anything else leaves the frame as the skin's exemplar drew it: Pure Inspired's thick bottom is
    /// border artwork, not a vacated strip.
    ///
    /// Both windows change. The chrome is a second window drawn **over** the contents, so moving the
    /// client alone left it under the same opaque band. In our copy the top pieces are cut to the new
    /// edge — tiled vertically, which draws the bitmap 1:1 and clips it where stretching would squash
    /// the bevel — and the side pieces start there. The client keeps the size the registry states,
    /// and the window is that much shorter: the materializer applies `hostedChromeLift` to a window it
    /// is still building, `hostedChromeLiftApplied` reaches one already on screen.
    private func liftHostedClient(into chrome: WasabiObject, for hosted: WasabiObject,
                                  pastHiddenControls hidden: [WasabiObject]) {
        func isLayout(_ object: WasabiObject?) -> Bool {
            object?.tag.is(.layout) == true
        }
        func number(_ object: WasabiObject, _ name: String) -> Double? {
            object.attributes[name].flatMap(Double.init)
        }
        guard !hidden.isEmpty,
              let chromeLayout = chrome.children.first(where: { isLayout($0) }),
              let hostedLayout = hosted.children.first(where: { isLayout($0) }),
              let contentID = hosted.xmlID.map({ "\($0).content" }),
              let client = hostedLayout.children.first(where: {
                  $0.xmlID?.caseInsensitiveCompare(contentID) == .orderedSame
              }),
              client.attributes["relatw"] == "1", client.attributes["relath"] == "1",
              client.attributes["relatx"] != "1", client.attributes["relaty"] != "1",
              let x = number(client, "x"), let y = number(client, "y"),
              let w = number(client, "w"), let h = number(client, "h"),
              w < 0, h < 0
        else { return }
        // The client tucks under the border (`clientBleed`); the chrome's edges are that far out.
        let bleed = WasabiSurfaceSynthesizer.clientBleed
        let stripBottom = y + bleed
        let top = max(x, -w - x, -h - y)
        guard top < y else { return }
        let lift = y - top
        let edge = top + bleed
        // Top-anchored, in the chrome layout's own coordinates — which are the client's, since the
        // frame script keeps the chrome window the hosted window's size.
        func topAnchored(_ object: WasabiObject) -> Double? {
            object.attributes["relaty"] == "1" ? nil : number(object, "y")
        }
        func startsInStrip(_ object: WasabiObject) -> Bool {
            guard let start = topAnchored(object) else { return false }
            return start > 0 && start < stripBottom
        }
        guard hidden.allSatisfy({ $0.parent === chromeLayout && startsInStrip($0) }) else { return }
        let hiddenIDs = Set(hidden.map(\.stableID))
        let drawn = chromeLayout.children.filter {
            !hiddenIDs.contains($0.stableID) && $0.attributes["visible"] != "0"
        }
        // A top piece starts at 0 and a side piece at the strip's bottom; the mover grip is an
        // imageless layer. Anything else starting in the strip is something the skin still draws.
        let stillDrawn = drawn.contains { child in
            startsInStrip(child)
                && (!child.tag.is(.layer)
                    || child.attributes["image"] != nil)
        }
        guard !stillDrawn else { return }
        for piece in drawn where piece.attributes["image"] != nil && piece.attributes["relath"] != "1" {
            guard topAnchored(piece) == 0 else { continue }
            _ = piece.setAttribute("h", value: String(Int(edge)))
            _ = piece.setAttribute("tiley", value: "1")
        }
        for piece in drawn where piece.attributes["image"] != nil && topAnchored(piece) == stripBottom {
            _ = piece.setAttribute("y", value: String(Int(edge)))
            if let height = number(piece, "h") {
                _ = piece.setAttribute("h", value: String(Int(height + lift)))
            }
        }
        // The client keeps its size in a window `lift` shorter: its top moves up, its bottom inset
        // stays, so `h` grows by what the canvas is about to lose.
        _ = client.setAttribute("y", value: String(Int(top)))
        _ = client.setAttribute("h", value: String(Int(h + lift)))
        for name in ["minimum_h", "default_h", "h"] {
            if let height = number(hostedLayout, name) {
                _ = hostedLayout.setAttribute(name, value: String(Int(height - lift)))
            }
        }
        hostedChromeLifts[hosted.stableID] = CGFloat(lift)
        hostedChromeLiftApplied?(hosted.stableID, CGFloat(lift))
    }

    /// The size floor the chrome a hosted window's frame script built imposes on it, once that script
    /// has run. Nil for a window whose frame draws inline.
    func hostedChromeFloor(of container: WasabiObject) -> CGSize? {
        hostedChromeFloors[container.stableID]
    }

    /// How much shorter a hosted window is than its synthesized layout, because its borrowed chrome
    /// dropped a strip that held only controls we hide. Nil when nothing was dropped.
    func hostedChromeLift(of container: WasabiObject) -> CGFloat? {
        hostedChromeLifts[container.stableID]
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

    /// What every playlist read answers from. The component host is the live queue; the text
    /// provider is the same snapshot under the headless harness, so a probe run and the app agree.
    var playlistSnapshot: WinampModernPlaylistSnapshot {
        componentHost?.playlistSnapshot() ?? WasabiTextMetrics.componentTextProvider?() ?? .empty
    }

    /// Every `System` table, in the order `invokeSystem` asks them: its own methods, then the ClassicPro
    /// file shell and the desk (`WinampModernScriptRuntimeDesktop.swift`).
    static let systemFamilies = [systemMethods, classicProFileMethods, systemClockMethods,
                                 systemScreenMethods, systemWindowMethods]

    /// The `System` receiver's own methods.
    static let systemMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        table.add("getcontainer", 1) { runtime, call in
            runtime.objectValue(runtime.findRoot(type: .container, xmlID: call.arguments[0].stringValue))
        }
        table.add("newdynamiccontainer", 1) { runtime, call in
            runtime.objectValue(runtime.dynamicContainer(named: call.arguments[0].stringValue, for: call.program))
        }
        table.add("getscriptgroup", 0) { runtime, call in
            runtime.objectValue(call.program.ownerID.flatMap(runtime.loadedSkin.runtime.graph.object(withID:)))
        }
        table.add("getparam", 0) { runtime, call in .string(call.program.parameter ?? "") }
        table.add("gettoken", 3) { runtime, call in
            let tokens = call.arguments[0].stringValue.components(separatedBy: call.arguments[1].stringValue)
            let index = Int(call.arguments[2].integerValue)
            return .string(tokens.indices.contains(index) ? tokens[index] : "")
        }
        table.add(["getleftvumeter", "getrightvumeter"], 0) { runtime, call in
            let value = runtime.vuValue(left: call.method == "getleftvumeter")
            if WinampModernScriptRuntime.tracesLayerFX { print("FX-TRACE \(call.method) -> \(value)") }
            return .integer(value)
        }
        // `extern Int System.getVisBand(int channel, int band); // 0,1 / 0..75` (std.mi). Every
        // meter a skin draws itself reads this — Defix's speaker cones, VU needles and level
        // bars all poll it from a timer — so without it those layers never move at all.
        table.add("getvisband", 2) { runtime, call in
            .integer(runtime.visBand(channel: call.arguments[0].integerValue, band: call.arguments[1].integerValue))
        }
        table.add("getvolume", 0) { runtime, call in .integer(Int32((runtime.host.volume * 255).rounded())) }
        // Winamp keeps the volume in a byte, so a level outside 0…255 wraps rather than clamps — and a
        // skin can be written against that. Symplicipod's rotary knob hands the left half of its
        // sweep over as −254…−127, which only reads as the 2…129 its right half continues from once
        // wrapped; clamped, half the knob was mute and the volume jumped as the pointer crossed the top.
        table.add("setvolume", 1) { runtime, call in
            let level = Int32(UInt8(truncatingIfNeeded: call.arguments[0].integerValue))
            runtime.host.volume = Double(level) / 255
            runtime.noteVolumeAnnounced()
            // The change is what a skin listens for. Re-entrancy is bounded by the dispatch guard, so
            // a handler that sets the volume again cannot recurse.
            _ = try? runtime.dispatchSystem(event: "onvolumechanged", arguments: [.integer(level)])
            runtime.postPosition(level, to: .volume)
            return .null
        }
        table.add("play", 0) { runtime, call in runtime.host.play(); return .null }
        table.add("pause", 0) { runtime, call in runtime.host.pause(); return .null }
        table.add("stop", 0) { runtime, call in runtime.host.stop(); return .null }
        table.add("previous", 0) { runtime, call in runtime.host.previous(); return .null }
        table.add("next", 0) { runtime, call in runtime.host.next(); return .null }
        // Winamp's eject is the open-file dialog, as the `EJECT` button action is.
        table.add("eject", 0) { runtime, call in runtime.host.openFiles(); return .null }
        // The player's own window commands: minimize takes the whole skin down together, and
        // closing the player quits (`Application.shutdown()`).
        table.add("minimizeapplication", 0) { runtime, call in
            runtime.hooks.actionRequested?("MINIMIZE", nil); return .null
        }
        table.add("shutdown", 0, on: MakiClassGUID.application) { runtime, call in
            runtime.hooks.actionRequested?("CLOSE", nil); return .null
        }
        table.add("restoreapplication", 0) { runtime, call in
            runtime.hooks.applicationRaiseRequested?(true); return .null
        }
        table.add("activateapplication", 0) { runtime, call in
            runtime.hooks.applicationRaiseRequested?(false); return .null
        }
        table.add("windowmenu", 0) { runtime, call in runtime.hooks.windowMenuRequested?(); return .null }
        // Milliseconds, like `getPosition` and `getPlayItemLength` — see `getposition`.
        table.add("seekto", 1) { runtime, call in
            runtime.host.seek(to: TimeInterval(call.arguments[0].integerValue) / 1000)
            return .null
        }
        table.add("getplayitemlength", 0) { runtime, call in
            .integer(WinampModernScriptRuntime.milliseconds(runtime.host.duration))
        }
        // The number of tracks in the queue, from the same snapshot `PE_Info` is built from, so a
        // skin that shows both cannot disagree with itself. Defix's playlist box reads it directly
        // (`Items: ` + `integerToString(getPlaylistLength())`) rather than parsing the status line —
        // and because the call sat *before* its `a3` write, the missing method aborted the whole
        // `onTimer` and took the readout with it.
        table.add("getplaylistlength", 0) { runtime, call in
            .integer(Int32(clamping: Int64(runtime.playlistSnapshot.trackCount)))
        }
        // The 0-based position of the playing entry — six of the seventeen skins ask for it, the most
        // demanded unimplemented method in the corpus. Winamp's own notifier shows it as
        // `getPlaylistIndex() + 1 + " of " + getPlaylistLength()`, which pins both the base and the
        // pairing. `-1` when nothing is playing, as `currentIndex` already means.
        table.add("getplaylistindex", 0) { runtime, call in
            .integer(Int32(clamping: Int64(runtime.playlistSnapshot.currentIndex)))
        }
        table.add("getposition", 0) { runtime, call in
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
            return .integer(WinampModernScriptRuntime.milliseconds(runtime.host.currentTime))
        }
        table.add("integertostring", 1) { runtime, call in .string(String(call.arguments[0].integerValue)) }
        // The argument is **milliseconds**, matching `getPosition`/`getPlayItemLength` — every corpus
        // caller feeds it one of those directly (micro's `oldTimer` pads the result to `mm:ss`, which
        // is the shape this has to keep).
        table.add("integertotime", 1) { runtime, call in
            let seconds = max(0, Int(call.arguments[0].integerValue)) / 1000
            return .string(String(format: "%d:%02d", seconds / 60, seconds % 60))
        }
        // Same milliseconds, `h:mm:ss`. ONYX V2's seek popup formats tracks over an hour with it, and
        // while it was missing that handler aborted before `seekTo`, so the seek arc never seeked.
        table.add("integertolongtime", 1) { runtime, call in
            let seconds = max(0, Int(call.arguments[0].integerValue)) / 1000
            return .string(String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60))
        }
        table.add("floattostring", 2) { runtime, call in
            let digits = max(0, min(12, Int(call.arguments[1].integerValue)))
            return .string(String(format: "%.*f", digits, call.arguments[0].doubleValue))
        }
        table.add("stringtointeger", 1) { runtime, call in
            .integer(Int32(call.arguments[0].stringValue) ?? 0)
        }
        // The mirror of `floattostring`, and the last method Love is War Miku's notifier preferences
        // reached for. A string that is not a number is 0, as it is on the integer side.
        table.add("stringtofloat", 1) { runtime, call in .float(Double(call.arguments[0].stringValue) ?? 0) }
        // MAKI's casts are System methods: `System.Integer(v)`, `System.Float(v)`, … A script
        // reaches for them wherever it mixes a float with an int-typed API — Love is War Miku's
        // volume buttons keep the level as a float and hand `Integer(level)` to `setVolume`, so
        // without these the whole volume path aborted at the first press.
        table.add("integer", 1) { runtime, call in .integer(call.arguments[0].integerValue) }
        table.add("float", 1) { runtime, call in .float(call.arguments[0].doubleValue) }
        table.add("string", 1) { runtime, call in .string(call.arguments[0].stringValue) }
        table.add("boolean", 1) { runtime, call in .boolean(call.arguments[0].truthy) }
        table.add("strlen", 1) { runtime, call in
            .integer(Int32(clamping: call.arguments[0].stringValue.count))
        }
        // A code point to a one-character string. Skins spell path separators (`chr(92)`) and
        // accented ranges with it; a value that is not a scalar answers empty rather than trapping.
        table.add("chr", 1) { runtime, call in
            return .string(Unicode.Scalar(UInt32(truncatingIfNeeded: call.arguments[0].integerValue))
                .map { String(Character($0)) } ?? "")
        }
        table.add("strlower", 1) { runtime, call in .string(call.arguments[0].stringValue.lowercased()) }
        table.add("strupper", 1) { runtime, call in .string(call.arguments[0].stringValue.uppercased()) }
        // Percent-encoding for a search term a skin is about to put in a URL. Every measured call
        // sits *inside* the expression that builds the address — Big Bento's lyrics finder is
        // `"…/search?q=" + urlEncode(artist) + " " + urlEncode(title) + " lyrics"` — so refusing
        // it took the whole handler down and the two magnifier buttons did nothing at all, one
        // layer before the navigation this phase is about (B40).
        // RFC 3986 unreserved set, everything else escaped. Deliberately stricter than
        // `.urlQueryAllowed`: the argument is one *term* being pasted into a query a skin is
        // assembling, so a `&`, a `?` or a `#` in an album title must not survive as syntax.
        table.add("urlencode", 1) { runtime, call in
            return .string(call.arguments[0].stringValue
                .addingPercentEncoding(withAllowedCharacters: WinampModernScriptRuntime.urlUnreserved) ?? "")
        }
        table.add("strsearch", 2) { runtime, call in
            let haystack = call.arguments[0].stringValue
            let range = haystack.range(of: call.arguments[1].stringValue)
            return .integer(range.map { Int32(haystack.distance(from: haystack.startIndex, to: $0.lowerBound)) } ?? -1)
        }
        table.add("strleft", 2) { runtime, call in
            .string(String(call.arguments[0].stringValue.prefix(max(0, Int(call.arguments[1].integerValue)))))
        }
        table.add("strright", 2) { runtime, call in
            .string(String(call.arguments[0].stringValue.suffix(max(0, Int(call.arguments[1].integerValue)))))
        }
        table.add("strmid", 3) { runtime, call in
            let value = call.arguments[0].stringValue
            let start = max(0, min(value.count, Int(call.arguments[1].integerValue)))
            let count = max(0, Int(call.arguments[2].integerValue))
            let lower = value.index(value.startIndex, offsetBy: start)
            return .string(String(value[lower...].prefix(count)))
        }
        // The extension of a filename, without the dot. Defix reads it off the playing item
        // (`getExtension(getPlayItemMetaDataString("filename"))`) for the display's format
        // readout, in the middle of the main layout's `onScriptLoaded` — so refusing it took the
        // rest of that handler, and the whole display area, down with it.
        table.add("getextension", 1) { runtime, call in
            // Windows separators as well as POSIX ones: a skin reads these out of playlist entries
            // and Winamp's own paths, and a dot in a *directory* name is not an extension.
            let name = call.arguments[0].stringValue
                .split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return .string("") }
            return .string(String(name[name.index(after: dot)...]))
        }
        // `getPath(filename)` — the *directory* half, the way `getExtension` is the tail. Pure
        // string work on a string the host already handed out: it opens nothing and reaches no
        // filesystem. Big Bento's file-info panel prints it as the track's folder, and the corpus
        // always calls it on the playing item.
        table.add("getpath", 1) { runtime, call in
            // The other half of the same split, and the same two separators. The trailing one is
            // dropped, as Winamp drops it: `getPath("C:\Music\a.mp3")` is `C:\Music`. A bare name
            // with no separator at all has no directory, and answers empty.
            let value = call.arguments[0].stringValue
            guard let separator = value.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
                return .string("")
            }
            return .string(String(value[value.startIndex..<separator]))
        }
        // …and its complement, the leaf. `getPath` + `removePath` is how a skin splits an item
        // into "folder" and "file" for two separate readouts.
        table.add("removepath", 1) { runtime, call in
            let value = call.arguments[0].stringValue
            guard let separator = value.lastIndex(where: { $0 == "/" || $0 == "\\" }) else {
                return .string(value)
            }
            return .string(String(value[value.index(after: separator)...]))
        }
        table.add("translate", 1) { runtime, call in .string(call.arguments[0].stringValue) }
        table.add("getprivateint", 3) { runtime, call in
            return .integer(runtime.loadedSkin.configuration.integer(section: call.arguments[0].stringValue,
                                                                     key: call.arguments[1].stringValue,
                                                              default: call.arguments[2].integerValue))
        }
        table.add("setprivateint", 3) { runtime, call in
            runtime.loadedSkin.configuration.setInteger(call.arguments[2].integerValue,
                                                        section: call.arguments[0].stringValue,
                                                key: call.arguments[1].stringValue)
            return .null
        }
        // The string half of the same store. Unreachable until Phase 24 dispatched `onResize`:
        // `CproTabs.m` reads its saved tab order out of it while laying the strip out, and the
        // missing method aborted that handler — so the tabs never re-sized to fit.
        table.add("getprivatestring", 3) { runtime, call in
            return .string(runtime.loadedSkin.configuration.string(section: call.arguments[0].stringValue,
                                                                   key: call.arguments[1].stringValue,
                                                           default: call.arguments[2].stringValue))
        }
        table.add("setprivatestring", 3) { runtime, call in
            runtime.loadedSkin.configuration.setString(call.arguments[2].stringValue,
                                                       section: call.arguments[0].stringValue,
                                               key: call.arguments[1].stringValue)
            return .null
        }
        table.add("getitem", 1) { runtime, call in
            let section = WinampModernConfigBridge.section(forItemName: call.arguments[0].stringValue)
            return runtime.dynamicValue(role: .configItem(section: section))
        }
        table.add("getitembyguid", 1) { runtime, call in
            // Winamp's config is addressed either by display name or by the owning component's GUID.
            // Both name the same private store here, so the GUID is simply the section key —
            // `loadattribs.maki` and `playlistmenu.maki` reach every attribute they need this way.
            return runtime.dynamicValue(role: .configItem(section: call.arguments[0].stringValue))
        }
        table.add("newitem", 2) { runtime, call in
            let name = call.arguments[0].stringValue
            let section = call.arguments[1].stringValue.isEmpty ? name : call.arguments[1].stringValue
            // The item's own name is the only human-readable label its attributes ever get: the
            // attribute names are the values ("Audio cassette"), the item is the setting
            // ("Visualizer"). Losing it would leave a settings list grouped by raw GUID.
            if !name.isEmpty, runtime.configItemNames[section] == nil,
               runtime.configItemNames.count < WinampModernScriptRuntime.maximumRegisteredSettings {
                runtime.configItemNames[section] = name
            }
            return runtime.dynamicValue(role: .configItem(section: section))
        }
        // `debugString(msg, level)` — a skin's own trace output. Two arguments, pinned by
        // ClassicPro (`debugString("setCustomVis=" + …, 9)`).
        // A skin's trace output. Deliberately dropped rather than logged: it is per-frame in some
        // skins, and nothing in NullPlayer consumes it.
        table.add("debugstring", 2) { runtime, call in .null }
        table.add("atan", 1) { runtime, call in .float(atan(call.arguments[0].doubleValue)) }
        // MAKI's math library, all `System` methods. Measured demand, not a shopping list:
        // Defix's VU needle computes its ballistics with `sqrt` and its rotation with `sin`/`cos`,
        // and the *whole* `onTimer` aborted on the first `sqrt` — which is why the needle styles
        // stood still even with Layer FX implemented.
        // The rest of MAKI's math library. Every result is guarded against a domain error: a script
        // that asks for `sqrt(-1)` gets 0 rather than a NaN that would then travel into a coordinate
        // and take a whole layer off screen.
        let unary: [String: (Double) -> Double] = [
            "sqrt": { $0 < 0 ? 0 : sqrt($0) }, "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
            "asin": { asin(min(1, max(-1, $0))) }, "acos": { acos(min(1, max(-1, $0))) },
            "log": { $0 > 0 ? log($0) : 0 }, "log10": { $0 > 0 ? log10($0) : 0 }, "exp": { exp($0) },
            "abs": { abs($0) },
        ]
        for (name, function) in unary {
            table.add(name, 1) { runtime, call in
                let result = function(call.arguments[0].doubleValue)
                return .double(result.isFinite ? result : 0)
            }
        }
        let binary: [String: (Double, Double) -> Double] = ["pow": { pow($0, $1) }, "atan2": { atan2($0, $1) }]
        for (name, function) in binary {
            table.add(name, 2) { runtime, call in
                let result = function(call.arguments[0].doubleValue, call.arguments[1].doubleValue)
                return .double(result.isFinite ? result : 0)
            }
        }
        table.add("geteq", 0) { runtime, call in
            .integer((runtime.hooks.equalizerEnabledRequested?() ?? false) ? 1 : 0)
        }
        table.add("geteqband", 1) { runtime, call in
            .integer(Int32(clamping: runtime.hooks.equalizerBandRequested?(Int(call.arguments[0].integerValue)) ?? 0))
        }
        table.add("seteqband", 2) { runtime, call in
            runtime.hooks.equalizerBandSetterRequested?(Int(call.arguments[0].integerValue),
                                                        Int(call.arguments[1].integerValue))
            // The change is what a skin listens for, exactly as `setVolume` announces itself. The
            // funnel dispatches only on a real change, so a handler that writes the band it was just
            // told about stops there rather than recursing.
            runtime.refreshEqualizerState()
            return .null
        }
        // The preamp is the band before band 0, on the same −127…127 scale. Rika's `eq.xml` reads it
        // while wiring its own equalizer window, and the miss aborted that whole script.
        table.add("geteqpreamp", 0) { runtime, call in
            .integer(Int32(clamping: runtime.hooks.equalizerPreampRequested?() ?? 0))
        }
        table.add("seteqpreamp", 1) { runtime, call in
            runtime.hooks.equalizerPreampSetterRequested?(Int(call.arguments[0].integerValue))
            runtime.refreshEqualizerState()
            return .null
        }
        table.add("seteq", 1) { runtime, call in
            runtime.hooks.equalizerEnabledSetterRequested?(call.arguments[0].truthy); return .null
        }
        table.add("getruntimeversion", 0) { runtime, call in .integer(5) }
        table.add("getskinname", 0) { runtime, call in .string(runtime.preferenceNamespace) }
        // `System.getSettingsPath()` — where the player keeps its own configuration. Arity 0,
        // pinned by the bytecode (`v82 = v67.getSettingsPath() + "/WACUP_Tools/koopa.ini"`, then
        // a `File.load`/`exists` pair): the string is only ever concatenated with a filename and
        // probed. Missing it aborted 23 of Big Bento Modern's `onScriptLoaded` handlers.
        // The player's own settings directory. Winamp answers its install/profile folder and skins
        // build sibling paths from it to sniff for another player's files — Big Bento Modern probes
        // `<settings>/WACUP_Tools/koopa.ini` to decide whether it is running under WACUP. Answering
        // NullPlayer's Application Support folder is the honest reply: the probe misses, the skin
        // takes its "not WACUP" branch, and the handler runs to the end. `File.exists()` is a
        // sandboxed `false` regardless, so nothing here widens what a script can read.
        table.add("getsettingspath", 0) { runtime, call in
            return .string(WinampModernSkinImporter.defaultDestinationDirectory()
                .deletingLastPathComponent().path)
        }
        // `System.getApplicationPath()` — where the *player* is installed, as against
        // `getSettingsPath`'s where it keeps its configuration. Arity 0, pinned by the bytecode
        // (`getApplicationPath() + "/Lang/Winamp-es-us.wlz"`, then a `File.load`/`exists`/
        // `getSize` probe). Big Bento's Localization page is built entirely out of those probes.
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
        table.add("getapplicationpath", 0) { runtime, call in .string(runtime.loadedSkin.vfs.winampRoot) }
        table.add("getcolortheme", 0) { runtime, call in
            .string(runtime.hooks.activeThemeRequested?() ?? "Default")
        }
        table.add("setcolortheme", 1) { runtime, call in
            _ = runtime.hooks.themeSwitchRequested?(call.arguments[0].stringValue)
            return .null
        }
        table.add("getnumcolorthemes", 0) { runtime, call in
            .integer(Int32(clamping: runtime.hooks.themeNamesRequested?().count ?? 0))
        }
        table.add("enumcolorthemes", 1) { runtime, call in
            let themes = runtime.hooks.themeNamesRequested?() ?? []
            let index = Int(call.arguments[0].integerValue)
            return .string(themes.indices.contains(index) ? themes[index] : "")
        }
        table.add("getplayitemdisplaytitle", 0) { runtime, call in .string(runtime.host.trackDisplayTitle) }
        // Winamp's play item string is the entry's filename or URL, not its title: 61 corpus call
        // sites hand it straight to `getExtension`, and ONYX V2's File Type readout printed the
        // title's tail ("sh - NullPlayer 20-minute sweep") while this answered the display title.
        // The title stays as the fallback for an item with no path, so `!= ""` still means playing.
        // Album-art scripts open their menu only when this is positive (BLAKK, Ebonite, B184). The
        // host holds the playing track's art only, so another item answers 0.
        table.add("getalbumart", 1) { runtime, call in
            .integer(call.arguments[0].stringValue == runtime.playItemString && runtime.host.albumArtwork != nil ? 1 : 0)
        }
        table.add("getplayitemstring", 0) { runtime, call in .string(runtime.playItemString) }
        // The whole key table lives on the host (`playItemMetadata(forKey:)`) rather than here: a
        // file-info panel asks for eighteen different fields and hides the line for every key that
        // comes back empty, and the harness has to answer them the same way the live host does.
        table.add("getplayitemmetadatastring", 1) { runtime, call in
            .string(runtime.host.playItemMetadata(forKey: call.arguments[0].stringValue))
        }
        table.add("getstatus", 0) { runtime, call in
            switch runtime.host.playbackState {
            case .playing: return .integer(1)
            case .paused: return .integer(-1)
            case .stopped: return .integer(0)
            }
        }
        table.add("getsonginfotext", 0) { runtime, call in .string(runtime.host.songInfoText) }
        // `System.getDecoderName(item)` — the input plugin decoding the named item. Counted from
        // the call site, which is `getDecoderName(getPlayItemString())`: one argument, a string
        // back. Big Bento's file-info panel fills its *Decoder* line from it, in the same
        // `onSetVisible` that fills every other line, so the whole panel stayed empty without it.
        // The argument names an item, but every call site in the corpus passes the *current* one, and
        // the host only knows what it is decoding now — so the answer is about the playing track.
        table.add("getdecodername", 1) { runtime, call in .string(runtime.host.decoderName) }
        table.add("isminimized", 0) { runtime, call in
            .boolean(runtime.hooks.applicationMinimizedRequested?() ?? false)
        }
        table.add("isvideo", 0) { runtime, call in .boolean(runtime.host.isVideo) }
        table.add("isvideofullscreen", 0) { _, _ in .boolean(false) }
        table.add("iskeydown", 1) { _, _ in .boolean(false) }
        // A *component's* window, addressed by GUID. Winamp answers for the plugin windows it has
        // loaded; the only ones we have are the components we put in a holder, so the question is
        // "did anything claim a holder for this GUID". A skin pairs it with the holder's own `hold`
        // param — Big Bento gates its waveform-seeker strip on both — so answering a blanket false
        // kept the strip hidden however the holder was stamped (BB18).
        table.add("isnamedwindowvisible", 1) { runtime, call in
            guard let kind = WinampModernComponentRegistry.kind(for: call.arguments[0].stringValue) else {
                return .boolean(false)
            }
            return .boolean(runtime.claimedComponentKinds.contains(kind))
        }
        // Answered honestly, unlike its neighbours: a skin *gates work* on it. Multipass's drawer
        // "Focus Mode" returns early from its 100 ms timer whenever the app is inactive, so a
        // hardcoded `false` would not just mis-report — it would stop the drawers from ever
        // opening again once that option was turned on.
        // Not in the group above on purpose — see the signature. Under the headless harness there is
        // no `NSApplication` at all, and "the app the skin is running in is in front" is then the
        // honest answer: the alternative reports every probe run as a background app and takes the
        // focus-gated half of a skin's behaviour out of measurement.
        table.add("isappactive", 0) { runtime, call in .boolean(NSApp?.isActive ?? true) }
        table.add(["istransparencyavailable", "istransparencysafe", "islayoutanimationsafe"], 0) { runtime, call in
            .boolean(true)
        }
        // **Not the same question as the three above.** Desktop alpha is not "can this window be
        // translucent" — it is Winamp asking whether the container runs on its `desktopalpha`
        // *layout*, a second layout built from a second set of artwork. A skin asks once and then
        // addresses that layout for the rest of the session without ever switching to it, because in
        // Winamp the container is already on it. So the answer is whether this skin has a container
        // that opens on one (`primaryLayout`): true sends a notifier's layout work to the layout on
        // screen, and a skin with none — CopperdeckII asks, then `return`s on a NULL
        // `getLayout("desktopalpha")` — keeps the `normal` branch it has always taken. Answered true
        // with nothing opened on it, Big Bento's notifier laid out a layout no window showed (BB27).
        table.add("isdesktopalphaavailable", 0) { runtime, call in .boolean(runtime.opensDesktopAlphaLayout) }
        // No video *component*: a `.wal` video holder gets the neutral backing every unhosted kind
        // gets, so a skin that asks is told the truth and lays itself out without a video tab. Defix
        // asks in the same `onScriptLoaded` that positions its whole tab strip — while the question
        // was refused, the strip was never laid out and its Album Art and Video tabs sat on top of
        // each other at the x both are declared at.
        table.add("hasvideosupport", 0) { runtime, call in .boolean(false) }
        // The playing video's native size. Zero is the honest answer here for the same reason
        // `hasVideoSupport` is false — there is no video component behind a `.wal` holder — and it
        // is also what Winamp answers for an audio track, which is the case skins branch on.
        table.add(["getidealvideowidth", "getidealvideoheight"], 0) { runtime, call in .integer(0) }
        table.add(["lockui", "unlockui"], 0) { _, _ in .null }
        table.add("hidenamedwindow", 1) { _, _ in .null }
        // Winamp's two global navigations, and they are not synonyms: `navigateUrl` means the user's
        // default browser and `navigateUrlBrowser` the player's own. Neither opens anything from
        // here — the request carries a skin-authored string, so it is handed to the window layer,
        // which resolves it through `WinampModernWebNavigationPolicy` (HTTP/HTTPS with a real host,
        // nothing else) and asks the user before the external one leaves the app (B40).
        table.add("navigateurl", 1) { runtime, call in
            runtime.hooks.globalNavigationRequested?(.defaultBrowser, call.arguments[0].stringValue)
            return .null
        }
        table.add("navigateurlbrowser", 1) { runtime, call in
            runtime.hooks.globalNavigationRequested?(.internalBrowser, call.arguments[0].stringValue)
            return .null
        }
        // The skin's own copy commands — Defix's playlist "Copy … to clipboard" items, the
        // ClassicPro engine's file-info and album-art menus. The string is whatever the script
        // built, so the host writes it as plain text and nothing else; it is an *outbound* seam
        // only, since Winamp has no matching read and a skin that could read the pasteboard would
        // be reading the user's other applications. Refusing it aborted the whole handler, which on
        // Defix is the one that builds the rest of that popup menu (BB13).
        table.add("setclipboardtext", 1) { runtime, call in
            runtime.host.setClipboardText(call.arguments[0].stringValue)
            return .null
        }
        table.add("newgroup", 1) { runtime, call in
            // Wasabi creates the group as a child of the calling script's own group; the script then
            // positions it with `setXmlParam`. This is how Winamp Modern fills a window frame's
            // client area (`content=` → `newGroup` → the whole player UI).
            guard let owner = call.program.ownerID.flatMap(runtime.loadedSkin.runtime.graph.object(withID:)) else {
                return .null
            }
            guard let created = try runtime.instantiateOrNull(call.arguments[0].stringValue, owner,
                                                              program: call.program) else {
                return .null
            }
            // The subtree's scripts start on **attachment**, not here: `newGroup` is only the first half
            // of Wasabi's two-step, and a script that runs before its group has been `init`'d into place
            // reads the wrong parent. See `pendingRuntimeGroups`.
            runtime.pendingRuntimeGroups.append(created)
            runtime.notifyGraphDidMutate()
            return runtime.objectValue(created)
        }
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
        table.add("newgroupaslayout", 1) { runtime, call in
            guard let parent = runtime.ownerLayout(forGroupDefinition: call.arguments[0].stringValue,
                                                   program: call.program)
            else { return .null }
            // Appended last, so it draws over the drawer background it sits on rather than under it.
            guard let floated = try runtime.instantiateOrNull(call.arguments[0].stringValue, parent,
                                                              program: call.program) else {
                return .null
            }
            runtime.pendingRuntimeGroups.append(floated)
            runtime.notifyGraphDidMutate()
            return runtime.objectValue(floated)
        }
        // Sandboxed: skins cannot create modal host UI.
        table.add("messagebox", 4) { runtime, call in .integer(0) }
        // ClassicPro version gate (a branch, not a hard block) + public config (see
        // `reportedWinampBuild`).
        table.add("getbuildnumber", 0) { runtime, call in
            .integer(WinampModernScriptRuntime.reportedWinampBuild)
        }
        table.add("getwinampversion", 0) { runtime, call in
            .string(WinampModernScriptRuntime.reportedWinampVersion)
        }
        table.add("getpublicint", 2) { runtime, call in
            return .integer(runtime.loadedSkin.configuration.integer(section: "@public",
                                                                     key: call.arguments[0].stringValue,
                                                             default: call.arguments[1].integerValue))
        }
        table.add("getpublicstring", 2) { runtime, call in
            return .string(runtime.loadedSkin.configuration.string(section: "@public",
                                                                   key: call.arguments[0].stringValue,
                                                           default: call.arguments[1].stringValue))
        }
        table.add("setpublicstring", 2) { runtime, call in
            runtime.loadedSkin.configuration.setString(call.arguments[1].stringValue,
                                                       section: "@public", key: call.arguments[0].stringValue)
            return .null
        }
        table.add("switchskin", 1) { runtime, call in
            // A skin asking the player to load a *different* skin is a host decision, not a script's.
            // The one caller here is ClassicPro's "the plugin is not installed" bail-out, which this
            // runtime does not reach: the engine is mounted or the skin does not load at all.
            return .null
        }
        table.add("setpublicint", 2) { runtime, call in
            runtime.loadedSkin.configuration.setInteger(call.arguments[1].integerValue,
                                                        section: "@public", key: call.arguments[0].stringValue)
            return .null
        }
        // `System.random(max)` — one argument, settled from the bytecode rather than guessed
        // (`WINAMP_MODERN_RENDER_DISASM=random`: every one of the eighteen call sites in the
        // stock skin's `about.maki` pushes the receiver and exactly one value before `op24`).
        // Winamp's `random(max)` answers 0…max-1. A non-positive bound has no range to draw from and
        // answers 0 rather than trapping — this is called from animation timers, where a crash would
        // take the skin down. Without it the stock skin's About page aborted at its first statement
        // and drew no text and no shooting stars at all.
        table.add("random", 1) { runtime, call in
            let bound = call.arguments[0].integerValue
            return .integer(bound > 0 ? Int32.random(in: 0..<bound) : 0)
        }
        // Demand-table batch (the S4 queue's tail): signatures from the corpus's own `.mi` headers.
        table.add("sqr", 1) { runtime, call in
            let x = call.arguments[0].doubleValue
            return .double((x * x).isFinite ? x * x : 0)
        }
        table.add("frac", 1) { runtime, call in
            let x = call.arguments[0].doubleValue
            return .double(x.isFinite ? x - x.rounded(.towardZero) : 0)
        }
        table.add("enqueuefile", 1) { runtime, call in
            if let url = runtime.skinSuppliedMediaURL(call.arguments[0].stringValue, method: call.method) {
                runtime.componentHost?.playlistAppend(mediaAt: url, play: false)
            }
            return .null
        }
        // A null check that also catches a graph object that has gone: the reference resolves the
        // way a method call on it would.
        table.add("isobjectvalid", 1) { runtime, call in
            guard case .object(let reference) = call.arguments[0] else { return .boolean(false) }
            if case .gui(let objectID) = reference.kind {
                return .boolean(runtime.loadedSkin.runtime.graph.object(withID: objectID) != nil)
            }
            if case .dynamic(let id) = reference.kind { return .boolean(runtime.dynamicObjects[id] != nil) }
            return .boolean(true)
        }
        // Arity settled off the call sites (`RENDER_DISASM=playFile`): T800's
        // `quicksongpick.maki` emits `op1(v0) op1(v44) op112(playfile)` — receiver, one push —
        // and Big Bento's `progbutton.maki` the same shape with the path built by a subroutine.
        // The name is unique across the installed corpus and belongs to `System` at both sites.
        table.add("playfile", 1) { runtime, call in
            if let url = runtime.skinSuppliedMediaURL(call.arguments[0].stringValue, method: call.method) {
                runtime.componentHost?.playlistAppend(mediaAt: url, play: true)
            }
            return .null
        }
        table.add("getfilesize", 1) { runtime, call in
            // Bounded no-op, for the same reason `findFiles` is one: a script that can stat any path
            // it names has a filesystem-probe capability, which this runtime does not grant. The
            // file-info readout shows 0 bytes rather than the script that draws it aborting.
            return .integer(0)
        }
        table.add("getlanguageid", 0) { runtime, call in .string("en") }
        // `WinampConfig.getGroup(guid)` → a `WinampConfigGroup`. Arities follow `winampconfig.mi`,
        // which is what the skin's compiler encoded.
        table.add("getgroup", 1) { runtime, call in
            // One section of Winamp's preferences, keyed by GUID. Backed by the skin's own namespaced
            // configuration store — MAKI never reads or writes real Winamp settings.
            return runtime.dynamicValue(role: .configGroup(section: call.arguments[0].stringValue))
        }
        // Stars, 0–5 — Winamp's unit, and the one NullPlayer's own star rows already use. The host
        // reads a local file's rating straight out of the library and asks the server for anything
        // else, announcing the late answer through `onCurrentTrackRated`.
        table.add("getcurrenttrackrating", 0) { runtime, call in
            .integer(Int32(clamping: runtime.host.currentTrackRating))
        }
        table.add("setcurrenttrackrating", 1) { runtime, call in
            runtime.host.currentTrackRating = Int(call.arguments[0].integerValue)
            return .null
        }
        return table
    }()
}
