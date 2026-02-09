import AppKit

// =============================================================================
// SKIN ELEMENTS - Sprite coordinates and layout constants
// =============================================================================
// For comprehensive documentation on skin skin format, sprite coordinates,
// and implementation notes, see: AGENT_DOCS/SKIN_FORMAT_RESEARCH.md
//
// =============================================================================

// MARK: - Sprite Definitions
// Note: WindowType, ButtonType, ButtonState, SliderType are defined in SkinTypes.swift

/// Contains all sprite coordinates from classic skin skin format
public struct SkinElements {
    
    // MARK: - Main Window Dimensions
    
    /// Main window size: 275x116 pixels
    public static let mainWindowSize = NSSize(width: 275, height: 116)
    
    /// Title bar height
    public static let titleBarHeight: CGFloat = 14
    
    // MARK: - Title Bar (titlebar.bmp - 275x14 x 2 rows + shade mode)
    
    struct TitleBar {
        /// Active state title bar
        public static let active = NSRect(x: 27, y: 0, width: 275, height: 14)
        /// Inactive state title bar  
        public static let inactive = NSRect(x: 27, y: 15, width: 275, height: 14)
        
        // Window control buttons (from titlebar.bmp)
        struct Buttons {
            // Menu button (leftmost)
            public static let menuNormal = NSRect(x: 0, y: 0, width: 9, height: 9)
            public static let menuPressed = NSRect(x: 0, y: 9, width: 9, height: 9)
            
            // Minimize button
            public static let minimizeNormal = NSRect(x: 9, y: 0, width: 9, height: 9)
            public static let minimizePressed = NSRect(x: 9, y: 9, width: 9, height: 9)
            
            // Shade button (normal mode - toggles to shade)
            public static let shadeNormal = NSRect(x: 0, y: 18, width: 9, height: 9)
            public static let shadePressed = NSRect(x: 9, y: 18, width: 9, height: 9)
            
            // Unshade button (shade mode - toggles back to normal)
            public static let unshadeNormal = NSRect(x: 0, y: 27, width: 9, height: 9)
            public static let unshadePressed = NSRect(x: 9, y: 27, width: 9, height: 9)
            
            // Close button
            public static let closeNormal = NSRect(x: 18, y: 0, width: 9, height: 9)
            public static let closePressed = NSRect(x: 18, y: 9, width: 9, height: 9)
        }
        
        // Positions on main window (normal mode)
        struct Positions {
            public static let menuButton = NSRect(x: 6, y: 3, width: 9, height: 9)
            public static let minimizeButton = NSRect(x: 244, y: 3, width: 9, height: 9)
            public static let shadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
            public static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
        }
        
        // Positions on main window (shade mode)
        struct ShadePositions {
            public static let menuButton = NSRect(x: 6, y: 3, width: 9, height: 9)
            public static let minimizeButton = NSRect(x: 244, y: 3, width: 9, height: 9)
            public static let unshadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
            public static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
        }
    }
    
    // MARK: - Main Window Shade Mode (titlebar.bmp rows 29-42)
    
    struct MainShade {
        /// Shade mode window size: 275x14 pixels
        public static let windowSize = NSSize(width: 275, height: 14)
        
        /// Shade mode background (active)
        public static let backgroundActive = NSRect(x: 27, y: 29, width: 275, height: 14)
        /// Shade mode background (inactive)
        public static let backgroundInactive = NSRect(x: 27, y: 42, width: 275, height: 14)
        
        /// Position bar in shade mode (from titlebar.bmp)
        /// Small position indicator showing playback progress
        public static let positionBarBackground = NSRect(x: 0, y: 36, width: 17, height: 7)
        public static let positionBarFill = NSRect(x: 0, y: 36, width: 17, height: 7)
        
        /// Shade mode position bar position on window
        struct Positions {
            public static let positionBar = NSRect(x: 226, y: 4, width: 17, height: 7)
        }
        
        /// Shade mode text display area
        public static let textArea = NSRect(x: 79, y: 4, width: 145, height: 6)
    }
    
    // MARK: - Equalizer Shade Mode
    
    struct EQShade {
        /// EQ shade mode window size: 275x14 pixels
        public static let windowSize = NSSize(width: 275, height: 14)
        
        /// EQ shade mode background (from eqmain.bmp)
        public static let backgroundActive = NSRect(x: 0, y: 164, width: 275, height: 14)
        public static let backgroundInactive = NSRect(x: 0, y: 178, width: 275, height: 14)
        
        /// Close button position in shade mode
        struct Positions {
            public static let closeButton = NSRect(x: 264, y: 3, width: 9, height: 9)
            public static let shadeButton = NSRect(x: 254, y: 3, width: 9, height: 9)
        }
    }
    
    // MARK: - Playlist Shade Mode
    
    struct PlaylistShade {
        /// Playlist shade mode height: 14 pixels (width is variable)
        public static let height: CGFloat = 14
        
        /// Playlist shade mode background tiles (from pledit.bmp)
        public static let leftCorner = NSRect(x: 72, y: 42, width: 25, height: 14)
        public static let rightCorner = NSRect(x: 99, y: 42, width: 75, height: 14)
        public static let tile = NSRect(x: 72, y: 57, width: 25, height: 14)
        
        /// Close button position in shade mode
        struct Positions {
            public static let closeButton = NSRect(x: -11, y: 3, width: 9, height: 9)  // Relative to right edge
            public static let shadeButton = NSRect(x: -21, y: 3, width: 9, height: 9)  // Relative to right edge
        }
    }
    
    // MARK: - Control Buttons (cbuttons.bmp - 136x36)
    
    struct Transport {
        // Each button is 23x18 (except next=22x18, eject=22x16)
        // Row 0 (y=0): normal state
        // Row 1 (y=18): pressed state
        
        public static let buttonHeight: CGFloat = 18
        public static let ejectHeight: CGFloat = 16
        
        // Previous button |<<
        public static let previousNormal = NSRect(x: 0, y: 0, width: 23, height: 18)
        public static let previousPressed = NSRect(x: 0, y: 18, width: 23, height: 18)
        
