import AppKit
import CoreGraphics
import Foundation

/// `XmlDoc`'s callback parser: which elements of a document a script's registered paths select.
enum WinampModernXmlDocReader {
    /// Ceiling on the paths one `XmlDoc` may register. Big Bento Modern registers one.
    static let maximumCallbacks = 16
    /// Ceiling on the elements one `parser_start()` reports. The measured document holds 31
    /// `<sourceitem>`s; the cap is what stops a hand-edited one — this file is the skin's own
    /// documented customisation point, so users do edit it — from driving an unbounded number of
    /// script dispatches inside a single event.
    private static let maximumElements = 512

    /// Calls `visit` with the path and element of every element a callback selects, in document
    /// order, up to `maximumElements`.
    static func forEachMatch(in roots: [WalXMLNode], callbacks: [String],
                             _ visit: (_ path: [String], _ node: WalXMLNode) -> Void) {
        var reported = 0
        func walk(_ node: WalXMLNode, path components: [String]) {
            guard reported < maximumElements else { return }
            let here = components + [node.name]
            if callbacks.contains(where: { parserPath($0, matches: here) }) {
                reported += 1
                visit(here, node)
            }
            for child in node.children { walk(child, path: here) }
        }
        for root in roots { walk(root, path: []) }
    }

    /// A `parser_addCallback` path against an element's own path.
    ///
    /// Three spellings, because the corpus uses three (B86; measured 2026-08-31 by pulling the
    /// literals out of the compiled `.maki`, since none of them appears in any XML):
    ///
    /// | Pattern | Registered by | Targets | Form |
    /// |---|---|---|---|
    /// | `WasabiXML/BrowserPro/*` | Big Bento's `main.maki` | `…/sourceitem` | absolute, same depth |
    /// | `ClassicPro/Visualization/BeatVis*` | ClassicPro `beat.maki` | `…/BeatVis/customvis` | absolute, **subtree** |
    /// | `ClassicPro/TextSettings*` | ClassicPro `player.maki`, `shade.maki` | `…/TextSettings/Style` | absolute, subtree |
    /// | `ClassicPro/About:Skin*` | ClassicPro `about.maki` | children of that node | absolute, subtree |
    /// | `BeatVis/*` | ClassicPro `beat.maki` | `ClassicPro/Visualization/BeatVis/customvis` | **relative** |
    ///
    /// This used to be the first row alone — equal component counts, `*` matching exactly one whole
    /// component. That is the shape Big Bento happens to have, and it silently rejected the other
    /// four: cPro's seven custom beat-vis animations never loaded, its songticker never got its
    /// antialias setting, and its About box never got its skin info. Nothing reported a failure,
    /// because a callback that never fires is indistinguishable from a document with nothing in it.
    ///
    /// Being generous here is safe by the callers' own construction: **every** `parser_onCallback`
    /// body in the corpus opens with `if (strlower(xmltag) == "<tag>")`, so an extra fire is
    /// discarded by the script itself. `beat.maki` registering two patterns for one set of nodes is
    /// the same defensiveness from the other side. What must not happen is a *missed* fire, so where
    /// the exact Winamp semantics are unknown this errs towards matching.
    /// Internal, not private, so the three spellings above can be pinned without a skin — the
    /// corpus patterns are the specification and a regression here is silent by nature.
    static func parserPath(_ pattern: String, matches components: [String]) -> Bool {
        let wanted = pattern.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !wanted.isEmpty, !components.isEmpty else { return false }

        func alike(_ expected: String, _ actual: String) -> Bool {
            expected == "*" || expected.caseInsensitiveCompare(actual) == .orderedSame
        }

        // Absolute, same depth — the original rule, kept exactly so Big Bento's provider list keeps
        // matching the nodes it matches today and no others.
        if wanted.count == components.count, zip(wanted, components).allSatisfy(alike) {
            return true
        }

        // Absolute with a trailing `*` glued to the final component (`BeatVis*`): that component is a
        // *prefix*, and the pattern covers the node it names **and everything beneath it**. A bare
        // final `*` is not this case — there it means one component, which the rule above handles.
        if let last = wanted.last, last != "*", last.hasSuffix("*"), components.count >= wanted.count {
            let stem = last.dropLast()
            let leading = wanted.dropLast()
            if zip(leading, components).allSatisfy(alike),
               components[leading.count].lowercased().hasPrefix(stem.lowercased()) {
                return true
            }
        }

        // Relative (`BeatVis/*`) — align the pattern with the *end* of the path. Requires at least
        // two components: a bare `foo` would otherwise match an element of that name at any depth,
        // which nothing asks for and which would fire callbacks a script never registered.
        if wanted.count >= 2, wanted.count < components.count,
           zip(wanted, components.suffix(wanted.count)).allSatisfy(alike) {
            return true
        }

        return false
    }
}

