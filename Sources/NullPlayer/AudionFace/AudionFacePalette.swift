import AppKit

/// The colours NullPlayer's own windows wear beside a face.
enum AudionFacePalette {
    /// A dark neutral, until a face-derived palette exists (Phase 5). App-authored, never another
    /// family's chrome.
    static let neutral = SkinnedSurfaceStyle(roles: SkinnedSurfaceRoles(
        background: NSColor(calibratedWhite: 0.12, alpha: 1),
        text: NSColor(calibratedWhite: 0.78, alpha: 1),
        currentText: .white,
        selectionBackground: NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.62, alpha: 1),
        selectionText: .white,
        treeText: NSColor(calibratedWhite: 0.78, alpha: 1),
        treeSelection: NSColor(calibratedRed: 0.22, green: 0.36, blue: 0.62, alpha: 1)))
}