        // Play button >
        public static let playNormal = NSRect(x: 23, y: 0, width: 23, height: 18)
        public static let playPressed = NSRect(x: 23, y: 18, width: 23, height: 18)
        
        // Pause button ||
        public static let pauseNormal = NSRect(x: 46, y: 0, width: 23, height: 18)
        public static let pausePressed = NSRect(x: 46, y: 18, width: 23, height: 18)
        
        // Stop button []
        public static let stopNormal = NSRect(x: 69, y: 0, width: 23, height: 18)
        public static let stopPressed = NSRect(x: 69, y: 18, width: 23, height: 18)
        
        // Next button >>|
        public static let nextNormal = NSRect(x: 92, y: 0, width: 22, height: 18)
        public static let nextPressed = NSRect(x: 92, y: 18, width: 22, height: 18)
        
        // Eject button (special: 22x16)
        public static let ejectNormal = NSRect(x: 114, y: 0, width: 22, height: 16)
        public static let ejectPressed = NSRect(x: 114, y: 16, width: 22, height: 16)
        
        // Positions on main window
        struct Positions {
            public static let previous = NSRect(x: 16, y: 88, width: 23, height: 18)
            public static let play = NSRect(x: 39, y: 88, width: 23, height: 18)
            public static let pause = NSRect(x: 62, y: 88, width: 23, height: 18)
            public static let stop = NSRect(x: 85, y: 88, width: 23, height: 18)
            public static let next = NSRect(x: 108, y: 88, width: 22, height: 18)
            public static let eject = NSRect(x: 136, y: 89, width: 22, height: 16)
        }
    }
    
    // MARK: - Shuffle/Repeat (shufrep.bmp - 28x15 x 8)
    
    struct ShuffleRepeat {
        // Shuffle button states
        public static let shuffleOffNormal = NSRect(x: 28, y: 0, width: 47, height: 15)
        public static let shuffleOffPressed = NSRect(x: 28, y: 15, width: 47, height: 15)
        public static let shuffleOnNormal = NSRect(x: 28, y: 30, width: 47, height: 15)
        public static let shuffleOnPressed = NSRect(x: 28, y: 45, width: 47, height: 15)
        
        // Repeat button states  
        public static let repeatOffNormal = NSRect(x: 0, y: 0, width: 28, height: 15)
        public static let repeatOffPressed = NSRect(x: 0, y: 15, width: 28, height: 15)
        public static let repeatOnNormal = NSRect(x: 0, y: 30, width: 28, height: 15)
        public static let repeatOnPressed = NSRect(x: 0, y: 45, width: 28, height: 15)
        
        // EQ toggle button
        public static let eqOffNormal = NSRect(x: 0, y: 61, width: 23, height: 12)
        public static let eqOffPressed = NSRect(x: 46, y: 61, width: 23, height: 12)
        public static let eqOnNormal = NSRect(x: 0, y: 73, width: 23, height: 12)
        public static let eqOnPressed = NSRect(x: 46, y: 73, width: 23, height: 12)
        
        // Playlist toggle button
        public static let plOffNormal = NSRect(x: 23, y: 61, width: 23, height: 12)
        public static let plOffPressed = NSRect(x: 69, y: 61, width: 23, height: 12)
        public static let plOnNormal = NSRect(x: 23, y: 73, width: 23, height: 12)
        public static let plOnPressed = NSRect(x: 69, y: 73, width: 23, height: 12)
        
        // Positions on main window
        struct Positions {
            public static let shuffle = NSRect(x: 164, y: 89, width: 47, height: 15)
            public static let repeatBtn = NSRect(x: 211, y: 89, width: 28, height: 15)
            public static let eqToggle = NSRect(x: 219, y: 58, width: 23, height: 12)
            public static let plToggle = NSRect(x: 242, y: 58, width: 23, height: 12)
        }
    }
    
    // MARK: - Numbers (numbers.bmp - 99x13)
    
    struct Numbers {
        /// Each digit is 9x13 pixels
        public static let digitWidth: CGFloat = 9
        public static let digitHeight: CGFloat = 13
        
        /// Order: 0,1,2,3,4,5,6,7,8,9,blank,minus
        public static func digit(_ digit: Int) -> NSRect {
            let x = CGFloat(digit) * digitWidth
            return NSRect(x: x, y: 0, width: digitWidth, height: digitHeight)
        }
        
        /// Blank/space character (index 10)
        public static let blank = NSRect(x: 90, y: 0, width: 9, height: 13)
        
        /// Minus sign (index 11)
        public static let minus = NSRect(x: 99, y: 0, width: 9, height: 13)
        
        // Time display positions on main window (minutes:seconds)
        // Standard skin positions - digits are 9px wide with tight spacing
        struct Positions {
            /// Minus sign position (for remaining time mode)
            public static let minus = NSPoint(x: 36, y: 26)
            public static let minuteTens = NSPoint(x: 48, y: 26)
            public static let minuteOnes = NSPoint(x: 60, y: 26)
            // Colon is baked into background at ~x: 69-77
            public static let secondTens = NSPoint(x: 78, y: 26)
            public static let secondOnes = NSPoint(x: 90, y: 26)
        }
    }
    
    // MARK: - Text Font (text.bmp - 155x18)
    
    struct TextFont {
        /// Each character is 5x6 pixels
        public static let charWidth: CGFloat = 5
        public static let charHeight: CGFloat = 6
        
        /// Characters per row
        public static let charsPerRow = 31
        
        /// Row 0: A-Z (uppercase)
        /// Row 1: Special characters or lowercase mapping
        /// Row 2: 0-9 and symbols
        
        public static func character(_ char: Character) -> NSRect {
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
            public static let marqueeArea = NSRect(x: 111, y: 24, width: 154, height: 13)
        }
    }
    
    // MARK: - Play/Pause Status (playpaus.bmp - 11x9 x 4)
    
    struct PlayStatus {
        /// Play indicator (animated/static)
        public static let play = NSRect(x: 0, y: 0, width: 9, height: 9)
        public static let pause = NSRect(x: 9, y: 0, width: 9, height: 9)
        public static let stop = NSRect(x: 18, y: 0, width: 9, height: 9)
        
