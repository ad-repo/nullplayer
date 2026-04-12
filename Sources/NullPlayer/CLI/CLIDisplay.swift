import AppKit
import NullPlayerCore

class CLIDisplay {

    /// Prints content above the progress bar line.
    /// Clears the current progress line, prints content, then
    /// leaves cursor on a fresh line for the next progress update.
    func printAboveProgress(_ text: String) {
        // Move to start of line, clear it (removes stale progress bar),
        // print the content, then leave a blank line for progress to rewrite.
        fputs("\r\u{1B}[K\(text)\n", stdout)
        fflush(stdout)
    }

    func printTrackInfo(_ track: Track?) {
        guard let track else { return }
        let artist = track.artist ?? "Unknown Artist"
        let title = track.title ?? "Unknown Title"
        let album = track.album ?? ""
        var info = "\nNow Playing: \(artist) - \(title)"
        if !album.isEmpty {
            info += "\n      Album: \(album)"
        }
        printAboveProgress(info)
    }

    enum RepeatMode { case off, one, all }

    func updateProgress(current: TimeInterval, duration: TimeInterval,
                        volume: Float, shuffle: Bool, repeat repeatMode: RepeatMode) {
        let cur = formatTime(current)
        let dur = formatTime(duration)
        let pct = duration > 0 ? current / duration : 0
        let barWidth = 30
        let filled = Int(pct * Double(barWidth))
        let bar = String(repeating: "=", count: filled) +
                  (filled < barWidth ? ">" : "") +
                  String(repeating: " ", count: max(0, barWidth - filled - 1))
        let vol = Int(volume * 100)

        var flags: [String] = []
        if shuffle { flags.append("Shuffle") }
        switch repeatMode {
        case .one: flags.append("Repeat One")
        case .all: flags.append("Repeat All")
        case .off: break
        }
        let flagStr = flags.isEmpty ? "" : "  [\(flags.joined(separator: "] ["))]"

        let line = "\r[\(bar)] \(cur) / \(dur)  Vol: \(vol)%\(flagStr)\u{1B}[K"
        fputs(line, stdout)
        fflush(stdout)
    }

    func printState(_ state: PlaybackState) {
        // Only print meaningful state changes
        switch state {
        case .paused:
            fputs("\r\u{1B}[K[Paused]\n", stdout)
        case .stopped:
            fputs("\r\u{1B}[K[Stopped]\n", stdout)
        default:
            break
        }
    }

    func printVolume(_ volume: Float) {
        fputs("\r\u{1B}[KVolume: \(Int(volume * 100))%", stdout)
        fflush(stdout)
    }

    func printStatus(shuffle: Bool, repeat repeatOn: Bool) {
        var parts: [String] = []
        parts.append("Shuffle: \(shuffle ? "On" : "Off")")
        parts.append("Repeat: \(repeatOn ? "On" : "Off")")
        fputs("\r\u{1B}[K\(parts.joined(separator: "  "))", stdout)
        fflush(stdout)
    }

    func printRepeatStatus(shuffle: Bool, repeat repeatMode: RepeatMode) {
        let modeStr: String
        switch repeatMode {
        case .off: modeStr = "Off"
        case .one: modeStr = "One"
        case .all: modeStr = "All"
        }
        fputs("\r\u{1B}[KShuffle: \(shuffle ? "On" : "Off")  Repeat: \(modeStr)", stdout)
        fflush(stdout)
    }

    // MARK: - Query Output

    static func printTable(headers: [String], rows: [[String]]) {
        guard !rows.isEmpty else {
            print("No results found.")
            return
        }

        // Calculate column widths
        var widths = headers.map { $0.count }
        for row in rows {
            for (i, cell) in row.enumerated() where i < widths.count {
                widths[i] = max(widths[i], cell.count)
            }
        }

        // Print header
        let headerLine = zip(headers, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ")
        print(headerLine)
        print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))

        // Print rows
        for row in rows {
            let line = zip(row, widths).map { $0.padding(toLength: $1, withPad: " ", startingAt: 0) }.joined(separator: "  ")
            print(line)
        }

