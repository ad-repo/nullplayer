import AppKit

/// The standard Winamp 2 playlist editor frame (`ClassicPlaylistStyle.winamp`): PLEDIT's title bar
/// with its own right corner, the 12px left and 20px scrollbar borders, and the 38px bottom bar.
extension SkinRenderer {
    func drawWinampPlaylistWindow(in context: CGContext, bounds: NSRect, isActive: Bool,
                                  closePressed: Bool, scrollPosition: CGFloat,
                                  runningTime: String, trackSeconds: Int?) {
        typealias PL = SkinElements.Playlist
        let titleHeight = PL.titleHeight
        let bottomHeight = PL.Editor.barHeight
        let rightBorder = PL.Editor.rightBorder
        let bottomY = bounds.height - bottomHeight

        skin.playlistColors.normalBackground.setFill()
        context.fill(bounds)

        // The shared title bar, then the skin's own right corner over its mirrored one: the original
        // corner is drawn to abut the 20px scrollbar border, and carries the close and shade glyphs.
        drawPlaylistTitleBar(in: context, bounds: bounds, isActive: isActive, pressedButton: nil)

        // `PlaylistView.isWinampStyle` picks this frame only for a skin with PLEDIT.BMP.
        guard let pledit = skin.pledit else { return }

        let rightCorner = isActive ? PL.TitleBarActive.rightCorner : PL.TitleBarInactive.rightCorner
        drawSprite(from: pledit, sourceRect: rightCorner,
                   to: NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight), in: context)
        if closePressed {
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(PL.Editor.closeGlyph(width: bounds.width))
        }

        // Side borders, tiled bottom-up so a partial tile lands under the title bar.
        let tileHeight: CGFloat = 29
        var y = bottomY - tileHeight
        while y > titleHeight - tileHeight {
            let drawY = max(titleHeight, y)
            let h = y + tileHeight - drawY
            drawSprite(from: pledit, sourceRect: NSRect(x: PL.leftSideTile.minX, y: PL.leftSideTile.minY,
                                                        width: 12, height: h),
                       to: NSRect(x: 0, y: drawY, width: 12, height: h), in: context)
            drawSprite(from: pledit, sourceRect: NSRect(x: PL.rightSideTile.minX, y: PL.rightSideTile.minY,
                                                        width: rightBorder, height: h),
                       to: NSRect(x: bounds.width - rightBorder, y: drawY, width: rightBorder, height: h),
                       in: context)
            y -= tileHeight
        }

        // Bottom bar: left corner, tiles, right corner.
        let rightCornerX = bounds.width - PL.Editor.rightCornerWidth
        var x: CGFloat = PL.bottomLeftCorner.width
        while x < rightCornerX {
            let w = min(PL.bottomTile.width, rightCornerX - x)
            drawSprite(from: pledit, sourceRect: NSRect(x: PL.bottomTile.minX, y: PL.bottomTile.minY,
                                                        width: w, height: bottomHeight),
                       to: NSRect(x: x, y: bottomY, width: w, height: bottomHeight), in: context)
            x += PL.bottomTile.width
        }
        drawSprite(from: pledit, sourceRect: PL.bottomLeftCorner,
                   to: NSRect(x: 0, y: bottomY, width: PL.bottomLeftCorner.width, height: bottomHeight),
                   in: context)
        drawSprite(from: pledit, sourceRect: PL.bottomRightCorner,
                   to: NSRect(x: rightCornerX, y: bottomY, width: PL.Editor.rightCornerWidth,
                              height: bottomHeight), in: context)

        // Scrollbar thumb.
        let groove = PL.Editor.scrollbarRect(size: bounds.size)
        let thumbHeight = PL.scrollbarThumbNormal.height
        let thumbY = groove.minY + max(0, groove.height - thumbHeight) * max(0, min(1, scrollPosition))
        drawSprite(from: pledit, sourceRect: PL.scrollbarThumbNormal,
                   to: NSRect(x: groove.minX, y: thumbY, width: groove.width, height: thumbHeight), in: context)

        // Running time and the playing track's time, in the skin's TEXT.BMP font.
        drawSkinText(runningTime, at: PL.Editor.runningTimeOrigin(size: bounds.size), in: context)
        if let trackSeconds {
            // Either side of the colon the art bakes in: minutes right-aligned to it, then seconds.
            let minutes = String(trackSeconds / 60), seconds = String(format: "%02d", trackSeconds % 60)
            let colon = PL.Editor.trackTimeColon(size: bounds.size)
            let minutesX = colon.x - 1 - CGFloat(minutes.count) * SkinElements.TextFont.charWidth
            drawSkinText(minutes, at: NSPoint(x: minutesX, y: colon.y), in: context)
            drawSkinText(seconds, at: NSPoint(x: colon.x + 3, y: colon.y), in: context)
        }
    }
}
