import CoreGraphics
import CoreText
import Foundation
import os

/// A loaded AIMP skin: what the skin supplies, immutable, built off the main thread by
/// `AIMPSkinLoader`. Forms are trees of layout `item`s and `control`s
/// (`reference/layout.md`); `Schema.xml` is the resource repository they name textures, colours
/// and fonts through. Sendable: a window draws it on a background queue (`AIMPSkinFrameScheduler`).
struct AIMPSkin: Sendable {
    /// A form besides the main one: a skin's speakers, amplifier, equalizer unit, remote, playlist
    /// or library, in a window of its own unless a dock site holds it (`AIMPSkinDockSites`). Its info,
    /// lyrics and visualization frames are NullPlayer's own windows instead.
    struct Companion: Sendable {
        let name: String
        /// `DisplayName`, through the language strings.
        let title: String
        let form: AIMPNode
        let initiallyVisible: Bool
        /// What the window holds, by its lists rather than its name (Akai GX-77's notepad playlist
        /// is `Win_1`).
        let role: Role
        /// False for a form NullPlayer has its own window for (Acubens' visualization): it shows
        /// only while docked.
        var opensWindow = true
        /// Where `Schema.xml` opens it beside its master (`Placement`), when it says.
        var declaredPlacement: DeclaredPlacement?
        /// Where it opens beside the deck when `Schema.xml` does not say: where the skin's layout puts
        /// it (AIMP 2's equalizer, right of the player), else from its name (`LSpeaker`,
        /// `SpeakerRightWindow`).
        let placement: Placement

        init(name: String, title: String, form: AIMPNode, initiallyVisible: Bool, role: Role, placement: Placement? = nil) {
            self.name = name
            self.title = title
            self.form = form
            self.initiallyVisible = initiallyVisible
            self.role = role
            self.placement = placement ?? AIMPFormRole.side(ofForm: name)
        }
        /// A speaker cabinet as tall as the deck or taller stands level with its bottom.
        var isSpeaker: Bool { name.lowercased().contains("speaker") }

        /// Where its window (`size`) opens beside the deck's window (`deck`), in screen coordinates
        /// (y up): as `Schema.xml` declares, its offset times `scale`, else by `placement`: beside
        /// the deck tops level (a speaker taller than the deck bottoms level), below it or above it
        /// at its left edge.
        func origin(size: CGSize, beside deck: CGRect, scale: CGFloat) -> CGPoint {
            if let declared = declaredPlacement {
                let offset = declared.offset * scale, centred = deck.midX - size.width / 2
                switch declared.side {
                case .left: return CGPoint(x: deck.minX - size.width, y: deck.maxY - offset - size.height)
                case .right: return CGPoint(x: deck.maxX, y: deck.maxY - offset - size.height)
                case .above: return CGPoint(x: centred, y: deck.maxY + offset)
                case .below: return CGPoint(x: centred, y: deck.minY - offset - size.height)
                }
            }
            var origin: CGPoint
            switch placement {
            case .left: origin = CGPoint(x: deck.minX - size.width, y: deck.maxY - size.height)
            case .right: origin = CGPoint(x: deck.maxX, y: deck.maxY - size.height)
            case .above: origin = CGPoint(x: deck.minX, y: deck.maxY)
            case .below: origin = CGPoint(x: deck.minX, y: deck.minY - size.height)
            }
            if isSpeaker, size.height > deck.height { origin.y = deck.minY }
            return origin
        }

        enum Role: Sendable { case playlist, library, other }
        enum Placement: Sendable { case left, above, right, below }

        /// A form's `Placement` in `Schema.xml`: `value` the side of its master it opens on (0 left,
        /// 1 above, 2 right, 3 below), `margins` (l, t, r, b) its offsets. A window beside the master
        /// stands `margins.t` below the master's top (Vilma M-212C's right speaker, -626: level with
        /// the deck's bottom); one above or below is centred on it, `margins.b` or `margins.t` clear
        /// of it (K-2's open glass lid and Sharp GF-777's handle stand on the deck).
        struct DeclaredPlacement: Equatable, Sendable {
            let side: Placement
            /// Down from the master's top, for a window beside it; the gap to it, above or below.
            let offset: CGFloat

