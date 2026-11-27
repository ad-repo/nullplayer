import AppKit
import CoreGraphics
import Foundation

/// The text surface a skin's objects bind to: the notifier's own strings and the width it
/// asks for, the `<text>` fields a script sets by id, and the per-frame refresh that pushes
/// the host's current track into them. Split out of `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    func setNotifierText(title: String, artist: String, album: String) {
        guard let container = findRoot(type: .container, xmlID: "notifier") else { return }
        let layouts = container.children.filter {
            $0.tag.is(.layout)
        }
        // The 350 is a *floor*, not a size. Stock Winamp Modern declares its notifier layout
        // `w="128"` and hangs a `w="-95" relatw="1"` text group inside it — 33px, too narrow for a
        // title — so that skin's toast has to be widened to be readable at all. A skin that already
        // declares a usable width must keep it: Big Bento's notifier is `w="540"` with a 310px text
        // group, and forcing 350 on it left 120px for 46pt text, clipping every line.
        var width = Self.notifierMinimumWidth
        for layout in layouts {
            setTextInSubtree(layout, id: "title", text: title)
            setTextInSubtree(layout, id: "artist", text: artist)
            setTextInSubtree(layout, id: "album", text: album)
            setTextInSubtree(layout, id: "plentry", text: "")
            setTextInSubtree(layout, id: "nexttrack", text: "")
            setTextInSubtree(layout, id: "endofplayback", text: "")
            let declared = CGFloat(Int32(layout.attributes["w"] ?? "") ?? 0)
            let target = max(declared, Self.notifierMinimumWidth)
            width = max(width, target)
            _ = layout.setAttribute("w", value: String(Int(target)))
        }
        let height = CGFloat(Int32(layouts.first?.attributes["h"] ?? "80") ?? 80)
        hooks.layoutResizeRequested?(container.stableID, CGSize(width: width, height: height))
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    /// The host's half of a track-change toast: the host's text in `<container id="notifier">` —
    /// unless that toast shows itself. Answers the container the host should show, or nil.
    ///
    /// No `onShowNotification` goes with it. That event is Winamp's *show the notification now*
    /// request, not a track change, and every corpus script that handles it also shows its toast from
    /// the `onTitleChange` the same track change already sent: sent here too, GlassAMPfinal's and
    /// ipamp14's toast showed twice per track, and the second show's `coverandbutton.resize(0,0,…)`
    /// pulled the cover and text out of their frame (B309).
    ///
    /// Only the plain `notifier` id is the host's to show. A `notifier.*` sibling is not a toast it
    /// can stand in for: Rectangular's are `notifier.preferences`, a settings window that popped up
    /// at the screen corner on every track change, and `notifier.popup`, which its own script
    /// shows (#810).
    func announceNotification(title: String, artist: String, album: String) -> WasabiObject? {
        guard let toast = findRoot(type: .container, xmlID: "notifier"),
              !notifierShowsItself(toast) else { return nil }
        setNotifierText(title: title, artist: artist, album: album)
        return toast
    }

    /// Whether `container` is a notifier whose own container carries the script that shows it: a
    /// program owned by the container, or by something inside it, listening for
    /// `System.onTitleChange` or `onShowNotification`. Such a toast is the skin's — Jpod's
    /// `Notifier-Notifier.maki` reads its Do Not Show, left/right and slide settings there, and
    /// shows, places, slides and hides the layout itself (#805). So the host neither shows nor
    /// fills it, and its moves are pins (`applyContainerGeometry`): the slide starts below the
    /// screen edge, and clamping that start on screen turned it into a 49px hop. Stock Winamp
    /// Modern's and Big Bento's notifier scripts are skin-level, not the container's, and keep the
    /// host's show.
    func notifierShowsItself(_ container: WasabiObject) -> Bool {
        guard container.tag.is(.container),
              WinampModernContainerTopology.isNotifier(id: container.xmlID ?? "") else { return false }
        // A script that took the toast as a `newDynamicContainer` builds, fills, places and dismisses
        // it itself, as Winamp's own notifier always did — stock Winamp Modern's, Love is War Miku's,
        // GlassAMPfinal's. Shown by the host as well, stock's script found its layout already
        // visible and slid it in from wherever the host had left it, across the whole screen (B479).
        if isDynamicallyClaimed(container.stableID) { return true }
        return programsBinding(MakiObjectReference(.system)) { Self.notifierTriggers.contains($0) }
            .contains { program in
                guard let ownerID = program.ownerID,
                      let owner = loadedSkin.runtime.graph.object(withID: ownerID) else { return false }
                return owner === container || Self.isDescendant(owner, of: container)
            }
    }

    private static let notifierTriggers: Set<String> = ["ontitlechange", "onshownotification"]

    private func setTextInSubtree(_ root: WasabiObject, id: String, text: String) {
        if let xmlID = root.xmlID,
           root.tag.is(.text),
           (xmlID.caseInsensitiveCompare(id) == .orderedSame ||
            xmlID.lowercased().hasPrefix(id.lowercased() + ".")) {
            _ = root.setAttribute("text", value: text)
            _ = root.setAttribute("default", value: text)
            _ = root.setAttribute(WasabiTextMetrics.scriptTextKey, value: text)
            _ = root.setAttribute(WasabiTextMetrics.scriptAlternateTextKey, value: "")
            notifyObjectDidMutate(root)
        }
        for child in root.children { setTextInSubtree(child, id: id, text: text) }
    }

    /// Test seam: what was last announced for an object, or `nil` if nothing has been.
    func lastDispatchedTextForTesting(_ object: WasabiObject) -> String? {
        lastDispatchedText[object.stableID]
    }

    /// Fire `onTextChanged(newtext)` on every text object whose host-bound content has changed.
    ///
    /// Winamp's `Text` object raises this whenever its content changes, and skins use it as the only
    /// signal that a host-supplied readout is worth re-reading. Defix's playlist box is the measured
    /// case: its `Items:`/`Time:` readouts are written by a subroutine whose **only** caller is
    /// `onTextChanged` — the `onTimer` beside it just stops a spinner. Never dispatching the event
    /// left that subroutine unreachable, so the box stayed on its XML placeholders no matter what the
    /// status line said.
    ///
    /// Bound text only: a `<text text="Add">` is a literal and cannot change, and re-dispatching for
    /// one would be a lie. Cheap enough to poll — the measured corpus declares a handful of bound
    /// text objects per skin, not hundreds.
    func refreshBoundText() {
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where WasabiTextMetrics.isHostBoundText(object) {
            let content = WasabiTextMetrics.content(of: object, host: host)
            let identifier = object.stableID
            if let previous = lastDispatchedText[identifier], previous == content { continue }
            // The **first** observation of real content fires too. Winamp raises the event when the
            // text goes from nothing to something, and a skin whose readouts are written only from
            // this handler has no other way to learn its opening value. Seeding silently instead —
            // the first thing this code did — meant a queue that was already populated before the
            // first poll never produced a change, so the event never fired at all and the readouts
            // stayed blank for the whole session. Empty content still says nothing.
            lastDispatchedText[identifier] = content
            guard !content.isEmpty else { continue }
            _ = try? dispatch(object: object, event: "ontextchanged", arguments: [.string(content)])
        }
    }

    /// The narrowest a track-change toast is allowed to be, whatever its layout declares.
    private static let notifierMinimumWidth: CGFloat = 350
}
