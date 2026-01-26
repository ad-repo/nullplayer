import Foundation
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Window Types

/// Types of windows in the Winamp interface
public enum WindowType: Sendable {
    case main
    case playlist
    case equalizer
    case mediaLibrary
}

// MARK: - Button Types

/// All button types in the Winamp interface
public enum ButtonType: CaseIterable, Sendable {
    // Transport controls
    case previous
    case play
    case pause
    case stop
    case next
    case eject
    
    // Window controls
    case close
    case minimize
    case shade
    case unshade  // Used in shade mode to return to normal
    case menu     // Top-left menu icon - opens Milkdrop
    
    // Toggle buttons
    case shuffle
    case repeatTrack
    case eqToggle
    case playlistToggle
    
    // Equalizer buttons
    case eqOnOff
    case eqAuto
    case eqPresets
    
    // Playlist buttons
    case playlistAdd
    case playlistRemove
    case playlistSelect
    case playlistMisc
    case playlistList
    
    // Logo button (opens Plex browser)
    case logo
}

/// Button visual state
public enum ButtonState: Sendable {
    case normal
    case pressed
    case active       // For toggles when ON
    case activePressed // For toggles when ON and pressed
}

// MARK: - Slider Types

/// Types of sliders in the interface
public enum SliderType: Sendable {
    case position    // Seek bar
    case volume      // Volume control
    case balance     // Left/right balance
    case eqBand      // EQ frequency band (vertical)
    case eqPreamp    // EQ preamp (vertical)
}

// MARK: - Cursor Types

/// Cursor types for different regions
public enum CursorType: Sendable {
    case normal
    case pointer    // Hand cursor for buttons
    case hResize    // Horizontal resize for sliders
    case vResize    // Vertical resize for EQ sliders
    case move       // Move cursor for window dragging
}

// MARK: - Player Actions

/// All possible actions from UI interactions
public enum PlayerAction: Equatable, Sendable {
    // Transport controls
    case previous
    case play
    case pause
    case stop
    case next
    case eject
    
    // Window controls
    case close
    case minimize
    case shade
    
    // Toggle controls
    case shuffle
    case `repeat`
    case toggleEQ
    case togglePlaylist
    
    // Sliders
    case seekPosition(CGFloat)  // 0.0 - 1.0
    case setVolume(CGFloat)     // 0.0 - 1.0
    case setBalance(CGFloat)    // -1.0 to 1.0
    
    // EQ controls
    case toggleEQOn
    case toggleEQAuto
    case openEQPresets
    case setEQBand(Int, CGFloat)  // band index (0-9), gain (-12 to +12)
    case setEQPreamp(CGFloat)     // gain (-12 to +12)
    
    // Playlist actions
    case playlistAdd
    case playlistAddDir
    case playlistAddFile
    case playlistRemove
    case playlistRemoveAll
    case playlistRemoveCrop
    case playlistSelectAll
    case playlistSelectNone
    case playlistSelectInvert
    case playlistSortByTitle
    case playlistSortByPath
    case playlistReverse
    case playlistRandomize
    
    // Generic slider interaction
    case sliderDrag(SliderType, CGFloat)
    
    // Menu actions
    case openMainMenu
    case openOptionsMenu
    
    // Plex
    case openPlexBrowser
}

// MARK: - Clickable Region

/// Defines a clickable area with associated action
public struct ClickableRegion: Sendable {
    public let rect: CGRect
    public let action: PlayerAction
    public let cursorType: CursorType
    
    public init(rect: CGRect, action: PlayerAction, cursor: CursorType = .normal) {
        self.rect = rect
        self.action = action
        self.cursorType = cursor
    }
}

// MARK: - Drag Region Tracker

/// Tracks slider dragging state
public final class SliderDragTracker: @unchecked Sendable {
    
    public var isDragging = false
    public var sliderType: SliderType?
    public var startValue: CGFloat = 0
    public var startPoint: CGPoint = .zero
    
