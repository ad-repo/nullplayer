import AppKit

/// The standard Winamp 2 playlist editor frame (`ClassicPlaylistStyle.winamp`): PLEDIT's title bar
/// with its own right corner, the 12px left and 20px scrollbar borders, and the 38px bottom bar.
extension SkinRenderer {
    func drawWinampPlaylistWindow(in context: CGContext, bounds: NSRect, isActive: Bool,
                                  closePressed: Bool, scrollPosition: CGFloat,
                                  runningTime: String, trackTime: (minutes: String, seconds: String)?) {
        typealias PL = SkinElements.Playlist
        let titleHeight = PL.titleHeight
        let bottomHeight = WinampPlaylistBar.bottomHeight
        let rightBorder = WinampPlaylistBar.rightBorder
        let bottomY = bounds.height - bottomHeight

        skin.playlistColors.normalBackground.setFill()
        context.fill(bounds)

        // The shared title bar, then the skin's own right corner over its mirrored one: the original
        // corner is drawn to abut the 20px scrollbar border, and carries the close and shade glyphs.
        drawPlaylistTitleBar(in: context, bounds: bounds, isActive: isActive, pressedButton: nil)

        guard let pledit = skin.pledit else {
            NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1).setFill()
            context.fill(NSRect(x: 0, y: titleHeight, width: 12, height: bottomY - titleHeight))
            context.fill(NSRect(x: bounds.width - rightBorder, y: titleHeight, width: rightBorder,
                                height: bottomY - titleHeight))
            context.fill(NSRect(x: 0, y: bottomY, width: bounds.width, height: bottomHeight))
            return
        }

        let rightCorner = isActive ? PL.TitleBarActive.rightCorner : PL.TitleBarInactive.rightCorner
        drawSprite(from: pledit, sourceRect: rightCorner,
                   to: NSRect(x: bounds.width - 25, y: 0, width: 25, height: titleHeight), in: context)
        if closePressed {
            NSColor(calibratedWhite: 0.3, alpha: 0.5).setFill()
            context.fill(NSRect(x: bounds.width - 11, y: 3, width: 9, height: 9))
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
        let rightCornerX = bounds.width - WinampPlaylistBar.rightCornerWidth
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
                   to: NSRect(x: rightCornerX, y: bottomY, width: WinampPlaylistBar.rightCornerWidth,
                              height: bottomHeight), in: context)

        // Scrollbar thumb.
        let groove = WinampPlaylistBar.scrollbarRect(size: bounds.size, titleHeight: titleHeight)
        let thumbHeight = PL.scrollbarThumbNormal.height
        let thumbY = groove.minY + max(0, groove.height - thumbHeight) * max(0, min(1, scrollPosition))
        drawSprite(from: pledit, sourceRect: PL.scrollbarThumbNormal,
                   to: NSRect(x: groove.minX, y: thumbY, width: groove.width, height: thumbHeight), in: context)

        // Running time and the playing track's time, in the skin's TEXT.BMP font.
        drawSkinText(runningTime, at: WinampPlaylistBar.runningTimeOrigin(size: bounds.size), in: context)
        if let trackTime {
            let charWidth = SkinElements.TextFont.charWidth
            let colonX = WinampPlaylistBar.trackTimeColonX(size: bounds.size)
            let timeY = WinampPlaylistBar.trackTimeY(size: bounds.size)
            drawSkinText(trackTime.minutes,
                         at: NSPoint(x: colonX - 1 - CGFloat(trackTime.minutes.count) * charWidth, y: timeY),
                         in: context)
            drawSkinText(trackTime.seconds, at: NSPoint(x: colonX + 3, y: timeY), in: context)
        }
    }
}
