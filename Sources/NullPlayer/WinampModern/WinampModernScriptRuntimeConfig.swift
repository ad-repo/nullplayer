import AppKit
import CoreGraphics
import Foundation

/// `cfgattrib` and `ConfigAttribute` state: bindings, toggles, radio groups, activation and the
/// registered settings the Skin Settings window lists. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// The `{GUID};Name` pair a control is bound to, or `nil` when it is not config-bound.
    static func configBinding(of object: WasabiObject) -> (section: String, key: String)? {
        guard let attribute = object.attributes["cfgattrib"] else { return nil }
        let parts = attribute.components(separatedBy: ";")
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1...].joined(separator: ";"))
    }

    /// The current value of a `cfgattrib`-bound control, for the renderer's active-state decision.
    func configValue(of object: WasabiObject) -> Bool {
        guard let binding = Self.configBinding(of: object) else { return false }
        // A number is not a lamp: mmd3's crossfade *slider* names `Crossfade time`, and reading its
        // seconds as truthiness would light an `activeimage` for any non-zero duration.
        if let bridged = WinampModernConfigBridge.attribute(section: binding.section, key: binding.key) {
            guard bridged.isFlag else { return false }
            return WinampModernConfigBridge.value(of: bridged, host: host) != 0
        }
        return loadedSkin.configuration.integer(section: binding.section, key: binding.key, default: 0) != 0
    }

    /// The raw integer behind a `cfgattrib` binding — the lamps' 0/1 and the sliders' own unit —
    /// from the host for a bridged attribute and from the skin's namespace for its own.
    func configInteger(of object: WasabiObject) -> Int32? {
        guard let binding = Self.configBinding(of: object) else { return nil }
        return configInteger(section: binding.section, key: binding.key)
    }

    func configInteger(section: String, key: String) -> Int32 {
        if let bridged = WinampModernConfigBridge.attribute(section: section, key: key) {
            return WinampModernConfigBridge.value(of: bridged, host: host)
        }
        return loadedSkin.configuration.integer(section: section, key: key, default: 0)
    }

    /// Flip a `cfgattrib`-bound control and tell the skin, returning false when it is not bound.
    ///
    /// Winamp's own preferences own these values, and a skin both writes them from its configurator
    /// and *reacts* to them. Defix's settings window is nine of these — each one a pair of
    /// togglebuttons over the same rect, a `ghost="1"` one that shows the state and a bare
    /// `rectrgn="1"` one that takes the click, both naming the same attribute. Neither carries an
    /// `action`, so nothing in the view had anything to run and every switch was inert.
    ///
    /// The notification is the half that matters: a skin applies a setting from `onDataChanged` on
    /// the `newAttribute` object it registered, not by polling. Writing the value silently would move
    /// the switch and change nothing on screen until the skin was reloaded. Every dynamic object bound
    /// to the same attribute is told, because each script registers its own.
    @discardableResult
    func toggleConfigAttribute(of object: WasabiObject) -> Bool {
        // A bound slider's attribute is its position, which the drag already wrote. Its release is
        // still a click on it, and flipping the number there put Tristania's crossfade back to 1 s
        // at the end of every drag.
        guard !object.tag.is(.slider), let binding = Self.configBinding(of: object) else { return false }
        let flipped = configInteger(section: binding.section, key: binding.key) != 0 ? "0" : "1"
        setConfigAttribute(section: binding.section, key: binding.key, value: flipped)
        // A click also tells the clicked button `onToggle`, bound or not, as Wasabi's does: Anunaki
        // prints "Shuffle On" / "Repeat Off" from its shuffle and repeat buttons' `onToggle` alone.
        _ = try? dispatch(object: object, event: "ontoggle", arguments: [.boolean(flipped == "1")])
        return true
    }

    /// Write a `cfgattrib`-bound **slider** from a drag, mapping 0…1 through the control's own
    /// `low…high`, and returning false when it is not bound.
    ///
    /// The unit is the slider's, not Winamp's 0…255: mmd3's crossfade slider is cut `high="20"` and
    /// its readout prints the position as seconds, so handing it a 0…255 would have shown "255s".
    @discardableResult
    func setConfigAttribute(of object: WasabiObject, normalized: CGFloat) -> Bool {
        guard let binding = Self.configBinding(of: object) else { return false }
        let low = Double(object.attributes["low"] ?? "0") ?? 0
        let high = Double(object.attributes["high"] ?? "255") ?? 255
        let value = Int32((low + Double(max(0, min(1, normalized))) * (high - low)).rounded())
        guard configInteger(section: binding.section, key: binding.key) != value else { return true }
        setConfigAttribute(section: binding.section, key: binding.key, value: String(value))
        return true
    }

    /// Flip a togglebutton the way a *click* does, and tell the skin — returning false for anything
    /// that is not a plain togglebutton.
    ///
    /// Wasabi's togglebutton owns its own state: pressing it flips `activated` and then calls
    /// `onToggle(activated)`. Ours only ever changed from `setActivated`, which is a script talking
    /// to itself, so a togglebutton a person clicked was inert however completely the skin
    /// implemented it. Multipass's bottom drawer opens from `buttonDrawerBottomToggle.onToggle` and
    /// from nothing else — the button was hit, its bindings were live, and every handler count was
    /// zero.
    ///
    /// A `cfgattrib`-bound control is deliberately excluded: for those the stored preference *is* the
    /// state (`configValue`), they already have `toggleConfigAttribute` as their route, and flipping a
    /// second copy of the state here would let `getActivated()` disagree with the value the skin reads.
    /// Click a `<Wasabi:CheckBox radioid="…">`: this one goes on and the rest of its set goes off
    /// (B66).
    ///
    /// A radio is not a toggle and must not be flipped like one — clicking the member that is already
    /// on leaves it on, which is the difference between "choose Classic" and "choose nothing". Styx's
    /// four preference pairs are all this shape, and its scripts read the choice back from
    /// `onToggle`, so every member that *changes* has to be told, not just the one clicked.
    ///
    /// The set is looked up from the top of the object's own tree: `radioid` is a flat name shared
    /// across whatever groups the skin happens to have nested, and Styx's pairs live in two different
    /// content groups of the same window.
    @discardableResult
    func selectRadioMember(_ object: WasabiObject) -> Bool {
        guard WasabiFormWidgets.kind(of: object) == .checkBox,
              let radio = WasabiFormWidgets.radioIdentifier(of: object) else { return false }
        var root = object
        while let parent = root.parent { root = parent }
        var members: [WasabiObject] = []
        func collect(_ node: WasabiObject) {
            if WasabiFormWidgets.radioIdentifier(of: node) == radio,
               WasabiFormWidgets.kind(of: node) == .checkBox {
                members.append(node)
            }
            node.children.forEach(collect)
        }
        collect(root)
        for member in members {
            let wanted = member === object
            guard (member.attributes["activated"] == "1") != wanted else { continue }
            setActivated(member, wanted)
            _ = try? dispatch(object: member, event: "ontoggle", arguments: [.boolean(wanted)])
            notifyActivated(member, activated: wanted)
        }
        return true
    }

    @discardableResult
    func toggleActivation(of object: WasabiObject) -> Bool {
        guard object.tag.is(anyOf: [.toggleButton, .nStatesButton]),
              Self.configBinding(of: object) == nil else { return false }
        // An `nstatesbutton` is a togglebutton that counts: a click advances it to the next state
        // and wraps, and `getCurCfgVal()` is how its script reads the position it landed on.
        // ClassicPro's mute is one of these with no binding — `mute_but.onToggle` is the whole of
        // its behaviour (save the volume, set it to zero, and back) and nothing was ever flipping
        // it, so the button was inert however completely the engine implemented it.
        let states = object.tag.is(.nStatesButton) ? max(1, Int(object.attributes["nstates"] ?? "") ?? 2) : 2
        let previous = Int(object.attributes["value"] ?? "") ?? (object.attributes["activated"] == "1" ? 1 : 0)
        let state = (max(0, previous) + 1) % states
        _ = object.setAttribute("value", value: String(state))
        let activated = state != 0
        _ = object.setAttribute("activated", value: activated ? "1" : "0")
        notifyObjectDidMutate(object)
        // The state is flipped *before* the notification, because that is what the handler reads:
        // multipass's `onToggle` asks the button `getActivated()` rather than trusting its argument.
        _ = try? dispatch(object: object, event: "ontoggle", arguments: [.boolean(activated)])
        notifyActivated(object, activated: activated)
        return true
    }

    /// Write a button's activation, keeping an `nstatesbutton`'s counted position in step with it.
    ///
    /// The two are one state, spelled twice: `activated` is what `getActivated()` and a togglebutton's
    /// `activeimage` read, `value` is the state index the artwork is cut in and what `getCurCfgVal()`
    /// answers. ClassicPro restores a persisted mute with `setActivated(true)` at startup, so without
    /// this the lamp came up lit while the button still counted itself as sitting on state 0.
    func setActivated(_ object: WasabiObject, _ activated: Bool) {
        _ = object.setAttribute("activated", value: activated ? "1" : "0")
        if object.tag.is(.nStatesButton) {
            _ = object.setAttribute("value", value: activated ? "1" : "0")
        }
        notifyObjectDidMutate(object)
    }

    /// `onActivate(int activated)` — Wasabi raises it whenever a button's activation changes,
    /// whoever changed it, and it is separate from `onToggle`: skins hang their *indicator* off this
    /// one. mmd3's three lamps and the three words in its display are `setAlpha(activated * 255)`
    /// from nothing else, so with no dispatch site at all no `.wal` skin could show a toggle's state.
    func notifyActivated(_ object: WasabiObject, activated: Bool) {
        _ = try? dispatch(object: object, event: "onactivate", arguments: [.boolean(activated)])
    }

    /// Tell the skin that one of Winamp's playback options moved from **outside** it — NullPlayer's
    /// own Playback menu, a keyboard shortcut, a restored session.
    ///
    /// Without this the bridge is only half a fix: `configValue` would answer correctly the next
    /// time anything asked, but mmd3's lamps are not polled — their alpha is written once, from
    /// `onActivate`, and a shuffle toggled in the menu bar left the skin showing the old state.
    /// That is the same drift two copies of the setting used to cause, arriving by a different road.
    func refreshBridgedConfigState() {
        var moved = false
        for attribute in WinampModernConfigBridge.Attribute.allCases {
            let value = WinampModernConfigBridge.value(of: attribute, host: host)
            let cacheKey = "\(attribute.section);\(attribute.key)"
            let previous = lastBridgedValues.updateValue(value, forKey: cacheKey)
            // First sight seeds the cache without notifying: the skin read the value itself at load
            // (mmd3's `getActivated()` / `getPosition()` init), and an event for a change that never
            // happened would be a lie about what the person just did.
            guard let previous, previous != value else { continue }
            notifyActivationChanged(section: attribute.section, key: attribute.key)
            notifyPositionChanged(section: attribute.section, key: attribute.key, value: value)
            moved = true
        }
        if moved { notifyGraphDidMutate() }
    }

    /// A bound **slider** learns the same news through `onSetPosition` — that is where mmd3 prints
    /// its crossfade readout, and a duration changed from the Fade Duration menu has to reach it.
    func notifyPositionChanged(section: String, key: String, value: Int32) {
        for object in loadedSkin.runtime.graph.allObjectsUnordered
        where object.tag.is(.slider) {
            guard let binding = Self.configBinding(of: object),
                  binding.section.caseInsensitiveCompare(section) == .orderedSame,
                  binding.key.caseInsensitiveCompare(key) == .orderedSame else { continue }
            _ = try? dispatch(object: object, event: "onsetposition", arguments: [.integer(value)])
        }
    }

    /// Tell every control bound to `{section};key` that its activation moved.
    ///
    /// Bounded by the graph: this walks the objects that already exist, and a skin cannot declare
    /// more of them at runtime than `newGroup`'s own ceiling allows.
    func notifyActivationChanged(section: String, key: String) {
        let activated = configInteger(section: section, key: key) != 0
        for object in loadedSkin.runtime.graph.allObjectsUnordered {
            guard let binding = Self.configBinding(of: object),
                  binding.section.caseInsensitiveCompare(section) == .orderedSame,
                  binding.key.caseInsensitiveCompare(key) == .orderedSame else { continue }
            notifyActivated(object, activated: activated)
        }
    }

    /// Write one configuration attribute and tell the skin — the single write route, shared by a
    /// `cfgattrib` control the skin drew itself and by the host's own settings list (Phase 27.3).
    /// A second route would let the two disagree about whether the skin was notified.
    func setConfigAttribute(section: String, key: String, value: String) {
        // A bridged attribute is Winamp's own playback option, and the host owns it. Writing it to
        // the skin's namespace as well would give one setting two homes that drift apart — a shuffle
        // toggled from the menu bar leaving the skin's lamp dark, and vice versa.
        if let bridged = WinampModernConfigBridge.attribute(section: section, key: key) {
            WinampModernConfigBridge.setValue(Int32(value) ?? (value.isEmpty ? 0 : 1),
                                              of: bridged, host: host)
            // The engine will post its options-changed notification for this very write, and
            // `refreshBridgedConfigState` must not read it back as news and raise `onActivate` a
            // second time for one click. Recording the settled value here is what makes the two
            // routes idempotent with each other.
            lastBridgedValues["\(bridged.section);\(bridged.key)"] =
                WinampModernConfigBridge.value(of: bridged, host: host)
        } else {
            loadedSkin.configuration.setString(value, section: section, key: key)
        }
        // Wasabi's togglebutton raises `onActivate` when its activation changes, and for a
        // config-bound button the attribute *is* that activation — so the write is the change. Every
        // object bound to this attribute hears it, because a skin declares the same switch once per
        // layout: mmd3's Crossfade button exists in `normal`, `shade` and `shade2`, and its
        // indicator layers are per-layout too.
        notifyActivationChanged(section: section, key: key)
        // **In creation order**, which is script-load order — never the dictionary's. Every script
        // that asks for an attribute gets its own object, so a radio group is a set of sibling
        // handlers that each re-assert their own state: Big Bento's Multi Content View has one per
        // page, and the one whose page is being *turned off* zeroes the others as it goes. Dispatched
        // in hash order, a sibling could run before the page the user actually picked and clear its
        // flag first, so that page's handler read `getData() != "1"` and never switched — the setting
        // changed, the panel did not, and on the next launch the stored page and the stored radio
        // disagreed and the skin opened both (the stretched visualization over the file info).
        // Swift's dictionary order is also unstable per process, so this failed differently per run.
        for (id, state) in dynamicObjects.sorted(by: { $0.key < $1.key }) {
            guard case .configAttribute(let attributeSection, let attributeKey) = state.role,
                  attributeSection.caseInsensitiveCompare(section) == .orderedSame,
                  attributeKey.caseInsensitiveCompare(key) == .orderedSame else { continue }
            _ = try? dispatch(target: MakiObjectReference(.dynamic(id)), event: "ondatachanged",
                              arguments: [])
        }
        notifyGraphDidMutate()
    }

    /// The registered settings that are actually *settings*, for a list a person reads.
    ///
    /// Winamp's config is a tree: a skin's root item registers one attribute per **child item**,
    /// whose value is that child's GUID (Defix: `Appearance = {F1036C9C-…}`). Measured against
    /// Defix, 6 of its 38 registrations are those structural links. They are navigation, not
    /// options, so they stay out of the list while `registeredSettings` keeps the raw measurement.
    var presentableSettings: [RegisteredSetting] {
        registeredSettings.filter { !Self.namesAnItem(configAttributeValue($0)) }
    }

    static func namesAnItem(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
    }

    /// The current value of a registered setting addressed the way `cfgattrib` addresses it, or nil
    /// when the skin registered no such attribute. Lets the renderer read a setting that no object in
    /// the scene carries a binding for — Big Bento Modern's two *File Info Components* check boxes
    /// live in its config window, which is closed while the panes they govern are on screen (BB9).
    func configAttributeValue(section: String, key: String) -> String? {
        guard let setting = registeredSettings.first(where: {
            $0.section.caseInsensitiveCompare(section) == .orderedSame &&
            $0.name.caseInsensitiveCompare(key) == .orderedSame
        }) else { return nil }
        return configAttributeValue(setting)
    }

    /// The current value of a registered setting, straight from the skin's own configuration.
    func configAttributeValue(_ setting: RegisteredSetting) -> String {
        loadedSkin.configuration.string(section: setting.section, key: setting.name,
                                        default: setting.defaultValue)
    }
}
