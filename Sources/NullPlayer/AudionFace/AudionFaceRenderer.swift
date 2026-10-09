/*
Copyright 2020-2021 Panic Inc.

This file is part of Audion.

Audion is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Audion is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Audion.  If not, see <https://www.gnu.org/licenses/>.
*/
// NullPlayer: `textImage` is adapted from FaceKit `FaceKit/AudionFaceView.swift` `draw(text:…)` at
// 5b7c847 (https://gitlab.com/panicinc/facekit). The compositing reproduces that view's layer
// stack in one CGContext; see `AudionFaceDrawOp.Layer`.

import AppKit

/// An `AudionFaceScene` to pixels: integer scale, nearest-neighbour, alpha kept. The harness and
/// the face window both draw through this, so what the sweep measures is what the screen shows.
enum AudionFaceRenderer {
    static func render(_ scene: AudionFaceScene) -> CGImage? {
        let scale = scene.scale
        let size = CGSize(width: scene.width * scale, height: scene.height * scale)
        guard let canvas = context(size) else { return nil }
        func device(_ rect: AudionFaceRect) -> CGRect {
            let flipped = rect.flipped(inHeight: scene.height)
            return CGRect(x: flipped.minX * CGFloat(scale), y: flipped.minY * CGFloat(scale),
                          width: flipped.width * CGFloat(scale), height: flipped.height * CGFloat(scale))
        }

        for layer in AudionFaceDrawOp.Layer.allCases {
            let ops = scene.ops.filter { $0.layer == layer }
            switch layer {
            case .base:
                for op in ops { canvas.clear(device(op.rect)); canvas.draw(op.image, in: device(op.rect)) }
            case .buttons:
                for op in ops { canvas.draw(op.image, in: device(op.rect)) }
            case .readouts:
                guard !ops.isEmpty, let readouts = context(size) else { continue }
                for op in ops { readouts.clear(device(op.rect)); readouts.draw(op.image, in: device(op.rect)) }
                readouts.makeImage().map { canvas.draw($0, in: CGRect(origin: .zero, size: size)) }
            case .labels:
                for op in ops {
                    let box = device(op.rect)
                    canvas.saveGState()
                    canvas.clip(to: box)
                    // Top-aligned at its own pixel size, as FaceKit's flipped label lays it out.
                    canvas.draw(op.image, in: CGRect(x: box.minX + CGFloat(op.textOffset),
                                                     y: box.maxY - CGFloat(op.image.height),
                                                     width: CGFloat(op.image.width), height: CGFloat(op.image.height)))
                    canvas.restoreGState()
                }
            case .mask:
                guard let op = ops.first, let content = canvas.makeImage(), let masked = context(size) else { continue }
                masked.draw(op.image, in: device(op.rect))
                masked.setBlendMode(.sourceIn)
                masked.draw(content, in: CGRect(origin: .zero, size: size))
                return masked.makeImage()
            }
        }
        return canvas.makeImage()
    }

    private static func context(_ size: CGSize) -> CGContext? {
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.interpolationQuality = .none
        return context
    }

    /// FaceKit `draw(text:…)`: the line rasterized at `scale`, in an image as wide as the whole
    /// string. When justified or under Reduce Motion, a string wider than its box is cut from the
    /// middle with an ellipsis. Nil for a box under 12 px or a string with no width.
    static func textImage(_ text: String, line: AudionFace.TextLine, justify: Bool, scale: Int,
                          reduceMotion: Bool) -> CGImage? {
        guard line.rect.width >= 12 else { return nil }
        var font = line.font
        if scale > 1 {
            font = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * CGFloat(scale), nil, nil)
        }
        func substitute(_ trait: CTFontSymbolicTraits, mask: CTFontSymbolicTraits) {
            if let substituted = CTFontCreateCopyWithSymbolicTraits(font, CTFontGetSize(font), nil, trait, mask) {
                font = substituted
            }
        }
        let style = line.style
        if style.contains(.bold) { substitute(.traitBold, mask: .traitBold) }
        if style.contains(.italic) { substitute(.traitItalic, mask: .traitItalic) }
        if style.contains(.condense) { substitute(.traitCondensed, mask: .traitCondensed) }
        // FaceKit's mask, kept: expanded is requested under the condensed bit.
        if style.contains(.extend) { substitute(.traitExpanded, mask: .traitCondensed) }

        let color = NSColor(cgColor: line.color) ?? .black
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if style.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.underlineColor] = color
        }
        if style.contains(.shadow) {
            let shadow = NSShadow()
            shadow.shadowColor = color
            shadow.shadowOffset = CGSize(width: 4, height: 4)
            attributes[.shadow] = shadow
        }
        if style.contains(.outline) {
            attributes[.foregroundColor] = NSColor.clear
            attributes[.strokeColor] = color
        }

        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.textMatrix = CGAffineTransform(translationX: 0, y: (CTFontGetAscent(font) - CTFontGetDescent(font)) / 2)

        let boxWidth = CGFloat(line.rect.width * scale)
        guard justify || reduceMotion, size.width > boxWidth else {
            CTLineDraw(CTLineCreateWithAttributedString(string), context)
            return context.makeImage()
        }
        // FaceKit trims one character from each side of the middle until the line fits, and draws
        // only on a strict fit. Stopping when nothing is left to trim is NullPlayer's: FaceKit
        // would loop forever on a font whose ellipsis alone is wider than the box.
        var head = Substring(text.prefix(text.count / 2)), tail = Substring(text.dropFirst(text.count / 2))
        while !head.isEmpty || !tail.isEmpty {
            head = head.dropLast()
            tail = tail.dropFirst()
            let shortened = NSAttributedString(string: head + "…" + tail, attributes: attributes)
            let width = shortened.size().width
            if width < boxWidth { CTLineDraw(CTLineCreateWithAttributedString(shortened), context) }
            if width <= boxWidth { break }
        }
        return context.makeImage()
    }
}
