import Foundation

/// The filesystem a skin can touch: the sandbox for a path it hands us (`PlEdit.enqueueFile`,
/// `System.playFile`) and ClassicPro's file shell, which `System` and a script-made object both
/// answer. Split out of `WinampModernScriptRuntimeSystem.swift`; see
/// `skills/winamp-modern-skin-guide/reference/compatibility/maki-surface.md`.
extension WinampModernScriptRuntime {
    /// The sandbox policy for the one kind of value a skin hands *us*: a filesystem path it chose,
    /// through `PlEdit.enqueueFile` and `System.playFile`.
    ///
    /// Everything else on this seam is a path the host gave out first, so those two are the only
    /// methods that could widen what a script can reach. They are deliberately narrow, and narrow in
    /// the same direction the rest of this file already is: `findFiles` answers `-1` and
    /// `getFileSize` answers `0` precisely so a script has no way to *discover* a path. The only
    /// strings it can hold are ones we handed it (`PlEdit.getFileName`,
    /// `System.getPlayItemMetaDataString("filename")`, or one it saved into its own private string
    /// earlier), plus whatever the skin's author or the user typed — which is exactly what the two
    /// real callers do: T800's five `Mem1…Mem5` song slots save the playing file and play it back,
    /// and Big Bento's programmable buttons play a path the *user* enters in the skin's own box.
    ///
    /// So the policy grants **ingest**, not enumeration:
    ///
    /// - an `http`/`https` URL passes straight through — that is the host's existing stream ingest
    ///   and involves no filesystem at all;
    /// - a filesystem path must be absolute, must resolve to an **existing regular file** (not a
    ///   directory, not a fifo or device node that would wedge the audio engine), and must carry an
    ///   extension the player already supports.
    ///
    /// Anything else answers `nil` and the call becomes a silent no-op. It must **not** raise: both
    /// methods are void, Winamp ignores a path it cannot play, and throwing would abandon the rest of
    /// the caller's handler over one bad string — the failure mode `reference/scripting.md` records.
    func skinSuppliedMediaURL(_ rawPath: String, method: String) -> URL? {
        func refuse(_ reason: String) -> URL? {
            if Self.tracesEveryCall {
                NSLog("WinampModern %@ refused %@: %@", method, rawPath, reason)
            }
            return nil
        }
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return refuse("empty path") }
        if let url = URL(string: path), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        // Absolute POSIX only. A relative path has no defined base here (the script's notion of
        // "current directory" is Winamp's, not ours) and a `C:\…` path is a Windows skin's literal
        // that never described this machine.
        guard path.hasPrefix("/") else { return refuse("not an absolute POSIX path") }
        let url = URL(fileURLWithPath: path)
        guard AudioFileValidator.supportedExtensions.contains(url.pathExtension.lowercased()) else {
            return refuse("unsupported format")
        }
        guard let isRegularFile = try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile,
              isRegularFile else {
            return refuse("not an existing regular file")
        }
        return url
    }

    /// The complete native surface ClassicPro's MAKI invokes (P0B §1): three `ClassicProFile`
    /// filesystem-shell helpers, each routed through the host's intentional reveal/open policy or a
    /// bounded no-op.
    static let classicProFileMethods: MakiMethodTable<Void> = {
        var table = MakiMethodTable<Void>()
        table.add("explorefile", 1) { runtime, call in
            runtime.host.revealInFinder(call.arguments[0].stringValue)
            return .null
        }
        table.add("openfile", 2) { runtime, call in
            runtime.host.openExternally(call.arguments[0].stringValue)
            return .null
        }
        table.add("findfiles", 3) { runtime, call in
            // Bounded no-op: report "unavailable" so callers take their early-return path rather than
            // enumerating results. Skins never gain a filesystem-search capability.
            return .integer(-1)
        }
        // `ClassicPro.applyStyle(object, id)`: every attribute of the skin's `ClassicPro.xml`
        // `<Style id=…>` but the id, written to the object as a `setXmlParam`. cPro Creed's
        // `displaymods.m` opens with one, and while it was missing the whole handler aborted, so its
        // file-info readouts stayed where the engine put them, on the song title's line.
        table.add("applystyle", 2) { runtime, call in
            guard case .object(let target) = call.arguments[0],
                  let path = runtime.xmlDocumentPath("@SKINPATH@ClassicPro.xml", program: call.program),
                  let data = try? runtime.loadedSkin.vfs.data(at: path, location: call.program.source),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                  let parsed = try? WalLenientXMLParser().parse(text, path: path) else { return .null }
            let id = call.arguments[1].stringValue
            var style: WalXMLNode?
            WinampModernXmlDocReader.forEachMatch(in: parsed.roots, callbacks: ["ClassicPro/TextSettings*"]) { _, node in
                if style == nil, node.name.caseInsensitiveCompare("style") == .orderedSame,
                   node.attributes["id"] == id { style = node }
            }
            for (key, value) in style?.orderedAttributes ?? [] where key.lowercased() != "id" {
                _ = try runtime.invoke(method: "setxmlparam", on: target,
                                       arguments: [.string(key), .string(value)], program: call.program)
            }
            return .null
        }
        return table
    }()
}
