import AppKit

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
            nullplayer --cli [OPTIONS]

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
            --tuning <off|Hz>           Reference Tuning target Hz
            --tuning-source <Hz>        Source reference Hz (default: 440)
            --tuning-offset-cents <n>   Direct tuning offset in cents
            --cast <device>             Cast to device
            --cast-type <type>          Filter: sonos, chromecast, dlna
            --sonos-rooms <rooms>       Group rooms (comma-separated) to --cast device
            --folder <name>             Radio folder: all, favorites, top-rated,
                                        unrated, recent, channels, genres, regions,
                                        genre, channel, region
            --channel <name>            Radio channel (with --folder channel)
            --region <name>             Radio region (with --folder region)
            --verbose                   Keep framework log output (suppressed by default)
            --no-art                    Disable album art
            --color-art                 Force color art (truecolor/256-color)
            --ascii-art                 Force monochrome character-ramp art
                                        (default auto-detects terminal color support;
                                        set NULLPLAYER_ART=ascii|color|auto to pin a
                                        per-terminal default)
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
        print("nullplayer -> NullPlayer \(version)")
    }

    // MARK: - ASCII Art

    /// Luminance ramp, darkest → brightest, for the no-color (mono) path.
    /// Assumes a dark terminal background so denser glyphs read as brighter pixels.
    private static let asciiRamp = Array(" .:-=+*#%@")

    enum ColorMode { case truecolor, ansi256, mono }

    /// Best-effort detection of the terminal's color capability from the environment.
    /// Purely declarative (env-based) — it reports what the terminal *claims*, which
    /// a color-disabled profile can still misrepresent; hence the explicit overrides.
    /// Only returns a color mode on a positive signal, so ambiguous terminals fall
    /// back to the always-safe monochrome ramp.
    static func detectColorMode() -> ColorMode {
        // Not a real terminal (piped/redirected) → color codes would be garbage.
        guard isatty(fileno(stdout)) != 0 else { return .mono }
        let env = ProcessInfo.processInfo.environment
        let colorterm = env["COLORTERM"]?.lowercased() ?? ""
        if colorterm.contains("truecolor") || colorterm.contains("24bit") { return .truecolor }
        let term = env["TERM"]?.lowercased() ?? ""
        if term.contains("truecolor") || term.contains("direct") { return .truecolor }
        if term.contains("256color") { return .ansi256 }
        return .mono
    }

    /// Render album art to the terminal.
    ///
    /// By default the mode is auto-detected (`detectColorMode`): a color-capable
    /// terminal gets truecolor/256 half-block art, everything else gets a monochrome
    /// luminance→character ramp that renders anywhere. The overrides exist because
    /// detection is declarative and a terminal can misreport its color support.
    /// Precedence: explicit flags > `NULLPLAYER_ART` env var > auto-detection.
    /// - Parameters:
    ///   - forceColor: force the color half-block path (`--color-art`).
    ///   - forceAscii: force the monochrome ramp (`--ascii-art`), for terminals that
    ///     claim color but don't actually render it.
    func printAsciiArt(_ image: NSImage, forceColor: Bool = false, forceAscii: Bool = false) {
        let detected = Self.detectColorMode()
        let asciiMode: Bool
        if forceAscii {
            asciiMode = true
        } else if forceColor {
            asciiMode = false
        } else {
            // Per-terminal default override. Detection is env-based and can't see through
            // a terminal that misreports color support (e.g. `export COLORTERM=truecolor`
            // in a shell profile makes every terminal claim truecolor even when it renders
            // monochrome). NULLPLAYER_ART lets such a terminal pin `ascii` in its profile
            // without passing a flag every time. Unset/"auto"/unrecognized → auto-detect.
            switch ProcessInfo.processInfo.environment["NULLPLAYER_ART"]?.lowercased() {
            case "ascii", "mono": asciiMode = true
            case "color":         asciiMode = false
            default:              asciiMode = (detected == .mono)
            }
        }
        let artWidth = 60  // characters wide
        // Terminal characters are ~2:1 tall:wide. In color mode each half-block char
        // (▀) covers 2 pixel rows, so a square image needs artWidth×artWidth pixels
        // (→ artWidth/2 output rows). In ascii mode each char covers 1 pixel, so a
        // square image needs artWidth × (artWidth/2) pixels (one char per pixel).
        let pixelWidth = artWidth
        let pixelHeight = asciiMode ? artWidth / 2 : artWidth

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

        // No-color path: map each pixel's luminance to a ramp glyph. Works on any
        // terminal because it carries the image in the characters themselves, not
        // in color codes. CGContext origin is bottom-left (memory row 0 = image top).
        if asciiMode {
            var lines: [String] = []
            for row in 0..<pixelHeight {
                var line = ""
                for x in 0..<pixelWidth {
                    let idx = row * bytesPerRow + x * bytesPerPixel
                    let r = Double(pixelData[idx])
                    let g = Double(pixelData[idx + 1])
                    let b = Double(pixelData[idx + 2])
                    // Rec. 601 luma → ramp index.
                    let luma = 0.299 * r + 0.587 * g + 0.114 * b
                    let rampIdx = min(Self.asciiRamp.count - 1,
                                      Int(luma / 255.0 * Double(Self.asciiRamp.count - 1)))
                    line.append(Self.asciiRamp[rampIdx])
                }
                lines.append(line)
            }
            fputs("\r\u{1B}[K\n", stdout)
            for line in lines { print(line) }
            print("")
            fflush(stdout)
            return
        }

        // Color half-block path. Every cell is the same ▀ glyph — the picture is
        // carried entirely by the per-cell color codes. Use truecolor only when it
        // was positively detected; otherwise emit the xterm 256-color palette (which
        // is what a forceColor request on an unknown terminal falls back to).
        let useTrueColor = (detected == .truecolor)

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
                if useTrueColor {
                    // True color: \e[38;2;R;G;Bm (fg) \e[48;2;R;G;Bm (bg)
                    line += "\u{1B}[38;2;\(tr);\(tg);\(tb);48;2;\(br);\(bg);\(bb)m▀"
                } else {
                    // 256-color fallback: \e[38;5;{n}m (fg) \e[48;5;{n}m (bg)
                    let fgIdx = Self.ansi256Index(r: tr, g: tg, b: tb)
                    let bgIdx = Self.ansi256Index(r: br, g: bg, b: bb)
                    line += "\u{1B}[38;5;\(fgIdx);48;5;\(bgIdx)m▀"
                }
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

    /// Map an 8-bit RGB color to the nearest xterm 256-color palette index.
    /// Considers both the 6×6×6 color cube (16–231) and the grayscale ramp
    /// (232–255), returning whichever candidate is closer to the source color.
    private static func ansi256Index(r: UInt8, g: UInt8, b: UInt8) -> Int {
        let ri = Int(r), gi = Int(g), bi = Int(b)

        // Nearest color-cube component using xterm's non-linear steps.
        let steps = [0, 95, 135, 175, 215, 255]
        func cubeIndex(_ v: Int) -> Int {
            var best = 0, bestDist = Int.max
            for (i, s) in steps.enumerated() {
                let d = abs(s - v)
                if d < bestDist { bestDist = d; best = i }
            }
            return best
        }
        let cr = cubeIndex(ri), cg = cubeIndex(gi), cb = cubeIndex(bi)
        let cubeColor = (steps[cr], steps[cg], steps[cb])
        let cubeCode = 16 + 36 * cr + 6 * cg + cb

        // Nearest grayscale-ramp entry (codes 232–255 → values 8, 18, …, 238).
        let gray = (ri + gi + bi) / 3
        let grayIdx = max(0, min(23, (gray - 8) / 10))
        let grayValue = 8 + grayIdx * 10
        let grayCode = 232 + grayIdx

        // Pick whichever candidate is closer (squared RGB distance).
        func dist(_ c: (Int, Int, Int)) -> Int {
            let dr = c.0 - ri, dg = c.1 - gi, db = c.2 - bi
            return dr * dr + dg * dg + db * db
        }
        return dist(cubeColor) <= dist((grayValue, grayValue, grayValue)) ? cubeCode : grayCode
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