extension WinampModernScriptRuntime {
    /// Where `XmlDoc.load(path)` landed, or `nil` when the file is not in the VFS. Skins call `load`
    /// speculatively and branch on `exists()`, so a miss is the ordinary case rather than a failure:
    /// Big Bento Modern's reader tries its own `@SKINSPATH@\…\reader_providers.xml` first and then
    /// falls back to a Windows install path under `getApplicationPath()`, which resolves to nothing
    /// here and must answer false rather than abort the handler.
    func xmlDocumentPath(_ rawPath: String, program: MakiProgram) -> String? {
        guard !rawPath.isEmpty else { return nil }
        guard let resolved = try? loadedSkin.vfs.resolve(rawPath, relativeTo: program.source.path,
                                                         location: program.source) else { return nil }
        return resolved.logicalPath
    }

    /// Walks the loaded document once and dispatches `parser_onCallback` at the `XmlDoc` for every
    /// element whose path matches one of the registered callbacks.
    ///
    /// The handler's four arguments are pinned by Big Bento Modern's bytecode, which pops them into
    /// `(String path, String tag, List names, List values)` and then walks the two lists in parallel
    /// with `getNumItems`/`enumItem`, branching on the name to fill its provider row. The two lists
    /// are one reused pair of dynamic objects rather than a pair per element: the callback reads them
    /// synchronously and keeps neither, and a document of hand-edited length would otherwise allocate
    /// a script object per attribute set with nothing to free it.
    func parserStart(documentAt path: String, callbacks: [String], id: UInt64,
                     program: MakiProgram) {
        guard !callbacks.isEmpty,
              let data = try? loadedSkin.vfs.data(at: path, location: program.source),
              let text = String(data: data, encoding: .utf8)
                  ?? String(data: data, encoding: .isoLatin1),
              let parsed = try? WalLenientXMLParser().parse(text, path: path) else { return }

        let names = newObjectID(), values = newObjectID()
        dynamicObjects[names] = DynamicObjectState()
        dynamicObjects[values] = DynamicObjectState()
        defer {
            dynamicObjects.removeValue(forKey: names)
            dynamicObjects.removeValue(forKey: values)
        }

        WinampModernXmlDocReader.forEachMatch(in: parsed.roots, callbacks: callbacks) { here, node in
            // Document order, not alphabetical: a `parser_onCallback` body reads these two lists
            // positionally and ClassicPro's keys its whole apply loop on reaching `id` first.
            // See `WalXMLNode.attributeOrder`.
            let attributes = node.orderedAttributes
            dynamicObjects[names]?.items = attributes.map { .string($0.key) }
            dynamicObjects[values]?.items = attributes.map { .string($0.value) }
            _ = try? dispatch(target: MakiObjectReference(.dynamic(id)),
                              event: "parser_oncallback",
                              arguments: [.string(here.joined(separator: "/")),
                                          .string(node.name),
                                          .object(MakiObjectReference(.dynamic(names))),
                                          .object(MakiObjectReference(.dynamic(values)))])
        }
    }
}
