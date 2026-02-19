#!/usr/bin/env swift
// generate_skulls_skin.swift
// Generates PNG assets for the Skulls modern skin.
// Run: swift scripts/generate_skulls_skin.swift
//
// Produces pixel-art style images with no antialiasing:
// - Character sprites (A-Z, a-z, 0-9, space, punctuation) in cream/silver
// - Amber 7-segment LED time digits (0-9, colon, minus)
// - Transport buttons (prev, play, pause, stop, next, eject) with pressed states
// - Seek/volume thumbs

import AppKit
import Foundation

// MARK: - Color Palette

struct C {
    static let cream      = (212, 207, 192)  // #d4cfc0 - silk-screen title text
    static let silver     = (160, 160, 160)  // #a0a0a0 - borders, text
    static let amber      = (224, 160, 48)   // #e0a030 - LED digits, accents
    static let charcoal   = (42, 42, 46)     // #2a2a2e - background
    static let darkPanel  = (26, 26, 30)     // #1a1a1e - recessed panels
    static let btnFace    = (51, 51, 56)     // #333338 - button fill
    static let btnBorder  = (128, 128, 128)  // #808080 - button border
    static let highlight  = (180, 180, 180)  // bevel highlight
    static let shadow     = (30, 30, 34)     // bevel shadow
    static let iconWhite  = (220, 220, 220)  // button icons
    static let transparent = (-1, -1, -1)    // sentinel for transparency
}

// MARK: - PNG Bitmap Helpers

func createBitmap(width: Int, height: Int, hasAlpha: Bool = true) -> NSBitmapImageRep {
    return NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: hasAlpha ? 4 : 3,
        hasAlpha: hasAlpha, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * (hasAlpha ? 4 : 3), bitsPerPixel: hasAlpha ? 32 : 24
    )!
}

func savePNG(_ rep: NSBitmapImageRep, to path: String) {
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
    print("  \(URL(fileURLWithPath: path).lastPathComponent)")
}

func setPixel(_ rep: NSBitmapImageRep, x: Int, y: Int, _ c: (Int, Int, Int)) {
    guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return }
    let ptr = rep.bitmapData!
    let spp = rep.samplesPerPixel
    let bpr = rep.bytesPerRow
    let offset = y * bpr + x * spp
    ptr[offset] = UInt8(clamping: c.0)
    ptr[offset + 1] = UInt8(clamping: c.1)
    ptr[offset + 2] = UInt8(clamping: c.2)
    if spp == 4 { ptr[offset + 3] = 255 }
}

func fillRect(_ rep: NSBitmapImageRep, x: Int, y: Int, w: Int, h: Int, _ c: (Int, Int, Int)) {
    for py in y..<min(y + h, rep.pixelsHigh) {
        for px in x..<min(x + w, rep.pixelsWide) {
            setPixel(rep, x: px, y: py, c)
        }
    }
}

func clearBitmap(_ rep: NSBitmapImageRep) {
    // Fill with transparent (alpha=0)
    guard rep.samplesPerPixel == 4 else { return }
    let ptr = rep.bitmapData!
    let total = rep.bytesPerRow * rep.pixelsHigh
    for i in stride(from: 0, to: total, by: 4) {
        ptr[i] = 0; ptr[i+1] = 0; ptr[i+2] = 0; ptr[i+3] = 0
    }
}

