import AppKit
import CoreGraphics
import Foundation

/// The text surface a skin's objects bind to: the notifier's own strings and the width it
/// asks for, the `<text>` fields a script sets by id, and the per-frame refresh that pushes
/// the host's current track into them. Split out of `WinampModernScriptRuntime.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    func setNotifierText(title: String, artist: String, album: String) {
        guard let container = findRoot(type: "container", xmlID: "notifier") else { return }
        let layouts = container.children.filter {
            $0.typeName.caseInsensitiveCompare("layout") == .orderedSame
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
        layoutResizeRequested?(container.stableID, CGSize(width: width, height: height))
        noteGeometryChange()
        notifyGraphDidMutate()
    }

    private func setTextInSubtree(_ root: WasabiObject, id: String, text: String) {
        if let xmlID = root.xmlID,
           root.typeName.caseInsensitiveCompare("text") == .orderedSame,
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
