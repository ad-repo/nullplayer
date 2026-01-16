import AppKit
import ZIPFoundation

/// Loads Winamp skins from .wsz files
class SkinLoader {
    
    // MARK: - Singleton
    
    static let shared = SkinLoader()
    
    private init() {}
    
    // MARK: - Loading
    
    /// Load a skin from a .wsz file
    func load(from url: URL) throws -> Skin {
        // Create temporary directory for extraction
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Extract ZIP (wsz is just a renamed zip)
        try FileManager.default.unzipItem(at: url, to: tempDir)
        
        // Load all skin assets
        return try loadSkin(from: tempDir)
    }
    
    /// Load the default/built-in skin
    func loadDefault() -> Skin {
        // Return a skin with nil images - will use fallback rendering
        return Skin(
            main: nil,
            cbuttons: nil,
            monoster: nil,
            numbers: nil,
            numsEx: nil,
            playpaus: nil,
            posbar: nil,
            shufrep: nil,
            text: nil,
            titlebar: nil,
            volume: nil,
            balance: nil,
            eqmain: nil,
            eqEx: nil,
            pledit: nil,
            playlistColors: .default,
            visColors: defaultVisColors(),
            regions: nil,
            cursors: [:]
        )
    }
    
    // MARK: - Private Methods
    
    private func loadSkin(from directory: URL) throws -> Skin {
        // Helper to load BMP with case-insensitive filename matching
        func loadImage(_ name: String) -> NSImage? {
            let possibleNames = [name, name.lowercased(), name.uppercased()]
            let extensions = ["bmp", "BMP", "Bmp"]
            
            for n in possibleNames {
                for ext in extensions {
                    let url = directory.appendingPathComponent("\(n).\(ext)")
                    if let image = loadBMP(from: url) {
                        return image
                    }
                }
            }
            return nil
        }
        
        // Load playlist colors
        let playlistColors = loadPlaylistColors(from: directory)
        
        // Load visualization colors
        let visColors = loadVisColors(from: directory)
        
        // Load regions
        let regions = loadRegions(from: directory)
        
        // Load cursors
        let cursors = loadCursors(from: directory)
        
        return Skin(
            main: loadImage("main"),
            cbuttons: loadImage("cbuttons"),
            monoster: loadImage("monoster"),
            numbers: loadImage("numbers"),
            numsEx: loadImage("nums_ex"),
            playpaus: loadImage("playpaus"),
            posbar: loadImage("posbar"),
            shufrep: loadImage("shufrep"),
            text: loadImage("text"),
            titlebar: loadImage("titlebar"),
            volume: loadImage("volume"),
            balance: loadImage("balance"),
            eqmain: loadImage("eqmain"),
            eqEx: loadImage("eq_ex"),
            pledit: loadImage("pledit"),
            playlistColors: playlistColors,
            visColors: visColors,
            regions: regions,
            cursors: cursors
        )
    }
    