func withFlippedCGContext(_ rep: NSBitmapImageRep, _ block: (CGContext, Int, Int) -> Void) {
    NSGraphicsContext.saveGraphicsState()
    if let gc = NSGraphicsContext(bitmapImageRep: rep) {
        NSGraphicsContext.current = gc
        let ctx = gc.cgContext
        // Flip to top-left origin matching bitmap row order
        ctx.translateBy(x: 0, y: CGFloat(rep.pixelsHigh))
        ctx.scaleBy(x: 1, y: -1)
        block(ctx, rep.pixelsWide, rep.pixelsHigh)
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - 7x11 Bold Pixel Font (stereo receiver style)

/// Each character is 7-wide x 11-tall, stored as 11 rows of UInt8 (bits 6..0 = pixels left-to-right).
/// Bold/thick strokes (2px wide) for a distinctive hi-fi receiver look.
let pixelFont: [Character: [UInt8]] = [
    "A": [0b0011100, 0b0111110, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b1111111, 0b1100011, 0b1100011, 0b1100011, 0b1100011],
    "B": [0b1111100, 0b1111110, 0b1100011, 0b1100011, 0b1111100, 0b1111110, 0b1100011, 0b1100011, 0b1100011, 0b1111110, 0b1111100],
    "C": [0b0111110, 0b1111111, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1111111, 0b0111110],
    "D": [0b1111100, 0b1111110, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1111110, 0b1111100],
    "E": [0b1111111, 0b1111111, 0b1100000, 0b1100000, 0b1111100, 0b1111100, 0b1100000, 0b1100000, 0b1100000, 0b1111111, 0b1111111],
    "F": [0b1111111, 0b1111111, 0b1100000, 0b1100000, 0b1111100, 0b1111100, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000],
    "G": [0b0111110, 0b1111111, 0b1100000, 0b1100000, 0b1100000, 0b1101111, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111110],
    "H": [0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b1111111, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011],
    "I": [0b0111110, 0b0111110, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0111110, 0b0111110],
    "J": [0b0001111, 0b0001111, 0b0000110, 0b0000110, 0b0000110, 0b0000110, 0b0000110, 0b1100110, 0b1100110, 0b0111100, 0b0011000],
    "K": [0b1100011, 0b1100110, 0b1101100, 0b1111000, 0b1110000, 0b1111000, 0b1101100, 0b1100110, 0b1100011, 0b1100011, 0b1100011],
    "L": [0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1111111, 0b1111111],
    "M": [0b1100011, 0b1110111, 0b1111111, 0b1101011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011],
    "N": [0b1100011, 0b1110011, 0b1111011, 0b1101011, 0b1100111, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011],
    "O": [0b0111110, 0b1111111, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111110],
    "P": [0b1111110, 0b1111111, 0b1100011, 0b1100011, 0b1111111, 0b1111110, 0b1100000, 0b1100000, 0b1100000, 0b1100000, 0b1100000],
    "Q": [0b0111110, 0b1111111, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1101011, 0b1100110, 0b1111111, 0b0111011],
    "R": [0b1111110, 0b1111111, 0b1100011, 0b1100011, 0b1111111, 0b1111110, 0b1101100, 0b1100110, 0b1100011, 0b1100011, 0b1100011],
    "S": [0b0111110, 0b1111111, 0b1100000, 0b1110000, 0b0111110, 0b0001111, 0b0000011, 0b0000011, 0b1000011, 0b1111111, 0b0111110],
    "T": [0b1111111, 0b1111111, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100],
    "U": [0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111110],
    "V": [0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b0110110, 0b0110110, 0b0011100, 0b0011100, 0b0001000, 0b0001000],
    "W": [0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1100011, 0b1101011, 0b1111111, 0b1110111, 0b1100011, 0b1100011],
    "X": [0b1100011, 0b1100011, 0b0110110, 0b0011100, 0b0001000, 0b0001000, 0b0011100, 0b0110110, 0b1100011, 0b1100011, 0b1100011],
    "Y": [0b1100011, 0b1100011, 0b0110110, 0b0011100, 0b0001000, 0b0001000, 0b0001000, 0b0001000, 0b0001000, 0b0001000, 0b0001000],
    "Z": [0b1111111, 0b1111111, 0b0000011, 0b0000110, 0b0001100, 0b0011000, 0b0110000, 0b1100000, 0b1100000, 0b1111111, 0b1111111],
    // Lowercase -- same as uppercase for this bold style (fallback handles it)
    // Digits
    "0": [0b0111110, 0b1111111, 0b1100011, 0b1100111, 0b1101011, 0b1110011, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111110],
    "1": [0b0001100, 0b0011100, 0b0111100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0111111, 0b0111111],
    "2": [0b0111110, 0b1111111, 0b1100011, 0b0000011, 0b0000110, 0b0001100, 0b0011000, 0b0110000, 0b1100000, 0b1111111, 0b1111111],
    "3": [0b0111110, 0b1111111, 0b0000011, 0b0000011, 0b0011110, 0b0011110, 0b0000011, 0b0000011, 0b0000011, 0b1111111, 0b0111110],
    "4": [0b0000110, 0b0001110, 0b0011110, 0b0110110, 0b1100110, 0b1111111, 0b1111111, 0b0000110, 0b0000110, 0b0000110, 0b0000110],
    "5": [0b1111111, 0b1111111, 0b1100000, 0b1100000, 0b1111110, 0b1111111, 0b0000011, 0b0000011, 0b0000011, 0b1111111, 0b0111110],
    "6": [0b0011110, 0b0111000, 0b1100000, 0b1100000, 0b1111110, 0b1111111, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111110],
    "7": [0b1111111, 0b1111111, 0b0000011, 0b0000110, 0b0001100, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011000],
    "8": [0b0111110, 0b1111111, 0b1100011, 0b1100011, 0b0111110, 0b0111110, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111110],
    "9": [0b0111110, 0b1111111, 0b1100011, 0b1100011, 0b1100011, 0b1111111, 0b0111111, 0b0000011, 0b0000011, 0b0011110, 0b0111100],
    // Punctuation
    " ": [0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000],
    "-": [0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b1111111, 0b1111111, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000],
    ".": [0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0011000, 0b0011000, 0b0000000],
    "_": [0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b1111111, 0b1111111],
    ":": [0b0000000, 0b0000000, 0b0011000, 0b0011000, 0b0000000, 0b0000000, 0b0000000, 0b0011000, 0b0011000, 0b0000000, 0b0000000],
    "(": [0b0000110, 0b0001100, 0b0011000, 0b0110000, 0b0110000, 0b0110000, 0b0110000, 0b0011000, 0b0001100, 0b0000110, 0b0000000],
    ")": [0b0110000, 0b0011000, 0b0001100, 0b0000110, 0b0000110, 0b0000110, 0b0000110, 0b0001100, 0b0011000, 0b0110000, 0b0000000],
    "[": [0b0011110, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011000, 0b0011110, 0b0000000],
    "]": [0b0111100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0001100, 0b0111100, 0b0000000],
    "&": [0b0011100, 0b0110110, 0b0110110, 0b0011100, 0b0111000, 0b1101011, 0b1100110, 0b1100110, 0b0111011, 0b0000000, 0b0000000],
    "'": [0b0011000, 0b0011000, 0b0110000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000, 0b0000000],
    "+": [0b0000000, 0b0000000, 0b0001100, 0b0001100, 0b0111111, 0b0111111, 0b0001100, 0b0001100, 0b0000000, 0b0000000, 0b0000000],
    "#": [0b0010010, 0b0010010, 0b1111111, 0b0010010, 0b0010010, 0b1111111, 0b0010010, 0b0010010, 0b0000000, 0b0000000, 0b0000000],
    "/": [0b0000011, 0b0000110, 0b0000110, 0b0001100, 0b0001100, 0b0011000, 0b0011000, 0b0110000, 0b0110000, 0b1100000, 0b0000000],
]

let charW = 7
let charH = 11

func renderCharSprite(char: Character, color: (Int, Int, Int)) -> NSBitmapImageRep {
    let rep = createBitmap(width: charW, height: charH)
    clearBitmap(rep)
    
    guard let rows = pixelFont[char] else { return rep }
    
    for row in 0..<charH {
        let bits = rows[row]
        for col in 0..<charW {
            if bits & (1 << (6 - col)) != 0 {
                setPixel(rep, x: col, y: row, color)
            }
        }
    }
    return rep
}

// MARK: - 7-Segment LED Digits (13x20)

/// Segment layout:  _a_
///                 |   |
///                 f   b
///                 |_g_|
///                 |   |
///                 e   c
///                 |_d_|
let segmentPatterns: [Character: [Bool]] = [
    // segments: a, b, c, d, e, f, g
    "0": [true,  true,  true,  true,  true,  true,  false],
    "1": [false, true,  true,  false, false, false, false],
    "2": [true,  true,  false, true,  true,  false, true],
    "3": [true,  true,  true,  true,  false, false, true],
    "4": [false, true,  true,  false, false, true,  true],
    "5": [true,  false, true,  true,  false, true,  true],
    "6": [true,  false, true,  true,  true,  true,  true],
    "7": [true,  true,  true,  false, false, false, false],
    "8": [true,  true,  true,  true,  true,  true,  true],
    "9": [true,  true,  true,  true,  false, true,  true],
]

func renderTimeDigit(char: Character, color: (Int, Int, Int)) -> NSBitmapImageRep {
    let w = 13, h = 20
    let rep = createBitmap(width: w, height: h)
    clearBitmap(rep)
    
    let segT = 2  // segment thickness
    let gap = 1
    let midY = h / 2
    
    if char == ":" {
        // Two dots
        let dotSize = 2
        let dotX = w / 2 - dotSize / 2
        fillRect(rep, x: dotX, y: 5, w: dotSize, h: dotSize, color)
        fillRect(rep, x: dotX, y: 13, w: dotSize, h: dotSize, color)
        return rep
    }
    
    if char == "-" {
        fillRect(rep, x: 2, y: midY - 1, w: w - 4, h: segT, color)
        return rep
    }
    
    guard let segs = segmentPatterns[char] else { return rep }
    
    // a (top horizontal)
    if segs[0] { fillRect(rep, x: 2, y: 0, w: w - 4, h: segT, color) }
    // b (top-right vertical)
    if segs[1] { fillRect(rep, x: w - segT - gap, y: gap + segT, w: segT, h: midY - segT - gap * 2, color) }
    // c (bottom-right vertical)
    if segs[2] { fillRect(rep, x: w - segT - gap, y: midY + gap, w: segT, h: midY - segT - gap * 2, color) }
    // d (bottom horizontal)
    if segs[3] { fillRect(rep, x: 2, y: h - segT, w: w - 4, h: segT, color) }
    // e (bottom-left vertical)
    if segs[4] { fillRect(rep, x: gap, y: midY + gap, w: segT, h: midY - segT - gap * 2, color) }
    // f (top-left vertical)
    if segs[5] { fillRect(rep, x: gap, y: gap + segT, w: segT, h: midY - segT - gap * 2, color) }
    // g (middle horizontal)
    if segs[6] { fillRect(rep, x: 2, y: midY - 1, w: w - 4, h: segT, color) }
    
    return rep
}

// MARK: - Transport Buttons (28x24 each)

func renderTransportButton(icon: String, pressed: Bool) -> NSBitmapImageRep {
    let w = 28, h = 24
    let rep = createBitmap(width: w, height: h)
    clearBitmap(rep)
    
    let face = pressed ? C.shadow : C.btnFace
    let hi = pressed ? C.shadow : C.highlight
    let sh = pressed ? C.highlight : C.shadow
    
    // Fill face
    fillRect(rep, x: 1, y: 1, w: w - 2, h: h - 2, face)
    
    // Top edge highlight
    fillRect(rep, x: 0, y: 0, w: w, h: 1, hi)
    // Left edge highlight
    for py in 0..<h { setPixel(rep, x: 0, y: py, hi) }
    // Bottom edge shadow
    fillRect(rep, x: 0, y: h - 1, w: w, h: 1, sh)
    // Right edge shadow
    for py in 0..<h { setPixel(rep, x: w - 1, y: py, sh) }
    
    // Border
    fillRect(rep, x: 0, y: 0, w: w, h: 1, C.btnBorder)
    fillRect(rep, x: 0, y: h - 1, w: w, h: 1, C.btnBorder)
    for py in 0..<h { setPixel(rep, x: 0, y: py, C.btnBorder); setPixel(rep, x: w - 1, y: py, C.btnBorder) }
    // Inner bevel
    if !pressed {
        fillRect(rep, x: 1, y: 1, w: w - 2, h: 1, hi)
        for py in 1..<(h-1) { setPixel(rep, x: 1, y: py, hi) }
        fillRect(rep, x: 1, y: h - 2, w: w - 2, h: 1, sh)
        for py in 1..<(h-1) { setPixel(rep, x: w - 2, y: py, sh) }
    }
    
    // Draw icon using Core Graphics — amber stroked/filled outlines
    let iconAlpha: CGFloat = pressed ? 0.7 : 1.0
    let iconColor = CGColor(
        red: CGFloat(C.amber.0) / 255.0,
        green: CGFloat(C.amber.1) / 255.0,
        blue: CGFloat(C.amber.2) / 255.0,
        alpha: iconAlpha
    )
    let fOx: CGFloat = pressed ? 1 : 0
    withFlippedCGContext(rep) { ctx, _, _ in
        let cx = CGFloat(w) / 2 + fOx
        let cy = CGFloat(h) / 2 + fOx
        ctx.setFillColor(iconColor)
        ctx.setStrokeColor(iconColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setShouldAntialias(true)
        switch icon {
        case "prev":
            // |<< — filled bar on left + two left-pointing chevron strokes
            ctx.fill(CGRect(x: cx - 8, y: cy - 6, width: 2, height: 12))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx - 4, y: cy))
            ctx.addLine(to: CGPoint(x: cx, y: cy + 6))
            ctx.strokePath()
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx + 6, y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx + 2, y: cy))
            ctx.addLine(to: CGPoint(x: cx + 6, y: cy + 6))
            ctx.strokePath()
        case "play":
            // ▶ — filled right-pointing triangle
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx - 5, y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx - 5, y: cy + 6))
            ctx.addLine(to: CGPoint(x: cx + 6, y: cy))
            ctx.closePath()
            ctx.fillPath()
        case "pause":
            // ‖ — two filled vertical bars
            ctx.fill(CGRect(x: cx - 5,   y: cy - 5.5, width: 3.5, height: 11))
            ctx.fill(CGRect(x: cx + 1.5, y: cy - 5.5, width: 3.5, height: 11))
        case "stop":
            // ■ — filled square
            ctx.fill(CGRect(x: cx - 5, y: cy - 5, width: 10, height: 10))
        case "next":
            // >>| — two right-pointing chevron strokes + filled bar on right
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx - 6, y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx - 2, y: cy))
            ctx.addLine(to: CGPoint(x: cx - 6, y: cy + 6))
            ctx.strokePath()
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx, y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx + 4, y: cy))
            ctx.addLine(to: CGPoint(x: cx, y: cy + 6))
            ctx.strokePath()
            ctx.fill(CGRect(x: cx + 6, y: cy - 6, width: 2, height: 12))
        case "eject":
            // △— — filled upward triangle + filled horizontal bar below
            ctx.beginPath()
            ctx.move(to: CGPoint(x: cx,     y: cy - 6))
            ctx.addLine(to: CGPoint(x: cx - 6, y: cy + 1))
            ctx.addLine(to: CGPoint(x: cx + 6, y: cy + 1))
            ctx.closePath()
            ctx.fillPath()
            ctx.fill(CGRect(x: cx - 6, y: cy + 3, width: 12, height: 2))
        default:
            break
        }
    }

    return rep
}

