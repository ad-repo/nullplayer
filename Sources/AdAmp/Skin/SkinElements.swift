import AppKit

// MARK: - Window Types

/// Types of windows in the Winamp interface
enum WindowType {
    case main
    case playlist
    case equalizer
    case mediaLibrary
}

// MARK: - Button Types

/// All button types in the Winamp interface
enum ButtonType: CaseIterable {
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
}

/// Button visual state
enum ButtonState {
    case normal
    case pressed
    case active       // For toggles when ON
    case activePressed // For toggles when ON and pressed
}

// MARK: - Slider Types

/// Types of sliders in the interface
enum SliderType {
    case position    // Seek bar
    case volume      // Volume control
    case balance     // Left/right balance
    case eqBand      // EQ frequency band (vertical)
    case eqPreamp    // EQ preamp (vertical)
}

// MARK: - Sprite Definitions

/// Contains all sprite coordinates from classic Winamp skin format
struct SkinElements {
    
    // MARK: - Main Window Dimensions
    
    /// Main window size: 275x116 pixels
    static let mainWindowSize = NSSize(width: 275, height: 116)
    
    /// Title bar height
    static let titleBarHeight: CGFloat = 14
    
    // MARK: - Title Bar (titlebar.bmp - 275x14 x 2 rows + shade mode)
    
    struct TitleBar {
        /// Active state title bar
        static let active = NSRect(x: 27, y: 0, width: 275, height: 14)
        /// Inactive state title bar  
        static let inactive = NSRect(x: 27, y: 15, width: 275, height: 14)
        
        // Window control buttons (from titlebar.bmp)
        struct Buttons {
            // Menu button (leftmost)
            static let menuNormal = NSRect(x: 0, y: 0, width: 9, height: 9)
            static let menuPressed = NSRect(x: 0, y: 9, width: 9, height: 9)
            
            // Minimize button
            static let minimizeNormal = NSRect(x: 9, y: 0, width: 9, height: 9)
            static let minimizePressed = NSRect(x: 9, y: 9, width: 9, height: 9)
            
            // Shade button (normal mode - toggles to shade)
            static let shadeNormal = NSRect(x: 0, y: 18, width: 9, height: 9)
            static let shadePressed = NSRect(x: 9, y: 18, width: 9, height: 9)
            
            // Unshade button (shade mode - toggles back to normal)
            static let unshadeNormal = NSRect(x: 0, y: 27, width: 9, height: 9)
            static let unshadePressed = NSRect(x: 9, y: 27, width: 9, height: 9)
            
            // Close button
            static let closeNormal = NSRect(x: 18, y: 0, width: 9, height: 9)
            static let closePressed = NSRect(x: 18, y: 9, width: 9, height: 9)
        }
        
        // Positions on main window (normal mode)
        struct Positions {
            static let menuButton = NSRect(x: 6, y: 3, width: 9, height: 9)
            static let minimizeButton = NSRect(x: 244, y: 3, width: 9, height: 9)
            static let shadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
            static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
        }
        
        // Positions on main window (shade mode)
        struct ShadePositions {
            static let menuButton = NSRect(x: 6, y: 3, width: 9, height: 9)
            static let minimizeButton = NSRect(x: 244, y: 3, width: 9, height: 9)
            static let unshadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
            static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
        }
    }
    
    // MARK: - Main Window Shade Mode (titlebar.bmp rows 29-42)
    
    struct MainShade {
        /// Shade mode window size: 275x14 pixels
        static let windowSize = NSSize(width: 275, height: 14)
        
        /// Shade mode background (active)
        static let backgroundActive = NSRect(x: 27, y: 29, width: 275, height: 14)
        /// Shade mode background (inactive)
        static let backgroundInactive = NSRect(x: 27, y: 42, width: 275, height: 14)
        
        /// Position bar in shade mode (from titlebar.bmp)
        /// Small position indicator showing playback progress
        static let positionBarBackground = NSRect(x: 0, y: 36, width: 17, height: 7)
        static let positionBarFill = NSRect(x: 0, y: 36, width: 17, height: 7)
        