        /// Work indicator (not playing = 0,0, playing = 0,9, paused = 0,18)
        public static let workStopped = NSRect(x: 27, y: 0, width: 3, height: 9)
        public static let workPlaying = NSRect(x: 27, y: 9, width: 3, height: 9)
        public static let workPaused = NSRect(x: 27, y: 18, width: 3, height: 9)
        
        // Position on main window
        struct Positions {
            public static let status = NSPoint(x: 26, y: 28)
            public static let work = NSPoint(x: 24, y: 28)
        }
    }
    
    // MARK: - Mono/Stereo (monoster.bmp - 56x12 x 2)
    
    struct MonoStereo {
        // Stereo indicator
        public static let stereoOn = NSRect(x: 0, y: 0, width: 29, height: 12)
        public static let stereoOff = NSRect(x: 0, y: 12, width: 29, height: 12)
        
        // Mono indicator
        public static let monoOn = NSRect(x: 29, y: 0, width: 27, height: 12)
        public static let monoOff = NSRect(x: 29, y: 12, width: 27, height: 12)
        
        // Position on main window
        struct Positions {
            public static let stereo = NSPoint(x: 239, y: 41)
            public static let mono = NSPoint(x: 212, y: 41)
        }
    }
    
    // MARK: - Position Bar (posbar.bmp - 248x10 background + 29x10 button x 2)
    
    struct PositionBar {
        /// Background track
        public static let background = NSRect(x: 0, y: 0, width: 248, height: 10)
        
        /// Slider thumb normal
        public static let thumbNormal = NSRect(x: 248, y: 0, width: 29, height: 10)
        /// Slider thumb pressed
        public static let thumbPressed = NSRect(x: 278, y: 0, width: 29, height: 10)
        
        // Position on main window
        struct Positions {
            public static let track = NSRect(x: 16, y: 72, width: 248, height: 10)
        }
    }
    
    // MARK: - Volume (volume.bmp - 68x13 background x 28 states + thumb)
    
    struct Volume {
        /// Volume background - 28 different fill states (0-27)
        public static func background(level: Int) -> NSRect {
            let row = min(27, max(0, level))
            return NSRect(x: 0, y: CGFloat(row) * 15, width: 68, height: 13)
        }
        
        /// Volume thumb/handle
        public static let thumbNormal = NSRect(x: 15, y: 422, width: 14, height: 11)
        public static let thumbPressed = NSRect(x: 0, y: 422, width: 14, height: 11)
        
        // Position on main window
        struct Positions {
            public static let slider = NSRect(x: 107, y: 57, width: 68, height: 13)
        }
    }
    
    // MARK: - Balance (balance.bmp - 38x13 background x 28 states + thumb)
    
    struct Balance {
        /// Balance background - 28 different states
        public static func background(level: Int) -> NSRect {
            // Level: -27 to +27, centered at 0
            let row = min(27, max(0, abs(level)))
            return NSRect(x: 9, y: CGFloat(row) * 15, width: 38, height: 13)
        }
        
        /// Balance thumb/handle
        public static let thumbNormal = NSRect(x: 15, y: 422, width: 14, height: 11)
        public static let thumbPressed = NSRect(x: 0, y: 422, width: 14, height: 11)
        
        // Position on main window
        struct Positions {
            public static let slider = NSRect(x: 177, y: 57, width: 38, height: 13)
        }
    }
    
    // MARK: - Clutterbar (main.bmp sections)
    
    struct Clutterbar {
        /// The clutterbar on the left side of the main window
        public static let area = NSRect(x: 0, y: 72, width: 8, height: 43)
        
        // Individual button areas (within clutterbar)
        public static let optionA = NSRect(x: 0, y: 0, width: 8, height: 8)
        public static let optionD = NSRect(x: 0, y: 9, width: 8, height: 8)
        public static let optionUp = NSRect(x: 0, y: 18, width: 8, height: 8)
        public static let optionDown = NSRect(x: 0, y: 27, width: 8, height: 8)
    }
    
    // MARK: - Bitrate/Sample Rate Display
    
    struct InfoDisplay {
        // Small text for bitrate (e.g., "128")
        // Each character is about 5x6 from text.bmp
        
        struct Positions {
            /// Bitrate display area (e.g., "128")
            public static let bitrate = NSRect(x: 111, y: 43, width: 15, height: 9)
            /// Sample rate display area (e.g., "44")  
            public static let sampleRate = NSRect(x: 156, y: 43, width: 10, height: 9)
        }
    }
    
    // MARK: - Visualization Area
    
    struct Visualization {
        /// The visualization display area on the main window
        /// Located where the spectrum analyzer/oscilloscope appears
        public static let displayArea = NSRect(x: 24, y: 43, width: 76, height: 16)
        
        /// Number of bars in the spectrum analyzer
        public static let barCount = 19
        
        /// Bar width
        public static let barWidth: CGFloat = 3
        
        /// Bar spacing
        public static let barSpacing: CGFloat = 1
    }
    
    // MARK: - Equalizer Elements (eqmain.bmp - 275x116)
    
    struct Equalizer {
        /// EQ window size
        public static let windowSize = NSSize(width: 275, height: 116)
        
        /// EQ Title bar active
        public static let titleActive = NSRect(x: 0, y: 134, width: 275, height: 14)
        /// EQ Title bar inactive
        public static let titleInactive = NSRect(x: 0, y: 149, width: 275, height: 14)
        
        /// ON button (from eqmain.bmp at y=119, width=26, height=12)
        /// Coordinates from skin spec
        public static let onButtonOffNormal = NSRect(x: 10, y: 119, width: 26, height: 12)
        public static let onButtonOffPressed = NSRect(x: 128, y: 119, width: 26, height: 12)
        public static let onButtonOnNormal = NSRect(x: 69, y: 119, width: 26, height: 12)
        public static let onButtonOnPressed = NSRect(x: 187, y: 119, width: 26, height: 12)
        public static let onButtonActive = NSRect(x: 69, y: 119, width: 26, height: 12)
        public static let onButtonInactive = NSRect(x: 10, y: 119, width: 26, height: 12)
        
