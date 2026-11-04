import CoreGraphics
import Foundation

extension AIMPSkinLayout {
    /// The controls `item` shows in `rect`, in drawing order. The playlist is a window of its own in
    /// AIMP, over whatever the skin draws beside it (Sony ES-Style Silver 2's scope behind its list),
    /// and its scroll bar over it: the item's playlist draws after its other controls, its scroll
    /// bars last (sized by the form's playlist once the form is laid out: `withScrollBars`).
    func controls(of item: AIMPSkinItem, in rect: CGRect) -> [Control] {
        let held = heldControls(item, own: item.controls)
        // A control wholly outside its item does not show: AIMP 4 and 5's controls are windows inside
        // their item's (RealPlayer 11's equalizer sliders sit below its 65-px panel until the window
        // grows). AIMP 3.0's belong to the window: the form built from `main.ini` keeps them all (Vega
        // AIO's equalizer, right of its panel, shows as the window widens).
        func inside(_ control: AIMPSkinControl) -> Bool {
            guard !controlsOutliveItems, let placement = control.placement else { return true }
            return placement.rect(in: rect, moved: control.name.flatMap { flow.state.script.margins[$0] }).intersects(rect)
        }
        func isPlaylist(_ control: AIMPSkinControl) -> Bool { control.node["link"] == AIMPSkinList.playlist.rawValue }
        func scrolls(_ control: AIMPSkinControl) -> Bool { if case .playlistScrollBar = control.kind { true } else { false } }
        var placed: [Control] = []
        for control in held where !isPlaylist(control) && !scrolls(control) && inside(control) {
            // Its window cuts a cover at the item's edge (W10's 136-px cover strip in its 50-px icon
            // bar lay over the big cover beside it).
            let cut: Bool
            if case .coverArt = control.kind { cut = !controlsOutliveItems } else { cut = false }
            placed += place(control, in: rect, cut: cut ? rect : nil).map { [$0] } ?? []
        }
        placed += held.filter(isPlaylist).compactMap { place($0, in: rect) }
        placed += held.filter(scrolls).compactMap { place($0, in: rect) }
        return placed
    }

    /// A control placed in `parent`, then the controls nested in it (a `Panel` holding animators);
    /// nil while it is not shown.
    func place(_ control: AIMPSkinControl, in parent: CGRect, cut: CGRect? = nil) -> Control? {
        // As a script restyled it (Unsquareable's light theme recolours its playlist).
        let control = skin.index.control(control, restyledBy: flow.state.script.propertySets)
        guard flow.isShown(control), let placement = control.placement else { return nil }
        let placed = placement.rect(in: parent, moved: control.name.flatMap { flow.state.script.margins[$0] })
        let rect = autoSized(placed, control)
        let image = flow.image(control.picture)
        let (look, targets) = look(control, image: image, in: rect)
        var gauge: (value: Double, up: Double, down: Double)?
        if case .gauge(let reaction?) = control.kind {
            gauge = (flow.boundValue(control, "DisplayValue") ?? 0, reaction.up, reaction.down)
        }
        return Control(control: control, image: image, placed: placed, rect: rect, cut: cut, look: look, targets: targets,
                       hint: flow.hint(control), gauge: gauge,
                       controls: heldControls(control, own: control.controls).compactMap { place($0, in: rect) })
    }