    public init() {}
    
    public func beginDrag(slider: SliderType, at point: CGPoint, currentValue: CGFloat) {
        isDragging = true
        sliderType = slider
        startValue = currentValue
        startPoint = point
    }
    
    public func updateDrag(to point: CGPoint, in rect: CGRect) -> CGFloat {
        guard isDragging, let slider = sliderType else { return startValue }
        
        switch slider {
        case .position, .volume:
            // Horizontal slider
            let delta = point.x - startPoint.x
            let range = rect.width
            let valueDelta = delta / range
            return min(1.0, max(0.0, startValue + valueDelta))
            
        case .balance:
            // Horizontal slider, -1 to 1
            let delta = point.x - startPoint.x
            let range = rect.width
            let valueDelta = (delta / range) * 2.0
            return min(1.0, max(-1.0, startValue + valueDelta))
            
        case .eqBand, .eqPreamp:
            // Vertical slider, inverted (up = higher value)
            let delta = startPoint.y - point.y
            let range = rect.height
            let valueDelta = (delta / range) * 24.0
            return min(12.0, max(-12.0, startValue + valueDelta))
        }
    }
    
    public func endDrag() {
        isDragging = false
        sliderType = nil
    }
}

// MARK: - Window Regions

public struct WindowRegions: Sendable {
    public let mainNormal: [CGPoint]?
    public let mainShade: [CGPoint]?
    public let eqNormal: [CGPoint]?
    public let eqShade: [CGPoint]?
    public let playlistNormal: [CGPoint]?
    public let playlistShade: [CGPoint]?
    
    public init(
        mainNormal: [CGPoint]? = nil,
        mainShade: [CGPoint]? = nil,
        eqNormal: [CGPoint]? = nil,
        eqShade: [CGPoint]? = nil,
        playlistNormal: [CGPoint]? = nil,
        playlistShade: [CGPoint]? = nil
    ) {
        self.mainNormal = mainNormal
        self.mainShade = mainShade
        self.eqNormal = eqNormal
        self.eqShade = eqShade
        self.playlistNormal = playlistNormal
        self.playlistShade = playlistShade
    }
}

// MARK: - Skin Constants

public enum SkinConstants {
    /// Scale factor for the UI (1.25 = 25% larger than original)
    public static let scaleFactor: CGFloat = 1.25
    
    /// Base Winamp dimensions (275x116 in classic Winamp)
    public static let baseMainSize = CGSize(width: 275, height: 116)
    
    /// Main window size scaled
    public static let mainWindowSize = CGSize(width: baseMainSize.width * scaleFactor, height: baseMainSize.height * scaleFactor)
    
    /// Equalizer window size scaled
    public static let eqWindowSize = CGSize(width: baseMainSize.width * scaleFactor, height: baseMainSize.height * scaleFactor)
    
    /// Shade mode height scaled
    public static let shadeHeight: CGFloat = 14 * scaleFactor
}

// MARK: - Playlist Colors

#if canImport(AppKit)
public struct PlaylistColors: Sendable {
    public let normalText: NSColor
    public let currentText: NSColor
    public let normalBackground: NSColor
    public let selectedBackground: NSColor
    public let font: NSFont
    
    public static let `default` = PlaylistColors(
        normalText: NSColor(hex: "#00FF00") ?? .green,
        currentText: .white,
        normalBackground: .black,
        selectedBackground: NSColor(hex: "#0000FF") ?? .blue,
        font: .systemFont(ofSize: 8)
    )
    
    public init(normalText: NSColor, currentText: NSColor, normalBackground: NSColor, selectedBackground: NSColor, font: NSFont) {
        self.normalText = normalText
        self.currentText = currentText
        self.normalBackground = normalBackground
        self.selectedBackground = selectedBackground
        self.font = font
    }
}

// MARK: - NSColor Extension

extension NSColor {
    public convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
    
    public var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
#endif