        /// AUTO button (from eqmain.bmp at y=119, width=32, height=12)
        /// Coordinates from skin spec
        public static let autoButtonOffNormal = NSRect(x: 36, y: 119, width: 32, height: 12)
        public static let autoButtonOffPressed = NSRect(x: 154, y: 119, width: 32, height: 12)
        public static let autoButtonOnNormal = NSRect(x: 95, y: 119, width: 32, height: 12)
        public static let autoButtonOnPressed = NSRect(x: 213, y: 119, width: 32, height: 12)
        public static let autoButtonActive = NSRect(x: 95, y: 119, width: 32, height: 12)
        public static let autoButtonInactive = NSRect(x: 36, y: 119, width: 32, height: 12)
        
        /// Presets button (from eqmain.bmp)
        public static let presetsNormal = NSRect(x: 224, y: 164, width: 44, height: 12)
        public static let presetsPressed = NSRect(x: 224, y: 176, width: 44, height: 12)
        
        /// Slider positions (preamp + 10 bands)
        struct Sliders {
            /// Preamp slider X position
            public static let preampX: CGFloat = 21
            /// First band X position
            public static let firstBandX: CGFloat = 78
            /// Band spacing
            public static let bandSpacing: CGFloat = 18
            /// Slider Y position
            public static let sliderY: CGFloat = 38
            /// Slider height (travel distance)
            public static let sliderHeight: CGFloat = 63
        }
        
        /// Slider thumb states (vertical EQ sliders) - 11x11 pixels
        /// Located in eqmain.bmp (NOT eq_ex.bmp) - coordinates from skin spec
        public static let sliderThumbNormal = NSRect(x: 0, y: 164, width: 11, height: 11)
        public static let sliderThumbPressed = NSRect(x: 0, y: 176, width: 11, height: 11)
        
        /// Colored slider bar sprites - 28 fill states horizontally arranged
        /// Located in eqmain.bmp at y=164, each state shows different fill level
        /// Colors: green (top/boost) → yellow → orange → red (bottom/cut)
        public static let sliderBarSpriteX: CGFloat = 13
        public static let sliderBarSpriteY: CGFloat = 164
        public static let sliderBarSpriteWidth: CGFloat = 209
        public static let sliderBarStateWidth: CGFloat = 209.0 / 28.0  // ~7.46 pixels per state
        public static let sliderBarStateCount: Int = 28
        public static let sliderBarHeight: CGFloat = 63
        
        /// Get source rect for a specific fill state (0-27)
        /// State 0 = minimal fill (knob at top), State 27 = full fill (knob at bottom)
        public static func sliderBarSource(state: Int) -> NSRect {
            let clampedState = min(27, max(0, state))
            let x = sliderBarSpriteX + CGFloat(clampedState) * sliderBarStateWidth
            return NSRect(x: x, y: sliderBarSpriteY, width: sliderBarStateWidth, height: sliderBarHeight)
        }
        
        /// Positions on EQ window
        struct Positions {
            public static let onButton = NSRect(x: 14, y: 18, width: 26, height: 12)
            public static let autoButton = NSRect(x: 40, y: 18, width: 32, height: 12)
            public static let presetsButton = NSRect(x: 217, y: 18, width: 44, height: 12)
        }
    }
    
    // MARK: - Playlist Elements (pledit.bmp - 280x186)
    // Coordinates verified from skin spec
    
    struct Playlist {
        /// Minimum playlist size
        public static let minSize = NSSize(width: 275, height: 116)
        
        /// Title bar height
        public static let titleHeight: CGFloat = 20
        
        /// Bottom border height (thin decorative border, no control bar)
        public static let bottomHeight: CGFloat = 3
        
        // === TITLE BAR (active: y=0, inactive: y=21) ===
        // Total width: 25 + 100 + 25 + 25 = 175px (tiled to fill)
        
        /// Title bar - active state components
        struct TitleBarActive {
            public static let leftCorner = NSRect(x: 0, y: 0, width: 25, height: 20)
            public static let title = NSRect(x: 26, y: 0, width: 100, height: 20)
            public static let tile = NSRect(x: 127, y: 0, width: 25, height: 20)
            public static let rightCorner = NSRect(x: 153, y: 0, width: 25, height: 20)
        }
        
        /// Title bar - inactive state components
        struct TitleBarInactive {
            public static let leftCorner = NSRect(x: 0, y: 21, width: 25, height: 20)
            public static let title = NSRect(x: 26, y: 21, width: 100, height: 20)
            public static let tile = NSRect(x: 127, y: 21, width: 25, height: 20)
            public static let rightCorner = NSRect(x: 153, y: 21, width: 25, height: 20)
        }
        
        // === SIDE TILES (for vertical stretching) ===
        
        /// Left side tile (12px wide)
        public static let leftSideTile = NSRect(x: 0, y: 42, width: 12, height: 29)
        
        /// Right side tile (20px wide) - includes scrollbar track
        public static let rightSideTile = NSRect(x: 31, y: 42, width: 20, height: 29)
        
        // === BOTTOM BAR (height: 38px) ===
        
        /// Bottom bar left corner (contains ADD/REM/SEL buttons)
        public static let bottomLeftCorner = NSRect(x: 0, y: 72, width: 125, height: 38)
        
        /// Bottom bar tile (fills middle)
        public static let bottomTile = NSRect(x: 179, y: 0, width: 25, height: 38)
        
        /// Bottom bar right corner (contains MISC/LIST buttons + resize grip)
        public static let bottomRightCorner = NSRect(x: 126, y: 72, width: 150, height: 38)
        
        // === SCROLLBAR ===
        
        /// Scrollbar handle - normal state
        public static let scrollbarThumbNormal = NSRect(x: 52, y: 53, width: 8, height: 18)
        
        /// Scrollbar handle - pressed state
        public static let scrollbarThumbPressed = NSRect(x: 61, y: 53, width: 8, height: 18)
        
        /// Scrollbar background/track (tiled vertically)
        public static let scrollbarTrack = NSRect(x: 36, y: 42, width: 8, height: 29)
        
