import CoreGraphics
import Foundation

/// Big Bento Modern's Multi Content View, laid out side by side (BB9).
///
/// The skin's Multi Content View has four pages, and its *Visualization* page is exclusive: the
/// stretched visualization pane `info.component.vis.full` is declared `x="0" w="0" relatw="1"` —
/// the full width of the holder — and `mcvcore`'s page routine hides the album art, the mini
/// visualization pane and the file-info text behind it.
///
/// Two things follow from that, and only the first is the skin's fault:
///
/// 1. `mcvcore` declares `System.onScriptLoaded()` **twice**, and the second body starts a 700 ms
///    one-shot whose `onTimer` shows the file-info panes again *unconditionally*, with no reference
///    to which page is current. At launch that timer is the last word, so the stretched pane and the
///    file-info panes all end up visible and drawn over each other. Do not try to fix that by
///    running only the first body — the second is where the panel's width layout lives, and dropping
///    it takes the sizing out (see `skins/big-bento-modern.md` → *BB9*).
/// 2. Even without the timer, the page is exclusive by design: you get the spectrum *or* the album
///    art, never both.
///
/// What is wanted here is neither: **cover | mini visualization | spectrum, side by side**. The skin
/// never lays that out, so this is a NullPlayer-side override rather than a skin behaviour to
/// restore. While the stretched pane is shown, this type answers two questions the renderer asks —
/// which of the holder's panes are visible, and where they sit — and the file-info text lines stay
/// hidden on this page, which is what the skin's own first `onScriptLoaded` body intended.
///
/// **Every number below is the skin's own.** The slot pitch comes from `mcvcore`'s both-ticked
/// placement (mini vis at `x=3`, cover at `x=195`) and the pane widths from the markup
/// (`player-normal-mcv.xml`: both panes are 186 wide, and the cover's script animates its width).
/// Scoped by the five object ids under one holder, so no other skin can enter it.
enum WinampModernBentoMultiContentView {

    // The holder's five panes, as `player-normal-mcv.xml` names them.
    static let stretchedVisID = "info.component.vis.full"
    static let miniVisID = "info.component.vis"
    static let coverID = "info.component.cover"
    static let infoDisplayID = "info.component.infodisplay"
    static let songInfoDisplayID = "info.component.songinfodisplay"

    /// The skin's *File Info Components* config item, and the attribute that says whether the user
    /// wants the mini visualization pane. A `cfgattrib` binding on a check box in `config.xml`; the
    /// key's trailing space is the skin's, not a typo.
    ///
    /// Its partner `Album Art` is deliberately **not** read — see `settings(reading:)` for why.
    static let fileInfoComponentsSection = "{8D3829F9-5790-4c8e-9C3A-C397D3602FF9}"
    static let miniVisKey = "Visualization "

    /// Only ids under this prefix can be affected — the cheap pre-filter for the per-object hooks.
    private static let idPrefix = "info.component."

    /// Left margin before the first pane, and the gutter between panes. `mcvcore` places the mini vis
    /// at `x=3` and the cover at `x=195` when both are ticked, so with a 186-wide pane the gutter is
    /// 6; with the cover alone the skin uses `x=6`, which is the second value here.
    private static let firstMargin: CGFloat = 3
    private static let coverOnlyMargin: CGFloat = 6
    private static let gutter: CGFloat = 6
    private static let paneWidth: CGFloat = 186

    /// Which panes the user asked for. Read from the skin's own registered settings, so a value the
    /// user has never touched still answers with the default the skin registered.
    struct Settings {
        let coverEnabled: Bool
        let miniVisEnabled: Bool
    }

    /// Reads a registered `cfgattrib` value, or nil when the skin registered no such attribute.
    typealias SettingReader = (_ section: String, _ key: String) -> Bool?

    static func settings(reading read: SettingReader?) -> Settings {
        // **The album art is not conditional on this page, and cannot be.** `Album Art` and
        // `Visualization ` are one either/or in the skin: they share the single 186px slot the *File
        // Info* page has room for, and the skin's own handler switches one off when the other is
        // ticked — writing both directly is flipped back at load. So there is no setting that means
        // "art *and* the mini pane", and reading `Album Art` here made the row collapse to nothing
        // whenever the user had picked the mini pane, leaving the spectrum the whole width again.
        //
        // The side-by-side layout is what removes the constraint the pair exists for: this page has
        // room for both, so the cover is shown here whenever the spectrum is, and the mini pane
        // joins it when its own check box is ticked. That is `cover | viz | spectrum`, reached
        // through the skin's own settings rather than through a new one.
        //
        // The mini pane's default is the `newAttribute` call's own — off. Read as nil only when
        // there is no reader at all, which is how the pixel tests build the renderer.
        Settings(coverEnabled: true,
                 miniVisEnabled: read?(fileInfoComponentsSection, miniVisKey) ?? false)
    }

    /// Whether this object is one of the holder's panes and the side-by-side layout applies to it.
    /// Cheap enough to sit in front of `isVisible`: an id that does not start with `info.component.`
    /// leaves immediately.
    private static func pane(_ object: WasabiObject) -> String? {
        guard let id = object.xmlID, id.hasPrefix(idPrefix) || id.lowercased().hasPrefix(idPrefix)
        else { return nil }
        return id.lowercased()
    }

