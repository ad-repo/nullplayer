import CoreGraphics
import Foundation

/// The loading limits for AIMP skins (`.acs5`, `.acs4`, `.acs3`, `.acs4proj`, AIMP 2's `.acs`). Never relax one to make a
/// skin load; argue the threat instead. The format is reverse-engineered: see
/// `skills/aimp-skin-guide/reference/format.md`.
enum AIMPSkinPolicy {
    /// AM0002. Catalog 4K skins reach ~600 MB; the file is memory-mapped, not read.
    static let fileBytes = 1_024 * 1_024 * 1_024
    /// AM0003. Soot has 2,958 entries (five DPI variants of every image).
    static let entries = 32_768
    /// AM0005. One inflated entry, or a whole `.acs4` body. Technics SL-1200's body is 539 MB
    /// (high-resolution artwork in an `.acs4`), measured 2026-10-31.
    static let inflatedBytes = 1_024 * 1_024 * 1_024
    /// AM0006, per frame: animation filmstrips are wide by design (Vega MP-120's tape reel is
    /// 58,580 px of 182 px frames). Memory is AM0007's job.
    static let imageSide = 16_384
    /// AM0007: the decoded pixels a skin holds at once (`AIMPSkinPixelBudget`), 1 GB of RGBA; one
    /// image over it does not load. Pictures decode when first drawn and the least recently drawn
    /// go first, so a skin's pictures may sum past it (Mayak-203's 1.1 Gpx, alternative reels of
    /// which one set shows; its window draws ~240 Mpx).
    static let decodedPixels = 256 * 1_024 * 1_024
    /// AM0009. Nesting and node count of one binary or text XML document.
    static let xmlDepth = 256
    static let xmlNodes = 1_000_000
}

/// What a `.zip` of skins is held to before a byte of it is written (`AIMPSkinImporter.unzipSkins`):
/// the catalog ships each skin in one. An entry over `entryBytes` is AM0002, the rest AM0012.
struct AIMPSkinZipLimits {
    /// Every entry of the zip, skins or not.
    var entries = AIMPSkinPolicy.entries
    /// One skin: the loader's own file limit.
    var entryBytes = UInt64(AIMPSkinPolicy.fileBytes)
    /// Every skin taken from it.
    var totalBytes: UInt64 = 4 * 1_024 * 1_024 * 1_024
    /// Past `ratioFloorBytes`, a skin that expands more than this many times is a bomb: skins are
    /// compressed already (zlib bodies, XORed entries), so a real one hardly squashes (`.wmz`
    /// Amendment 1's floor and ratio, as Audion's).
    var ratio: UInt64 = 200
    var ratioFloorBytes: UInt64 = 1 * 1_024 * 1_024

    static let production = AIMPSkinZipLimits()
}

/// How a window is measured where the skin does not say (`AIMPSkinRenderer.naturalSize`): AIMP's
/// own behaviour as the corpus shows it, not limits.
extension AIMPSkinPolicy {
    /// A texture at least this each way is a picture the window is sized by, not a tile (Technicss'
    /// whole-player `Deck`, RealPlayer 11's 210-px cover page); a 1-px gradient strip is a tile.
    static let pictureSide: CGFloat = 64
    /// A sizable main form with no picture opens at the least its docked parts allow when that is a
    /// window at least this each way (Unsquareable's).
    static let leastWindowSide: CGFloat = 64
    /// A playlist or library window leaves its list this tall (TASCAM CD-RW750's playlist under its
    /// cover-art panel); a list a pixel short of it, a rounded share, is left as it is.
    static let listRoom: CGFloat = 160
    /// It grows toward that in a few steps, as panels may take the first growth, and no taller
    /// than three times its start or 800 px (a list in a fixed-height panel never grows).
    static let listGrowthSteps = 4
    static let listGrowthFactor: CGFloat = 3
    static let listGrowthCeiling: CGFloat = 800

    /// Whether `image` is a picture a window is sized by (`pictureSide`).
    static func isPicture(_ image: AIMPSkinImage) -> Bool {
        image.hasPixels && image.frameSize.width >= pictureSide && image.frameSize.height >= pictureSide
    }
}

/// The stable `AM####` codes. Meaning is fixed once written; wording may improve.
enum AIMPSkinDiagnosticCode: String, Sendable {
    case notAnArchive = "AM0001"
    case fileTooLarge = "AM0002"
    case tooManyEntries = "AM0003"
    case entryOutOfBounds = "AM0004"
    case inflatedTooLarge = "AM0005"
    case imageTooLarge = "AM0006"
    case pixelBudgetExceeded = "AM0007"
    /// A warning: the entry is skipped.
    case entryUnreadable = "AM0008"
    case xmlMalformed = "AM0009"
    case noMainForm = "AM0010"
    /// An `ACS` container this engine does not read (an `ACSP` version other than 2 or 3).
    case unsupportedFormat = "AM0011"
    /// A `.zip` import past `AIMPSkinZipLimits`, or a skin in it failing its CRC or size.
    case zipRejected = "AM0012"
}

/// One finding. A fatal one is thrown; warnings ride on the loaded skin.
struct AIMPSkinFinding: LocalizedError, Hashable, CustomStringConvertible, Sendable {
    let code: AIMPSkinDiagnosticCode
    let message: String

    init(_ code: AIMPSkinDiagnosticCode, _ message: String) {
        self.code = code
        self.message = message
    }

    var description: String { "[\(code.rawValue)] \(message)" }
    var errorDescription: String? { description }
}