        /// Shade mode position bar position on window
        struct Positions {
            static let positionBar = NSRect(x: 226, y: 4, width: 17, height: 7)
        }
        
        /// Shade mode text display area
        static let textArea = NSRect(x: 79, y: 4, width: 145, height: 6)
    }
    
    // MARK: - Equalizer Shade Mode
    
    struct EQShade {
        /// EQ shade mode window size: 275x14 pixels
        static let windowSize = NSSize(width: 275, height: 14)
        
        /// EQ shade mode background (from eqmain.bmp)
        static let backgroundActive = NSRect(x: 0, y: 164, width: 275, height: 14)
        static let backgroundInactive = NSRect(x: 0, y: 178, width: 275, height: 14)
        
        /// Close button position in shade mode
        struct Positions {
            static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
            static let shadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
        }
    }
    
    // MARK: - Playlist Shade Mode
    
    struct PlaylistShade {
        /// Playlist shade mode height: 14 pixels (width is variable)
        static let height: CGFloat = 14
        
        /// Playlist shade mode background tiles (from pledit.bmp)
        static let leftCorner = NSRect(x: 72, y: 42, width: 25, height: 14)
        static let rightCorner = NSRect(x: 99, y: 42, width: 75, height: 14)
        static let tile = NSRect(x: 72, y: 57, width: 25, height: 14)
        
        /// Close button position in shade mode
        struct Positions {
            static let closeButton = NSRect(x: -11, y: 3, width: 9, height: 9)  // Relative to right edge
            static let shadeButton = NSRect(x: -21, y: 3, width: 9, height: 9)  // Relative to right edge
        }
    }
    
    // MARK: - Control Buttons (cbuttons.bmp - 136x36)
    
    struct Transport {
        // Each button is 23x18 (except next=22x18, eject=22x16)
        // Row 0 (y=0): normal state
        // Row 1 (y=18): pressed state
        
        static let buttonHeight: CGFloat = 18
        static let ejectHeight: CGFloat = 16
        
        // Previous button |<<
        static let previousNormal = NSRect(x: 0, y: 0, width: 23, height: 18)
        static let previousPressed = NSRect(x: 0, y: 18, width: 23, height: 18)
        
        // Play button >
        static let playNormal = NSRect(x: 23, y: 0, width: 23, height: 18)
        static let playPressed = NSRect(x: 23, y: 18, width: 23, height: 18)
        
        // Pause button ||
        static let pauseNormal = NSRect(x: 46, y: 0, width: 23, height: 18)
        static let pausePressed = NSRect(x: 46, y: 18, width: 23, height: 18)
        
        // Stop button []
        static let stopNormal = NSRect(x: 69, y: 0, width: 23, height: 18)
        static let stopPressed = NSRect(x: 69, y: 18, width: 23, height: 18)
        
        // Next button >>|
        static let nextNormal = NSRect(x: 92, y: 0, width: 22, height: 18)
        static let nextPressed = NSRect(x: 92, y: 18, width: 22, height: 18)
        
        // Eject button (special: 22x16)
        static let ejectNormal = NSRect(x: 114, y: 0, width: 22, height: 16)
        static let ejectPressed = NSRect(x: 114, y: 16, width: 22, height: 16)
        
        // Positions on main window
        struct Positions {
            static let previous = NSRect(x: 16, y: 88, width: 23, height: 18)
            static let play = NSRect(x: 39, y: 88, width: 23, height: 18)
            static let pause = NSRect(x: 62, y: 88, width: 23, height: 18)
            static let stop = NSRect(x: 85, y: 88, width: 23, height: 18)
            static let next = NSRect(x: 108, y: 88, width: 22, height: 18)
            static let eject = NSRect(x: 136, y: 89, width: 22, height: 16)
        }
    }
    