            init?(_ node: AIMPNode?) {
                guard let node, let value = node["value"].flatMap(Int.init) else { return nil }
                let sides: [Placement] = [.left, .above, .right, .below]
                guard sides.indices.contains(value) else { return nil }
                let margins = AIMPNode.numbers(node["margins"] ?? "")
                side = sides[value]
                guard margins.count == 4 else { offset = 0; return }
                switch side {
                case .left, .right: offset = CGFloat(margins[1])
                case .above: offset = CGFloat(margins[3])
                case .below: offset = CGFloat(margins[1])
                }
            }
        }
    }

    let archive: AIMPSkinArchive
    let schema: AIMPNode?
    let mainForm: AIMPNode
    let companions: [Companion]
    /// `Schema.xml`'s resources by `ID`: each item's `property` children by name.
    let resources: [String: [String: AIMPNode]]
    /// The `.lng` strings for `@Lng:N;` captions: the user's language over English (`AIMPSkinLanguage`).
    let strings: [String: String]
    /// Decoded images by lowercased entry name; DPI variants (`-120`, `-144`…) are left out.
    let images: [String: AIMPSkinImage]
    let findings: [AIMPSkinFinding]
    /// Every script, compiled once as the skin loads (off the main thread): scripts run every
    /// frame while playing.
    let scripts: AIMPSkinScript.Library
    /// What the forms and `Schema.xml` declare, by name, built as the skin loads.
    let index: AIMPSkinIndex
    /// Covers blurred for a `CoverArtDisplay`'s `BlurLevel`, kept while the skin is.
    let blurredCovers = AIMPSkinBlurredCovers()
    /// Each window's natural size, by form name (the main form's is ""), measured as the skin loads.
    fileprivate(set) var naturalSizes: [String: CGSize] = [:]

    /// The natural size of form `name` (nil: the main form).
    func naturalSize(form name: String?) -> CGSize? { naturalSizes[name ?? ""] }

    var name: String { archive.name }

    /// The companions that hold `role`'s list (or none of them, for `.other`), docked or not.
    func companions(_ role: Companion.Role) -> [Companion] { companions.filter { $0.role == role } }

    /// The form called `name`; the main form for nil.
    func form(_ name: String?) -> AIMPNode? {
        guard let name else { return mainForm }
        return companions.first { $0.name == name }?.form
    }

    /// The resource `reference` names, through its aliases: `links` a script repointed, read before
    /// the skin's own, and a `Resource` holding no value that names another resource, by `link`
    /// (Vega MP-120's `Skin.BodyFace_` → `Skin.BodyFace_4`, its cassette sticker) or by `ID` (Soot's
    /// `clrTintFAB` → `clrTintFAB.D`). `id`: the name reached; `node`: its `Resource`, nil where the
    /// name is no resource (an image entry named directly, a font of AIMP's own theme); `chain`: each
    /// `Resource` passed on the way, the last first-named (a font's own settings override the one
    /// it names: Tascam Fireone's `Skin.Fonts.Header.SelectedFocused`, `Skin.Fonts.Common.Title` in
    /// white). One resolver for images, colours and fonts.
    static func resource(_ reference: String?, in resources: [String: [String: AIMPNode]], links: [String: String] = [:])
        -> (id: String, node: AIMPNode?, chain: [AIMPNode])? {
        guard var name = reference, !name.isEmpty else { return nil }
        var chain: [AIMPNode] = []
        for _ in 0..<8 {
            if let link = links[name] {
                name = link
                continue
            }
            guard let node = resources[name]?["Resource"] else { return (name, nil, chain) }
            chain.insert(node, at: 0)
            let holdsValue = !(node["value"] ?? "").isEmpty || node.named["Value"] != nil
            // One naming itself is itself (M5's `Skin.Fonts.Buttons.Dark`).
            guard !holdsValue, let alias = node["link"] ?? node.named["ID"]?["value"], !alias.isEmpty, alias != name
            else { return (name, node, chain) }
            name = alias
        }
        return nil
    }

