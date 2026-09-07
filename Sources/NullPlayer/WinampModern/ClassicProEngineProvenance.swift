import CryptoKit
import Foundation

/// The one ClassicPro engine build this app has been tested against.
///
/// The engine is third-party, proprietary and user-supplied, so it cannot be committed as a fixture —
/// these digests are all we can keep. They verify *nothing* on their own: the check only runs against
/// the user's own copy, at import time.
///
/// Re-deriving them, should a second build ever be blessed:
///   * `installerSHA256` — `shasum -a 256 ClassicPro_2.01.exe`.
///   * `engineTreeSHA256` — the value `ClassicProEngineStore.validate` computes as
///     `ClassicProEngineInfo.contentHash`: SHA-256 over the sorted (path, bytes) of the engine tree.
///     Import the installer and read `.engine-info.json`, rather than recomputing it by hand.
enum ClassicProKnownGood {
    /// `ClassicPro_2.01.exe`, 1 370 091 bytes. Confirmed identical across two independent downloads.
    static let installerSHA256 = "c118937b6b80c1582cfc8dbb3c1cb7f038b9904c321158910fd29a141159e939"

    /// The 309-file engine tree that installer extracts to, as observed after the NSIS last-wins fix
    /// (before it, a first-wins reader produced `53a9ff68…` with a stubbed PlaylistPro `_v1`).
    ///
    /// A tree hash other than this one is a signal to **investigate**, never to update this constant:
    /// with the installer digest matching, a changed tree means our extractor changed behavior.
    static let engineTreeSHA256 = "265193d8c20a0fedbad6ceba8e352c3e378a097f9faf5e13abbe38d1800e3956"
}

/// How an installed engine compares to the tested build.
enum ClassicProProvenanceVerdict: String, Equatable {
    /// The extracted tree is byte-for-byte the build we test against.
    case knownGood
    /// Some other build, or a source we cannot identify. Ordinary, and allowed with confirmation.
    case unrecognized
    /// The tested installer extracted to an *unexpected* tree — i.e. our own extractor changed.
    case treeMismatch
}

enum ClassicProDigests {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The tree hash is the authority. A recognized installer that extracts to the wrong tree is the
    /// exact regression this check exists to catch, so it must never be allowed to vouch for the tree.
    static func verdict(installerDigest: String?, engineTreeSHA256: String) -> ClassicProProvenanceVerdict {
        if engineTreeSHA256 == ClassicProKnownGood.engineTreeSHA256 { return .knownGood }
        if installerDigest == ClassicProKnownGood.installerSHA256 { return .treeMismatch }
        return .unrecognized
    }
}
