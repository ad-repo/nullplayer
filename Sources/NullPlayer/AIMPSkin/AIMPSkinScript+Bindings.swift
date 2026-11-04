import Foundation

/// Binding sets a script holds as objects (`TASEBindings`): one it makes (`TASEBindings.Create`,
/// then `LinkAdd` and `Set('Source', …)`: Redly's font picker reads its text box this way), or a
/// control's own (`Control.Get('Bindings')`: Victor KD-D55's long press runs its key's
/// `ActionOnHold`). Their links are `AIMPSkinLink`s, read through the dataflow as the forms' are.
extension AIMPSkinScript {
    /// Which binding set: one the script made, or an object's own, by its name.
    enum BindingSetKey: Hashable {
        case made(Int)
        case own(String)
    }

    /// A binding set's links by target pin, the first of a pin winning.
    typealias BindingSet = [String: AIMPSkinLink]
}

extension AIMPSkinScript.Run {
    /// Nil when `member` is not a bindings method on `target`, so the host bridge carries on.
    func bindingsMethod(_ target: Value, _ member: Member, _ args: [Value]) throws -> Value? {
        let first = args.first?.string ?? ""
        switch (target, member) {
        case (.bindingsClass, .create):
            bindingSetsMade += 1
            let key = AIMPSkinScript.BindingSetKey.made(bindingSetsMade)
            bindingSets[key] = [:]
            return .bindings(key)
        case (.object(let owner), .get) where args.count == 1 && first == "Bindings":
            return .bindings(ownBindings(owner))
        // A script frees what it made; nothing here holds on to it.
        case (_, .free):
            return Value.none
        case (.link(let set, let pin), .set) where args.count == 2:
            bindingSets[set, default: [:]][pin] = Self.link(bindingSets[set]?[pin], setting: first, to: args[1].string,
                                                             names: skin.index.names)
            return Value.none
        case (.link(let set, let pin), .get) where args.count == 1:
            return .string(bindingSets[set]?[pin].flatMap { Self.attribute(first, of: $0) } ?? "")
        case (.bindings(let set), _):
            return try method(onSet: set, member, first)
        default:
            return nil
        }
    }

    private func method(onSet set: AIMPSkinScript.BindingSetKey, _ member: Member, _ pin: String) throws -> Value {
        let link = bindingSets[set]?[pin]
        switch member {
        case .linkAdd:
            bindingSets[set, default: [:]][pin] = Self.link(link, setting: "TargetPin", to: pin, names: skin.index.names)
            return .link(set, pin: pin)
        case .linkFind:
            return link == nil ? Value.none : .link(set, pin: pin)
        case .linkDelete:
            bindingSets[set]?[pin] = nil
            return Value.none
        case .clear:
            bindingSets[set] = [:]
            return Value.none
        case .getDataAsText:
            return .string(link.map(text) ?? "")
        case .getDataAsNumber:
            return .number(link.map { flow.value(of: $0) } ?? 0)
        case .executeAction:
            if let link { perform(link) }
            return Value.none
        default:
            throw Unsupported(what: "method \(member) on bindings")
        }
    }

    /// An object's own links (a control's, an item's, a provider's), loaded into a set of its name
    /// the first time.
    private func ownBindings(_ owner: HostObject) -> AIMPSkinScript.BindingSetKey {
        let key = AIMPSkinScript.BindingSetKey.own(owner.name)
        guard bindingSets[key] == nil else { return key }
        let bindings: AIMPSkinBindings?
        switch owner.element {
        case .control(let control): bindings = control.bindings
        case .item(let item): bindings = AIMPSkinBindings(item.node, names: skin.index.names)
        case nil: bindings = owner.provider?.bindings
        }
        bindingSets[key] = Dictionary((bindings?.links ?? []).compactMap { link in link.target.map { ($0, link) } },
                                      uniquingKeysWith: { first, _ in first })
        return key
    }

    /// The link's source value as text: a file's tags through its `TextFormat`, a tabbed group's
    /// page by name, a text a script set, else the number.
    func text(of link: AIMPSkinLink) -> String {
        let source = link.source ?? "", pin = link.pin ?? ""
        if pin == "FileInfo" { return AIMPSkinTemplate.format(link.textFormat ?? "%T", host: engine.host) }
        if pin == "ActivePage", let pages = skin.index.groups[source], !pages.isEmpty { return pages[flow.activePage(source)] }
        if let text = engine.state.script.texts[source] { return text }
        return Value.number(flow.value(of: link)).string
    }

    /// A link to `source`'s `pin` (`BindingsGetDataAsText3`), with its `Expression` when it has one.
    func link(source: String, pin: String, expression: String, textFormat: String) -> AIMPSkinLink {
        var attributes = ["Source": source, "SourcePin": pin, "TextFormat": textFormat]
        if !expression.isEmpty { attributes["Expression"] = expression }
        return AIMPSkinLink(AIMPNode(tag: "link", attributes: attributes, children: [], text: nil), names: skin.index.names)
    }

    /// What pressing a control bound so does: an AIMP action, a counter stepped by the link's
    /// `Expression`, a tabbed group's page, or an item shown or hidden.
    private func perform(_ link: AIMPSkinLink) {
        let source = link.source ?? "", pin = link.pin ?? ""
        if let action = AIMPAction(source) {
            engine.ask(.action(action))
        } else if pin == "ActivePage", skin.index.groups[source] != nil {
            engine.state.script.activePages[source] = Int(flow.value(of: link))
        } else if pin == "Visible" || pin == "Visibility" {
            engine.state.script.visible[source] = flow.value(source, pin) == 0
        } else if pin == "Position", skin.index.providers[source]?.kind.isCounter == true {
            engine.setCounter(source, to: flow.wrapped(Int(flow.value(of: link)), counter: source))
        }
    }

    // MARK: - A link's attributes

    /// The attributes a link object answers `Get` and `Set` for, as AIMP names them.
    private static func attribute(_ name: String, of link: AIMPSkinLink) -> String? {
        switch name {
        case "Source": return link.source
        case "SourcePin": return link.pin
        case "TargetPin": return link.target
        case "Expression": return link.expression
        case "TextFormat": return link.textFormat
        default: return nil
        }
    }

    /// `link` (a new one for nil) with `attribute` set to `value`, read again so its expression is
    /// compiled. An attribute a link does not have is dropped.
    private static func link(_ link: AIMPSkinLink?, setting attribute: String, to value: String,
                             names index: AIMPSkinIndex.Names) -> AIMPSkinLink {
        let names = ["Source", "SourcePin", "TargetPin", "Expression", "TextFormat"]
        var attributes: [String: String] = [:]
        for name in names { attributes[name] = link.flatMap { Self.attribute(name, of: $0) } }
        if names.contains(attribute) { attributes[attribute] = value }
        return AIMPSkinLink(AIMPNode(tag: "link", attributes: attributes, children: [], text: nil), names: index)
    }
}
