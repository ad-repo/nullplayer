import Foundation

/// Wasabi's *available component* handshake: a holder a skin reserves but never fills itself, for
/// the host to claim.
///
/// A `<windowholder hold="none" autoavailable="1">` is not the same thing as a holder that names a
/// component. `none` means "this holder holds nothing" — see `WasabiRenderer.componentReference` —
/// and `autoavailable="1"` is the skin adding "…unless something turns up". In Winamp the something
/// is a plugin: it publishes a window under a GUID, Wasabi stamps that GUID into the holder's `hold`
/// param, and the skin's own script reads it back to decide what to do with the space.
///
/// **The skin's gate is the `hold` param, not a setting.** Big Bento Modern's waveform-seeker strip
/// looked unreachable because `Use integrated Waveform Seeker` is never registered on a non-WACUP
/// host (it is created by `wacup_checker.maki` only when the koopa.ini probe succeeds, and that probe
/// must keep failing — see [wacup.md](../../../skills/winamp-modern-skin-guide/reference/wacup.md)).
/// Reading the layout's own bytecode says otherwise. Its `onTimer` gate is:
///
/// ```
/// System.isNamedWindowVisible("{E124F4D6-…}")
///   && wdh.waveseeker.getXmlParam("hold") == "{E124F4D6-…}"
/// ```
///
/// Nothing in the skin ever writes `hold`. So the strip is reachable by *supplying the component*,
/// which needs no dialect concept and no impersonation: we are not claiming to be WACUP, we are
/// answering a handshake that is open to any host. When the gate passes the skin does the rest
/// itself — it shows `waveseeker.rounder.bg` and shifts its whole transport row down 6px.
///
/// **We claim only what we can actually draw.** A holder we stamp is a holder the renderer must
/// fill; an unclaimed one keeps `hold="none"` and keeps drawing nothing, which is the behaviour BB12
/// established and must not regress.
enum WinampModernAvailableComponents {

    /// The kinds NullPlayer offers to an available holder, and nothing else. Deliberately a set of
    /// one: the playlist, library, video and visualization surfaces are claimed by holders that
    /// *name* them, and offering those here as well would let an id heuristic place a second copy of
    /// a surface the skin already positioned.
    static let offered: Set<WinampModernComponentKind> = [.waveformSeeker]

    /// Stamp each available holder we have a component for, and answer what was claimed.
    ///
    /// Runs on the initialized graph **before the scripts start**, because a skin reads `hold` from
    /// `onScriptLoaded` onwards and a claim applied later would arrive a whole layout after the
    /// decision it feeds.
    @discardableResult
    static func claim(in graph: WasabiObjectGraph) -> [WasabiObjectID: WinampModernComponentKind] {
        var claimed: [WasabiObjectID: WinampModernComponentKind] = [:]
        for object in graph.allObjectsUnordered {
            guard let kind = offerableKind(for: object),
                  let guid = WinampModernComponentRegistry.canonicalGUID(for: kind) else { continue }
            object.setAttribute("hold", value: guid)
            claimed[object.stableID] = kind
        }
        return claimed
    }

    /// What this object is asking for, or `nil` if it is not an available holder or we have nothing
    /// to put in it.
    ///
    /// The kind comes from the holder's **id**, which is the only name it carries — an available
    /// holder names no component by definition. That is the same fuzzy rule `centro.windowholder.
    /// library` goes through, and it stays scoped to holder ids for the same reason.
    static func offerableKind(for object: WasabiObject) -> WinampModernComponentKind? {
        guard WinampModernComponentRegistry.isHolderElement(object.typeName) else { return nil }
        guard isAvailable(object), holdsNothing(object) else { return nil }
        guard let id = object.xmlID,
              let kind = WinampModernComponentRegistry.kindFromHolderIdentifier(id),
              offered.contains(kind) else { return nil }
        return kind
    }

    /// `autoavailable="1"` — the skin opting the holder in. Absent is **not** available: a holder
    /// that says `hold="none"` and nothing else is a skin reserving space for itself.
    private static func isAvailable(_ object: WasabiObject) -> Bool {
        guard let raw = object.attributes["autoavailable"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return raw == "1" || raw.caseInsensitiveCompare("true") == .orderedSame
    }

    /// Empty or the literal `none`. Anything else is a holder that already named its component, and
    /// the skin's choice outranks ours.
    private static func holdsNothing(_ object: WasabiObject) -> Bool {
        let value = object.attributes["hold"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty || value.caseInsensitiveCompare("none") == .orderedSame
    }
}