        // === BUTTON GROUPS (each button is 22x18, pressed state at x+23) ===
        // Button groups are positioned in the bottom bar
        
        struct Buttons {
            /// Button size
            public static let buttonWidth: CGFloat = 22
            public static let buttonHeight: CGFloat = 18
            
            // ADD button group (3 options in popup)
            public static let addURLNormal = NSRect(x: 0, y: 111, width: 22, height: 18)
            public static let addURLPressed = NSRect(x: 23, y: 111, width: 22, height: 18)
            public static let addDirNormal = NSRect(x: 0, y: 130, width: 22, height: 18)
            public static let addDirPressed = NSRect(x: 23, y: 130, width: 22, height: 18)
            public static let addFileNormal = NSRect(x: 0, y: 149, width: 22, height: 18)
            public static let addFilePressed = NSRect(x: 23, y: 149, width: 22, height: 18)
            
            // REM button group (4 options in popup)
            public static let remAllNormal = NSRect(x: 54, y: 111, width: 22, height: 18)
            public static let remAllPressed = NSRect(x: 77, y: 111, width: 22, height: 18)
            public static let remCropNormal = NSRect(x: 54, y: 130, width: 22, height: 18)
            public static let remCropPressed = NSRect(x: 77, y: 130, width: 22, height: 18)
            public static let remSelectedNormal = NSRect(x: 54, y: 149, width: 22, height: 18)
            public static let remSelectedPressed = NSRect(x: 77, y: 149, width: 22, height: 18)
            public static let remMiscNormal = NSRect(x: 54, y: 168, width: 22, height: 18)
            public static let remMiscPressed = NSRect(x: 77, y: 168, width: 22, height: 18)
            
            // SEL button group (3 options in popup)
            public static let selInvertNormal = NSRect(x: 104, y: 111, width: 22, height: 18)
            public static let selInvertPressed = NSRect(x: 127, y: 111, width: 22, height: 18)
            public static let selZeroNormal = NSRect(x: 104, y: 130, width: 22, height: 18)
            public static let selZeroPressed = NSRect(x: 127, y: 130, width: 22, height: 18)
            public static let selAllNormal = NSRect(x: 104, y: 149, width: 22, height: 18)
            public static let selAllPressed = NSRect(x: 127, y: 149, width: 22, height: 18)
            
            // MISC button group (3 options in popup)
            public static let miscSortNormal = NSRect(x: 154, y: 111, width: 22, height: 18)
            public static let miscSortPressed = NSRect(x: 177, y: 111, width: 22, height: 18)
            public static let miscInfoNormal = NSRect(x: 154, y: 130, width: 22, height: 18)
            public static let miscInfoPressed = NSRect(x: 177, y: 130, width: 22, height: 18)
            public static let miscOptsNormal = NSRect(x: 154, y: 149, width: 22, height: 18)
            public static let miscOptsPressed = NSRect(x: 177, y: 149, width: 22, height: 18)
            
            // LIST button group (3 options in popup)
            public static let listNewNormal = NSRect(x: 204, y: 111, width: 22, height: 18)
            public static let listNewPressed = NSRect(x: 227, y: 111, width: 22, height: 18)
            public static let listSaveNormal = NSRect(x: 204, y: 130, width: 22, height: 18)
            public static let listSavePressed = NSRect(x: 227, y: 130, width: 22, height: 18)
            public static let listLoadNormal = NSRect(x: 204, y: 149, width: 22, height: 18)
            public static let listLoadPressed = NSRect(x: 227, y: 149, width: 22, height: 18)
        }
        
        /// Button positions in the bottom bar (in skin coordinates)
        struct ButtonPositions {
            // Button positions relative to bottom-left of window
            // These are at y=0 of the bottom bar (which is 38px tall)
            public static let addButton = NSRect(x: 11, y: 0, width: 25, height: 18)
            public static let remButton = NSRect(x: 40, y: 0, width: 25, height: 18)
            public static let selButton = NSRect(x: 70, y: 0, width: 25, height: 18)
            public static let miscButton = NSRect(x: 99, y: 0, width: 25, height: 18)
            // LIST button is positioned relative to right edge
            public static let listButtonOffset: CGFloat = 46  // From right edge
        }
        
        /// Mini transport button positions in the bottom bar (top-left area)
        /// These are the small prev/play/pause/stop/next buttons visible in the skin
        struct MiniTransportPositions {
            // Button dimensions - small transport buttons
            public static let buttonWidth: CGFloat = 8
            public static let buttonHeight: CGFloat = 7
            // Y position from top of bottom bar
            public static let buttonY: CGFloat = 4
            // X positions for each button
            public static let previousX: CGFloat = 7
            public static let playX: CGFloat = 16
            public static let pauseX: CGFloat = 25
            public static let stopX: CGFloat = 34
            public static let nextX: CGFloat = 43
        }
        
        /// Window control button positions in title bar
        struct TitleBarButtons {
            // Relative to right edge of window
            public static let closeOffset: CGFloat = 11   // Right edge - 11px
            public static let shadeOffset: CGFloat = 20   // Right edge - 20px
        }
    }
    
    // MARK: - Plex Browser Elements
    // Uses playlist sprites for frame/chrome with custom content areas
    
    struct PlexBrowser {
        /// Minimum window size (wider than playlist to fit tabs)
        /// Width must be: (N * 25) + 50 for pixel-perfect tile alignment
        /// 500 = 18 tiles * 25 + 50 (corners)
        public static let minSize = NSSize(width: 500, height: 300)
        
        /// Default window size
        public static let defaultSize = NSSize(width: 550, height: 450)
        
        /// Layout constants for Plex browser areas
        struct Layout {
            public static let titleBarHeight: CGFloat = 20
            public static let tabBarHeight: CGFloat = 24
            public static let serverBarHeight: CGFloat = 24
            public static let searchBarHeight: CGFloat = 26
            public static let statusBarHeight: CGFloat = 6  // Bottom padding
            public static let scrollbarWidth: CGFloat = 10
            public static let alphabetWidth: CGFloat = 16
            public static let leftBorder: CGFloat = 6
            public static let rightBorder: CGFloat = 6
            public static let padding: CGFloat = 3
        }
        
