import Foundation

/// The loading limits, the executable source of truth for `docs/audion-face/phase-0-decision-record.md`
/// § *Loading limits*. Never relax one to make a face load; amend the record, arguing the threat.
///
/// Scope, as the record's *What each limit covers* says: `faceFiles` and `faceBytes` bound the walk
/// and count every entry in it. `imageSide`, `imageBytes` and `decodedPixels` bound decode memory and
/// time, so they apply only to the images the loader decodes.
enum AudionFacePolicy {
    /// AUD0003.
    static let indexBytes = 256 * 1_024
    /// AUD0004.
    static let imageSide = 4_096
    static let imageBytes = 8 * 1_024 * 1_024
    /// AUD0005. Entries, not only regular files: a directory or a FIFO costs the walk the same.
    static let faceFiles = 2_000
    static let faceBytes = 64 * 1_024 * 1_024
    /// AUD0007.
    static let pictIDs = 0...99_999
    /// AUD0013: a rect edge outside this is malformed, so no rect arithmetic can overflow. The corpus's
    /// largest is 1,318.
    static let coordinates = -65_536...65_536
    /// A font size outside this reads as absent (Helvetica 12, FaceKit's rule for a missing size), so
    /// text rasterizes into a bounded image. The corpus spans 0–90.
    static let fontSizes = 0...1_024
    /// AUD0011, summed over the distinct files decoded. 64 Mpx is 256 MB of RGBA.
    static let decodedPixels = 64 * 1_024 * 1_024
}

/// AUD0010's bounds, set in Phase 1 under the `.wmz` Amendment 1 rule: absolute expanded bytes
/// bound the threat, and the ratio test applies only above a size floor.
///
/// Measured against Panic's distribution (`Faces - 2021-01-05.zip`, 2026-10-08): 81,111 entries,
/// 235,586,373 bytes expanded, the largest entry 613,876 bytes, the worst ratio 52:1 and no entry
/// over 1 MiB at all. The bounds admit that whole archive as one import with about 1.6× and 2.2×
/// headroom. An entry past `entryBytes` could never belong to a loadable face (`faceBytes`).
/// Settable only so a test can reach a bound without building a huge archive.
struct AudionFaceZipLimits {
    var entries = 131_072
    var totalBytes: UInt64 = 512 * 1_024 * 1_024
    var entryBytes = UInt64(AudionFacePolicy.faceBytes)
    var ratio: UInt64 = 200
    var ratioFloorBytes: UInt64 = 1 * 1_024 * 1_024

    static let production = AudionFaceZipLimits()
}