    /// A display that sizes its height to its text (`AutoSize` `csHeight`) is as tall as its lines,
    /// down from its top margin, whatever the margins leave it (FLAT DARK's tips: -38 px).
    func autoSized(_ rect: CGRect, _ control: AIMPSkinControl) -> CGRect {
        guard control.kind.key?.role == .textDisplay else { return rect }
        let text = control.text, name = control.name ?? ""
        // A fixed label (no bindings, left-aligned, one line) is as wide as its text: AIMP sized it
        // so where it was drawn (Red Bias 2.0's 39-px " Вид:" box reads " Layout:" in English).
        if !control.bindings.declared, !text.declaresAutoSize, !text.declaresAlignment, !text.wraps, flow.state.script.texts[name] == nil {
            let width = AIMPSkinText.width(flow.displayText(control), font: text.font) + 8
            if width > rect.width { return CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height) }
            return rect
        }
        guard text.sizesHeight else { return rect }
        let shown = flow.state.script.texts[name].map { AIMPSkinTemplate.format($0, host: flow.host) } ?? flow.displayText(control)
        let lines = shown.isEmpty ? 0 : text.wraps ? AIMPSkinText.lines(shown, font: text.font, width: abs(rect.width)).count : 1
        return CGRect(x: rect.origin.x, y: rect.origin.y, width: abs(rect.width), height: CGFloat(lines) * AIMPSkinText.lineHeight(text.font))
    }

    // MARK: What a control shows and does

    /// How `control` looks at `rect`, all the painter needs to draw it, and the click targets it offers.
    private func look(_ control: AIMPSkinControl, image: AIMPSkinImage?, in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let name = control.name ?? ""
        let host = flow.host, state = flow.state
        func target(_ name: String, _ kind: AIMPSkinTarget.Kind, rect: CGRect = rect) -> [AIMPSkinTarget] {
            [AIMPSkinTarget(control: control.id, name: name, kind: kind, rect: rect)]
        }
        let frames = max(1, image?.frameCount ?? 1)
        switch control.kind {
        case .key(let key):
            return self.key(control, key, image: image, name: name, in: rect)
        // The track's rating, five stars across; without a picture, a key's.
        case .rating(let key):
            guard image != nil else { return self.key(control, key, image: image, name: name, in: rect) }
            return (.rating(Int(flow.boundValue(control, "DisplayValue") ?? 0)), [])
        // The standard playlist a skin places in its own frame, and the library window's group tree
        // and table: rows from the top, the first the quick search and scrolling leave.
        case .playlist(let style):
            let shown = host.playlistIndices(matching: state.lists.playlistSearch)
            let rows = Rows(top: state.lists.playlistTop, count: shown.count, height: CGFloat((style.fonts[.normal]?.height ?? 13) + 4),
                            room: rect.height)
            return (.playlist(style, rows: rows, shown: shown),
                    target(AIMPSkinList.playlist.rawValue, .playlist(first: rows.first, rowHeight: rows.height)))
        case .libraryTree(let style):
            guard let library = host.player.library else { return (.picture, []) }
            let tree = library.rows(state.lists.libraryGrouping, expanded: state.lists.libraryExpanded, search: state.lists.libraryTreeSearch)
            let rows = Rows(top: state.lists.libraryTreeTop, count: tree.count, height: CGFloat(style.font.height + 6), room: rect.height)
            return (.libraryTree(style, rows: rows, tree: tree),
                    target(AIMPSkinList.libraryTree.rawValue, .libraryTree(first: rows.first, rowHeight: rows.height)))
        case .libraryTable(let style):
            guard let library = host.player.library else { return (.picture, []) }
            let header = max(flow.image(style.header)?.frameSize.height ?? 0, CGFloat(style.headerFont.height + 8))
            let table = library.table(state.lists.libraryGrouping, path: state.lists.libraryPath, search: state.lists.librarySearch)
            let rows = Rows(top: state.lists.libraryTableTop, count: table.count, height: CGFloat(style.font.height + 6),
                            room: max(0, rect.height - header))
            return (.libraryTable(style, library: library, rows: rows, table: table, header: header),
                    target(AIMPSkinList.libraryTable.rawValue, .libraryTable(first: rows.first, rowHeight: rows.height, header: header)))
        case .playlistScrollBar(let thumb):
            return scrollBar(control, thumb: thumb, in: rect, playlistRows: 10)
        // A list's quick search box: a click types into it; while the window's field types over
        // it, the field shows the text.
        case .search(let list):
            let search = state.lists.search(list)
            return (.search(search.isEmpty || state.lists.searchEditing == list ? nil : search, font: control.text.font),
                    target(name.isEmpty ? list.rawValue + "Search" : name, .search(list: list)))
        case .tabControl(let tabs, let manager):
            return (.tabControl(tabs, caption: manager == "prvMusicLibraryManager" ? "Music Library" : "Playlist"), [])
        case .playlistTabs(let tabs):
            return (.playlistTabs(tabs, playing: host.player.playState == .playing), [])
        case .playlistBox(let font, let centred):
            return (.playlistBox(font: font, centred: centred), [])
        // A filmstrip of needle positions; `DisplayValue` runs 0–100. Where the skin gives it
        // reaction speeds the window eases it (Denon Classic Style's peak bars fall slowly).
        case .gauge:
            let value = host.feedback.gaugeLevels[control.id] ?? flow.boundValue(control, "DisplayValue") ?? 0
            let index = (value / 100 * Double(frames - 1)).rounded()
            return (.frame(Int(min(max(index, 0), Double(frames - 1)))), [])
        case .animator:
            // A free-running animator's flat last frame is its mask, not a picture (RealPlayer 11's
            // cover-column glows: a picture and a solid block, which cycled as a white flash).
            let bound = control.bindings["AnimationFrameIndex"] != nil
            let shown = !bound && frames > 1 && image?.lastFrameFlat == true ? frames - 1 : frames
            return (.frame(flow.animatorFrame(control, frames: shown)), [])
        case .stateDisplay:
            // The frame its `State` names: a script's (`Counter1.Set('State', …)`), else its binding's,
            // `State` or `DisplayValue` (Technics RS-1700 4K's drums and tape bands, on counters).
            let state = state.animation.animatorFrames[name]
                ?? Int(flow.boundValue(control, "State") ?? flow.boundValue(control, "DisplayValue") ?? 0)
            return (.frame(min(max(state, 0), frames - 1)), [])
        case .time(let digits):
            let seconds = max(0, Int(flow.boundValue(control, "DisplayValue") ?? Double(host.player.elapsedSeconds)))
            return (.time(seconds: seconds, digits), [])
        case .digits(let digits):
            return self.digits(control, digits, image: image, name: name, in: rect)
        case .equalizer(let preamp, let curve): return (.equalizer(preamp: preamp, curve: curve), [])
        case .coverArt(let cover): return (.coverArt(cover), [])
        case .glass(let blur, let tint): return (.glass(blur: blur, tint: tint), [])
        case .waveForm(let trace): return (.waveForm(trace), [])
        case .visualization(let spectrum, let cover): return (.visualization(spectrum, cover: cover), [])
        case .spectrum(let spectrum): return (.spectrum(spectrum), [])
        case .selector:
            return selector(control, image: image, name: name, in: rect)
        case .slider(let slider):
            let fraction = slider.isSeek ? host.player.position
                : control.input.source.flatMap { p in skin.index.counterModule(p).map { flow.value(p, "Position") / Double($0 - 1) } }
                ?? host.player.value(for: flow.provider(control))
            let kind: AIMPSkinTarget.Kind = slider.isSeek ? .seek : .slider(provider: flow.provider(control), vertical: slider.isVertical)
            return (.slider(slider, fraction: fraction, thumb: flow.image(slider.thumb)), target(name, kind))
        }
    }

    /// The playlist's scroll bar: the thumb as long as the share of the playlist's rows in view.
    private func scrollBar(_ control: AIMPSkinControl, thumb: String?, in rect: CGRect, playlistRows: Int) -> (Look, [AIMPSkinTarget]) {
        let lists = flow.state.lists
        let total = flow.host.playlistIndices(matching: lists.playlistSearch).count, maxTop = max(0, total - playlistRows)
        let picture = flow.image(thumb)
        let length = min(rect.height, max(picture?.frameSize.height ?? 8, rect.height * CGFloat(playlistRows) / CGFloat(max(1, total))))
        let top = min(max(0, lists.playlistTop), maxTop)
        return (.scrollBar(thumb: picture, length: length, share: maxTop > 0 ? CGFloat(top) / CGFloat(maxTop) : nil),
                [AIMPSkinTarget(control: control.id, name: "PlaylistScrollBar", kind: .playlistScroll(maxTop: maxTop, thumb: length), rect: rect)])
    }

    /// `tree` with each playlist scroll bar sized by the rows of the playlist laid out last before
    /// it, in drawing order (ten before any): the bar may sit in another item than its list (21 of
    /// the gate set's playlist windows).
    func withScrollBars(_ tree: Item) -> Item {
        var shown = 10
        func resized(_ control: Control) -> Control {
            var control = control
            if case .playlist(_, let rows, _) = control.look { shown = rows.visible }
            if case .playlistScrollBar(let thumb) = control.control.kind {
                (control.look, control.targets) = scrollBar(control.control, thumb: thumb, in: control.rect, playlistRows: shown)
            }
            control.controls = control.controls.map(resized)
            return control
        }
        func resized(_ item: Item) -> Item {
            var item = item
            item.controls = item.controls.map(resized)
            item.items = item.items.map(resized)
            return item
        }
        return resized(tree)
    }

    /// A digit strip; a key drawn as one (Sony TC-RX80's EQ, MUTE, RANDOM and LOOP: out, latched,
    /// held) shows its last frame while held down.
    private func digits(_ control: AIMPSkinControl, _ digits: AIMPControlClass.Digits, image: AIMPSkinImage?, name: String,
                        in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let input = control.input
        let look = Look.digits(value: flow.boundValue(control, "DisplayValue") ?? 0, digits)
        func target(_ kind: AIMPSkinTarget.Kind, rect: CGRect = rect) -> [AIMPSkinTarget] {
            [AIMPSkinTarget(control: control.id, name: name, kind: kind, rect: rect)]
        }
        if input.isActionKey, interaction.pressed == control.id, let image, image.frameCount > 2 {
            return (.frame(image.frameCount - 1), input.press.map { target($0) } ?? [])
        }
        // A display bound to an `Action` is a key whose value picks its picture (Onkyo TA-2066's
        // AMPLIFIER, MUSIC LIBRARY and TAPE SELECTOR keys).
        if input.isActionKey, let kind = input.press { return (look, target(kind)) }
        // A lamp that picks its counter's position; the LEDs are a few pixels, so the click lands
        // within a margin of them.
        if let lamp = input.lamp {
            return (look, target(.counter(name: lamp.counter, step: AIMPSkinStep(String(lamp.position))), rect: rect.insetBy(dx: -10, dy: -10)))
        }
        return (look, [])
    }

    /// A filmstrip slider: its position, and what a click or drag on it does.
    private func selector(_ control: AIMPSkinControl, image: AIMPSkinImage?, name: String, in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        let source = control.input.source
        let frames = max(1, image?.frameCount ?? 1)
        func target(_ kind: AIMPSkinTarget.Kind) -> [AIMPSkinTarget] { [AIMPSkinTarget(control: control.id, name: name, kind: kind, rect: rect)] }
        // A selector over a tabbed group (Pioneer's TAPE switch): its page picks the position,
        // and a click steps to the next.
        if let group = source, let pages = skin.index.groups[group], pages.count > 1 {
            return (.frame(Self.frame(of: flow.activePage(group), among: pages.count, frames: frames)),
                    target(.page(group: group, step: AIMPSkinStep("(value+1) mod \(pages.count)"))))
        }
        // A selector over a skin counter (Akai CS-F33's TAPE SELECTOR, DISPLAY MODE and REV
        // SELECTOR): its position picks the frame. A few positions step by click; a knob's many
        // (the GX-F90's and Teac's bass and treble, 121 quarter-dB steps) turn by dragging.
        if let counter = source, let module = skin.index.counterModule(counter) {
            let position = min(max(Int(flow.value(counter, "Position")), 0), module - 1)
            return (.frame(Self.frame(of: position, among: module, frames: frames)),
                    target(module > 12 ? .knob(provider: .named(counter)) : .counter(name: counter, step: AIMPSkinStep("Value + 1"))))
        }
        // A filmstrip of a player value (a knob's rotation): the value picks the frame. Its last
        // frame is its mask (grey by angle: AIMP reads a turn from it), not a position
        // (Mayak-120's knobs: 101 positions and a mask).
        let provider = flow.provider(control)
        let positions = max(1, frames - 1)
        let frame = Int((flow.host.player.value(for: provider) * Double(positions - 1)).rounded())
        guard let provider, provider != .position, source.flatMap(AIMPSkinProvider.init(player:)) != nil else { return (.frame(frame), []) }
        return (.frame(frame), target(.knob(provider: provider)))
    }

    /// The frame showing `position` of `count` in a strip of `frames`: one frame per position (plus
    /// a mask) maps straight; otherwise the positions spread over the turns (Technicss' tape
    /// selector: 7 over 91; the GX-F90's tone knobs: 121 over 101).
    static func frame(of position: Int, among count: Int, frames: Int) -> Int {
        let turns = max(1, frames - 1)
        guard turns != count, frames != count else { return position }
        return Int((Double(position) / Double(max(1, count - 1)) * Double(turns - 1)).rounded())
    }

    /// A key's or picture's frame and caption, and the click target a key offers.
    private func key(_ control: AIMPSkinControl, _ key: AIMPControlClass.Key, image: AIMPSkinImage?, name: String,
                     in rect: CGRect) -> (Look, [AIMPSkinTarget]) {
        // Buttons stack normal, hot, pressed (and disabled) frames. A switch has a run of
        // `FramesPerState` of them per state, off then on; it is on while its action's `State` is.
        // `Frame` fixes the picture (an AIMP 3.0 skin's lit playlist tab).
        let input = control.input, interaction = interaction
        let caption = key.showsText ? flow.text(control) : ""
        // A left-aligned key whose caption opens with spaces leaves them for its centred glyph
        // (Unsquareable's radios: a 22-px circle, then "       Light", in a box as wide as its words).
        let glyphFirst = key.isKey && image?.fill == .center && control.text.isLeftJustified && flow.displayText(control).first == " "
        func look(_ frame: Int) -> Look { .key(key, frame: frame, caption: caption, glyphFirst: glyphFirst) }
        var frame = key.fixedFrame
        guard let press = input.press else { return (look(frame), []) }
        // Only keys have hot and pressed frames: a display that opens a menu (SL-1200's
        // `Menu_Mask` over its label) keeps its picture under the pointer.
        if key.isKey {
            frame = interaction.pressed == control.id ? 2 : interaction.hovered == control.id ? 1 : 0
        }
        // A switch, or a button with a strip per state (SL-1200's shuffle and repeat keys, GX-R60's
        // slide switches over a counter), shows the run of frames for its `State`: its binding,
        // else its action's.
        let isButton = key.role == .button
        var perStateFrames = key.framesPerState ?? (key.role == .switch ? 3 : 0)
        var state = flow.boundValue(control, "State")
        // A key bound to a `State` with a switch's seven frames (three off, three on, the mask)
        // is a switch: Aiwa AD-M700's PLAYLIST lever stays at SHOW while the playlist is.
        if perStateFrames == 0, isButton, state != nil, image?.frameCount == 7 { perStateFrames = 3 }
        // Eight frames bound to a `State`: a key's four (normal, hot, pressed, disabled) off,
        // then on (Unsquareable's customize radios).
        if perStateFrames == 0, isButton, state != nil, image?.frameCount == 8 { perStateFrames = 4 }
        if state == nil, case .action(let action) = press { state = flow.host.pin(action.name, "State") }
        let stateIndex = max(0, Int(state ?? 0))
        if perStateFrames > 0, stateIndex > 0,
           key.role == .switch || (image?.frameCount ?? 0) >= (stateIndex + 1) * perStateFrames {
            frame += stateIndex * perStateFrames
        }
        // A frame left over after whole runs of state frames is the hit mask: `FramesPerState`
        // per state (4 by default: normal, hot, pressed, disabled), plus one. Pioneer CT-F1000's
        // REW and FF share one rect, each opaque only on its half of the mask.
        let perState = key.framesPerState ?? 4
        let count = image?.frameCount ?? 0
        var mask: Int? = count > perState && (count - 1) % perState == 0 ? count - 1 : nil
        // Four frames are a key's whole set: the last is its disabled glyph, not a mask (W10's
        // toolbar keys hit only on their 54-px glyphs).
        if mask == nil, isButton, count > 2, count != perState, image?.lastFrameFlat == true { mask = count - 1 }
        // AIMP hits a key on its pixels: one whose resting picture is empty lets clicks through
        // to what is under it (RealPlayer 11's 209-px A-B key over its whole transport row).
        if mask == nil, isButton, image?.firstFrameBlank == true { mask = frame }
        if case .hold = press, !isButton, count > 0 {
            // A reel or record a press seeks on (Tascam 32's, SL-1200's) is hit only on its tape or
            // grooves, the picture's last frame (its hover highlight, lit like AIMP's); its square
            // would cover the keys beside it.
            mask = count - 1
            if count > 1, interaction.hovered == control.id, image?.firstFrameBlank == false { frame = count - 1 }
        }
        // A key its `Accessibility` turns off (Kenwood KX-800's PLAY while playing) shows its
        // disabled frame and does nothing.
        if key.isKey, flow.boundValue(control, "Accessibility") == 0 {
            if isButton, count >= 4 { frame = 3 }
            return (look(frame), [])
        }
        var target = AIMPSkinTarget(control: control.id, name: name, kind: press, rect: rect,
                                    mask: AIMPAlphaMask(mask.flatMap { image?.frame($0) }))
        target.holdAction = input.holdAction
        target.longClick = input.longClick
        switch press {
        case .action, .menu, .maximize: target.releaseHandler = input.onMouseUp
        default: break
        }
        return (look(frame), [target])
    }
}
