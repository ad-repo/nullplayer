import Foundation

/// What crosses from a `<groupdef embed_xui="…">` wrapper onto the control it embeds.
///
/// `embed_xui` does not only say where the instance's children go — it says which object *is* the
/// XUI, so the group answers for the embedded control's mouse events. Defix's `bento.tabbutton`
/// embeds its `mousetrap` button and the core script hooks `onLeftClick` on the **group**
/// (`switch.ml`); with nothing carrying the click across, the tab lit up under the pointer and the
/// SUI body never changed. Recorded on the group so the runtime can find it from the child at
/// dispatch time; `id` is not unique, but the pair (this group, that id) is what the initializer's
/// lookup already resolved.
///
/// Geometry and identity never cross: they belong to the wrapper, and forwarding them would move
/// the control inside its own group. What crosses is what the embedded object itself acts on — its
/// range, its commands, a text's or button's label styling, a widget's structure — and only onto
/// attributes it does not state.
enum WasabiEmbeddedXUI {
    private enum KeyGroup: CaseIterable {
        /// The wrapper *is* the control, so the range it declares is the **embedded** object's
        /// range — a `<SC:VScrollBar low="0" high="100">` wrapping a bare `<slider>` means that
        /// slider counts 0…100, not Winamp's default 0…255.
        ///
        /// Measured, from a live trace of Big Bento Modern's settings scrollbar: its up button
        /// does `slider.setPosition(slider.getPosition() + 5)` on the **inner** slider, and the
        /// page computes `scrollToPercent(99 - position)`. On the 0…255 default the positions
        /// ran 113 → 118 → 123 → 128, so the percentage was *negative every time* and the page
        /// clamped back to the top on every press: the bar moved, and nothing scrolled (BB19).
        case range
        /// The **commands** the instance declares, for the same reason: the wrapper is a
        /// `<group>`, which has no click behaviour of its own, and the object the pointer
        /// actually lands on is the embedded one. Enkera's whole transport is `<button:glow …
        /// action="play">` over a bare `<button id="but" fitparent="1"/>`, and Defix's two
        /// button bars are `<Defix:Bottom.bar.button action="PE_Add">` over a `mousetrap`: in
        /// both the artwork drew, the press animated, and the command reached nothing, because
        /// it stayed on a group that cannot run it.
        case commands
        /// A wrapped **text** draws with the typography its wrapper declares, because the
        /// wrapper draws no text of its own. Tristania's `<Deimos:TickerText font="ttf"
        /// fontsize="20" color="color.Display" valign="top">` wraps a bare `<text>`, and left
        /// with none of it the song ticker drew small, in the default font, across the
        /// display's EQ/PL/ML buttons. Styling only: `display`/`text` stay put, since Big
        /// Bento fills its wrapped lines from script and a bound value would show through the
        /// ones it leaves empty.
        case textStyling
        /// A wrapped **button** takes its label the same way, centred unless the skin says
        /// otherwise (Azenis²'s own `Wasabi:Button`, a grid under a bare `<button>`).
        case buttonLabel
        /// A wrapped **button** draws the artwork and keeps the state its wrapper declares, because
        /// the wrapper is a group and Wasabi hands both to the button. Tristania's
        /// `<Deimos:GlowButton image=…>` wraps a bare `<ToggleButton>` and its script shows Play or
        /// Pause by hiding the inner button: drawn on the wrapper, Play's blank disc covered Pause's
        /// ‖ glyph while playing and still took the click. Its `<Deimos:NStatesGlowButton
        /// image="player.button.repeat" nstates="3" cfgattrib=…>` drew nothing at all, because the
        /// state suffix and the binding only mean something on the `NStatesButton` inside.
        case buttonArtwork
        /// The **structure** a host-built widget is told to show: 1010 Fullscreen's
        /// `<Deimos:ConfigPage content=… title=…>` wraps a `<Wasabi:TitleBox>`, and its
        /// `<Deimos:ConfigSheet children=…>` a `<Wasabi:TabSheet>`. The widget was created
        /// with the template, before these reached it, so its body is built afterwards; without it
        /// every page of that skin's Preferences window was an empty box (B214).
        case structure