        print("\n\(rows.count) result(s)")
    }

    static func printJSON<T: Encodable>(_ items: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        }
    }

    static func printHelp() {
        print("""
        NullPlayer CLI Mode

        USAGE:
            NullPlayer --cli [OPTIONS]

        QUERY COMMANDS (print and exit):
            --list-sources              List configured sources
            --list-artists              List artists (requires --source)
            --list-albums               List albums (optional --artist filter)
            --list-tracks               List tracks (optional --artist/--album filter)
            --list-genres               List genres (local library only)
            --list-playlists            List playlists
            --list-stations             List radio stations (optional --folder filter)
            --list-devices              List cast devices
            --list-outputs              List audio output devices
            --list-eq                   List EQ presets

        PLAYBACK:
            --source <name>             Source: local, plex, subsonic, jellyfin, emby, radio
            --artist <name>             Select by artist
            --album <name>              Select by album
            --track <name>              Select by track title
            --genre <name>              Select by genre
            --search <query>            Search within source
            --playlist <name>           Play playlist
            --radio <mode>              Radio: library, genre, decade, hits, deep-cuts,
                                        rating, favorites, artist, album, track
            --station <name>            Play internet radio station
            --search <query>            Search and play (or print results if no
                                        playback flags are given)

        OPTIONS:
            --shuffle                   Enable shuffle
            --repeat-all                Repeat entire playlist
            --repeat-one                Repeat current track
            --volume <0-100>            Set volume
            --eq <preset>               Set EQ preset
            --output <device>           Set audio output device
            --cast <device>             Cast to device
            --cast-type <type>          Filter: sonos, chromecast, dlna
            --sonos-rooms <rooms>       Multi-room (comma-separated)
            --folder <name>             Radio folder: all, favorites, top-rated,
                                        unrated, recent, channels, genres, regions,
                                        genre, channel, region
            --channel <name>            Radio channel (with --folder channel)
            --region <name>             Radio region (with --folder region)
            --no-art                    Disable ASCII album art
            --json                      JSON output for queries

        KEYBOARD CONTROLS (during playback):
            Space       Pause/Resume
            q           Quit
            > / <       Next / Previous track
            Arrow keys  Right/Left: Seek | Up/Down: Volume
            s           Toggle shuffle
            r           Cycle repeat (off -> all -> one -> off)
            m           Toggle mute
            i           Show track info
        """)
    }

    static func printVersion() {
        // Bundle.main may not resolve in CLI mode if invoked as bare binary;
        // fall back to the marketing version compiled into the app
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle(for: CLIDisplay.self).infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "unknown"
        print("NullPlayer \(version)")
    }

    // MARK: - ASCII Art

    func printAsciiArt(_ image: NSImage) {
        let artWidth = 60  // characters wide
        // Terminal characters are ~2:1 tall:wide. Each half-block char (▀) covers
        // 2 pixel rows, so one character cell ≈ 1 square pixel visually.
        // To produce a square image: artWidth cols × (artWidth/2) rows of chars,
        // sampled from an artWidth×artWidth pixel grid.
        let pixelWidth = artWidth
        let pixelHeight = artWidth  // artWidth/2 output rows × 2 pixel-rows each

        // cgImage(forProposedRect:) returns nil in headless processes (no display context).
        // tiffRepresentation rasterizes at native size without needing a screen.
        guard let tiff = image.tiffRepresentation else {
            NSLog("[CLIArt] printAsciiArt: tiffRepresentation returned nil")
            return
        }
        guard let rep = NSBitmapImageRep(data: tiff) else {
            NSLog("[CLIArt] printAsciiArt: NSBitmapImageRep(data:) returned nil")
            return
        }
        guard let cgImage = rep.cgImage else {
            NSLog("[CLIArt] printAsciiArt: rep.cgImage returned nil")
            return
        }
        NSLog("[CLIArt] printAsciiArt: rendering %dx%d image", cgImage.width, cgImage.height)

        // Draw into a small bitmap for sampling
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))

        // Build ASCII art using half-block characters.
        // Each output row combines two pixel rows:
        //   top pixel → foreground color (▀ upper half block)
        //   bottom pixel → background color
        // CGContext origin is bottom-left: memory row 0 = image top (CG flips on draw).
        // Iterate from row 0 upward; reverse x for correct horizontal orientation.
        var lines: [String] = []
        var row = 0
        while row < pixelHeight - 1 {
            var line = ""
            for x in 0..<pixelWidth {
                let topIdx = row * bytesPerRow + x * bytesPerPixel
                let botIdx = (row + 1) * bytesPerRow + x * bytesPerPixel
                let tr = pixelData[topIdx]
                let tg = pixelData[topIdx + 1]
                let tb = pixelData[topIdx + 2]
                let br = pixelData[botIdx]
                let bg = pixelData[botIdx + 1]
                let bb = pixelData[botIdx + 2]
                // True color: \e[38;2;R;G;Bm (fg) \e[48;2;R;G;Bm (bg)
                line += "\u{1B}[38;2;\(tr);\(tg);\(tb);48;2;\(br);\(bg);\(bb)m▀"
            }
            line += "\u{1B}[0m"  // reset
            lines.append(line)
            row += 2
        }

        // Clear current progress line before printing art
        fputs("\r\u{1B}[K\n", stdout)
        for line in lines {
            print(line)
        }
        // Leave blank line so progress bar rewrites below the art
        print("")
        fflush(stdout)
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