        /// Shade mode height (same as playlist shade)
        public static let shadeHeight: CGFloat = 14
        
        /// Window control button positions in title bar (same as playlist)
        struct TitleBarButtons {
            // Relative to right edge of window
            public static let closeOffset: CGFloat = 11
            public static let shadeOffset: CGFloat = 20
        }
    }
    
    // MARK: - Library Window Elements
    // Custom library window skin from library-window.png (500x348 pixels)
    // Used for the Media Library window as a replacement for playlist-based Plex browser chrome
    
    struct LibraryWindow {
        /// The PNG dimensions
        public static let imageSize = NSSize(width: 500, height: 348)
        
        /// Minimum window size (same as image dimensions)
        public static let minSize = NSSize(width: 480, height: 300)
        
        /// Default window size
        public static let defaultSize = NSSize(width: 500, height: 400)
        
        // MARK: - Title Bar (18px height)
        struct TitleBar {
            public static let height: CGFloat = 18
            
            /// Left corner - contains decorative element
            public static let leftCorner = NSRect(x: 0, y: 0, width: 25, height: 18)
            
            /// Tileable middle section
            public static let tile = NSRect(x: 25, y: 0, width: 25, height: 18)
            
            /// Right corner - contains close button area
            public static let rightCorner = NSRect(x: 475, y: 0, width: 25, height: 18)
            
            /// Title sprite containing "NULLPLAYER LIBRARY" text - extracted from center of title bar
            /// This is the actual rendered title text from the PNG, not a tile
            public static let titleSprite = NSRect(x: 175, y: 0, width: 150, height: 18)
        }
        
        // MARK: - Side Borders
        struct Borders {
            /// Left side border width
            public static let leftWidth: CGFloat = 6
            
            /// Right side border width (includes scrollbar track)
            public static let rightWidth: CGFloat = 20
            
            /// Left side tile (repeatable vertically)
            public static let leftTile = NSRect(x: 0, y: 18, width: 6, height: 29)
            
            /// Right side tile (repeatable vertically, includes scrollbar track)
            public static let rightTile = NSRect(x: 480, y: 18, width: 20, height: 29)
        }
        
        // MARK: - Status Bar / Bottom (28px height)
        struct StatusBar {
            public static let height: CGFloat = 28
            
            /// Left corner - contains Play/Remove buttons
            public static let leftCorner = NSRect(x: 0, y: 320, width: 125, height: 28)
            
            /// Tileable middle section
            public static let tile = NSRect(x: 125, y: 320, width: 25, height: 28)
            
            /// Right corner
            public static let rightCorner = NSRect(x: 450, y: 320, width: 50, height: 28)
        }
        
        // MARK: - Scrollbar
        struct Scrollbar {
            /// Scrollbar track width
            public static let width: CGFloat = 14
            
            /// Scrollbar track tile (repeatable vertically)
            public static let trackTile = NSRect(x: 486, y: 50, width: 14, height: 29)
            
            /// Scrollbar thumb
            public static let thumbHeight: CGFloat = 18
            public static let thumb = NSRect(x: 486, y: 100, width: 14, height: 18)
        }
        
        // MARK: - Layout Constants
        struct Layout {
            public static let titleBarHeight: CGFloat = 18
            public static let searchBarHeight: CGFloat = 24
            public static let columnHeaderHeight: CGFloat = 22
            public static let statusBarHeight: CGFloat = 3   // Thin bottom border
            public static let scrollbarWidth: CGFloat = 8    // Match playlist scrollbar
            public static let leftBorder: CGFloat = 3        // Thin side borders
            public static let rightBorder: CGFloat = 11      // Scrollbar (8) + edge (3)
            public static let padding: CGFloat = 3
        }
        
        // MARK: - Window Button Positions
        struct TitleBarButtons {
            /// Close button offset from right edge
            public static let closeOffset: CGFloat = 5
            /// Shade button offset from right edge
            public static let shadeOffset: CGFloat = 15
        }
    }
    
    // MARK: - ProjectM Visualization Window
    // Uses PLEDIT.BMP title bar style with GenFont text
    
    struct ProjectM {
        /// Minimum window size
        public static let minSize = NSSize(width: 275, height: 150)
        
        /// Default window size - matches Plex Browser (height = 3 stacked main windows)
        public static var defaultSize: NSSize {
            let height = SkinConstants.mainWindowSize.height * 3
            return NSSize(width: 550, height: height)
        }
        
        /// Title bar height (same as playlist: 20px)
        public static let titleBarHeight: CGFloat = 20
        
        /// Shade mode height (title bar only)
        public static let shadeHeight: CGFloat = 14
        
        /// Layout constants - playlist style title bar with thin borders
        struct Layout {
            public static let titleBarHeight: CGFloat = 20   // Same as playlist
            public static let leftBorder: CGFloat = 3        // Thin borders
            public static let rightBorder: CGFloat = 3       
            public static let bottomBorder: CGFloat = 3      
        }
        
        // MARK: - Title Bar (same style as playlist)
        
        struct TitleBar {
            /// Title bar height (same as playlist)
            public static let height: CGFloat = 20
            
            /// Close button position (relative to right edge of title bar)
            public static let closeButtonOffset: CGFloat = 11
            public static let closeButtonY: CGFloat = 3
            public static let closeButtonSize: CGFloat = 9
        }
        
        /// Window control button positions in title bar
        struct TitleBarButtons {
            // Relative to right edge of window (same as playlist)
            public static let closeOffset: CGFloat = 11
            public static let shadeOffset: CGFloat = 20
        }
        
        /// Shade mode positions
        struct ShadePositions {
            public static let closeButton = NSRect(x: -11, y: 3, width: 9, height: 9)  // Relative to right edge
        }
    }
    
    // MARK: - Art Visualizer Window
    // Audio-reactive album art visualization window
    // Uses same chrome style as ProjectM window
    
    struct ArtVisualizer {
        /// Minimum window size
        public static let minSize = NSSize(width: 300, height: 300)
        