        var keys: [String] {
            switch self {
            case .range: return ["low", "high"]
            case .commands: return ["action", "param", "dblclickaction", "dbclickaction", "rightclickaction", "tooltip"]
            case .textStyling:
                return ["font", "fontsize", "color", "align", "valign", "bold", "italic", "antialias",
                        "shadowcolor", "shadowx", "shadowy", "forceuppercase", "forcelowercase",
                        "timecolonwidth", "timeroffstyle", "timerhours", "wrap"]
            case .buttonLabel: return ["text", "font", "fontsize", "color", "bold"]
            case .buttonArtwork:
                return ["image", "hoverimage", "downimage", "activeimage", "nstates", "cfgattrib", "cfgvals"]
            case .structure: return ["content", "title", "children"]
            }
        }

        func applies(to embedded: WasabiObject, wrapper attributes: [String: String]) -> Bool {
            switch self {
            case .range, .commands, .structure: return true
            case .textStyling:
                return embedded.tag.isStandard(.text)
            case .buttonLabel:
                return embedded.tag.isStandard(anyOf: [.button, .toggleButton])
                    && embedded.attributes["text"] == nil && !(attributes["text"] ?? "").isEmpty
            case .buttonArtwork:
                // All or nothing: a button that states its own `image` keeps its own artwork whole,
                // rather than gaining the wrapper's hover and press frames over it.
                return embedded.tag.is(anyOf: WasabiKind.buttons)
                    && embedded.attributes["image"] == nil && attributes["image"] != nil
            }
        }
    }

    /// The embedded widget's tag when `object` is an `embed_xui` wrapper, else nil.
    static func embeddedTag(of object: WasabiObject) -> String? { object.attributes[markerKey] }

    /// Whether `object` is a wrapper whose `image` crossed onto the button it embeds. Such a wrapper
    /// keeps its box — its children are laid out and clipped in it — but the button inside draws
    /// the artwork and takes the press, so the wrapper does neither.
    static func wrapsButton(_ object: WasabiObject) -> Bool { object.attributes[buttonMarkerKey] == "1" }

    private static let markerKey = "nullplayer.embedxui"
    private static let buttonMarkerKey = "nullplayer.embedbutton"

    /// Mark `wrapper` as the XUI for `embedded` (found by `tag`) and forward what crosses from the
    /// wrapper's `attributes`. Answers whether the wrapper's structure crossed, in which case the
    /// caller builds the embedded widget's hosted body.
    static func forward(_ attributes: [String: String], from wrapper: WasabiObject, tag: String,
                        onto embedded: WasabiObject) -> Bool {
        _ = wrapper.setAttribute(markerKey, value: tag.lowercased())
        var structureCrossed = false
        for group in KeyGroup.allCases where group.applies(to: embedded, wrapper: attributes) {
            var forwarded = false
            for key in group.keys where embedded.attributes[key] == nil {
                if let value = attributes[key] {
                    _ = embedded.setAttribute(key, value: value)
                    forwarded = true
                }
            }
            // Only artwork that actually moved takes the drawing with it: Big Bento's tab mousetrap
            // states its own placeholder `image="wtf"`, and its wrapper draws the tab icon as before.
            if group == .buttonArtwork { _ = wrapper.setAttribute(buttonMarkerKey, value: "1") }
            if group == .buttonLabel, embedded.attributes["align"] == nil {
                _ = embedded.setAttribute("align", value: attributes["align"] ?? "center")
            }
            if group == .structure { structureCrossed = forwarded }
        }
        seedVerticalSlider(embedded)
        return structureCrossed
    }

    /// A **vertical** slider starts at the top of its travel, which is `high` — not at the zero a
    /// missing value would otherwise read as. Only one that drives nothing itself (no `action`, so
    /// no host value to take) and states a range is seeded; a seek or volume slider is told its
    /// position by the host and must not be pre-empted.
    ///
    /// Measured: each of Big Bento Modern's settings pages opens by reading its scrollbar's position
    /// and calling `scrollToPercent(99 - position)`. Read as 0 that is *99% — the bottom*, and seven
    /// of the skin's nine pages launched scrolled to the end of themselves. Seeding the attribute
    /// rather than special-casing the getter keeps the thumb, the hit test and the script's
    /// arithmetic on one number.
    private static func seedVerticalSlider(_ embedded: WasabiObject) {
        guard embedded.tag.is(.slider),
              WasabiSceneRenderer.isVerticalOrientation(embedded),
              embedded.attributes["action"] == nil,
              embedded.attributes["value"] == nil,
              let high = embedded.attributes["high"] else { return }
        _ = embedded.setAttribute("value", value: high)
    }
}