    // MARK: - Shuffle/Repeat (shufrep.bmp - 28x15 x 8)
    
    struct ShuffleRepeat {
        // Shuffle button states
        static let shuffleOffNormal = NSRect(x: 28, y: 0, width: 47, height: 15)
        static let shuffleOffPressed = NSRect(x: 28, y: 15, width: 47, height: 15)
        static let shuffleOnNormal = NSRect(x: 28, y: 30, width: 47, height: 15)
        static let shuffleOnPressed = NSRect(x: 28, y: 45, width: 47, height: 15)
        
        // Repeat button states  
        static let repeatOffNormal = NSRect(x: 0, y: 0, width: 28, height: 15)
        static let repeatOffPressed = NSRect(x: 0, y: 15, width: 28, height: 15)
        static let repeatOnNormal = NSRect(x: 0, y: 30, width: 28, height: 15)
        static let repeatOnPressed = NSRect(x: 0, y: 45, width: 28, height: 15)
        
        // EQ toggle button
        static let eqOffNormal = NSRect(x: 0, y: 61, width: 23, height: 12)
        static let eqOffPressed = NSRect(x: 46, y: 61, width: 23, height: 12)
        static let eqOnNormal = NSRect(x: 0, y: 73, width: 23, height: 12)
        static let eqOnPressed = NSRect(x: 46, y: 73, width: 23, height: 12)
        
        // Playlist toggle button
        static let plOffNormal = NSRect(x: 23, y: 61, width: 23, height: 12)
        static let plOffPressed = NSRect(x: 69, y: 61, width: 23, height: 12)
        static let plOnNormal = NSRect(x: 23, y: 73, width: 23, height: 12)
        static let plOnPressed = NSRect(x: 69, y: 73, width: 23, height: 12)
        
        // Positions on main window
        struct Positions {
            static let shuffle = NSRect(x: 164, y: 89, width: 47, height: 15)
            static let repeatBtn = NSRect(x: 211, y: 89, width: 28, height: 15)
            static let eqToggle = NSRect(x: 219, y: 58, width: 23, height: 12)
            static let plToggle = NSRect(x: 242, y: 58, width: 23, height: 12)
        }
    }
    
    // MARK: - Numbers (numbers.bmp - 99x13)
    
    struct Numbers {
        /// Each digit is 9x13 pixels
        static let digitWidth: CGFloat = 9
        static let digitHeight: CGFloat = 13
        
        /// Order: 0,1,2,3,4,5,6,7,8,9,blank,minus
        static func digit(_ digit: Int) -> NSRect {
            let x = CGFloat(digit) * digitWidth
            return NSRect(x: x, y: 0, width: digitWidth, height: digitHeight)
        }
        
        /// Blank/space character (index 10)
        static let blank = NSRect(x: 90, y: 0, width: 9, height: 13)
        
        /// Minus sign (index 11)
        static let minus = NSRect(x: 99, y: 0, width: 9, height: 13)
        
        // Time display positions on main window (minutes:seconds)
        // Total width for 5 characters (MM:SS without colon visual)
        struct Positions {
            static let minuteTens = NSPoint(x: 48, y: 26)
            static let minuteOnes = NSPoint(x: 57, y: 26)
            // Colon is implicit at x: 66
            static let secondTens = NSPoint(x: 78, y: 26)
            static let secondOnes = NSPoint(x: 87, y: 26)
        }
    }
    
    // MARK: - Text Font (text.bmp - 155x18)
    
    struct TextFont {
        /// Each character is 5x6 pixels
        static let charWidth: CGFloat = 5
        static let charHeight: CGFloat = 6
        
        /// Characters per row
        static let charsPerRow = 31
        
        /// Row 0: A-Z (uppercase)
        /// Row 1: Special characters or lowercase mapping
        /// Row 2: 0-9 and symbols
        