    private func loadBMP(from url: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: url)
            return BMPParser.parse(data: data)
        } catch {
            print("Failed to load BMP from \(url): \(error)")
            return nil
        }
    }
    
    private func loadPlaylistColors(from directory: URL) -> PlaylistColors {
        let possiblePaths = [
            directory.appendingPathComponent("pledit.txt"),
            directory.appendingPathComponent("PLEDIT.TXT"),
            directory.appendingPathComponent("Pledit.txt")
        ]
        
        for path in possiblePaths {
            if let colors = parsePlaylistColors(from: path) {
                return colors
            }
        }
        
        return .default
    }
    
    private func parsePlaylistColors(from url: URL) -> PlaylistColors? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        var normalText = PlaylistColors.default.normalText
        var currentText = PlaylistColors.default.currentText
        var normalBG = PlaylistColors.default.normalBackground
        var selectedBG = PlaylistColors.default.selectedBackground
        var font = PlaylistColors.default.font
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.lowercased().hasPrefix("normal=") {
                if let color = parseColor(from: trimmed) {
                    normalText = color
                }
            } else if trimmed.lowercased().hasPrefix("current=") {
                if let color = parseColor(from: trimmed) {
                    currentText = color
                }
            } else if trimmed.lowercased().hasPrefix("normalbg=") {
                if let color = parseColor(from: trimmed) {
                    normalBG = color
                }
            } else if trimmed.lowercased().hasPrefix("selectedbg=") {
                if let color = parseColor(from: trimmed) {
                    selectedBG = color
                }
            } else if trimmed.lowercased().hasPrefix("font=") {
                let fontName = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let loadedFont = NSFont(name: fontName, size: 8) {
                    font = loadedFont
                }
            }
        }
        
        return PlaylistColors(
            normalText: normalText,
            currentText: currentText,
            normalBackground: normalBG,
            selectedBackground: selectedBG,
            font: font
        )
    }
    
    private func parseColor(from line: String) -> NSColor? {
        guard let equalsIndex = line.firstIndex(of: "=") else { return nil }
        let colorString = String(line[line.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespaces)
        return NSColor(hex: colorString)
    }
    
    private func loadVisColors(from directory: URL) -> [NSColor] {
        let possiblePaths = [
            directory.appendingPathComponent("viscolor.txt"),
            directory.appendingPathComponent("VISCOLOR.TXT"),
            directory.appendingPathComponent("Viscolor.txt")
        ]
        
        for path in possiblePaths {
            if let colors = parseVisColors(from: path) {
                return colors
            }
        }
        
        return defaultVisColors()
    }
    
    private func parseVisColors(from url: URL) -> [NSColor]? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        var colors: [NSColor] = []
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("//") || trimmed.hasPrefix(";") {
                continue
            }
            
            // Parse RGB values (comma or space separated)
            let components = trimmed.components(separatedBy: CharacterSet(charactersIn: ", "))
                .filter { !$0.isEmpty }
                .compactMap { Int($0) }
            
            if components.count >= 3 {
                let color = NSColor(
                    red: CGFloat(components[0]) / 255.0,
                    green: CGFloat(components[1]) / 255.0,
                    blue: CGFloat(components[2]) / 255.0,
                    alpha: 1.0
                )
                colors.append(color)
            }
        }
        
        // Winamp expects 24 colors for visualizations
        while colors.count < 24 {
            colors.append(.green)
        }
        
        return colors
    }
    
    private func defaultVisColors() -> [NSColor] {
        // Default green gradient for visualizations
        return (0..<24).map { i in
            let brightness = CGFloat(i) / 23.0
            return NSColor(red: 0, green: brightness, blue: 0, alpha: 1.0)
        }
    }
    
    private func loadRegions(from directory: URL) -> WindowRegions? {
        let possiblePaths = [
            directory.appendingPathComponent("region.txt"),
            directory.appendingPathComponent("REGION.TXT"),
            directory.appendingPathComponent("Region.txt")
        ]
        
        for path in possiblePaths {
            if let regions = parseRegions(from: path) {
                return regions
            }
        }
        
        return nil
    }
    
    private func parseRegions(from url: URL) -> WindowRegions? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        
        // Parse region.txt format
        // Can contain multiple sections: [Normal], [WindowShade], [Equalizer], etc.
        
        var currentSection = ""
        var mainNormal: [NSPoint]?
        var mainShade: [NSPoint]?
        var eqNormal: [NSPoint]?
        var eqShade: [NSPoint]?
        var playlistNormal: [NSPoint]?
        var playlistShade: [NSPoint]?
        
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast()).lowercased()
            } else if trimmed.lowercased().hasPrefix("pointlist=") {
                let points = parsePointList(from: trimmed)
                
                switch currentSection {
                case "normal", "":
                    mainNormal = points
                case "windowshade":
                    mainShade = points
                case "equalizer":
                    eqNormal = points
                case "equalizershade":
                    eqShade = points
                case "playlist":
                    playlistNormal = points
                case "playlistshade":
                    playlistShade = points
                default:
                    break
                }
            }
        }
        
        return WindowRegions(
            mainNormal: mainNormal,
            mainShade: mainShade,
            eqNormal: eqNormal,
            eqShade: eqShade,
            playlistNormal: playlistNormal,
            playlistShade: playlistShade
        )
    }
    
    private func parsePointList(from line: String) -> [NSPoint]? {
        guard let equalsIndex = line.firstIndex(of: "=") else { return nil }
        let pointsString = String(line[line.index(after: equalsIndex)...])
            .trimmingCharacters(in: .whitespaces)
        
        let values = pointsString.components(separatedBy: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        
        guard values.count >= 2 && values.count % 2 == 0 else { return nil }
        
        var points: [NSPoint] = []
        for i in stride(from: 0, to: values.count, by: 2) {
            points.append(NSPoint(x: values[i], y: values[i + 1]))
        }
        
        return points
    }
    
    private func loadCursors(from directory: URL) -> [String: NSCursor] {
        // Load custom cursors from cursors/ subdirectory
        var cursors: [String: NSCursor] = [:]
        
        let cursorDir = directory.appendingPathComponent("cursors")
        guard FileManager.default.fileExists(atPath: cursorDir.path) else { return cursors }
        
        let cursorFiles = [
            "normal", "close", "titlebar", "mainmenu",
            "posbar", "volume", "eqslider", "eqnormal"
        ]
        
        for name in cursorFiles {
            let extensions = ["cur", "CUR", "ani", "ANI"]
            for ext in extensions {
                let url = cursorDir.appendingPathComponent("\(name).\(ext)")
                if let cursor = loadCursor(from: url) {
                    cursors[name] = cursor
                    break
                }
            }
        }
        
        return cursors
    }
    
    private func loadCursor(from url: URL) -> NSCursor? {
        // For now, return nil - cursor loading is complex
        // TODO: Implement .cur/.ani file parsing
        return nil
    }
}