    /// The image a skin, texture or resource reference names (`resource(_:in:links:)`): the entry
    /// is the resource's `value`, else the name itself, as `<name>.img` or `<name>Resource.img`
    /// (`.acs4`'s naming). `links` are aliases a script repointed.
    func image(_ reference: String?, links: [String: String] = [:]) -> AIMPSkinImage? {
        guard let (id, node, _) = Self.resource(reference, in: resources, links: links) else { return nil }
        let name = node?["value"].flatMap { $0.isEmpty ? nil : $0 } ?? id
        return images[(name + ".img").lowercased()] ?? images[(name + "Resource.img").lowercased()]
    }

    /// A `TACLResourceColor` by `ID`, as ARGB, through its aliases (`resource(_:in:links:)`).
    /// `clrNone` and unknown IDs are nil.
    static func color(_ reference: String?, in resources: [String: [String: AIMPNode]], links: [String: String] = [:]) -> UInt32? {
        guard let resource = Self.resource(reference, in: resources, links: links)?.node,
              let argb = (resource.named["Value"] ?? resource.child("property")).flatMap({ $0["value"] }).flatMap({ Int64($0) })
        else { return nil }
        return UInt32(truncatingIfNeeded: argb)
    }

    /// A `Color` property's ARGB (`AIMPSkinColor`), through the resource aliases a script repointed.
    /// AIMP 3.0's and AIMP 2's Delphi colours are ARGB by the time their forms are read (`AIMPSkinLegacy`).
    func color(_ color: AIMPSkinColor?, links: [String: String] = [:]) -> UInt32? {
        switch color {
        case .argb(let argb): return argb
        case .resource(let name): return Self.color(name, in: resources, links: links)
        case nil: return nil
        }
    }
}

/// Artwork blurred by a `CoverArtDisplay`'s `BlurLevel` (Soot's backdrop): the same cover blurs the
/// same way every frame, so the last few are kept, one set per skin (`AIMPSkinCache`).
final class AIMPSkinBlurredCovers: Sendable {
    private let made = AIMPSkinCache<Key, Blurred>(limit: 4)

    /// A cover by identity: the entry holds the cover, so no other picture takes its identity while
    /// the entry is kept.
    private struct Key: Hashable, Sendable {
        let cover: ObjectIdentifier
        let level: Double
    }

    private struct Blurred: Sendable {
        let cover: CGImage
        let image: CGImage?
    }

    /// `cover` at `level`, as `blur` makes it, made once.
    func image(_ cover: CGImage, level: Double, blur: () -> CGImage?) -> CGImage? {
        made.value(Key(cover: ObjectIdentifier(cover), level: level)) { Blurred(cover: cover, image: blur()) }.image
    }
}

/// A skin font (`TASEFont`): its face, pixel height, weight and ARGB colour.
struct AIMPSkinFont: Equatable, Sendable {
    var name: String
    var height: Int
    var bold: Bool
    var color: UInt32
    /// The `TASEFont` resource it was read from, and what that gave, which a script may repoint
    /// (`resolved(in:links:)`).
    var resource: Resource? = nil

    struct Resource: Equatable, Sendable {
        let id: String
        let name: String
        let height: Int
        let bold: Bool
        let color: UInt32
    }

    /// As drawn, through the resource aliases a script repointed (M5's and Soot's themes): what the
    /// resource gave comes from the one it now names; what the skin set over it stays.
    func resolved(in resources: [String: [String: AIMPNode]], links: [String: String]) -> AIMPSkinFont {
        guard let resource, !links.isEmpty, let chain = AIMPSkin.resource(resource.id, in: resources, links: links)?.chain,
              !chain.isEmpty else { return self }
        let now = AIMPSkinFont(resource: chain)
        var font = self
        if name == resource.name { font.name = now.name }
        if height == resource.height { font.height = now.height }
        if bold == resource.bold { font.bold = now.bold }
        if color == resource.color { font.color = now.color }
        return font
    }

    /// Points, from AIMP's pixel height.
    var pointSize: CGFloat { CGFloat(max(8, (Double(height) * 0.8).rounded())) }