// MARK: - Skull Decoration Sprite (11x11)

/// 11-wide x 11-tall skull for title bar decorations. Uses UInt16 rows (bits 10..0 = pixels left-to-right).
/// Larger than the 7-wide font glyphs for better readability at small sizes.
/// Features: 2px-wide eye sockets, bold nose, clear alternating teeth.
let skullW = 11
let skullH = 11
let skullRows: [UInt16] = [
    0b00111111100,  // ..#######..  cranium top
    0b01111111110,  // .#########.  cranium
    0b11111111111,  // ###########  cranium full
    0b11001110011,  // ##..###..##  eye sockets (2px wide)
    0b11001110011,  // ##..###..##  eye sockets (2px tall)
    0b11111111111,  // ###########  bridge
    0b11110101111,  // ####.#.####  nose
    0b01111111110,  // .#########.  upper jaw
    0b01010101010,  // .#.#.#.#.#.  teeth
    0b00111111100,  // ..#######..  lower jaw
    0b00011111000,  // ...#####...  chin
]

func renderSkullSprite(color: (Int, Int, Int)) -> NSBitmapImageRep {
    let rep = createBitmap(width: skullW, height: skullH)
    clearBitmap(rep)
    
    for row in 0..<skullH {
        let bits = skullRows[row]
        for col in 0..<skullW {
            if bits & (1 << (10 - col)) != 0 {
                setPixel(rep, x: col, y: row, color)
            }
        }
    }
    return rep
}