        static func character(_ char: Character) -> NSRect {
            let ascii = char.asciiValue ?? 0
            var col: Int
            var row: Int
            
            switch char {
            case "A"..."Z":
                row = 0
                col = Int(ascii) - 65  // A=0, B=1, etc.
            case "a"..."z":
                // Lowercase maps to uppercase
                row = 0
                col = Int(ascii) - 97
            case "0"..."9":
                row = 1
                col = Int(ascii) - 48
            case "\"":
                row = 0; col = 26
            case "@":
                row = 0; col = 27
            case " ":
                row = 0; col = 29  // Space
            case ":":
                row = 1; col = 12
            case "(":
                row = 1; col = 13
            case ")":
                row = 1; col = 14
            case "-":
                row = 1; col = 15
            case "'":
                row = 1; col = 16
            case "!":
                row = 1; col = 17
            case "_":
                row = 1; col = 18
            case "+":
                row = 1; col = 19
            case "\\":
                row = 1; col = 20
            case "/":
                row = 1; col = 21
            case "[":
                row = 1; col = 22
        case "]":
            row = 1; col = 23
            case "^":
                row = 1; col = 24
            case "&":
                row = 1; col = 25
            case "%":
                row = 1; col = 26
            case ".":
                row = 1; col = 27
            case "=":
                row = 1; col = 28
            case "$":
                row = 1; col = 29
            case "#":
                row = 1; col = 30
            case "?":
                row = 2; col = 0
            case "*":
                row = 2; col = 1
            default:
                row = 0; col = 29  // Default to space
            }
            
            return NSRect(x: CGFloat(col) * charWidth,
                         y: CGFloat(row) * charHeight,
                         width: charWidth,
                         height: charHeight)
        }
        
        // Marquee position on main window
        struct Positions {
            static let marqueeArea = NSRect(x: 111, y: 24, width: 154, height: 13)
        }
    }
    
    // MARK: - Play/Pause Status (playpaus.bmp - 11x9 x 4)
    
    struct PlayStatus {
        /// Play indicator (animated/static)
        static let play = NSRect(x: 0, y: 0, width: 9, height: 9)
        static let pause = NSRect(x: 9, y: 0, width: 9, height: 9)
        static let stop = NSRect(x: 18, y: 0, width: 9, height: 9)
        
        /// Work indicator (not playing = 0,0, playing = 0,9, paused = 0,18)
        static let workStopped = NSRect(x: 27, y: 0, width: 3, height: 9)
        static let workPlaying = NSRect(x: 27, y: 9, width: 3, height: 9)
        static let workPaused = NSRect(x: 27, y: 18, width: 3, height: 9)
        
        // Position on main window
        struct Positions {
            static let status = NSPoint(x: 26, y: 28)
            static let work = NSPoint(x: 24, y: 28)
        }
    }
    
    // MARK: - Mono/Stereo (monoster.bmp - 56x12 x 2)
    
    struct MonoStereo {
        // Stereo indicator
        static let stereoOn = NSRect(x: 0, y: 0, width: 29, height: 12)
        static let stereoOff = NSRect(x: 0, y: 12, width: 29, height: 12)
        
        // Mono indicator
        static let monoOn = NSRect(x: 29, y: 0, width: 27, height: 12)
        static let monoOff = NSRect(x: 29, y: 12, width: 27, height: 12)
        
        // Position on main window
        struct Positions {
            static let stereo = NSPoint(x: 239, y: 41)
            static let mono = NSPoint(x: 212, y: 41)
        }
    }
    
    // MARK: - Position Bar (posbar.bmp - 248x10 background + 29x10 button x 2)
    
    struct PositionBar {
        /// Background track
        static let background = NSRect(x: 0, y: 0, width: 248, height: 10)
        
        /// Slider thumb normal
        static let thumbNormal = NSRect(x: 248, y: 0, width: 29, height: 10)
        /// Slider thumb pressed
        static let thumbPressed = NSRect(x: 278, y: 0, width: 29, height: 10)
        
        // Position on main window
        struct Positions {
            static let track = NSRect(x: 16, y: 72, width: 248, height: 10)
        }
    }
    