    /// The stretched pane among this object's siblings, if it is shown. Everything below is
    /// conditional on it: with the Visualization page closed the holder is the skin's own again and
    /// nothing here applies.
    private static func shownStretchedSibling(of object: WasabiObject) -> WasabiObject? {
        guard let holder = object.parent else { return nil }
        guard let stretched = holder.children.first(where: {
            $0.xmlID?.caseInsensitiveCompare(stretchedVisID) == .orderedSame
        }), isShown(stretched) else { return nil }
        return stretched
    }

    /// The renderer's own visibility rule, repeated here so the two cannot disagree about the pane
    /// this whole override keys on.
    private static func isShown(_ object: WasabiObject) -> Bool {
        guard !object.isTornDown else { return false }
        let value = object.attributes["visible"]?.lowercased()
        return value != "0" && value != "false" && value != "no"
    }

    /// Whether this object's visibility is decided here rather than by the skin's script, and what
    /// the answer is. Nil means "not ours — ask the skin".
    static func forcedVisibility(of object: WasabiObject, reading read: SettingReader?) -> Bool? {
        guard let id = pane(object), id != stretchedVisID else { return nil }
        switch id {
        case miniVisID, coverID, infoDisplayID, songInfoDisplayID: break
        default: return nil
        }
        guard shownStretchedSibling(of: object) != nil else { return nil }
        let settings = settings(reading: read)
        switch id {
        // The file-info text lines are what the 700 ms one-shot brings back over the bars. They are
        // the one thing this page has no room for, so they stay hidden while the spectrum is up.
        case infoDisplayID, songInfoDisplayID: return false
        // The cover and the mini vis follow the user's own two check boxes rather than the page
        // routine that hid them, which is the whole point of the side-by-side layout.
        case coverID: return settings.coverEnabled
        case miniVisID: return settings.miniVisEnabled
        default: return nil
        }
    }

    /// The corrected frame for one of the holder's panes, or nil to leave the skin's own.
    ///
    /// Only two panes ever move: the cover, when the mini vis sits to its left (the skin's own `195`),
    /// and the stretched pane, which is narrowed to the span the visible panes leave it.
    static func correctedFrame(for object: WasabiObject, parentFrame: CGRect, resolved: CGRect,
                               reading read: SettingReader?) -> CGRect? {
        guard let id = pane(object), id == stretchedVisID || id == coverID else { return nil }
        if id == coverID {
            guard shownStretchedSibling(of: object) != nil else { return nil }
        } else {
            guard isShown(object) else { return nil }
        }
        let settings = settings(reading: read)
        let row = slots(in: parentFrame, settings: settings)
        switch id {
        case coverID:
            guard let x = row.coverX else { return nil }
            // The width as well as the x: `fileinfo.maki` animates the cover's width to zero when it
            // hides the pane, and on this page it hid it — so the box the skin leaves behind has
            // nothing in it to draw. A slot in the side-by-side row is a fixed 186 either way.
            return CGRect(x: x, y: resolved.minY, width: paneWidth, height: resolved.height)
        default:
            let width = parentFrame.maxX - firstMargin - row.stretchedX
            guard width > 0 else { return nil }
            return CGRect(x: row.stretchedX, y: resolved.minY,
                          width: width, height: resolved.height)
        }
    }

    /// Where each visible pane starts, in absolute coordinates. Left to right: mini vis, cover, then
    /// whatever is left for the spectrum.
    private static func slots(in parentFrame: CGRect,
                              settings: Settings) -> (miniVisX: CGFloat?, coverX: CGFloat?,
                                                      stretchedX: CGFloat) {
        // With the mini vis on the skin starts the row at 3; with the cover alone it starts at 6.
        var x = parentFrame.minX + (settings.miniVisEnabled ? firstMargin : coverOnlyMargin)
        var miniVisX: CGFloat?
        var coverX: CGFloat?
        if settings.miniVisEnabled {
            miniVisX = x
            x += paneWidth + gutter
        }
        if settings.coverEnabled {
            coverX = x
            x += paneWidth + gutter
        }
        return (miniVisX, coverX, x)
    }

    /// Whether this `{0000000A}` holder is the stretched pane's own box.
    ///
    /// `WinampModernVisualizationHolder` routes the engine on the **box**: a holder at or above 3:1
    /// is a letterbox strip and draws the analyzer instead. The stretched pane is declared
    /// `w="0" relatw="1"` — the whole holder, a 7:1 strip — and it is only ever narrower than that
    /// because the side-by-side layout above narrowed it. Measuring the narrowed box would take it
    /// under the ratio and hand it the engine, which is the one placement BB9 settled as a
    /// **spectrum analyzer**. So the routing asks here first, and the answer is the pane's declared
    /// shape rather than its laid-out one.
    ///
    /// The holder is the `<component id="vis">` *inside* the pane group, so this reads the parent.
    static func isStretchedVisualizationPane(_ object: WasabiObject) -> Bool {
        object.parent?.xmlID?.caseInsensitiveCompare(stretchedVisID) == .orderedSame
    }

}
