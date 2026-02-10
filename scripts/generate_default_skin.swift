#!/usr/bin/env swift
// generate_default_skin.swift
// Standalone macOS Swift script that generates all BMP sprite sheets for
// a complete Winamp-format .wsz classic skin: NullPlayer-Silver.
// Run: swift scripts/generate_default_skin.swift

import AppKit
import Foundation

// MARK: - Color Palette

struct C {
    static let bgSilver       = (224, 224, 224)
    static let bgDarker       = (200, 200, 200)
    static let titleActive1   = (192, 192, 192) // gradient start
    static let titleActive2   = (208, 208, 208) // gradient end
    static let titleInactive  = (224, 224, 224)
    static let buttonFace     = (216, 216, 216)
    static let buttonPressed  = (176, 176, 176)
    static let iconDark       = (64, 64, 64)
    static let insetBG        = (26, 26, 46)
    static let insetText      = (200, 255, 208)
    static let sliderTrack    = (160, 160, 160)
    static let sliderFill     = (255, 140, 0)
    static let posThumb       = (80, 128, 192)
    static let posThumbPress  = (64, 96, 144)
    static let activeToggle   = (96, 160, 96)
    static let activeToggleP  = (64, 128, 64)
    static let magenta        = (255, 0, 255)
    static let playlistBG     = (240, 240, 240)
    static let playlistText   = (48, 48, 48)
    static let playlistCurr   = (0, 0, 0)
    static let playlistSel    = (192, 216, 240)
    static let highlight      = (255, 255, 255)
    static let shadow         = (128, 128, 128)
    static let darkShadow     = (96, 96, 96)
    static let lcdDimText     = (64, 64, 64)
    static let amber          = (255, 215, 0)
    static let white          = (240, 240, 240)
    static let dimWhite       = (128, 128, 128)
    static let black          = (0, 0, 0)
}

// MARK: - Bitmap Helpers

func createBitmap(width: Int, height: Int) -> NSBitmapImageRep {
    return NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 3,
        hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 3, bitsPerPixel: 24
    )!
}

func saveBMP(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .bmp, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

func setPixel(_ rep: NSBitmapImageRep, x: Int, y: Int, r: Int, g: Int, b: Int) {
    guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return }
    let ptr = rep.bitmapData!
    let bpr = rep.bytesPerRow
    let offset = y * bpr + x * 3
    ptr[offset] = UInt8(clamping: r)
    ptr[offset + 1] = UInt8(clamping: g)
    ptr[offset + 2] = UInt8(clamping: b)
}

func fillRect(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int, r: Int, g: Int, b: Int) {
    for py in y..<(y + h) {
        for px in x..<(x + w) {
            setPixel(rep, x: px, y: py, r: r, g: g, b: b)
        }
    }
}

func fillRect(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int, _ c: (Int, Int, Int)) {
    fillRect(rep, x: x, y: y, w: w, h: h, r: c.0, g: c.1, b: c.2)
}

/// Horizontal gradient fill
func fillGradientH(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int,
                   from c1: (Int, Int, Int), to c2: (Int, Int, Int)) {
    for px in 0..<w {
        let t = w > 1 ? Double(px) / Double(w - 1) : 0.0
        let r = Int(Double(c1.0) + t * Double(c2.0 - c1.0))
        let g = Int(Double(c1.1) + t * Double(c2.1 - c1.1))
        let b = Int(Double(c1.2) + t * Double(c2.2 - c1.2))
        for py in 0..<h {
            setPixel(rep, x: x + px, y: y + py, r: r, g: g, b: b)
        }
    }
}

