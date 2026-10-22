import AppKit
import CoreGraphics
import Foundation

/// Which script bindings have been parsed into the runtime's programs, so a runtime-instantiated
/// group's scripts are started exactly once even if the same group is instantiated again, and how
/// deeply those starts are nested.
struct WinampModernScriptStarts {
    /// How deeply a runtime-instantiated group's `onScriptLoaded` may instantiate further groups.
    /// ClassicPro nests two levels (the SUI builds the tab strip, which builds each tab).
    static let maximumDepth = 8
    private var bound: Set<WasabiScriptBinding>
    private var depth = 0

    init(bound: Set<WasabiScriptBinding>) { self.bound = bound }

    func isBound(_ binding: WasabiScriptBinding) -> Bool { bound.contains(binding) }
    mutating func bind(_ binding: WasabiScriptBinding) { bound.insert(binding) }

    /// One level deeper, or false at `maximumDepth`. Each `true` is paired with `leave()`.
    mutating func enter() -> Bool {
        guard depth < Self.maximumDepth else { return false }
        depth += 1
        return true
    }

    mutating func leave() { depth -= 1 }
}

/// Scripts for groups added after load: pending runtime groups, starting their programs, and
/// the layout that owns a group definition. Split out of
/// `WinampModernScriptRuntime.swift`.
extension WinampModernScriptRuntime {
    /// Start the scripts of a pending runtime group, if `object` is one (or contains one — a script may
    /// `init` an ancestor of the group it created).
    func startPendingScripts(for object: WasabiObject) throws {
        let matches = pendingRuntimeGroups.filter { $0 === object || Self.isDescendant($0, of: object) }
        guard !matches.isEmpty else { return }
        pendingRuntimeGroups.removeAll { pending in matches.contains { $0 === pending } }
        for match in matches { try startScripts(addedBeneath: match) }
    }

    /// Everything still waiting, in creation order. Called once the outermost dispatch unwinds.
    func drainPendingScripts() {
        while !pendingRuntimeGroups.isEmpty {
            let next = pendingRuntimeGroups.removeFirst()
            // A group's `onScriptLoaded` can create more groups; those join the queue behind it.
            try? startScripts(addedBeneath: next)
        }
    }

    static func isDescendant(_ object: WasabiObject, of ancestor: WasabiObject) -> Bool {
        var node = object.parent
        while let current = node {
            if current === ancestor { return true }
            node = current.parent
        }
        return false
    }

    func startScripts(addedBeneath root: WasabiObject) throws {
        // A group's `onScriptLoaded` may itself instantiate groups (ClassicPro's tab strip does exactly
        // that, five times), so this is genuinely recursive. `maximumRuntimePrograms` bounds the total
        // but not the native stack depth, which this does.
        guard scriptStarts.enter() else {
            loadedSkin.runtime.record(WalDiagnostic(.scriptBudgetExceeded,
                                                    "Runtime group instantiation nested deeper than "
                                                    + "\(WinampModernScriptStarts.maximumDepth); the "
                                                    + "scripts of '\(root.xmlID ?? root.typeName)' were "
                                                    + "not started.",
                                                    severity: .warning, location: root.source))
            return
        }
        defer { scriptStarts.leave() }
        var added: [MakiProgram] = []
        func collect(_ object: WasabiObject) throws {
            for binding in object.scriptBindings where !scriptStarts.isBound(binding) {
                guard programs.count + added.count < Self.maximumRuntimePrograms else { return }
                scriptStarts.bind(binding)
                do {
                    let data = try loadedSkin.vfs.data(at: binding.logicalPath, location: binding.source)
                    added.append(try MakiBytecodeParser().parse(data, source: binding.source,
                                                                ownerID: binding.ownerID,
                                                                parameter: binding.parameter))
                } catch let failure as WalFailure {
                    // Same tolerance as the initial load: an unreadable program is dropped, not fatal.
                    recordScriptFailure(failure)
                }
            }
            for child in object.children { try collect(child) }
        }
        try collect(root)
        guard !added.isEmpty else { return }
        added.forEach(Self.seedHostSingletons)
        programs.append(contentsOf: added)
        try dispatchSystem(event: "onscriptloaded", to: added)
        deliverXUIParams(forSubtreeOf: root)
        seedPlaybackState(to: added)
    }

