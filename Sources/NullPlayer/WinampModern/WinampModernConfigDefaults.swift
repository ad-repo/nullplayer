import Foundation

/// First-run values for a skin's **own** configuration, written before its scripts start.
///
/// **This file should stay almost empty**, for the same reason `WasabiSkinQuirks` does: the engine
/// runs a skin's scripts and stores what they write, and inventing values on their behalf is how a
/// host ends up deciding what a skin looks like. An entry belongs here only when all of this holds:
///
/// 1. the skin's own scripts treat a set of `cfgattrib`s as a **radio group** — exactly one member
///    carries `"1"` — and enforce that themselves on every change,
/// 2. every member is registered with a `"0"` default, so a profile that has never run the skin
///    lands in a state **the skin has no branch for** (not a state it chose), and
/// 3. the value written here is the one the skin's own markup is laid out for, so it restores the
///    author's arrangement rather than picking a look for them.
///
/// It is idempotent and self-healing: once any member reads `"1"` — because this seeded it, or
/// because the user picked a different one in the skin's settings — nothing is written again.
enum WinampModernConfigDefaults {

    /// Big Bento Modern's SUI tab strip (all four variants share these scripts).
    ///
    /// `tabswitch.maki`, `tabcontrol.maki` and `tabbutton.maki` each lay the strip out from three
    /// attributes in the skin's `Appearance` item — `Tabs: Hidden`, `Tabs: Icons`,
    /// `Tabs: Icons + Text` — and each is a three-way `if` with **no else**. `loadattribs.maki`
    /// registers all three with a `"0"` default, so on a profile that has never run the skin every
    /// branch is skipped and nothing runs at all:
    ///
    /// - `tabs.switch`, the divider between the strip and the content, keeps its markup `x` of 0 and
    ///   draws *over the left edge of the icons* instead of at 45, where the icons branch puts it;
    /// - its `image`/`hoverimage` stay the "open" arrow rather than the "close" one, and
    /// - clicking it does nothing for ever: `onLeftClick` only cycles *between* the three states, so
    ///   the strip cannot be reached from the state it starts in.
    ///
    /// The markup is already laid out for the icons mode (`sui.tabs w="40"`,
    /// `sui.components x="57"` — the exact numbers the icons branch writes), so `Tabs: Icons` is the
    /// arrangement it was authored to start in, and the two things that branch adds are precisely the
    /// two the markup cannot express.
    private static let radioGroups: [RadioGroup] = [
        RadioGroup(members: ["Tabs: Hidden", "Tabs: Icons", "Tabs: Icons + Text"],
                   preferred: "Tabs: Icons")
    ]

    /// Seeds the skin's namespace, keyed on the skin's own markup: a group is only considered when
    /// the document binds a control to one of its members, and the section comes from that binding
    /// rather than from anything hard-coded here. A skin that declares none of them is untouched.
    static func apply(document: WalExpandedXMLDocument, configuration: WinampModernConfiguration) {
        let sections = configSections(in: document)
        guard !sections.isEmpty else { return }
        for group in radioGroups {
            guard let section = sections[group.preferred.lowercased()] else { continue }
            // Every member has to be bound in the same section, or this is a different skin that
            // happens to reuse one name.
            guard group.members.allSatisfy({ sections[$0.lowercased()] == section }) else { continue }
            let alreadyChosen = group.members.contains {
                configuration.string(section: section, key: $0) == "1"
            }
            guard !alreadyChosen else { continue }
            configuration.setString("1", section: section, key: group.preferred)
        }
    }

    private struct RadioGroup {
        /// Attribute names exactly as the skin's script registers them with `newAttribute`, which is
        /// what the stored keys are named after. The markup's own spelling is only used to find the
        /// section, so a `cfgattrib` typo (Bento's `Tabs: Icons + text`) cannot write a stray key.
        let members: [String]
        let preferred: String
    }

    /// `cfgattrib="{GUID};Name"` bindings anywhere in the expanded document, including the groupdefs
    /// a skin only instantiates later — Bento's three checkboxes live in a settings page that is
    /// built long after the scripts that read these attributes have already run.
    private static func configSections(in document: WalExpandedXMLDocument) -> [String: String] {
        var wanted: Set<String> = []
        for group in radioGroups { for member in group.members { wanted.insert(member.lowercased()) } }
        var found: [String: String] = [:]
        var stack = document.roots
        while let node = stack.popLast() {
            stack.append(contentsOf: node.children)
            guard let binding = node.attribute("cfgattrib") else { continue }
            let parts = binding.components(separatedBy: ";")
            guard parts.count >= 2 else { continue }
            let key = parts[1...].joined(separator: ";")
                .trimmingCharacters(in: .whitespaces).lowercased()
            guard wanted.contains(key) else { continue }
            found[key] = parts[0].trimmingCharacters(in: .whitespaces)
        }
        return found
    }
}