    // MARK: - Volume (volume.bmp - 68x13 background x 28 states + thumb)
    
    struct Volume {
        /// Volume background - 28 different fill states (0-27)
        static func background(level: Int) -> NSRect {
            let row = min(27, max(0, level))
            return NSRect(x: 0, y: CGFloat(row) * 15, width: 68, height: 13)
        }
        
        /// Volume thumb/handle
        static let thumbNormal = NSRect(x: 15, y: 422, width: 14, height: 11)
        static let thumbPressed = NSRect(x: 0, y: 422, width: 14, height: 11)
        
        // Position on main window
        struct Positions {
            static let slider = NSRect(x: 107, y: 57, width: 68, height: 13)
        }
    }
    
    // MARK: - Balance (balance.bmp - 38x13 background x 28 states + thumb)
    
    struct Balance {
        /// Balance background - 28 different states
        static func background(level: Int) -> NSRect {
            // Level: -27 to +27, centered at 0
            let row = min(27, max(0, abs(level)))
            return NSRect(x: 9, y: CGFloat(row) * 15, width: 38, height: 13)
        }
        
        /// Balance thumb/handle
        static let thumbNormal = NSRect(x: 15, y: 422, width: 14, height: 11)
        static let thumbPressed = NSRect(x: 0, y: 422, width: 14, height: 11)
        
        // Position on main window
        struct Positions {
            static let slider = NSRect(x: 177, y: 57, width: 38, height: 13)
        }
    }
    
    // MARK: - Clutterbar (main.bmp sections)
    
    struct Clutterbar {
        /// The clutterbar on the left side of the main window
        static let area = NSRect(x: 0, y: 72, width: 8, height: 43)
        
        // Individual button areas (within clutterbar)
        static let optionA = NSRect(x: 0, y: 0, width: 8, height: 8)
        static let optionD = NSRect(x: 0, y: 9, width: 8, height: 8)
        static let optionUp = NSRect(x: 0, y: 18, width: 8, height: 8)
        static let optionDown = NSRect(x: 0, y: 27, width: 8, height: 8)
    }
    
    // MARK: - Bitrate/Sample Rate Display
    
    struct InfoDisplay {
        // Small text for bitrate (e.g., "128")
        // Each character is about 5x6 from text.bmp
        
        struct Positions {
            /// Bitrate display area (e.g., "128")
            static let bitrate = NSRect(x: 111, y: 43, width: 15, height: 9)
            /// Sample rate display area (e.g., "44")  
            static let sampleRate = NSRect(x: 156, y: 43, width: 10, height: 9)
        }
    }
    
    // MARK: - Visualization Area
    
    struct Visualization {
        /// The visualization display area on the main window
        /// Located where the spectrum analyzer/oscilloscope appears
        static let displayArea = NSRect(x: 24, y: 43, width: 76, height: 16)
        
        /// Number of bars in the spectrum analyzer
        static let barCount = 19
        
        /// Bar width
        static let barWidth: CGFloat = 3
        
        /// Bar spacing
        static let barSpacing: CGFloat = 1
    }
    
    // MARK: - Equalizer Elements (eqmain.bmp - 275x116)
    
    struct Equalizer {
        /// EQ window size
        static let windowSize = NSSize(width: 275, height: 116)
        
        /// EQ Title bar active
        static let titleActive = NSRect(x: 0, y: 134, width: 275, height: 14)
        /// EQ Title bar inactive
        static let titleInactive = NSRect(x: 0, y: 149, width: 275, height: 14)
        
        /// ON button
        static let onButtonActive = NSRect(x: 0, y: 119, width: 26, height: 12)
        static let onButtonInactive = NSRect(x: 0, y: 107, width: 26, height: 12)
        
        /// AUTO button
        static let autoButtonActive = NSRect(x: 36, y: 119, width: 32, height: 12)
        static let autoButtonInactive = NSRect(x: 36, y: 107, width: 32, height: 12)
        