    /// Tell a subtree started **mid-session** what is already playing (B82).
    ///
    /// A script that loads with the skin hears the opening `onTitleChange` and `onPlay` from the
    /// window's first track update. One brought up later — a widget, a `GroupList` entry, a hosted
    /// window — would otherwise hear nothing until the next track: ClassicPro's Now Playing widget
    /// fills its three `SC:FadeText` lines only from `onTitleChange`, and the NOW tab builds a fresh
    /// instance on every click, so the lines stayed empty for the rest of the song.
    ///
    /// Scoped to the new programs. A skin-wide dispatch would replay the title to every running
    /// script, and `beat.m` resets its VU maximum on each one. Before the skin has started this is
    /// left to that first update, which reaches these programs too.
    func seedPlaybackState(to added: [MakiProgram]) {
        guard loadedSkin.runtime.hasStartedScripts else { return }
        let title = host.trackDisplayTitle
        if !title.isEmpty {
            _ = try? dispatch(target: MakiObjectReference(.system), event: "ontitlechange",
                              arguments: [.string(title)], in: added)
        }
        if host.playbackState == .playing { _ = try? dispatchSystem(event: "onplay", to: added) }
    }

    /// Start a subtree inserted by the host after global skin startup. The ordering is the same as
    /// any runtime-created group: object-owned `onScriptLoaded`, then XUI params. Global scripts are
    /// already running and are deliberately not restarted.
    func startTrustedHostedWindowScripts(beneath root: WasabiObject) throws {
        guard root.tag.is(.container),
              root.source.path == WasabiSurfaceSynthesizer.sourcePath,
              root.attributes[WinampModernContainerTopology.synthesizedAttribute] == "1"
        else {
            throw WalFailure(WalDiagnostic(.unsupportedScriptCapability,
                                           "Refused to start an untrusted hosted-window subtree.",
                                           location: root.source))
        }
        if let layout = root.children.first(where: {
            $0.tag.is(.layout)
        }) {
            activeLayoutByContainer[root.stableID] = layout.stableID
            realizedLayouts.insert(layout.stableID)
        }
        try startScripts(addedBeneath: root)
    }

    /// Which layout a `newGroupAsLayout` group hangs off: the one its groupdef names in
    /// `owner="<container>,<layout>"`, falling back to the calling script's own ancestor layout when
    /// there is no `owner=` or it names something this skin did not instantiate.
    ///
    /// The fallback matters because the caller is often not under a layout at all — multipass's
    /// `system.maki` is a `skin.xml`-level script whose owner is the `<scripts>` element — in which
    /// case there is nothing to parent to and the call answers null rather than misplacing the group.
    func ownerLayout(forGroupDefinition identifier: String, program: MakiProgram) -> WasabiObject? {
        let owner = (try? loadedSkin.runtime.types.resolved(identifier: identifier))?
            .defaultAttributes["owner"] ?? ""
        let parts = owner.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        if let containerID = parts.first, let container = findRoot(type: .container, xmlID: containerID) {
            let layouts = container.children.filter {
                $0.tag.is(.layout)
            }
            // `owner="main"` with no layout half means the container's first layout.
            if parts.count < 2 { if let first = layouts.first { return first } }
            if let named = layouts.first(where: { $0.xmlID?.caseInsensitiveCompare(parts[1]) == .orderedSame }) {
                return named
            }
        }
        guard let caller = program.ownerID.flatMap(loadedSkin.runtime.graph.object(withID:)) else { return nil }
        return ancestor(of: caller, type: .layout)
    }
}
