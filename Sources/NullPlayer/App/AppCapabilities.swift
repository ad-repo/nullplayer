import Foundation

/// A feature that a product *edition* may choose not to support.
///
/// The full (default) edition supports everything. A downstream edition can
/// narrow the set by building with the `EDITION_CUSTOM` compilation condition
/// and supplying an `EditionPolicy` type (see `AppCapabilities.supports`).
///
/// Add cases here for any capability an edition might want to turn off. Keep
/// the cases named after the *feature*, not after any particular edition — this
/// enum is edition-agnostic on purpose.
enum AppFeature {
    case classicMode
    case modernMode
    case metalMode
}

/// Edition-agnostic capability seam.
///
/// This is the *only* place the app asks "does this edition support X?". The
/// default build answers "yes" to everything, so introducing the seam is inert
/// for the full edition. A downstream edition activates its own policy purely by
/// defining `EDITION_CUSTOM` and adding an `EditionPolicy` — upstream never needs
/// to know which edition that is.
enum AppCapabilities {
    static func supports(_ feature: AppFeature) -> Bool {
        #if EDITION_CUSTOM
        return EditionPolicy.supports(feature)
        #else
        return true
        #endif
    }
}