        /// Presets button
        static let presetsNormal = NSRect(x: 224, y: 164, width: 44, height: 12)
        static let presetsPressed = NSRect(x: 224, y: 176, width: 44, height: 12)
        
        /// Slider positions (preamp + 10 bands)
        struct Sliders {
            /// Preamp slider X position
            static let preampX: CGFloat = 21
            /// First band X position
            static let firstBandX: CGFloat = 78
            /// Band spacing
            static let bandSpacing: CGFloat = 18
            /// Slider Y position
            static let sliderY: CGFloat = 38
            /// Slider height (travel distance)
            static let sliderHeight: CGFloat = 63
        }
        
        /// Slider thumb states (vertical EQ sliders)
        static let sliderThumbNormal = NSRect(x: 0, y: 164, width: 14, height: 63)
        static let sliderThumbPressed = NSRect(x: 0, y: 164, width: 14, height: 63)
        
        /// Positions on EQ window
        struct Positions {
            static let onButton = NSRect(x: 14, y: 18, width: 26, height: 12)
            static let autoButton = NSRect(x: 40, y: 18, width: 32, height: 12)
            static let presetsButton = NSRect(x: 217, y: 18, width: 44, height: 12)
        }
    }
    
    // MARK: - Playlist Elements (pledit.bmp)
    
    struct Playlist {
        /// Minimum playlist size
        static let minSize = NSSize(width: 275, height: 116)
        
        /// Title bar height
        static let titleHeight: CGFloat = 20
        
        /// Corner sections for resizable window
        static let topLeftCorner = NSRect(x: 0, y: 0, width: 25, height: 20)
        static let topTile = NSRect(x: 26, y: 0, width: 100, height: 20)
        static let topRightCorner = NSRect(x: 153, y: 0, width: 25, height: 20)
        
        static let bottomLeftCorner = NSRect(x: 0, y: 42, width: 125, height: 38)
        static let bottomTile = NSRect(x: 179, y: 0, width: 25, height: 38)
        static let bottomRightCorner = NSRect(x: 126, y: 42, width: 150, height: 38)
        
        /// Side tiles
        static let leftTile = NSRect(x: 0, y: 21, width: 12, height: 20)
        static let rightTile = NSRect(x: 31, y: 21, width: 19, height: 20)
        
        /// Scrollbar
        static let scrollbarTop = NSRect(x: 52, y: 53, width: 8, height: 18)
        static let scrollbarMiddle = NSRect(x: 61, y: 53, width: 8, height: 18)
        static let scrollbarBottom = NSRect(x: 69, y: 72, width: 8, height: 17)
        static let scrollbarThumb = NSRect(x: 52, y: 72, width: 8, height: 18)
        
        /// Control buttons at bottom
        struct Buttons {
            static let addURL = NSRect(x: 0, y: 111, width: 22, height: 18)
            static let addDir = NSRect(x: 23, y: 111, width: 22, height: 18)
            static let addFile = NSRect(x: 46, y: 111, width: 22, height: 18)
            
            static let removeAll = NSRect(x: 54, y: 111, width: 22, height: 18)
            static let removeCrop = NSRect(x: 77, y: 111, width: 22, height: 18)
            static let removeSelected = NSRect(x: 100, y: 111, width: 22, height: 18)
            
            static let selectInvert = NSRect(x: 104, y: 111, width: 22, height: 18)
            static let selectZero = NSRect(x: 127, y: 111, width: 22, height: 18)
            static let selectAll = NSRect(x: 150, y: 111, width: 22, height: 18)
        }
    }
}

// MARK: - Helper Extensions

extension SkinElements {
    