        /// Default window size - square for album art
        public static let defaultSize = NSSize(width: 500, height: 500)
        
        /// Title bar height (same as ProjectM/playlist)
        public static let titleBarHeight: CGFloat = 20
        
        /// Shade mode height (title bar only)
        public static let shadeHeight: CGFloat = 14
        
        /// Layout constants
        struct Layout {
            public static let titleBarHeight: CGFloat = 20
            public static let leftBorder: CGFloat = 3
            public static let rightBorder: CGFloat = 3
            public static let bottomBorder: CGFloat = 3
        }
        
        /// Window control button positions in title bar
        struct TitleBarButtons {
            // Relative to right edge of window (same as ProjectM)
            public static let closeOffset: CGFloat = 11
            public static let shadeOffset: CGFloat = 20
        }
    }
    
    // MARK: - GEN.BMP (Generic/AVS/ProjectM window)
    
    /// Sprites from GEN.BMP - used for AVS/ProjectM window chrome
    /// GEN.BMP layout (194x109):
    /// - Y=0-19: Active title bar (20px) - left corner (25px), tile (29px at x=26), right corner (41px at x=153)
    /// - Y=21-40: Inactive title bar (20px) - same structure as active
    /// - Y=42-70: Side borders (29px) - left border (11px at x=0), right border (11px at x=12)
    /// - Y=72-85: Bottom bar (14px) - left corner (11px), tile (29px at x=12), right corner (11px at x=42)
    /// - Y=88-93: Alphabet A-Z (5x6 pixels each, 1px spacing between)
    /// - Y=96-101: Numbers 0-9 and symbols (5x6 pixels each)
    struct GenWindow {
        /// GEN.BMP dimensions
        public static let imageWidth: CGFloat = 194
        public static let imageHeight: CGFloat = 109
        
        /// Title bar height
        public static let titleBarHeight: CGFloat = 20
        
        // MARK: - Title Bar Active (y=0-19)
        struct TitleBarActive {
            /// Left corner (grip area)
            public static let leftCorner = NSRect(x: 0, y: 0, width: 25, height: 20)
            /// Tileable middle section
            public static let tile = NSRect(x: 26, y: 0, width: 29, height: 20)
            /// Right corner (contains window buttons)
            public static let rightCorner = NSRect(x: 153, y: 0, width: 41, height: 20)
        }
        
        // MARK: - Title Bar Inactive (y=21-40)
        struct TitleBarInactive {
            /// Left corner (grip area)
            public static let leftCorner = NSRect(x: 0, y: 21, width: 25, height: 20)
            /// Tileable middle section
            public static let tile = NSRect(x: 26, y: 21, width: 29, height: 20)
            /// Right corner (contains window buttons)
            public static let rightCorner = NSRect(x: 153, y: 21, width: 41, height: 20)
        }
        
        // MARK: - Window Chrome (y=42-71)
        struct Chrome {
            /// Left border tile (for vertical tiling)
            public static let leftBorder = NSRect(x: 0, y: 42, width: 11, height: 29)
            /// Right border tile
            public static let rightBorder = NSRect(x: 12, y: 42, width: 11, height: 29)
            /// Bottom left corner
            public static let bottomLeftCorner = NSRect(x: 0, y: 72, width: 11, height: 14)
            /// Bottom tile (for horizontal tiling)
            public static let bottomTile = NSRect(x: 12, y: 72, width: 29, height: 14)
            /// Bottom right corner
            public static let bottomRightCorner = NSRect(x: 42, y: 72, width: 11, height: 14)
        }
        
        // MARK: - Window Button Positions (relative to right edge)
        struct Buttons {
            public static let closeOffset: CGFloat = 9
            public static let shadeOffset: CGFloat = 18
        }
    }
    
    /// Font sprites from GEN.BMP - used for AVS/ProjectM window titles
    /// Gen.gif layout: 194x109 pixels - VARIABLE WIDTH FONT
    /// Y=89-94: Active alphabet A-Z (white/bright, 6px tall, variable width)
    /// Y=97-102: Inactive alphabet A-Z (muted/darker, 6px tall, variable width)
    struct GenFont {
        public static let charHeight: CGFloat = 6
        public static let charSpacing: CGFloat = 1  // Space between characters when rendering
        
        /// Y position of the ACTIVE alphabet row in GEN.BMP (white/bright)
        public static let activeAlphabetY: CGFloat = 89
        
        /// Y position of the INACTIVE alphabet row in GEN.BMP (muted/darker)
        public static let inactiveAlphabetY: CGFloat = 97
        
        /// Character positions - (startX, width) for each letter A-Z
        /// Extracted from gen.png cyan separator columns
        public static let charPositions: [(x: CGFloat, width: CGFloat)] = [
            (1, 6),    // A
            (8, 7),    // B
            (16, 7),   // C
            (24, 6),   // D
            (31, 6),   // E
            (38, 6),   // F
            (45, 7),   // G
            (53, 6),   // H
            (60, 4),   // I
            (65, 6),   // J
            (72, 7),   // K
            (80, 5),   // L
            (86, 8),   // M
            (95, 6),   // N
            (102, 6),  // O
            (109, 6),  // P
            (116, 7),  // Q
            (124, 7),  // R
            (132, 6),  // S
            (139, 5),  // T
            (145, 6),  // U
            (152, 6),  // V
            (159, 8),  // W
            (168, 7),  // X
            (176, 6),  // Y
            (183, 5),  // Z
        ]
        
        /// Get the source rect for a character from GEN.BMP
        /// - Parameters:
        ///   - char: The character to get
        ///   - active: Whether to use the active (bright) or inactive (muted) row
        /// - Returns: Source rect and character width, or nil for unsupported chars
        public static func character(_ char: Character, active: Bool = true) -> (rect: NSRect, width: CGFloat)? {
            let upperChar = char.uppercased().first ?? char
            let alphabetY = active ? activeAlphabetY : inactiveAlphabetY
            
            switch upperChar {
            case "A"..."Z":
                let index = Int(upperChar.asciiValue! - Character("A").asciiValue!)
                let pos = charPositions[index]
                return (NSRect(x: pos.x, y: alphabetY, width: pos.width, height: charHeight), pos.width)
            case " ":
                // Space - return width but no rect
                return nil
            default:
                return nil
            }
        }
        
