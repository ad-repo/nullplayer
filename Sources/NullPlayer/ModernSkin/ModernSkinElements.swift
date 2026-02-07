import AppKit

/// Catalog of all skinnable elements in the modern UI system.
/// Each element has an ID, default geometry, valid states, and whether it supports animation.
///
/// This is the modern equivalent of `SkinElements.swift` but completely independent.
/// Element IDs are used as keys in `skin.json` element overrides and as image file name prefixes.
///
/// Coordinate system: bottom-left origin (standard macOS). Y increases upward.
/// All rects are in the 275x116 base coordinate space. The renderer scales by `scaleFactor`.
enum ModernSkinElements {
    
    // MARK: - Constants
    
    /// Base window size for the modern main window (unscaled)
    /// Matches classic Winamp dimensions for docking compatibility
    static let baseMainSize = NSSize(width: 275, height: 116)
    
    /// Scale factor for modern UI rendering
    static let scaleFactor: CGFloat = 1.25
    
    /// Scaled main window size
    static let mainWindowSize = NSSize(
        width: baseMainSize.width * scaleFactor,
        height: baseMainSize.height * scaleFactor
    )
    
    // MARK: - Element Definition
    
    struct Element {
        let id: String
        let defaultRect: NSRect
        let states: [String]
        let supportsAnimation: Bool
        
        init(_ id: String, _ rect: NSRect, states: [String] = ["normal"], animated: Bool = false) {
            self.id = id
            self.defaultRect = rect
            self.states = states
            self.supportsAnimation = animated
        }
    }
    
    // MARK: - Window Chrome
    
    static let windowBackground = Element("window_background", NSRect(x: 0, y: 0, width: 275, height: 116))
    static let windowBorder = Element("window_border", NSRect(x: 0, y: 0, width: 275, height: 116))
    
    // MARK: - Title Bar (top 14px)
    
    static let titleBar = Element("titlebar", NSRect(x: 0, y: 102, width: 275, height: 14))
    static let titleBarText = Element("titlebar_text", NSRect(x: 50, y: 102, width: 175, height: 14))
    
    /// Window control buttons (right side of title bar)
    static let btnClose = Element("btn_close", NSRect(x: 256, y: 104, width: 10, height: 10),
                                  states: ["normal", "pressed"])
    static let btnMinimize = Element("btn_minimize", NSRect(x: 232, y: 104, width: 10, height: 10),
                                     states: ["normal", "pressed"])
    static let btnShade = Element("btn_shade", NSRect(x: 244, y: 104, width: 10, height: 10),
                                  states: ["normal", "pressed"])
    
    // MARK: - Time Display (left side)
    
    /// Time display area -- region for 7-segment LED digits (to the right of status indicator)
    static let timeDisplay = Element("time_display", NSRect(x: 18, y: 68, width: 72, height: 26))
    
    /// Individual time digits -- 7-segment LED style, sized to match reference
    static let timeDigitSize = NSSize(width: 13, height: 20)
    static let timeColonSize = NSSize(width: 6, height: 20)
    
    // MARK: - Marquee / Info Panel (right side)
    
    /// Marquee display area (right side of upper display)
    static let marqueeBackground = Element("marquee_bg", NSRect(x: 93, y: 60, width: 174, height: 38))
    
    /// Info labels row (below marquee text, inside marquee panel)
    static let infoBitrate = Element("info_bitrate", NSRect(x: 95, y: 62, width: 55, height: 9))
    static let infoSampleRate = Element("info_samplerate", NSRect(x: 150, y: 62, width: 45, height: 9))
    static let infoStereo = Element("info_stereo", NSRect(x: 195, y: 62, width: 30, height: 9),
                                    states: ["off", "on"])
    static let infoMono = Element("info_mono", NSRect(x: 195, y: 62, width: 30, height: 9),
                                  states: ["off", "on"])
    static let infoCast = Element("info_cast", NSRect(x: 224, y: 62, width: 40, height: 9),
                                  states: ["off", "on"])
    
    // MARK: - Status Indicator (left of time display)
    
    /// Play/pause/stop status indicator (small icon to the left of time digits)
    static let statusPlay = Element("status_play", NSRect(x: 8, y: 72, width: 8, height: 10))
    static let statusPause = Element("status_pause", NSRect(x: 8, y: 72, width: 8, height: 10))
    static let statusStop = Element("status_stop", NSRect(x: 8, y: 72, width: 8, height: 10))
    
    /// Mini spectrum analyzer area (to the left of status)
    static let spectrumArea = Element("spectrum_area", NSRect(x: 10, y: 42, width: 60, height: 16),
                                      animated: true)
    
    // MARK: - Window Toggle Buttons (above seek bar, right side)
    
    static let btnEQ = Element("btn_eq", NSRect(x: 152, y: 42, width: 20, height: 14),
                               states: ["off", "on", "off_pressed", "on_pressed"])
    static let btnPlaylist = Element("btn_playlist", NSRect(x: 174, y: 42, width: 20, height: 14),
                                     states: ["off", "on", "off_pressed", "on_pressed"])
    static let btnLibrary = Element("btn_library", NSRect(x: 196, y: 42, width: 20, height: 14),
                                    states: ["off", "on", "off_pressed", "on_pressed"])
    static let btnProjectM = Element("btn_projectm", NSRect(x: 218, y: 42, width: 22, height: 14),
                                     states: ["off", "on", "off_pressed", "on_pressed"])
    static let btnSpectrum = Element("btn_spectrum", NSRect(x: 242, y: 42, width: 22, height: 14),
                                     states: ["off", "on", "off_pressed", "on_pressed"])
    
    // MARK: - Seek Bar (thin line spanning full width)
    
