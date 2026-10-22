import CoreGraphics
import Foundation

/// A cover image a skin's script looks for **beside the playing file**, answered with the album art
/// NullPlayer already has — for a local file and a stream alike.
///
/// Skins older than `<AlbumArt>` find the cover themselves, and the corpus has three families of
/// script for it. Deimos's `cover.maki` (Mac OS X Panther, Vortex, 1010 Fullscreen…) takes
/// `getPath(getPlayItemString())`, drops its first seven characters, appends `cover.jpg`,
/// `folder.jpg`, `front.jpg`… and tests each with an animated layer's `getLength()`. The larger
/// family (Drone, CNY, Styx, Core-X5, MIPOD, Ebonite, Winamp-2006 and their notifiers) probes each
/// candidate with `Map.loadMap(path)` and `getValue(0,0) > 0` or the map's `getWidth()`, then sets
/// the hit as a layer's `image=`. A third form names **the media file itself**: Skin Consortium's
/// `SC:Cover` (Ebonite, MusicshowB) does `Map.loadMap(PlEdit.getFileName(i))` and sizes its
/// `<AlbumArt>` holders from that map — Winamp's loader answers a media file with its embedded art,
/// and here it answered nothing, so the holders came out 0x0 and the window stayed blank.
/// Winamp read all of these from disk. A skin may never read the host filesystem here, so nothing
/// is opened: a request that names an image in the playing track's folder, or the playing file, **is**
/// a request for the cover, and the cover is the host's artwork.
enum WinampModernTrackFolderImage {

    /// Whether `value` names the cover of the track at `trackPath`: an image in its folder, or the
    /// track's own file.
    ///
    /// Scripts only ever *cut from the left* of the folder they were handed — `cover.maki` drops
    /// seven characters, others strip `file://` — so the request's folder is a **tail** of the
    /// track's. Everything else is normalised away on both sides, because these paths come from
    /// string arithmetic rather than from a filesystem: either separator, any case, a `file:` or URL
    /// scheme kept or chopped, `//` collapsed (Foundation's own path helpers turn `https://` into
    /// `https:/`, which is why none are used here), percent-encoding in or out.
    static func names(_ value: String, trackPath: String) -> Bool {
        let file = normalisedFolder(withoutQuery(trackPath))
        if !file.isEmpty, normalisedFolder(withoutQuery(value)) == file { return true }
        guard let request = split(value), imageExtensions.contains(request.leafExtension),
              let track = split(trackPath) else { return false }
        let folder = normalisedFolder(request.folder)
        let trackFolder = normalisedFolder(track.folder)
        return !folder.isEmpty && trackFolder.hasSuffix(folder)
    }

    /// What stands in for the cover while NullPlayer is still fetching it: square, because covers
    /// are, so a script that sizes its panel from `getWidth()`/`getHeight()` lays out the shape the
    /// real art will have; and opaque white, so a `getValue(0,0) > 0` probe reads "found".
    static let loadingStandIn: CGImage? = {
        let side = 300
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }()

    private static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "bmp", "gif"]

    private static func split(_ path: String) -> (folder: String, leafExtension: String)? {
        let unified = path.replacingOccurrences(of: "\\", with: "/")
        guard let slash = unified.lastIndex(of: "/") else { return nil }
        let leaf = unified[unified.index(after: slash)...]
        let leafExtension = leaf.lastIndex(of: ".").map { String(leaf[leaf.index(after: $0)...]) } ?? ""
        return (String(unified[..<slash]), leafExtension.lowercased())
    }

    /// A playlist row's file name can carry a stream URL's query (a server token); the host's own
    /// `trackPath` never does.
    private static func withoutQuery(_ path: String) -> String {
        path.firstIndex(of: "?").map { String(path[..<$0]) } ?? path
    }

    private static func normalisedFolder(_ folder: String) -> String {
        var text = (folder.removingPercentEncoding ?? folder).lowercased()
        while text.contains("//") { text = text.replacingOccurrences(of: "//", with: "/") }
        if text.hasPrefix("file:") { text.removeFirst("file:".count) }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

extension WinampModernHost {
    func isTrackFolderImage(_ value: String) -> Bool {
        WinampModernTrackFolderImage.names(value, trackPath: trackPath)
    }

    /// The image a cover request answers with: the artwork, or the stand-in while it is fetched.
    /// `nil` — "not found", so the skin shows its own placeholder — only when there is none to come.
    func trackFolderCover(forImage value: String) -> CGImage? {
        guard isTrackFolderImage(value) else { return nil }
        if let albumArtwork { return albumArtwork }
        return isArtworkLoading ? WinampModernTrackFolderImage.loadingStandIn : nil
    }
}

extension WinampModernTrackFolderImage {
    /// Who asked, so a late cover can be offered again to them and only them.
    struct Seekers {
        fileprivate var programs: [ObjectIdentifier: MakiProgram] = [:]
        fileprivate var lastRedelivered: String?
    }
}

extension WinampModernScriptRuntime {
    /// Record that `program` asked for `value`, when `value` is a cover beside the playing file.
    func noteCoverRequest(_ value: String, by program: MakiProgram) {
        guard host.isTrackFolderImage(value) else { return }
        coverSeekers.programs[ObjectIdentifier(program)] = program
    }

    /// A script looks once, on the title change, and the art can land after it looked — a stream's
    /// cover always does, a local file's often. So when the art for the playing track arrives, the
    /// scripts that went looking hear `onTitleChange` once more and find it. Only them: a skin-wide
    /// replay would reset `beat.m`'s running VU maximum mid-song. Once per track, so a script that
    /// finds nothing even then is not asked forever.
    func redeliverTitleToCoverSeekers() {
        guard !coverSeekers.programs.isEmpty, host.albumArtwork != nil,
              coverSeekers.lastRedelivered != host.trackPath else { return }
        coverSeekers.lastRedelivered = host.trackPath
        _ = try? dispatch(target: MakiObjectReference(.system), event: "ontitlechange",
                          arguments: [.string(host.trackDisplayTitle)],
                          in: Array(coverSeekers.programs.values))
    }
}