        /// Calculate total width needed for a string
        public static func textWidth(_ text: String) -> CGFloat {
            var width: CGFloat = 0
            let chars = Array(text.uppercased())
            for (i, char) in chars.enumerated() {
                if let charInfo = character(char) {
                    width += charInfo.width
                    if i < chars.count - 1 {
                        width += charSpacing
                    }
                } else if char == " " {
                    width += 4 + charSpacing  // Space width
                }
            }
            return width
        }
    }
    
    // MARK: - Title Bar Font
    
    /// Character sources for title bar text
    /// Characters can come from:
    /// - PLEDIT.BMP title sprite (26,0 - 100x20): "NULLPLAYER PLAYLIST"
    /// - EQMAIN.BMP title bar (0, 134 - 275x14): "EQUALIZER"
    struct TitleBarFont {
        public static let charWidth: CGFloat = 5
        public static let charHeight: CGFloat = 6
        public static let charSpacing: CGFloat = 1
        
        /// Source image for a character
        enum CharSource {
            case pledit(x: CGFloat, y: CGFloat)  // From pledit.bmp title sprite area
            case eqmain(x: CGFloat, y: CGFloat)  // From eqmain.bmp title bar
            case fallback  // Not available, use pixel fallback
        }
        
        /// Get the source for a character
        /// PLEDIT title sprite: "NULLPLAYER PLAYLIST" at (26,0), text starts ~x=33, y=5
        /// EQMAIN title bar: "EQUALIZER" at (0,134), text starts ~x=108, y=5
        public static func charSource(for char: Character) -> CharSource {
            // Offsets within the respective sprites
            let pleditBase: CGFloat = 26 + 7  // Title sprite starts at 26, text at +7
            let pleditY: CGFloat = 5
            let eqBase: CGFloat = 108  // "EQUALIZER" centered in 275px title bar
            let eqY: CGFloat = 134 + 5  // Title bar at y=134, text at +5
            
            switch char.uppercased().first ?? " " {
            // From "NULLPLAYER PLAYLIST" in pledit.bmp
            case "W": return .pledit(x: pleditBase + 0, y: pleditY)
            case "I": return .pledit(x: pleditBase + 6, y: pleditY)
            case "N": return .pledit(x: pleditBase + 12, y: pleditY)
            case "A": return .pledit(x: pleditBase + 18, y: pleditY)
            case "M": return .pledit(x: pleditBase + 24, y: pleditY)
            case "P": return .pledit(x: pleditBase + 30, y: pleditY)
            case " ": return .pledit(x: pleditBase + 36, y: pleditY)
            case "L": return .pledit(x: pleditBase + 48, y: pleditY)
            case "Y": return .pledit(x: pleditBase + 60, y: pleditY)
            case "S": return .pledit(x: pleditBase + 78, y: pleditY)
            case "T": return .pledit(x: pleditBase + 84, y: pleditY)
            
            // From "EQUALIZER" in eqmain.bmp
            case "E": return .eqmain(x: eqBase + 0, y: eqY)
            case "Q": return .eqmain(x: eqBase + 6, y: eqY)
            case "U": return .eqmain(x: eqBase + 12, y: eqY)
            // A already from NULLPLAYER
            // L already from PLAYLIST
            // I already from NULLPLAYER
            case "Z": return .eqmain(x: eqBase + 30, y: eqY)
            case "R": return .eqmain(x: eqBase + 42, y: eqY)  // Last R in EQUALIZER
            
            // Fallback for missing characters (X, B, O, etc.)
            default: return .fallback
            }
        }
        
        /// Pixel patterns for fallback characters (5x6 pixels)
        /// Each row is 5 bits, MSB on left
        public static func fallbackPixels(for char: Character) -> [UInt8] {
            switch char.uppercased().first ?? "?" {
            case "B": return [0b11110, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]
            case "C": return [0b01110, 0b10001, 0b10000, 0b10000, 0b10001, 0b01110]
            case "D": return [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]
            case "F": return [0b11111, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]
            case "G": return [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b01110]
            case "H": return [0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]
            case "J": return [0b00111, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100]
            case "K": return [0b10001, 0b10010, 0b11100, 0b10010, 0b10001, 0b10001]
            case "O": return [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]
            case "V": return [0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100]
            case "X": return [0b10001, 0b01010, 0b00100, 0b00100, 0b01010, 0b10001]
            default:  return [0b11111, 0b10001, 0b10001, 0b10001, 0b10001, 0b11111] // Box
            }
        }
    }
}

// MARK: - Helper Extensions

public extension SkinElements {
    
    /// Get sprite rect for a button type and state
    public static func spriteRect(for button: ButtonType, state: ButtonState) -> NSRect {
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
            switch state {
            case .normal: return Equalizer.onButtonOffNormal
            case .pressed: return Equalizer.onButtonOffPressed
            case .active: return Equalizer.onButtonOnNormal
            case .activePressed: return Equalizer.onButtonOnPressed
            }
        case .eqAuto:
            switch state {
            case .normal: return Equalizer.autoButtonOffNormal
            case .pressed: return Equalizer.autoButtonOffPressed
            case .active: return Equalizer.autoButtonOnNormal
            case .activePressed: return Equalizer.autoButtonOnPressed
            }
        case .eqPresets:
            return state == .pressed ? Equalizer.presetsPressed : Equalizer.presetsNormal
        default:
            return .zero
        }
    }
    
    /// Get hit rect for a button on the main window (normal mode)
    public static func hitRect(for button: ButtonType) -> NSRect {
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
    public static func shadeHitRect(for button: ButtonType) -> NSRect {
        switch button {
        case .close: return TitleBar.ShadePositions.closeButton
        case .minimize: return TitleBar.ShadePositions.minimizeButton
        case .unshade: return TitleBar.ShadePositions.unshadeButton
        default: return .zero
        }
    }
}