    static let seekTrack = Element("seek_track", NSRect(x: 8, y: 36, width: 259, height: 3))
    static let seekFill = Element("seek_fill", NSRect(x: 8, y: 36, width: 0, height: 3))
    static let seekThumb = Element("seek_thumb", NSRect(x: 8, y: 34, width: 6, height: 6),
                                   states: ["normal", "pressed"])
    
    // MARK: - Transport Buttons (bottom-left, 6 buttons)
    
    static let btnPrev = Element("btn_prev", NSRect(x: 6, y: 3, width: 28, height: 24),
                                 states: ["normal", "pressed", "disabled"])
    static let btnPlay = Element("btn_play", NSRect(x: 34, y: 3, width: 28, height: 24),
                                 states: ["normal", "pressed", "disabled"])
    static let btnPause = Element("btn_pause", NSRect(x: 62, y: 3, width: 28, height: 24),
                                  states: ["normal", "pressed", "disabled"])
    static let btnStop = Element("btn_stop", NSRect(x: 90, y: 3, width: 28, height: 24),
                                 states: ["normal", "pressed", "disabled"])
    static let btnNext = Element("btn_next", NSRect(x: 118, y: 3, width: 28, height: 24),
                                 states: ["normal", "pressed", "disabled"])
    static let btnEject = Element("btn_eject", NSRect(x: 146, y: 3, width: 28, height: 24),
                                  states: ["normal", "pressed"])
    
    // MARK: - Volume Slider (bottom-right, replaces old shuffle/repeat/cast buttons)
    
    static let volumeTrack = Element("volume_track", NSRect(x: 180, y: 12, width: 85, height: 3))
    static let volumeFill = Element("volume_fill", NSRect(x: 180, y: 12, width: 0, height: 3))
    static let volumeThumb = Element("volume_thumb", NSRect(x: 180, y: 10, width: 6, height: 6),
                                     states: ["normal", "pressed"])
    
    // MARK: - Playlist Window
    
    /// Playlist window size (same width as main window for docking; height expandable)
    static let playlistWindowSize = NSSize(
        width: baseMainSize.width * scaleFactor,
        height: baseMainSize.height * scaleFactor
    )
    
    /// Playlist window minimum size (width locked, height expandable)
    static let playlistMinSize = playlistWindowSize
    
    /// Playlist window shade mode height
    static let playlistShadeHeight: CGFloat = 18 * scaleFactor
    
    /// Playlist window title bar height
    static let playlistTitleBarHeight: CGFloat = 14 * scaleFactor
    
    /// Playlist window bottom bar height (ADD/REM/SEL/MISC/LIST buttons)
    static let playlistBottomBarHeight: CGFloat = 20 * scaleFactor
    
    /// Playlist window border width
    static let playlistBorderWidth: CGFloat = 3 * scaleFactor
    
    /// Playlist track row height
    static let playlistItemHeight: CGFloat = 15 * scaleFactor
    
    /// Playlist title bar element (per-window skinning)
    static let playlistTitleBar = Element("playlist_titlebar", NSRect(x: 0, y: 102, width: 275, height: 14))
    
    /// Playlist close button
    static let playlistBtnClose = Element("playlist_btn_close", NSRect(x: 256, y: 104, width: 10, height: 10),
                                          states: ["normal", "pressed"])
    
    /// Playlist shade button
    static let playlistBtnShade = Element("playlist_btn_shade", NSRect(x: 244, y: 104, width: 10, height: 10),
                                          states: ["normal", "pressed"])
    
    // MARK: - Spectrum Window
    
    /// Spectrum analyzer window size (same base as main window for docking compatibility)
    static let spectrumWindowSize = NSSize(
        width: baseMainSize.width * scaleFactor,
        height: baseMainSize.height * scaleFactor
    )
    
    /// Spectrum window minimum size
    static let spectrumMinSize = spectrumWindowSize
    
    /// Spectrum window shade mode height
    static let spectrumShadeHeight: CGFloat = 18 * scaleFactor
    
    /// Spectrum window title bar height
    static let spectrumTitleBarHeight: CGFloat = 14 * scaleFactor
    
    /// Spectrum window border width
    static let spectrumBorderWidth: CGFloat = 3 * scaleFactor
    
    /// Number of bars in the standalone spectrum window
    static let spectrumBarCount = 84
    
    /// Spectrum window title bar (same base geometry as main title bar, allows per-window skinning)
    static let spectrumTitleBar = Element("spectrum_titlebar", NSRect(x: 0, y: 102, width: 275, height: 14))
    
    /// Spectrum window close button (allows per-window skinning)
    static let spectrumBtnClose = Element("spectrum_btn_close", NSRect(x: 256, y: 104, width: 10, height: 10),
                                          states: ["normal", "pressed"])
    
    // MARK: - All Elements
    
    static let allElements: [Element] = [
        windowBackground, windowBorder,
        titleBar, titleBarText, btnClose, btnMinimize, btnShade,
        timeDisplay,
        marqueeBackground,
        infoBitrate, infoSampleRate, infoStereo, infoMono, infoCast,
        statusPlay, statusPause, statusStop,
        spectrumArea,
        btnEQ, btnPlaylist, btnLibrary, btnProjectM, btnSpectrum,
        seekTrack, seekFill, seekThumb,
        btnPrev, btnPlay, btnPause, btnStop, btnNext, btnEject,
        volumeTrack, volumeFill, volumeThumb,
        playlistTitleBar, playlistBtnClose, playlistBtnShade,
        spectrumTitleBar, spectrumBtnClose
    ]
    
    /// Look up element by ID
    static func element(withId id: String) -> Element? {
        allElements.first { $0.id == id }
    }
}