// MARK: - Seek/Volume Thumb (6x6)

func renderThumb() -> NSBitmapImageRep {
    let s = 6
    let rep = createBitmap(width: s, height: s)
    clearBitmap(rep)
    fillRect(rep, x: 0, y: 0, w: s, h: s, C.silver)
    // Highlight top
    fillRect(rep, x: 0, y: 0, w: s, h: 1, C.highlight)
    for py in 0..<s { setPixel(rep, x: 0, y: py, C.highlight) }
    // Shadow bottom-right
    fillRect(rep, x: 0, y: s - 1, w: s, h: 1, C.shadow)
    for py in 0..<s { setPixel(rep, x: s - 1, y: py, C.shadow) }
    return rep
}

// MARK: - Main

let outputDir: String
if CommandLine.arguments.count > 1 {
    outputDir = CommandLine.arguments[1]
} else {
    outputDir = "Sources/NullPlayer/Resources/Skins/Skulls/images"
}

// Create output directory
try! FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

print("Generating Skulls skin assets to: \(outputDir)")

// Character-to-filename mapping (filesystem-safe: no case collisions on macOS APFS)
func charFilename(_ c: Character) -> String {
    switch c {
    case "A"..."Z": return "title_upper_\(c)"
    case "a"..."z": return "title_lower_\(c)"
    case "0"..."9": return "title_char_\(c)"
    case " ": return "title_char_space"
    case "-": return "title_char_dash"
    case ".": return "title_char_dot"
    case "_": return "title_char_underscore"
    case ":": return "title_char_colon"
    case "(": return "title_char_lparen"
    case ")": return "title_char_rparen"
    case "[": return "title_char_lbracket"
    case "]": return "title_char_rbracket"
    case "&": return "title_char_amp"
    case "'": return "title_char_apos"
    case "+": return "title_char_plus"
    case "#": return "title_char_hash"
    case "/": return "title_char_slash"
    default: return "title_char_\(c)"
    }
}