    /// The face, bold when asked; one the Mac lacks (`Segoe UI`, `Tahoma`) falls back to the system
    /// font. Made once per face, size and weight: text is set many times a frame.
    var ctFont: CTFont {
        let key = Face(name: name, size: pointSize, bold: bold)
        if let made = Self.faces.withLockUnchecked({ $0[key] }) { return made }
        let font = CTFontCreateWithName(name as CFString, pointSize, nil)
        let face: CTFont
        if (CTFontCopyFamilyName(font) as String) != name {
            face = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, pointSize, nil) ?? font
        } else {
            face = bold ? CTFontCreateCopyWithSymbolicTraits(font, pointSize, nil, .traitBold, .traitBold) ?? font : font
        }
        Self.faces.withLockUnchecked { $0[key] = face }
        return face
    }

    private struct Face: Hashable {
        let name: String
        let size: CGFloat
        let bold: Bool
    }

    /// The faces made, shared by every skin (CTFont is immutable and safe across threads).
    private static let faces = OSAllocatedUnfairLock<[Face: CTFont]>(uncheckedState: [:])
}

enum AIMPSkinLoader {
    /// The production entry point: leaves the caller's executor before the file is touched.
    static func load(file: URL) async throws -> AIMPSkin {
        try await Task.detached(priority: .userInitiated) {
            try load(contentsOf: file)
        }.value
    }

    static func load(contentsOf file: URL) throws -> AIMPSkin {
        guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else {
            throw AIMPSkinFinding(.notAnArchive, "'\(file.lastPathComponent)' cannot be read.")
        }
        guard size <= AIMPSkinPolicy.fileBytes else {
            throw AIMPSkinFinding(.fileTooLarge, "\(size) bytes, more than \(AIMPSkinPolicy.fileBytes).")
        }
        guard let data = try? Data(contentsOf: file, options: .alwaysMapped) else {
            throw AIMPSkinFinding(.notAnArchive, "'\(file.lastPathComponent)' cannot be read.")
        }
        return try load(data: data)
    }