/// Draw 3D raised border (light top-left, dark bottom-right)
func drawRaisedRect(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int) {
    // Top edge - highlight
    for px in x..<(x + w) { setPixel(rep, x: px, y: y, r: 255, g: 255, b: 255) }
    // Left edge - highlight
    for py in y..<(y + h) { setPixel(rep, x: x, y: py, r: 255, g: 255, b: 255) }
    // Bottom edge - shadow
    for px in x..<(x + w) { setPixel(rep, x: px, y: y + h - 1, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    // Right edge - shadow
    for py in y..<(y + h) { setPixel(rep, x: x + w - 1, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
}

/// Draw 3D sunken border (dark top-left, light bottom-right)
func drawSunkenRect(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int) {
    for px in x..<(x + w) { setPixel(rep, x: px, y: y, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    for py in y..<(y + h) { setPixel(rep, x: x, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    for px in x..<(x + w) { setPixel(rep, x: px, y: y + h - 1, r: 255, g: 255, b: 255) }
    for py in y..<(y + h) { setPixel(rep, x: x + w - 1, y: py, r: 255, g: 255, b: 255) }
}

/// Draw icon from pattern array where '#' = colored pixel
func drawIcon(_ rep: NSBitmapImageRep, pattern: [String], x: Int, y: Int, r: Int, g: Int, b: Int) {
    for (row, line) in pattern.enumerated() {
        for (col, ch) in line.enumerated() {
            if ch == "#" {
                setPixel(rep, x: x + col, y: y + row, r: r, g: g, b: b)
            }
        }
    }
}

func drawIcon(_ rep: NSBitmapImageRep, pattern: [String], x: Int, y: Int, _ c: (Int, Int, Int)) {
    drawIcon(rep, pattern: pattern, x: x, y: y, r: c.0, g: c.1, b: c.2)
}

// MARK: - 5x6 Pixel Font

let font5x6: [Character: [String]] = [
    "A": [" ### ", "#   #", "#####", "#   #", "#   #", "     "],
    "B": ["#### ", "#   #", "#### ", "#   #", "#### ", "     "],
    "C": [" ### ", "#   #", "#    ", "#   #", " ### ", "     "],
    "D": ["#### ", "#   #", "#   #", "#   #", "#### ", "     "],
    "E": ["#####", "#    ", "#### ", "#    ", "#####", "     "],
    "F": ["#####", "#    ", "#### ", "#    ", "#    ", "     "],
    "G": [" ### ", "#    ", "# ###", "#   #", " ### ", "     "],
    "H": ["#   #", "#   #", "#####", "#   #", "#   #", "     "],
    "I": [" ### ", "  #  ", "  #  ", "  #  ", " ### ", "     "],
    "J": ["  ###", "   # ", "   # ", "#  # ", " ## ", "     "],
    "K": ["#  # ", "# #  ", "##   ", "# #  ", "#  # ", "     "],
    "L": ["#    ", "#    ", "#    ", "#    ", "#####", "     "],
    "M": ["#   #", "## ##", "# # #", "#   #", "#   #", "     "],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "     "],
    "O": [" ### ", "#   #", "#   #", "#   #", " ### ", "     "],
    "P": ["#### ", "#   #", "#### ", "#    ", "#    ", "     "],
    "Q": [" ### ", "#   #", "# # #", "#  # ", " ## #", "     "],
    "R": ["#### ", "#   #", "#### ", "# #  ", "#  ##", "     "],
    "S": [" ####", "#    ", " ### ", "    #", "#### ", "     "],
    "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "     "],
    "U": ["#   #", "#   #", "#   #", "#   #", " ### ", "     "],
    "V": ["#   #", "#   #", " # # ", " # # ", "  #  ", "     "],
    "W": ["#   #", "#   #", "# # #", "## ##", "#   #", "     "],
    "X": ["#   #", " # # ", "  #  ", " # # ", "#   #", "     "],
    "Y": ["#   #", " # # ", "  #  ", "  #  ", "  #  ", "     "],
    "Z": ["#####", "   # ", "  #  ", " #   ", "#####", "     "],
    "0": [" ### ", "#  ##", "# # #", "##  #", " ### ", "     "],
    "1": ["  #  ", " ##  ", "  #  ", "  #  ", " ### ", "     "],
    "2": [" ### ", "#   #", "  ## ", " #   ", "#####", "     "],
    "3": ["#### ", "    #", " ### ", "    #", "#### ", "     "],
    "4": ["#  # ", "#  # ", "#####", "   # ", "   # ", "     "],
    "5": ["#####", "#    ", "#### ", "    #", "#### ", "     "],
    "6": [" ### ", "#    ", "#### ", "#   #", " ### ", "     "],
    "7": ["#####", "   # ", "  #  ", " #   ", " #   ", "     "],
    "8": [" ### ", "#   #", " ### ", "#   #", " ### ", "     "],
    "9": [" ### ", "#   #", " ####", "    #", " ### ", "     "],
    ":": ["     ", "  #  ", "     ", "  #  ", "     ", "     "],
    "(": ["  #  ", " #   ", " #   ", " #   ", "  #  ", "     "],
    ")": ["  #  ", "   # ", "   # ", "   # ", "  #  ", "     "],
    "-": ["     ", "     ", " ### ", "     ", "     ", "     "],
    "'": ["  #  ", "  #  ", "     ", "     ", "     ", "     "],
    "!": ["  #  ", "  #  ", "  #  ", "     ", "  #  ", "     "],
    "_": ["     ", "     ", "     ", "     ", "#####", "     "],
    "+": ["     ", "  #  ", " ### ", "  #  ", "     ", "     "],
    "\\": ["#    ", " #   ", "  #  ", "   # ", "    #", "     "],
    "/": ["    #", "   # ", "  #  ", " #   ", "#    ", "     "],
    "[": [" ##  ", " #   ", " #   ", " #   ", " ##  ", "     "],
    "]": ["  ## ", "   # ", "   # ", "   # ", "  ## ", "     "],
    "^": ["  #  ", " # # ", "     ", "     ", "     ", "     "],
    "&": [" ##  ", "#  # ", " ##  ", "#  # ", " ## #", "     "],
    "%": ["#  # ", "   # ", "  #  ", " #   ", "#  # ", "     "],
    ".": ["     ", "     ", "     ", "     ", "  #  ", "     "],
    "=": ["     ", " ### ", "     ", " ### ", "     ", "     "],
    "$": ["  #  ", " ####", " ##  ", "  ## ", "#### ", "  #  "],
    "#": [" # # ", "#####", " # # ", "#####", " # # ", "     "],
    "?": [" ### ", "#   #", "  ## ", "     ", "  #  ", "     "],
    "*": ["     ", " # # ", "  #  ", " # # ", "     ", "     "],
    "\"":["# #  ", "# #  ", "     ", "     ", "     ", "     "],
    "@": [" ### ", "# ###", "# # #", "# ## ", " ### ", "     "],
    " ": ["     ", "     ", "     ", "     ", "     ", "     "],
]

func drawChar5x6(_ rep: NSBitmapImageRep, char: Character, x: Int, y: Int, r: Int, g: Int, b: Int) {
    guard let pattern = font5x6[char] ?? font5x6[Character(char.uppercased())] else { return }
    drawIcon(rep, pattern: pattern, x: x, y: y, r: r, g: g, b: b)
}

func drawChar5x6(_ rep: NSBitmapImageRep, char: Character, x: Int, y: Int, _ c: (Int, Int, Int)) {
    drawChar5x6(rep, char: char, x: x, y: y, r: c.0, g: c.1, b: c.2)
}

func drawString5x6(_ rep: NSBitmapImageRep, text: String, x: Int, y: Int, _ c: (Int, Int, Int)) {
    for (i, ch) in text.enumerated() {
        drawChar5x6(rep, char: ch, x: x + i * 5, y: y, c)
    }
}

// MARK: - 7-Segment Display Digits

struct Seg7 {
    // Segment definitions for a 9x13 cell
    // top, upperLeft, upperRight, middle, lowerLeft, lowerRight, bottom
    static let segments: [[Bool]] = [
        [true, true, true, false, true, true, true],       // 0
        [false, false, true, false, false, true, false],    // 1
        [true, false, true, true, true, false, true],       // 2
        [true, false, true, true, false, true, true],       // 3
        [false, true, true, true, false, true, false],      // 4
        [true, true, false, true, false, true, true],       // 5
        [true, true, false, true, true, true, true],        // 6
        [true, false, true, false, false, true, false],     // 7
        [true, true, true, true, true, true, true],         // 8
        [true, true, true, true, false, true, true],        // 9
    ]

    static func draw(_ rep: NSBitmapImageRep, digit: Int, x: Int, y: Int,
                     fg: (Int, Int, Int), bg: (Int, Int, Int)) {
        // Fill background
        fillRect(rep, x: x, y: y, w: 9, h: 13, bg)

        if digit == 10 { return } // blank
        if digit == 11 {
            // minus sign - middle segment only
            for px in 2...6 {
                setPixel(rep, x: x + px, y: y + 6, r: fg.0, g: fg.1, b: fg.2)
            }
            return
        }

        guard digit >= 0 && digit <= 9 else { return }
        let segs = segments[digit]

        // Top horizontal: y+1, x+2..x+6
        if segs[0] {
            for px in 2...6 { setPixel(rep, x: x + px, y: y + 1, r: fg.0, g: fg.1, b: fg.2) }
        }
        // Upper-left vertical: x+1, y+2..y+5
        if segs[1] {
            for py in 2...5 { setPixel(rep, x: x + 1, y: y + py, r: fg.0, g: fg.1, b: fg.2) }
        }
        // Upper-right vertical: x+7, y+2..y+5
        if segs[2] {
            for py in 2...5 { setPixel(rep, x: x + 7, y: y + py, r: fg.0, g: fg.1, b: fg.2) }
        }
        // Middle horizontal: y+6, x+2..x+6
        if segs[3] {
            for px in 2...6 { setPixel(rep, x: x + px, y: y + 6, r: fg.0, g: fg.1, b: fg.2) }
        }
        // Lower-left vertical: x+1, y+7..y+10
        if segs[4] {
            for py in 7...10 { setPixel(rep, x: x + 1, y: y + py, r: fg.0, g: fg.1, b: fg.2) }
        }
        // Lower-right vertical: x+7, y+7..y+10
        if segs[5] {
            for py in 7...10 { setPixel(rep, x: x + 7, y: y + py, r: fg.0, g: fg.1, b: fg.2) }
        }
        // Bottom horizontal: y+11, x+2..x+6
        if segs[6] {
            for px in 2...6 { setPixel(rep, x: x + px, y: y + 11, r: fg.0, g: fg.1, b: fg.2) }
        }
    }
}

// MARK: - GenFont (Variable-Width Pixel Letters)

/// Variable-width pixel art glyphs for GenFont, 6px tall
let genFontPatterns: [(Character, Int, [String])] = [
    // (char, width, 6 rows)
    ("A", 6, [" #### ", "#    #", "######", "#    #", "#    #", "      "]),
    ("B", 7, ["#####  ", "#    # ", "#####  ", "#    # ", "#####  ", "       "]),
    ("C", 7, [" ##### ", "#      ", "#      ", "#      ", " ##### ", "       "]),
    ("D", 6, ["####  ", "#   # ", "#   # ", "#   # ", "####  ", "      "]),
    ("E", 6, ["##### ", "#     ", "####  ", "#     ", "##### ", "      "]),
    ("F", 6, ["##### ", "#     ", "####  ", "#     ", "#     ", "      "]),
    ("G", 7, [" ##### ", "#      ", "#  ### ", "#    # ", " ##### ", "       "]),
    ("H", 6, ["#   # ", "#   # ", "##### ", "#   # ", "#   # ", "      "]),
    ("I", 4, ["### ", " #  ", " #  ", " #  ", "### ", "    "]),
    ("J", 6, ["  ### ", "    # ", "    # ", "#   # ", " ### ", "      "]),
    ("K", 7, ["#   #  ", "#  #   ", "###    ", "#  #   ", "#   #  ", "       "]),
    ("L", 5, ["#    ", "#    ", "#    ", "#    ", "#### ", "     "]),
    ("M", 8, ["#    # #", "##  ## #", "# ## # #", "#    # #", "#    # #", "        "]),
    ("N", 6, ["#   # ", "##  # ", "# # # ", "#  ## ", "#   # ", "      "]),
    ("O", 6, [" #### ", "#    #", "#    #", "#    #", " #### ", "      "]),
    ("P", 6, ["##### ", "#    #", "##### ", "#     ", "#     ", "      "]),
    ("Q", 7, [" ####  ", "#    # ", "# #  # ", "#  # # ", " #### #", "       "]),
    ("R", 7, ["#####  ", "#    # ", "#####  ", "#  #   ", "#   ## ", "       "]),
    ("S", 6, [" #####", "#     ", " #### ", "     #", "##### ", "      "]),
    ("T", 5, ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "     "]),
    ("U", 6, ["#   # ", "#   # ", "#   # ", "#   # ", " ### ", "      "]),
    ("V", 6, ["#   # ", "#   # ", " # #  ", " # #  ", "  #   ", "      "]),
    ("W", 8, ["#    # #", "#    # #", "# ## # #", "##  ## #", "#    # #", "        "]),
    ("X", 7, ["#    # ", " #  #  ", "  ##   ", " #  #  ", "#    # ", "       "]),
    ("Y", 6, ["#   # ", " # #  ", "  #   ", "  #   ", "  #   ", "      "]),
    ("Z", 5, ["#####", "   # ", "  #  ", " #   ", "#####", "     "]),
]

// GenFont charPositions (x, width) for A-Z as specified in SkinElements
let genFontCharPositions: [(Int, Int)] = [
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

// MARK: - BMP Generators

// ============================================================
// 1. main.bmp -- 275 x 116
// ============================================================
func generateMain(dir: String) {
    let rep = createBitmap(width: 275, height: 116)
    // Fill entire background silver
    fillRect(rep, x: 0, y: 0, w: 275, h: 116, C.bgSilver)

    // Title bar area (will be overdrawn by titlebar.bmp sprites, but set background)
    fillRect(rep, x: 0, y: 0, w: 275, h: 14, C.bgDarker)

    // Visualization area (24,43) 76x16
    fillRect(rep, x: 24, y: 43, w: 76, h: 16, C.insetBG)
    drawSunkenRect(rep, x: 23, y: 42, w: 78, h: 18)

    // Marquee text area (111,24) 154x13
    fillRect(rep, x: 111, y: 24, w: 154, h: 13, C.insetBG)
    drawSunkenRect(rep, x: 110, y: 23, w: 156, h: 15)

    // Time display area (36,26) to (99,39) => 63x13
    fillRect(rep, x: 36, y: 26, w: 63, h: 13, C.insetBG)
    drawSunkenRect(rep, x: 35, y: 25, w: 65, h: 15)
    // Draw colon dots at approx x=69-70 within time display
    setPixel(rep, x: 73, y: 29, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 74, y: 29, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 73, y: 30, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 74, y: 30, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 73, y: 34, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 74, y: 34, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 73, y: 35, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)
    setPixel(rep, x: 74, y: 35, r: C.insetText.0, g: C.insetText.1, b: C.insetText.2)

    // Bitrate display (111,43) 15x9
    fillRect(rep, x: 111, y: 43, w: 15, h: 9, C.insetBG)

    // Sample rate display (156,43) 10x9
    fillRect(rep, x: 156, y: 43, w: 10, h: 9, C.insetBG)

    // Position bar area (16,72) 248x10
    fillRect(rep, x: 16, y: 72, w: 248, h: 10, C.sliderTrack)
    drawSunkenRect(rep, x: 16, y: 72, w: 248, h: 10)

    // Volume slider area (107,57) 68x13
    fillRect(rep, x: 107, y: 57, w: 68, h: 13, C.sliderTrack)
    drawSunkenRect(rep, x: 107, y: 57, w: 68, h: 13)

    // Balance slider area (177,57) 38x13
    fillRect(rep, x: 177, y: 57, w: 38, h: 13, C.sliderTrack)
    drawSunkenRect(rep, x: 177, y: 57, w: 38, h: 13)

    // Transport button area (16,88) 142x18
    fillRect(rep, x: 16, y: 88, w: 142, h: 18, C.bgDarker)

    // Shuffle/repeat area (164,89) 75x15
    fillRect(rep, x: 164, y: 89, w: 75, h: 15, C.bgDarker)

    // EQ/PL toggle area (219,58) 46x12
    fillRect(rep, x: 219, y: 58, w: 46, h: 12, C.bgDarker)

    // Mono/stereo indicator area (212,41) 56x12
    fillRect(rep, x: 212, y: 41, w: 56, h: 12, C.insetBG)

    saveBMP(rep, to: "\(dir)/main.bmp")
    print("  Generated main.bmp")
}

// ============================================================
// 2. titlebar.bmp -- 302 x 56
// ============================================================
func generateTitlebar(dir: String) {
    let rep = createBitmap(width: 302, height: 56)
    fillRect(rep, x: 0, y: 0, w: 302, h: 56, C.bgSilver)

    // Window control buttons (9x9 each)
    // Menu normal (0,0)
    fillRect(rep, x: 0, y: 0, w: 9, h: 9, C.buttonFace)
    drawRaisedRect(rep, x: 0, y: 0, w: 9, h: 9)
    drawIcon(rep, pattern: ["       ", " ##### ", "       ", " ##### ", "       ", " ##### ", "       "],
             x: 1, y: 1, C.iconDark)

    // Menu pressed (0,9)
    fillRect(rep, x: 0, y: 9, w: 9, h: 9, C.buttonPressed)
    drawSunkenRect(rep, x: 0, y: 9, w: 9, h: 9)
    drawIcon(rep, pattern: ["       ", " ##### ", "       ", " ##### ", "       ", " ##### ", "       "],
             x: 1, y: 10, C.iconDark)

    // Minimize normal (9,0)
    fillRect(rep, x: 9, y: 0, w: 9, h: 9, C.buttonFace)
    drawRaisedRect(rep, x: 9, y: 0, w: 9, h: 9)
    drawIcon(rep, pattern: ["     ", "     ", "     ", "     ", "#####"],
             x: 11, y: 2, C.iconDark)

    // Minimize pressed (9,9)
    fillRect(rep, x: 9, y: 9, w: 9, h: 9, C.buttonPressed)
    drawSunkenRect(rep, x: 9, y: 9, w: 9, h: 9)
    drawIcon(rep, pattern: ["     ", "     ", "     ", "     ", "#####"],
             x: 11, y: 11, C.iconDark)

    // Close normal (18,0)
    fillRect(rep, x: 18, y: 0, w: 9, h: 9, C.buttonFace)
    drawRaisedRect(rep, x: 18, y: 0, w: 9, h: 9)
    drawIcon(rep, pattern: ["#   #", " # # ", "  #  ", " # # ", "#   #"],
             x: 20, y: 2, C.iconDark)

    // Close pressed (18,9)
    fillRect(rep, x: 18, y: 9, w: 9, h: 9, C.buttonPressed)
    drawSunkenRect(rep, x: 18, y: 9, w: 9, h: 9)
    drawIcon(rep, pattern: ["#   #", " # # ", "  #  ", " # # ", "#   #"],
             x: 20, y: 11, C.iconDark)

    // Shade normal (0,18)
    fillRect(rep, x: 0, y: 18, w: 9, h: 9, C.buttonFace)
    drawRaisedRect(rep, x: 0, y: 18, w: 9, h: 9)
    drawIcon(rep, pattern: ["  #  ", " ### ", "#####"],
             x: 2, y: 21, C.iconDark)

    // Shade pressed (9,18)
    fillRect(rep, x: 9, y: 18, w: 9, h: 9, C.buttonPressed)
    drawSunkenRect(rep, x: 9, y: 18, w: 9, h: 9)
    drawIcon(rep, pattern: ["  #  ", " ### ", "#####"],
             x: 11, y: 21, C.iconDark)

    // Unshade normal (0,27)
    fillRect(rep, x: 0, y: 27, w: 9, h: 9, C.buttonFace)
    drawRaisedRect(rep, x: 0, y: 27, w: 9, h: 9)
    drawIcon(rep, pattern: ["#####", " ### ", "  #  "],
             x: 2, y: 30, C.iconDark)

    // Unshade pressed (9,27)
    fillRect(rep, x: 9, y: 27, w: 9, h: 9, C.buttonPressed)
    drawSunkenRect(rep, x: 9, y: 27, w: 9, h: 9)
    drawIcon(rep, pattern: ["#####", " ### ", "  #  "],
             x: 11, y: 30, C.iconDark)

    // Active title bar (27,0) 275x14
    fillGradientH(rep, x: 27, y: 0, w: 275, h: 14, from: C.titleActive1, to: C.titleActive2)
    // Draw 1px border at top and bottom
    for px in 27..<302 {
        setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 13, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    // Inactive title bar (27,15) 275x14
    fillRect(rep, x: 27, y: 15, w: 275, h: 14, C.titleInactive)
    for px in 27..<302 {
        setPixel(rep, x: px, y: 15, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 28, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    // Shade mode active (27,29) 275x14
    fillGradientH(rep, x: 27, y: 29, w: 275, h: 14, from: C.titleActive1, to: C.titleActive2)
    for px in 27..<302 {
        setPixel(rep, x: px, y: 29, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 42, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    // Shade mode inactive (27,42) 275x14
    fillRect(rep, x: 27, y: 42, w: 275, h: 14, C.titleInactive)
    for px in 27..<302 {
        setPixel(rep, x: px, y: 42, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 55, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    saveBMP(rep, to: "\(dir)/titlebar.bmp")
    print("  Generated titlebar.bmp")
}

// ============================================================
// 3. cbuttons.bmp -- 136 x 36
// ============================================================
func generateCButtons(dir: String) {
    let rep = createBitmap(width: 136, height: 36)
    fillRect(rep, x: 0, y: 0, w: 136, h: 36, C.bgSilver)

    struct Btn { let x: Int; let w: Int; let h: Int; let icon: [String] }
    let buttons = [
        Btn(x: 0, w: 23, h: 18, icon: [
            "       ",
            "  #  # ",
            " ## ## ",
            "## ### ",
            " ## ## ",
            "  #  # ",
            "       "]),
        Btn(x: 23, w: 23, h: 18, icon: [
            "       ",
            " #     ",
            " ##    ",
            " ###   ",
            " ##    ",
            " #     ",
            "       "]),
        Btn(x: 46, w: 23, h: 18, icon: [
            "       ",
            " ## ## ",
            " ## ## ",
            " ## ## ",
            " ## ## ",
            " ## ## ",
            "       "]),
        Btn(x: 69, w: 23, h: 18, icon: [
            "       ",
            " ##### ",
            " ##### ",
            " ##### ",
            " ##### ",
            " ##### ",
            "       "]),
        Btn(x: 92, w: 22, h: 18, icon: [
            "       ",
            " #  #  ",
            " ## ## ",
            " ### ##",
            " ## ## ",
            " #  #  ",
            "       "]),
        Btn(x: 114, w: 22, h: 16, icon: [
            "       ",
            "   #   ",
            "  ###  ",
            " ##### ",
            "       ",
            " ##### ",
            "       "]),
    ]

    for btn in buttons {
        // Normal row
        fillRect(rep, x: btn.x, y: 0, w: btn.w, h: btn.h, C.buttonFace)
        drawRaisedRect(rep, x: btn.x, y: 0, w: btn.w, h: btn.h)
        let iy = (btn.h - btn.icon.count) / 2
        let ix = (btn.w - (btn.icon.first?.count ?? 0)) / 2
        drawIcon(rep, pattern: btn.icon, x: btn.x + ix, y: iy, C.iconDark)

        // Pressed row
        let pressedY = btn.h == 16 ? 16 : 18
        fillRect(rep, x: btn.x, y: pressedY, w: btn.w, h: btn.h, C.buttonPressed)
        drawSunkenRect(rep, x: btn.x, y: pressedY, w: btn.w, h: btn.h)
        drawIcon(rep, pattern: btn.icon, x: btn.x + ix + 1, y: pressedY + iy + 1, C.iconDark)
    }

    saveBMP(rep, to: "\(dir)/cbuttons.bmp")
    print("  Generated cbuttons.bmp")
}

// ============================================================
// 4. numbers.bmp -- 108 x 13
// ============================================================
func generateNumbers(dir: String) {
    let rep = createBitmap(width: 108, height: 13)
    // Fill entire background with inset color
    fillRect(rep, x: 0, y: 0, w: 108, h: 13, C.insetBG)

    // Digits 0-9, then blank (10), then minus (11)
    for i in 0...11 {
        Seg7.draw(rep, digit: i, x: i * 9, y: 0, fg: C.insetText, bg: C.insetBG)
    }

    saveBMP(rep, to: "\(dir)/numbers.bmp")
    print("  Generated numbers.bmp")
}

// ============================================================
// 5. text.bmp -- 155 x 18
// ============================================================
func generateText(dir: String) {
    let rep = createBitmap(width: 155, height: 18)
    fillRect(rep, x: 0, y: 0, w: 155, h: 18, C.insetBG)

    // Row 0 (y=0): A-Z at cols 0-25, then ", @, unused, space, unused
    let row0chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ\"@ "
    for (i, ch) in row0chars.enumerated() {
        if i < 31 {
            drawChar5x6(rep, char: ch, x: i * 5, y: 0, C.insetText)
        }
    }

    // Row 1 (y=6): 0-9, unused, unused, :, (, ), -, ', !, _, +, \, /, [, ], ^, &, %, ., =, $, #
    let row1chars: [Character] = ["0","1","2","3","4","5","6","7","8","9"," "," ",":","(",")","-","'","!","_","+","\\","/","[","]","^","&","%",".","=","$","#"]
    for (i, ch) in row1chars.enumerated() {
        if i < 31 {
            drawChar5x6(rep, char: ch, x: i * 5, y: 6, C.insetText)
        }
    }

    // Row 2 (y=12): ?, *, rest blank
    drawChar5x6(rep, char: "?", x: 0, y: 12, C.insetText)
    drawChar5x6(rep, char: "*", x: 5, y: 12, C.insetText)

    saveBMP(rep, to: "\(dir)/text.bmp")
    print("  Generated text.bmp")
}

// ============================================================
// 6. posbar.bmp -- 307 x 10
// ============================================================
func generatePosbar(dir: String) {
    let rep = createBitmap(width: 307, height: 10)

    // Track background (0,0) 248x10
    fillRect(rep, x: 0, y: 0, w: 248, h: 10, C.sliderTrack)
    drawSunkenRect(rep, x: 0, y: 0, w: 248, h: 10)

    // Thumb normal (248,0) 29x10
    fillRect(rep, x: 248, y: 0, w: 29, h: 10, C.posThumb)
    drawRaisedRect(rep, x: 248, y: 0, w: 29, h: 10)
    // Draw a small grip in center of thumb
    for gx in [258, 260, 262] {
        for gy in 3...6 {
            setPixel(rep, x: gx, y: gy, r: 255, g: 255, b: 255)
            setPixel(rep, x: gx + 1, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        }
    }

    // Thumb pressed (278,0) 29x10
    fillRect(rep, x: 278, y: 0, w: 29, h: 10, C.posThumbPress)
    drawSunkenRect(rep, x: 278, y: 0, w: 29, h: 10)
    for gx in [288, 290, 292] {
        for gy in 3...6 {
            setPixel(rep, x: gx, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        }
    }

    saveBMP(rep, to: "\(dir)/posbar.bmp")
    print("  Generated posbar.bmp")
}

// ============================================================
// 7. volume.bmp -- 68 x 433
// ============================================================
func generateVolume(dir: String) {
    let rep = createBitmap(width: 68, height: 433)
    fillRect(rep, x: 0, y: 0, w: 68, h: 433, C.bgSilver)

    // 28 fill states (0-27), each 68x13 at 15px pitch
    for i in 0...27 {
        let y = i * 15
        // Background groove
        fillRect(rep, x: 0, y: y, w: 68, h: 13, C.sliderTrack)
        drawSunkenRect(rep, x: 0, y: y, w: 68, h: 13)
        // Orange fill from left
        if i > 0 {
            let fillW = Int(round(Double(64) * Double(i) / 27.0))
            fillRect(rep, x: 2, y: y + 2, w: fillW, h: 9, C.sliderFill)
        }
    }

    // Thumb normal (15,422) 14x11
    fillRect(rep, x: 15, y: 422, w: 14, h: 11, C.buttonFace)
    drawRaisedRect(rep, x: 15, y: 422, w: 14, h: 11)
    // Small vertical grip lines
    for gx in [19, 21, 23] {
        for gy in (422+3)...(422+7) {
            setPixel(rep, x: gx, y: gy, r: 255, g: 255, b: 255)
            setPixel(rep, x: gx + 1, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        }
    }

    // Thumb pressed (0,422) 14x11
    fillRect(rep, x: 0, y: 422, w: 14, h: 11, C.buttonPressed)
    drawSunkenRect(rep, x: 0, y: 422, w: 14, h: 11)
    for gx in [4, 6, 8] {
        for gy in (422+3)...(422+7) {
            setPixel(rep, x: gx, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        }
    }

    saveBMP(rep, to: "\(dir)/volume.bmp")
    print("  Generated volume.bmp")
}

// ============================================================
// 8. balance.bmp -- 47 x 433
// ============================================================
func generateBalance(dir: String) {
    let rep = createBitmap(width: 47, height: 433)
    fillRect(rep, x: 0, y: 0, w: 47, h: 433, C.bgSilver)

    // 28 fill states at offset x=9, width 38
    for i in 0...27 {
        let y = i * 15
        fillRect(rep, x: 9, y: y, w: 38, h: 13, C.sliderTrack)
        drawSunkenRect(rep, x: 9, y: y, w: 38, h: 13)
        // Fill from center outward
        if i > 0 {
            let fillW = Int(round(Double(34) * Double(i) / 27.0))
            let cx = 9 + 17 // center of 38px area
            let halfFill = fillW / 2
            fillRect(rep, x: cx - halfFill, y: y + 2, w: fillW, h: 9, C.sliderFill)
        }
    }

    // Thumb normal (15,422) 14x11
    fillRect(rep, x: 15, y: 422, w: 14, h: 11, C.buttonFace)
    drawRaisedRect(rep, x: 15, y: 422, w: 14, h: 11)
    for gx in [19, 21, 23] {
        for gy in (422+3)...(422+7) {
            setPixel(rep, x: gx, y: gy, r: 255, g: 255, b: 255)
            setPixel(rep, x: gx + 1, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        }
    }

    // Thumb pressed (0,422) 14x11
    fillRect(rep, x: 0, y: 422, w: 14, h: 11, C.buttonPressed)
    drawSunkenRect(rep, x: 0, y: 422, w: 14, h: 11)
    for gx in [4, 6, 8] {
        for gy in (422+3)...(422+7) {
            setPixel(rep, x: gx, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        }
    }

    saveBMP(rep, to: "\(dir)/balance.bmp")
    print("  Generated balance.bmp")
}

// ============================================================
// 9. shufrep.bmp -- 92 x 85
// ============================================================
func generateShufRep(dir: String) {
    let rep = createBitmap(width: 92, height: 85)
    fillRect(rep, x: 0, y: 0, w: 92, h: 85, C.bgSilver)

    // Helper to draw a labeled toggle button
    func drawToggle(x: Int, y: Int, w: Int, h: Int, label: String,
                    bg: (Int, Int, Int), fg: (Int, Int, Int), pressed: Bool) {
        fillRect(rep, x: x, y: y, w: w, h: h, bg)
        if pressed {
            drawSunkenRect(rep, x: x, y: y, w: w, h: h)
        } else {
            drawRaisedRect(rep, x: x, y: y, w: w, h: h)
        }
        // Center text
        let textW = label.count * 5
        let tx = x + (w - textW) / 2
        let ty = y + (h - 6) / 2
        drawString5x6(rep, text: label, x: tx, y: ty, fg)
    }

    // Repeat (28x15, 4 states at x=0)
    drawToggle(x: 0, y: 0, w: 28, h: 15, label: "REP", bg: C.buttonFace, fg: C.iconDark, pressed: false)
    drawToggle(x: 0, y: 15, w: 28, h: 15, label: "REP", bg: C.buttonPressed, fg: C.iconDark, pressed: true)
    drawToggle(x: 0, y: 30, w: 28, h: 15, label: "REP", bg: C.activeToggle, fg: C.white, pressed: false)
    drawToggle(x: 0, y: 45, w: 28, h: 15, label: "REP", bg: C.activeToggleP, fg: C.white, pressed: true)

    // Shuffle (47x15, 4 states at x=28)
    drawToggle(x: 28, y: 0, w: 47, h: 15, label: "SHUF", bg: C.buttonFace, fg: C.iconDark, pressed: false)
    drawToggle(x: 28, y: 15, w: 47, h: 15, label: "SHUF", bg: C.buttonPressed, fg: C.iconDark, pressed: true)
    drawToggle(x: 28, y: 30, w: 47, h: 15, label: "SHUF", bg: C.activeToggle, fg: C.white, pressed: false)
    drawToggle(x: 28, y: 45, w: 47, h: 15, label: "SHUF", bg: C.activeToggleP, fg: C.white, pressed: true)

    // EQ toggle (23x12, 4 states)
    drawToggle(x: 0, y: 61, w: 23, h: 12, label: "EQ", bg: C.buttonFace, fg: C.iconDark, pressed: false)
    drawToggle(x: 46, y: 61, w: 23, h: 12, label: "EQ", bg: C.buttonPressed, fg: C.iconDark, pressed: true)
    drawToggle(x: 0, y: 73, w: 23, h: 12, label: "EQ", bg: C.activeToggle, fg: C.white, pressed: false)
    drawToggle(x: 46, y: 73, w: 23, h: 12, label: "EQ", bg: C.activeToggleP, fg: C.white, pressed: true)

    // PL toggle (23x12, 4 states)
    drawToggle(x: 23, y: 61, w: 23, h: 12, label: "PL", bg: C.buttonFace, fg: C.iconDark, pressed: false)
    drawToggle(x: 69, y: 61, w: 23, h: 12, label: "PL", bg: C.buttonPressed, fg: C.iconDark, pressed: true)
    drawToggle(x: 23, y: 73, w: 23, h: 12, label: "PL", bg: C.activeToggle, fg: C.white, pressed: false)
    drawToggle(x: 69, y: 73, w: 23, h: 12, label: "PL", bg: C.activeToggleP, fg: C.white, pressed: true)

    saveBMP(rep, to: "\(dir)/shufrep.bmp")
    print("  Generated shufrep.bmp")
}

// ============================================================
// 10. playpaus.bmp -- 30 x 27
// ============================================================
func generatePlayPaus(dir: String) {
    let rep = createBitmap(width: 30, height: 27)
    fillRect(rep, x: 0, y: 0, w: 30, h: 27, C.insetBG)

    // Play indicator (0,0) 9x9 -- green triangle
    drawIcon(rep, pattern: [
        " #       ",
        " ##      ",
        " ###     ",
        " ####    ",
        " ###     ",
        " ##      ",
        " #       ",
    ], x: 0, y: 1, C.activeToggle)

    // Pause indicator (9,0) 9x9 -- amber bars
    drawIcon(rep, pattern: [
        " ## ##   ",
        " ## ##   ",
        " ## ##   ",
        " ## ##   ",
        " ## ##   ",
        " ## ##   ",
        " ## ##   ",
    ], x: 9, y: 1, C.amber)

    // Stop indicator (18,0) 9x9 -- dark/empty
    fillRect(rep, x: 18, y: 0, w: 9, h: 9, C.insetBG)

    // Work stopped (27,0) 3x9 -- dark
    fillRect(rep, x: 27, y: 0, w: 3, h: 9, C.insetBG)

    // Work playing (27,9) 3x9 -- green dot
    fillRect(rep, x: 27, y: 9, w: 3, h: 9, C.insetBG)
    setPixel(rep, x: 28, y: 13, r: C.activeToggle.0, g: C.activeToggle.1, b: C.activeToggle.2)

    // Work paused (27,18) 3x9 -- amber dot
    fillRect(rep, x: 27, y: 18, w: 3, h: 9, C.insetBG)
    setPixel(rep, x: 28, y: 22, r: C.amber.0, g: C.amber.1, b: C.amber.2)

    saveBMP(rep, to: "\(dir)/playpaus.bmp")
    print("  Generated playpaus.bmp")
}

// ============================================================
// 11. monoster.bmp -- 56 x 24
// ============================================================
func generateMonoSter(dir: String) {
    let rep = createBitmap(width: 56, height: 24)
    fillRect(rep, x: 0, y: 0, w: 56, h: 24, C.insetBG)

    // Stereo ON (0,0) 29x12
    drawString5x6(rep, text: "ST", x: 9, y: 3, C.insetText)

    // Stereo OFF (0,12) 29x12
    drawString5x6(rep, text: "ST", x: 9, y: 15, C.lcdDimText)

    // Mono ON (29,0) 27x12
    drawString5x6(rep, text: "MO", x: 37, y: 3, C.insetText)

    // Mono OFF (29,12) 27x12
    drawString5x6(rep, text: "MO", x: 37, y: 15, C.lcdDimText)

    saveBMP(rep, to: "\(dir)/monoster.bmp")
    print("  Generated monoster.bmp")
}

// ============================================================
// 12. eqmain.bmp -- 275 x 192
// ============================================================
func generateEQMain(dir: String) {
    let rep = createBitmap(width: 275, height: 192)

    // EQ Background (0,0) 275x116
    fillRect(rep, x: 0, y: 0, w: 275, h: 116, C.bgSilver)

    // Draw slider grooves - preamp at x=21, 10 bands starting at x=78 with 18px spacing
    let sliderXs = [21] + (0..<10).map { 78 + $0 * 18 }
    for sx in sliderXs {
        fillRect(rep, x: sx, y: 38, w: 11, h: 63, C.sliderTrack)
        drawSunkenRect(rep, x: sx, y: 38, w: 11, h: 63)
    }

    // Frequency labels below bands (sliders are y=38..101, labels at y=103)
    let freqLabels = ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"]
    for (i, label) in freqLabels.enumerated() {
        let lx = 78 + i * 18 + (11 - label.count * 5) / 2
        drawString5x6(rep, text: label, x: lx, y: 103, C.iconDark)
    }

    // ON/AUTO buttons at y=119 (12px tall)
    func drawEQBtn(x: Int, y: Int, w: Int, h: Int, label: String,
                   bg: (Int, Int, Int), fg: (Int, Int, Int), pressed: Bool) {
        fillRect(rep, x: x, y: y, w: w, h: h, bg)
        if pressed { drawSunkenRect(rep, x: x, y: y, w: w, h: h) }
        else { drawRaisedRect(rep, x: x, y: y, w: w, h: h) }
        let tx = x + (w - label.count * 5) / 2
        let ty = y + (h - 6) / 2
        drawString5x6(rep, text: label, x: tx, y: ty, fg)
    }

    // ON off-normal (10,119) 26x12
    drawEQBtn(x: 10, y: 119, w: 26, h: 12, label: "ON", bg: C.buttonFace, fg: C.iconDark, pressed: false)
    // AUTO off-normal (36,119) 32x12
    drawEQBtn(x: 36, y: 119, w: 32, h: 12, label: "AUTO", bg: C.buttonFace, fg: C.iconDark, pressed: false)
    // ON on-normal (69,119) 26x12
    drawEQBtn(x: 69, y: 119, w: 26, h: 12, label: "ON", bg: C.activeToggle, fg: C.white, pressed: false)
    // AUTO on-normal (95,119) 32x12
    drawEQBtn(x: 95, y: 119, w: 32, h: 12, label: "AUTO", bg: C.activeToggle, fg: C.white, pressed: false)
    // ON off-pressed (128,119) 26x12
    drawEQBtn(x: 128, y: 119, w: 26, h: 12, label: "ON", bg: C.buttonPressed, fg: C.iconDark, pressed: true)
    // AUTO off-pressed (154,119) 32x12
    drawEQBtn(x: 154, y: 119, w: 32, h: 12, label: "AUTO", bg: C.buttonPressed, fg: C.iconDark, pressed: true)
    // ON on-pressed (187,119) 26x12
    drawEQBtn(x: 187, y: 119, w: 26, h: 12, label: "ON", bg: C.activeToggleP, fg: C.white, pressed: true)
    // AUTO on-pressed (213,119) 32x12
    drawEQBtn(x: 213, y: 119, w: 32, h: 12, label: "AUTO", bg: C.activeToggleP, fg: C.white, pressed: true)

    // Title bars (275x14 each)
    // Active (0,134)
    fillGradientH(rep, x: 0, y: 134, w: 275, h: 14, from: C.titleActive1, to: C.titleActive2)
    for px in 0..<275 {
        setPixel(rep, x: px, y: 134, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 147, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    // Inactive (0,149)
    fillRect(rep, x: 0, y: 149, w: 275, h: 14, C.titleInactive)
    for px in 0..<275 {
        setPixel(rep, x: px, y: 149, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 162, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    // Slider thumb normal (0,164) 11x11
    fillRect(rep, x: 0, y: 164, w: 11, h: 11, C.buttonFace)
    drawRaisedRect(rep, x: 0, y: 164, w: 11, h: 11)
    // Grip marks
    for gy in (164+3)...(164+7) {
        setPixel(rep, x: 4, y: gy, r: 255, g: 255, b: 255)
        setPixel(rep, x: 5, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
        setPixel(rep, x: 7, y: gy, r: 255, g: 255, b: 255)
        setPixel(rep, x: 8, y: gy, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    // Slider thumb pressed (0,176) 11x11
    fillRect(rep, x: 0, y: 176, w: 11, h: 11, C.buttonPressed)
    drawSunkenRect(rep, x: 0, y: 176, w: 11, h: 11)

    // Slider bar strip (13,164) 209x63 -- 28 states, colored gradient
    // Each state is ~7.46px wide (209/28)
    for state in 0..<28 {
        let sx = 13 + Int(round(Double(state) * 209.0 / 28.0))
        let sw = Int(round(Double(state + 1) * 209.0 / 28.0)) - Int(round(Double(state) * 209.0 / 28.0))
        // Draw vertical bar with gradient: green top, yellow middle, red bottom
        for py in 0..<63 {
            let t = Double(py) / 62.0 // 0 at top, 1 at bottom
            let r: Int, g: Int, b: Int
            if t < 0.33 {
                // Green to yellow
                let lt = t / 0.33
                r = Int(lt * 255); g = 255; b = 0
            } else if t < 0.66 {
                // Yellow to orange
                let lt = (t - 0.33) / 0.33
                r = 255; g = Int(255 - lt * 100); b = 0
            } else {
                // Orange to red
                let lt = (t - 0.66) / 0.34
                r = 255; g = Int(155 - lt * 155); b = 0
            }
            // Fill amount based on state
            let fillH = Int(round(Double(63) * Double(27 - state) / 27.0))
            if py >= fillH {
                fillRect(rep, x: sx, y: 164 + py, w: sw, h: 1, r: r, g: g, b: b)
            } else {
                fillRect(rep, x: sx, y: 164 + py, w: sw, h: 1, C.sliderTrack)
            }
        }
    }

    // PRESETS button normal (224,164) 44x12
    drawEQBtn(x: 224, y: 164, w: 44, h: 12, label: "PRESETS", bg: C.buttonFace, fg: C.iconDark, pressed: false)

    // PRESETS button pressed (224,176) 44x12
    drawEQBtn(x: 224, y: 176, w: 44, h: 12, label: "PRESETS", bg: C.buttonPressed, fg: C.iconDark, pressed: true)

    // EQ shade backgrounds
    // Active (0,164) 275x14 -- note: overlaps slider area, this is a known Winamp format quirk
    // We already drew content at (0,164), shade mode uses only the first 275x14 pixels
    // The slider strip continues from x=13 so the left 13px becomes shade active
    // Just ensure (0,164)-(12,177) has valid title-bar-like content
    // (In practice this is already handled since we filled the slider thumb there)

    // Inactive shade (0,178) 275x14
    fillRect(rep, x: 0, y: 178, w: 275, h: 14, C.titleInactive)
    for px in 0..<275 {
        setPixel(rep, x: px, y: 178, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2)
        setPixel(rep, x: px, y: 191, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2)
    }

    saveBMP(rep, to: "\(dir)/eqmain.bmp")
    print("  Generated eqmain.bmp")
}

// ============================================================
// 13. pledit.bmp -- 280 x 186
// ============================================================
func generatePledit(dir: String) {
    let rep = createBitmap(width: 280, height: 186)
    fillRect(rep, x: 0, y: 0, w: 280, h: 186, C.bgSilver)

    // --- Title bar active (y=0) ---
    // Left corner (0,0) 25x20
    fillRect(rep, x: 0, y: 0, w: 25, h: 20, C.bgDarker)
    for py in 0..<20 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for px in 0..<25 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Title area (26,0) 100x20
    fillGradientH(rep, x: 26, y: 0, w: 100, h: 20, from: C.titleActive1, to: C.titleActive2)
    for px in 26..<126 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Tileable middle (127,0) 25x20
    fillRect(rep, x: 127, y: 0, w: 25, h: 20, C.bgDarker)
    for px in 127..<152 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Right corner (153,0) 25x20
    fillRect(rep, x: 153, y: 0, w: 25, h: 20, C.bgDarker)
    for px in 153..<178 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for py in 0..<20 { setPixel(rep, x: 177, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // --- Title bar inactive (y=21) ---
    fillRect(rep, x: 0, y: 21, w: 25, h: 20, C.titleInactive)
    for py in 21..<41 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for px in 0..<25 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    fillRect(rep, x: 26, y: 21, w: 100, h: 20, C.titleInactive)
    for px in 26..<126 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    fillRect(rep, x: 127, y: 21, w: 25, h: 20, C.titleInactive)
    for px in 127..<152 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    fillRect(rep, x: 153, y: 21, w: 25, h: 20, C.titleInactive)
    for px in 153..<178 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for py in 21..<41 { setPixel(rep, x: 177, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // --- Side tiles (y=42) ---
    // Left side tile (0,42) 12x29
    fillRect(rep, x: 0, y: 42, w: 12, h: 29, C.bgDarker)
    for py in 42..<71 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Right side tile (31,42) 20x29
    fillRect(rep, x: 31, y: 42, w: 20, h: 29, C.bgDarker)
    for py in 42..<71 { setPixel(rep, x: 50, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // Scrollbar track (36,42) 8x29
    fillRect(rep, x: 36, y: 42, w: 8, h: 29, C.sliderTrack)
    drawSunkenRect(rep, x: 36, y: 42, w: 8, h: 29)

    // Scrollbar thumb normal (52,53) 8x18
    fillRect(rep, x: 52, y: 53, w: 8, h: 18, C.buttonFace)
    drawRaisedRect(rep, x: 52, y: 53, w: 8, h: 18)

    // Scrollbar thumb pressed (61,53) 8x18
    fillRect(rep, x: 61, y: 53, w: 8, h: 18, C.buttonPressed)
    drawSunkenRect(rep, x: 61, y: 53, w: 8, h: 18)

    // --- Shade tiles ---
    // Shade left corner (72,42) 25x14
    fillGradientH(rep, x: 72, y: 42, w: 25, h: 14, from: C.titleActive1, to: C.titleActive2)
    for px in 72..<97 { setPixel(rep, x: px, y: 42, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Shade right corner (99,42) 75x14
    fillGradientH(rep, x: 99, y: 42, w: 75, h: 14, from: C.titleActive1, to: C.titleActive2)
    for px in 99..<174 { setPixel(rep, x: px, y: 42, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Shade tile (72,57) 25x14
    fillGradientH(rep, x: 72, y: 57, w: 25, h: 14, from: C.titleActive1, to: C.titleActive2)

    // --- Bottom bar (38px tall) ---
    // Bottom left corner (0,72) 125x38
    fillRect(rep, x: 0, y: 72, w: 125, h: 38, C.bgDarker)
    for px in 0..<125 { setPixel(rep, x: px, y: 109, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    for py in 72..<110 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Bottom tile (179,0) 25x38 -- NOTE: at y=0 not y=72
    fillRect(rep, x: 179, y: 0, w: 25, h: 38, C.bgDarker)
    for px in 179..<204 { setPixel(rep, x: px, y: 37, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // Bottom right corner (126,72) 150x38
    fillRect(rep, x: 126, y: 72, w: 150, h: 38, C.bgDarker)
    for px in 126..<276 { setPixel(rep, x: px, y: 109, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    for py in 72..<110 { setPixel(rep, x: 275, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // --- Button groups (22x18 each) ---
    func drawPlBtn(x: Int, y: Int, label: String, pressed: Bool) {
        let bg = pressed ? C.buttonPressed : C.buttonFace
        fillRect(rep, x: x, y: y, w: 22, h: 18, bg)
        if pressed { drawSunkenRect(rep, x: x, y: y, w: 22, h: 18) }
        else { drawRaisedRect(rep, x: x, y: y, w: 22, h: 18) }
        let textW = min(label.count * 5, 20)
        let tx = x + (22 - textW) / 2
        drawString5x6(rep, text: label, x: tx, y: y + 6, C.iconDark)
    }

    // ADD: +URL (0,111), +DIR (0,130), +FILE (0,149)
    drawPlBtn(x: 0, y: 111, label: "URL", pressed: false)
    drawPlBtn(x: 23, y: 111, label: "URL", pressed: true)
    drawPlBtn(x: 0, y: 130, label: "DIR", pressed: false)
    drawPlBtn(x: 23, y: 130, label: "DIR", pressed: true)
    drawPlBtn(x: 0, y: 149, label: "FIL", pressed: false)
    drawPlBtn(x: 23, y: 149, label: "FIL", pressed: true)

    // REM: ALL (54,111), CROP (54,130), SEL (54,149), MISC (54,168)
    drawPlBtn(x: 54, y: 111, label: "ALL", pressed: false)
    drawPlBtn(x: 77, y: 111, label: "ALL", pressed: true)
    drawPlBtn(x: 54, y: 130, label: "CRP", pressed: false)
    drawPlBtn(x: 77, y: 130, label: "CRP", pressed: true)
    drawPlBtn(x: 54, y: 149, label: "SEL", pressed: false)
    drawPlBtn(x: 77, y: 149, label: "SEL", pressed: true)
    drawPlBtn(x: 54, y: 168, label: "MSC", pressed: false)
    drawPlBtn(x: 77, y: 168, label: "MSC", pressed: true)

    // SEL: INV (104,111), NIL (104,130), ALL (104,149)
    drawPlBtn(x: 104, y: 111, label: "INV", pressed: false)
    drawPlBtn(x: 127, y: 111, label: "INV", pressed: true)
    drawPlBtn(x: 104, y: 130, label: "NIL", pressed: false)
    drawPlBtn(x: 127, y: 130, label: "NIL", pressed: true)
    drawPlBtn(x: 104, y: 149, label: "ALL", pressed: false)
    drawPlBtn(x: 127, y: 149, label: "ALL", pressed: true)

    // MISC: SORT (154,111), INFO (154,130), OPTS (154,149)
    drawPlBtn(x: 154, y: 111, label: "SRT", pressed: false)
    drawPlBtn(x: 177, y: 111, label: "SRT", pressed: true)
    drawPlBtn(x: 154, y: 130, label: "INF", pressed: false)
    drawPlBtn(x: 177, y: 130, label: "INF", pressed: true)
    drawPlBtn(x: 154, y: 149, label: "OPT", pressed: false)
    drawPlBtn(x: 177, y: 149, label: "OPT", pressed: true)

    // LIST: NEW (204,111), SAVE (204,130), LOAD (204,149)
    drawPlBtn(x: 204, y: 111, label: "NEW", pressed: false)
    drawPlBtn(x: 227, y: 111, label: "NEW", pressed: true)
    drawPlBtn(x: 204, y: 130, label: "SAV", pressed: false)
    drawPlBtn(x: 227, y: 130, label: "SAV", pressed: true)
    drawPlBtn(x: 204, y: 149, label: "LOD", pressed: false)
    drawPlBtn(x: 227, y: 149, label: "LOD", pressed: true)

    saveBMP(rep, to: "\(dir)/pledit.bmp")
    print("  Generated pledit.bmp")
}

// ============================================================
// 14. gen.bmp -- 194 x 109
// ============================================================
func generateGen(dir: String) {
    let rep = createBitmap(width: 194, height: 109)
    fillRect(rep, x: 0, y: 0, w: 194, h: 109, C.bgSilver)

    // --- Title bar active (y=0-19) ---
    // Left corner (0,0) 25x20
    fillRect(rep, x: 0, y: 0, w: 25, h: 20, C.bgDarker)
    for py in 0..<20 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for px in 0..<25 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Tileable middle (26,0) 29x20
    fillGradientH(rep, x: 26, y: 0, w: 29, h: 20, from: C.titleActive1, to: C.titleActive2)
    for px in 26..<55 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Right corner (153,0) 41x20
    fillRect(rep, x: 153, y: 0, w: 41, h: 20, C.bgDarker)
    for px in 153..<194 { setPixel(rep, x: px, y: 0, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for py in 0..<20 { setPixel(rep, x: 193, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    // Close button area (9px from right edge of corner = x=153+41-9-2)
    fillRect(rep, x: 183, y: 5, w: 9, h: 9, C.buttonFace)
    drawRaisedRect(rep, x: 183, y: 5, w: 9, h: 9)
    drawIcon(rep, pattern: ["#   #", " # # ", "  #  ", " # # ", "#   #"],
             x: 185, y: 7, C.iconDark)

    // --- Title bar inactive (y=21-40) ---
    fillRect(rep, x: 0, y: 21, w: 25, h: 20, C.titleInactive)
    for py in 21..<41 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for px in 0..<25 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    fillRect(rep, x: 26, y: 21, w: 29, h: 20, C.titleInactive)
    for px in 26..<55 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    fillRect(rep, x: 153, y: 21, w: 41, h: 20, C.titleInactive)
    for px in 153..<194 { setPixel(rep, x: px, y: 21, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for py in 21..<41 { setPixel(rep, x: 193, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // --- Window chrome (y=42-85) ---
    // Left border tile (0,42) 11x29
    fillRect(rep, x: 0, y: 42, w: 11, h: 29, C.bgDarker)
    for py in 42..<71 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }

    // Right border tile (12,42) 11x29
    fillRect(rep, x: 12, y: 42, w: 11, h: 29, C.bgDarker)
    for py in 42..<71 { setPixel(rep, x: 22, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // Bottom left corner (0,72) 11x14
    fillRect(rep, x: 0, y: 72, w: 11, h: 14, C.bgDarker)
    for py in 72..<86 { setPixel(rep, x: 0, y: py, r: C.highlight.0, g: C.highlight.1, b: C.highlight.2) }
    for px in 0..<11 { setPixel(rep, x: px, y: 85, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // Bottom tile (12,72) 29x14
    fillRect(rep, x: 12, y: 72, w: 29, h: 14, C.bgDarker)
    for px in 12..<41 { setPixel(rep, x: px, y: 85, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // Bottom right corner (42,72) 11x14
    fillRect(rep, x: 42, y: 72, w: 11, h: 14, C.bgDarker)
    for py in 72..<86 { setPixel(rep, x: 52, y: py, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }
    for px in 42..<53 { setPixel(rep, x: px, y: 85, r: C.shadow.0, g: C.shadow.1, b: C.shadow.2) }

    // --- GenFont Active alphabet at y=89, 6px tall ---
    // Dark LCD background with bright text for maximum readability
    fillRect(rep, x: 0, y: 87, w: 194, h: 8, C.insetBG)
    fillRect(rep, x: 0, y: 95, w: 194, h: 8, C.insetBG)

    // Draw each letter at exact x positions from genFontCharPositions
    for (i, entry) in genFontPatterns.enumerated() {
        let (_, _, pattern) = entry
        let (xPos, width) = genFontCharPositions[i]
        // Draw pixel pattern at (xPos, 89) for active - bright white on dark LCD
        for (row, line) in pattern.enumerated() {
            for (col, ch) in line.enumerated() {
                if ch == "#" && col < width {
                    setPixel(rep, x: xPos + col, y: 89 + row, r: 255, g: 255, b: 255)
                }
            }
        }
        // Draw same pattern at (xPos, 97) for inactive (dimmer on dark LCD)
        for (row, line) in pattern.enumerated() {
            for (col, ch) in line.enumerated() {
                if ch == "#" && col < width {
                    setPixel(rep, x: xPos + col, y: 97 + row, r: 100, g: 100, b: 100)
                }
            }
        }
    }

    saveBMP(rep, to: "\(dir)/gen.bmp")
    print("  Generated gen.bmp")
}

// ============================================================
// 15. pledit.txt
// ============================================================
func generatePleditTxt(dir: String) {
    let content = """
    [Text]
    Normal=#C0C0C0
    Current=#FFFFFF
    NormalBG=#1A1A2E
    SelectedBG=#2A3A5E
    Font=
    """
    try! content.write(toFile: "\(dir)/pledit.txt", atomically: true, encoding: .utf8)
    print("  Generated pledit.txt")
}

// ============================================================
// 16. viscolor.txt
// ============================================================
func generateViscolorTxt(dir: String) {
    let colors = [
        "0,0,0",
        "10,20,40",
        "20,40,80",
        "30,60,110",
        "40,80,140",
        "50,100,160",
        "60,120,180",
        "70,140,190",
        "80,160,200",
        "90,180,210",
        "100,195,220",
        "120,210,230",
        "140,220,240",
        "160,230,245",
        "180,240,250",
        "200,245,255",
        "210,250,255",
        "220,255,255",
        "230,255,240",
        "240,255,220",
        "250,255,200",
        "255,245,180",
        "255,230,160",
        "255,220,140",
    ]
    try! colors.joined(separator: "\n").write(toFile: "\(dir)/viscolor.txt", atomically: true, encoding: .utf8)
    print("  Generated viscolor.txt")
}

// MARK: - Main

func main() {
    print("NullPlayer Silver Skin Generator")
    print("=================================")

    let fm = FileManager.default

    // Create temp directory
    let tmpDir = NSTemporaryDirectory() + "NullPlayerSkinGen_\(ProcessInfo.processInfo.processIdentifier)"
    try! fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
    print("Working directory: \(tmpDir)")

    // Generate all BMPs and config files
    print("\nGenerating sprite sheets...")
    generateMain(dir: tmpDir)
    generateTitlebar(dir: tmpDir)
    generateCButtons(dir: tmpDir)
    generateNumbers(dir: tmpDir)
    generateText(dir: tmpDir)
    generatePosbar(dir: tmpDir)
    generateVolume(dir: tmpDir)
    generateBalance(dir: tmpDir)
    generateShufRep(dir: tmpDir)
    generatePlayPaus(dir: tmpDir)
    generateMonoSter(dir: tmpDir)
    generateEQMain(dir: tmpDir)
    generatePledit(dir: tmpDir)
    generateGen(dir: tmpDir)
    generatePleditTxt(dir: tmpDir)
    generateViscolorTxt(dir: tmpDir)

    // Determine project root (script is in scripts/)
    let scriptPath = CommandLine.arguments[0]
    let scriptURL = URL(fileURLWithPath: scriptPath).standardized
    let projectRoot: String
    if scriptURL.pathComponents.contains("scripts") {
        projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent().path
    } else {
        projectRoot = fm.currentDirectoryPath
    }

    print("\nProject root: \(projectRoot)")

    // Output paths
    let distSkinsDir = "\(projectRoot)/dist/Skins"
    let resourceSkinsDir = "\(projectRoot)/Sources/NullPlayer/Resources/Skins"
    let distOutput = "\(distSkinsDir)/NullPlayer-Silver.wsz"
    let resourceOutput = "\(resourceSkinsDir)/NullPlayer-Silver.wsz"

    // Ensure output directories exist
    try! fm.createDirectory(atPath: distSkinsDir, withIntermediateDirectories: true)
    try! fm.createDirectory(atPath: resourceSkinsDir, withIntermediateDirectories: true)

    // Collect all files in temp dir
    let files = try! fm.contentsOfDirectory(atPath: tmpDir)
        .map { "\(tmpDir)/\($0)" }

    // Create ZIP as .wsz
    let wszPath = "\(tmpDir)/NullPlayer-Silver.wsz"
    let zipProcess = Process()
    zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    zipProcess.arguments = ["-j", wszPath] + files
    zipProcess.launch()
    zipProcess.waitUntilExit()

    guard zipProcess.terminationStatus == 0 else {
        print("ERROR: zip failed with status \(zipProcess.terminationStatus)")
        exit(1)
    }

    // Copy to output locations
    if fm.fileExists(atPath: distOutput) { try! fm.removeItem(atPath: distOutput) }
    try! fm.copyItem(atPath: wszPath, toPath: distOutput)
    print("  Copied to: \(distOutput)")

    if fm.fileExists(atPath: resourceOutput) { try! fm.removeItem(atPath: resourceOutput) }
    try! fm.copyItem(atPath: wszPath, toPath: resourceOutput)
    print("  Copied to: \(resourceOutput)")

    // Cleanup
    try? fm.removeItem(atPath: tmpDir)

    print("\nDone! NullPlayer-Silver.wsz generated successfully.")
}

main()