    /// Get sprite rect for a button type and state
    static func spriteRect(for button: ButtonType, state: ButtonState) -> NSRect {
        switch button {
        case .previous:
            return state == .pressed ? Transport.previousPressed : Transport.previousNormal
        case .play:
            return state == .pressed ? Transport.playPressed : Transport.playNormal
        case .pause:
            return state == .pressed ? Transport.pausePressed : Transport.pauseNormal
        case .stop:
            return state == .pressed ? Transport.stopPressed : Transport.stopNormal
        case .next:
            return state == .pressed ? Transport.nextPressed : Transport.nextNormal
        case .eject:
            return state == .pressed ? Transport.ejectPressed : Transport.ejectNormal
        case .close:
            return state == .pressed ? TitleBar.Buttons.closePressed : TitleBar.Buttons.closeNormal
        case .minimize:
            return state == .pressed ? TitleBar.Buttons.minimizePressed : TitleBar.Buttons.minimizeNormal
        case .shade:
            return state == .pressed ? TitleBar.Buttons.shadePressed : TitleBar.Buttons.shadeNormal
        case .unshade:
            return state == .pressed ? TitleBar.Buttons.unshadePressed : TitleBar.Buttons.unshadeNormal
        case .shuffle:
            switch state {
            case .normal: return ShuffleRepeat.shuffleOffNormal
            case .pressed: return ShuffleRepeat.shuffleOffPressed
            case .active: return ShuffleRepeat.shuffleOnNormal
            case .activePressed: return ShuffleRepeat.shuffleOnPressed
            }
        case .repeatTrack:
            switch state {
            case .normal: return ShuffleRepeat.repeatOffNormal
            case .pressed: return ShuffleRepeat.repeatOffPressed
            case .active: return ShuffleRepeat.repeatOnNormal
            case .activePressed: return ShuffleRepeat.repeatOnPressed
            }
        case .eqToggle:
            switch state {
            case .normal: return ShuffleRepeat.eqOffNormal
            case .pressed: return ShuffleRepeat.eqOffPressed
            case .active: return ShuffleRepeat.eqOnNormal
            case .activePressed: return ShuffleRepeat.eqOnPressed
            }
        case .playlistToggle:
            switch state {
            case .normal: return ShuffleRepeat.plOffNormal
            case .pressed: return ShuffleRepeat.plOffPressed
            case .active: return ShuffleRepeat.plOnNormal
            case .activePressed: return ShuffleRepeat.plOnPressed
            }
        case .eqOnOff:
            return state == .active ? Equalizer.onButtonActive : Equalizer.onButtonInactive
        case .eqAuto:
            return state == .active ? Equalizer.autoButtonActive : Equalizer.autoButtonInactive
        case .eqPresets:
            return state == .pressed ? Equalizer.presetsPressed : Equalizer.presetsNormal
        default:
            return .zero
        }
    }
    
    /// Get hit rect for a button on the main window (normal mode)
    static func hitRect(for button: ButtonType) -> NSRect {
        switch button {
        case .previous: return Transport.Positions.previous
        case .play: return Transport.Positions.play
        case .pause: return Transport.Positions.pause
        case .stop: return Transport.Positions.stop
        case .next: return Transport.Positions.next
        case .eject: return Transport.Positions.eject
        case .close: return TitleBar.Positions.closeButton
        case .minimize: return TitleBar.Positions.minimizeButton
        case .shade: return TitleBar.Positions.shadeButton
        case .unshade: return TitleBar.ShadePositions.unshadeButton
        case .shuffle: return ShuffleRepeat.Positions.shuffle
        case .repeatTrack: return ShuffleRepeat.Positions.repeatBtn
        case .eqToggle: return ShuffleRepeat.Positions.eqToggle
        case .playlistToggle: return ShuffleRepeat.Positions.plToggle
        default: return .zero
        }
    }
    
    /// Get hit rect for a button on the main window in shade mode
    static func shadeHitRect(for button: ButtonType) -> NSRect {
        switch button {
        case .close: return TitleBar.ShadePositions.closeButton
        case .minimize: return TitleBar.ShadePositions.minimizeButton
        case .unshade: return TitleBar.ShadePositions.unshadeButton
        default: return .zero
        }
    }
}