    /// `languages`: the preferred languages, most wanted first, that `@Lng:N;` captions are read in.
    static func load(data: Data, languages: [String] = Locale.preferredLanguages) throws -> AIMPSkin {
        let archive = try AIMPSkinArchive.read(data)
        // Every document is read through one reader, which keeps what does not read as a finding.
        let documents = AIMPSkinDocuments(archive)

        // AIMP 3.0 and AIMP 2 skins have no form documents: their form is read from `main.ini` once
        // the pictures it is sized by are read.
        var parsedForm = archive.isLegacy ? nil
            : try documents.throwing("AIMPMainForm.xml", missing: "The skin has no AIMPMainForm.", documents.node)
        let schema = documents.node("Schema.xml")

        var resources: [String: [String: AIMPNode]] = [:]
        for item in schema?.child("properties")?.child("resources")?.children("item") ?? [] {
            let properties = item.named
            if let id = properties["ID"]?["value"] { resources[id] = properties }
        }

        let strings = AIMPSkinLanguage.strings(in: documents, preferred: languages)

        // Pictures are read from their headers here and decode when first drawn, within one
        // budget of resident pixels (`AIMPSkinPixelBudget`). DPI variants end in -120, -144, -168,
        // -192. Older skins name the same pictures `.myimg` (Sony TC-MR2), AIMP 3.0's BMP skins
        // `.bmp`, laid out by `main.ini`; each is filed as `.img`, which wins, then `.myimg`. AIMP 2's
        // bitmaps are laid out as its form is read (`AIMPSkinLegacy.AIMP2`).
        let budget = AIMPSkinPixelBudget()
        let layouts = archive.format != .acsp ? archive.mainINI.map(AIMPSkinLegacy.bitmapLayouts) ?? [:] : [:]
        var images: [String: AIMPSkinImage] = [:]
        for (name, entry) in archive.entries.sorted(by: { $0.key < $1.key }) {
            guard let ext = [".img", ".myimg", ".bmp"].first(where: name.hasSuffix), archive.isLegacy || ext != ".bmp" else { continue }
            let stem = String(name.dropLast(ext.count))
            if ext != ".img", archive.entries[stem + ".img"] != nil { continue }
            if ext == ".bmp", archive.entries[stem + ".myimg"] != nil { continue }
            if let dash = stem.lastIndex(of: "-"), Int(stem[stem.index(after: dash)...]) != nil { continue }
            do {
                let payload = try archive.payload(entry)
                let source = { try archive.payload(entry) }
                let image = ext == ".bmp"
                    ? try AIMPSkinImage(bitmap: payload, name: entry.name, layout: layouts[stem] ?? .init(), budget: budget, source: source)
                    : try AIMPSkinImage(payload, name: entry.name, budget: budget, source: source)
                let frame = image.frameSize
                guard frame.width <= CGFloat(AIMPSkinPolicy.imageSide), frame.height <= CGFloat(AIMPSkinPolicy.imageSide) else {
                    throw AIMPSkinFinding(.imageTooLarge, "\(entry.name) has \(Int(frame.width))×\(Int(frame.height)) frames.")
                }
                guard image.width * image.height <= budget.limit else {
                    throw AIMPSkinFinding(.pixelBudgetExceeded,
                                          "\(entry.name) alone has \(image.width * image.height) pixels, more than \(budget.limit).")
                }
                images[stem + ".img"] = image
            } catch let finding as AIMPSkinFinding where finding.code == .entryUnreadable {
                documents.record(finding)
            }
        }

        // AIMP 3.0's and AIMP 2's forms come from `main.ini`, with AIMP 2's equalizer as a window of its own.
        var companions: [AIMPSkin.Companion] = []
        if let ini = archive.mainINI {
            let read = try AIMPSkinLegacy.forms(documents, ini: ini, images: images)
            parsedForm = read.main
            companions = read.companions
            images = read.images
        }
        guard let mainForm = parsedForm else {
            throw AIMPSkinFinding(.noMainForm, "The skin's layout and main.ini give no form.")
        }
        var scriptFindings: [AIMPSkinFinding] = []
        let scripts = AIMPSkinScript.Library(archive, findings: &scriptFindings)
        scriptFindings.forEach(documents.record)
        // `Schema.xml` lists the forms; the ones NullPlayer has its own window for stay out, and so
        // does TC-MR2's `Menu`, a popup its MENU key stands in for with NullPlayer's. The skin's own
        // playlist and library windows open, over NullPlayer's playlist and library.
        // A skin's own cover window (Tascam CD-RW2000's, AIMP-Cassette's) has no NullPlayer twin: it opens.
        for entry in schema?.child("forms")?.children("form") ?? [] {
            guard let name = entry["name"], entry["master"] == "AIMPMainForm",
                  !AIMPFormRole(name).isNullPlayers,
                  let form = documents.node(name + ".xml") else { continue }
            let props = entry.properties.mapValues { $0["value"] ?? "" }
            let links = Set(form.descendants().compactMap { $0["link"] })
            let role: AIMPSkin.Companion.Role = links.contains("MLTable") || links.contains("MLGroupingTree") ? .library
                : links.contains("Playlist") ? .playlist : .other
            let title = props["DisplayName"].map { AIMPSkinLanguage.expanded($0, strings: strings) } ?? AIMPFormRole.title(ofForm: name, role: role)
            var companion = AIMPSkin.Companion(name: name, title: title, form: form,
                                               initiallyVisible: props["InitialVisible"] != "False", role: role)
            companion.declaredPlacement = .init(entry.properties["Placement"])
            companions.append(companion)
        }
        // A dock site may hold one of the forms NullPlayer has its own window for (Acubens'
        // visualization and file info): it joins the companions, shown only while docked.
        let sites = archive.isLegacy ? [:] : AIMPSkinDockSites.sites(in: mainForm) { name in
            if let companion = companions.first(where: { $0.name == name }) { return companion.form }
            guard let form = documents.node(name + ".xml") else { return nil }
            var companion = AIMPSkin.Companion(name: name, title: AIMPFormRole.title(ofForm: name, role: .other), form: form,
                                               initiallyVisible: true, role: .other)
            companion.opensWindow = false
            companions.append(companion)
            return form
        }
        let index = AIMPSkinIndex(main: mainForm, companions: companions, schema: schema, sites: sites,
                                  resources: resources, strings: strings)
        var skin = AIMPSkin(archive: archive, schema: schema, mainForm: mainForm, companions: companions, resources: resources,
                        strings: strings, images: images, findings: documents.findings, scripts: scripts, index: index)
        // Each window's natural size, measured with trial frames here, off the main thread, rather
        // than when the window shows the skin.
        skin.naturalSizes = Dictionary(uniqueKeysWithValues: ([nil] + companions.map(\.name)).compactMap { form in
            AIMPSkinRenderer.naturalSize(skin, form: form).map { (form ?? "", $0) }
        })
        return skin
    }
}
