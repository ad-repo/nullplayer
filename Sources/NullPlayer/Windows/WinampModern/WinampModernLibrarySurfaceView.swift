import AppKit

/// The real library browser, embedded in a `.wal` skin's holder: the shared
/// `EmbeddedLibraryBrowserSurface`, plus the palette the skin engine hands it. Every other member of
/// `WinampModernLibrarySurface` is the shared surface's own.
final class WinampModernLibrarySurfaceView: EmbeddedLibraryBrowserSurface, @preconcurrency WinampModernLibrarySurface {
    func applyPalette(_ palette: WasabiPalette) {
        // The browser used to paint with the classic skin's colours and bitmap font, which inside a
        // `.wal` window is a foreign UI coloured by a skin the user is not even looking at. It now
        // draws from the loaded skin's own palette instead (Phase 16).
        applyStyle(WinampModernSurfaceStyle(palette: palette))
    }
}