// 1. Character sprites
print("\n--- Character Sprites ---")
for (char, _) in pixelFont {
    let rep = renderCharSprite(char: char, color: C.cream)
    let name = charFilename(char)
    savePNG(rep, to: "\(outputDir)/\(name).png")
}

// 2. Time digits
print("\n--- Time Digits ---")
for digit in "0123456789" {
    let rep = renderTimeDigit(char: digit, color: C.amber)
    savePNG(rep, to: "\(outputDir)/time_digit_\(digit).png")
}
savePNG(renderTimeDigit(char: ":", color: C.amber), to: "\(outputDir)/time_colon.png")
savePNG(renderTimeDigit(char: "-", color: C.amber), to: "\(outputDir)/time_minus.png")

// 3. Transport buttons
print("\n--- Transport Buttons ---")
let icons = ["prev", "play", "pause", "stop", "next", "eject"]
for icon in icons {
    savePNG(renderTransportButton(icon: icon, pressed: false), to: "\(outputDir)/btn_\(icon)_normal.png")
    savePNG(renderTransportButton(icon: icon, pressed: true), to: "\(outputDir)/btn_\(icon)_pressed.png")
}

// 4. Thumbs
print("\n--- Thumbs ---")
savePNG(renderThumb(), to: "\(outputDir)/seek_thumb_normal.png")
savePNG(renderThumb(), to: "\(outputDir)/volume_thumb_normal.png")

// 5. Title decoration sprites
print("\n--- Title Decorations ---")
savePNG(renderSkullSprite(color: C.cream), to: "\(outputDir)/title_decoration_skull.png")

print("\nDone! Generated \(pixelFont.count + 12 + 12 + 2 + 1) assets.")
