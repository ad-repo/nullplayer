import Foundation
import NullPlayerCore

/// Represents an equalizer preset
struct EQPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var preamp: Float
    var bands: [Float]  // Active layout bands, -12 to +12 dB
    
    init(name: String, preamp: Float = 0, bands: [Float]? = nil) {
        self.id = UUID()
        self.name = name
        self.preamp = preamp
        self.bands = bands ?? Array(repeating: 0, count: Self.activeLayout.bandCount)
    }

    /// Create a built-in preset with a stable UUID so identity is consistent across accesses
    private init(stableID: UUID, name: String, preamp: Float = 0, bands: [Float]) {
        self.id = stableID
        self.name = name
        self.preamp = preamp
        self.bands = bands
    }

    private static let presetSourceLayout = EQConfiguration.classic10

    private static var activeLayout: EQConfiguration {
        EQConfiguration.forModernUI(UserDefaults.standard.bool(forKey: "modernUIEnabled"))
    }

    private static func preset(stableID: UUID, name: String, preamp: Float = 0, classicBands: [Float]) -> EQPreset {
        EQPreset(
            stableID: stableID,
            name: name,
            preamp: preamp,
            bands: activeLayout.gainValues(remapping: classicBands, from: presetSourceLayout)
        )
    }

    // MARK: - Built-in Presets

    // Stable UUIDs for built-in presets so Identifiable views don't treat them as new items on every access
    private static let flatID       = UUID(uuidString: "00000000-E000-0000-0000-000000000001")!
    private static let imOldID      = UUID(uuidString: "00000000-E000-0000-0000-000000000002")!
    private static let imYoungID    = UUID(uuidString: "00000000-E000-0000-0000-000000000003")!
    private static let rockID       = UUID(uuidString: "00000000-E000-0000-0000-000000000004")!
    private static let popID        = UUID(uuidString: "00000000-E000-0000-0000-000000000005")!
    private static let electronicID = UUID(uuidString: "00000000-E000-0000-0000-000000000006")!
    private static let hipHopID     = UUID(uuidString: "00000000-E000-0000-0000-000000000007")!
    private static let jazzID       = UUID(uuidString: "00000000-E000-0000-0000-000000000008")!
    private static let classicalID  = UUID(uuidString: "00000000-E000-0000-0000-000000000009")!

    static var flat: EQPreset {
        EQPreset(stableID: flatID, name: "Flat", bands: Array(repeating: 0, count: activeLayout.bandCount))
    }

    static var imOld: EQPreset {
        preset(
            stableID: imOldID,
            name: "I'm Old",
            preamp: 0,
            classicBands: [-2, -1, 0, 0, 1, 2, 4, 6, 7, 8]
        )
    }

    static var imYoung: EQPreset {
        preset(
            stableID: imYoungID,
            name: "I'm Young",
            preamp: -2,
            classicBands: [8, 6, 4, 2, 0, -1, 0, 1, 1, 0]
        )
    }

    static var allPresets: [EQPreset] {
        [.flat, .imOld, .imYoung, .rock, .pop, .electronic, .hipHop, .jazz, .classical]
    }

    /// Presets shown as compact toggle buttons in the modern EQ window (excludes I'm Old / I'm Young)
    static var buttonPresets: [(preset: EQPreset, label: String)] {
        [(.flat, "FLAT"), (.rock, "ROCK"), (.pop, "POP"),
         (.electronic, "ELEC"), (.hipHop, "HIP"), (.jazz, "JAZZ"), (.classical, "CLSC")]
    }

    // MARK: - Genre-Based Auto EQ Presets

    static var rock: EQPreset {
        preset(stableID: rockID, name: "Rock", preamp: 0, classicBands: [4, 3, 1, -1, 0, 2, 3, 4, 3, 3])
    }

    static var pop: EQPreset {
        preset(stableID: popID, name: "Pop", preamp: 0, classicBands: [2, 3, 2, 0, 1, 2, 2, 1, 1, 1])
    }

    static var electronic: EQPreset {
        preset(stableID: electronicID, name: "Electronic", preamp: -1, classicBands: [5, 4, 2, 0, -1, 0, 2, 3, 3, 2])
    }

    static var hipHop: EQPreset {
        preset(stableID: hipHopID, name: "Hip-Hop", preamp: -1, classicBands: [5, 4, 2, 0, 1, 2, 1, 1, 1, 1])
    }

    static var jazz: EQPreset {
        preset(stableID: jazzID, name: "Jazz", preamp: 0, classicBands: [3, 2, 1, 0, 0, 1, 2, 3, 2, 2])
    }

    static var classical: EQPreset {
        preset(stableID: classicalID, name: "Classical", preamp: 0, classicBands: [2, 1, 0, 0, 0, 0, 1, 1, 1, 0])
    }
    
    /// Map a genre string to an appropriate EQ preset using fuzzy matching
    /// - Parameter genre: The genre string from track metadata
    /// - Returns: A matching EQPreset, or nil if no match found
    static func forGenre(_ genre: String?) -> EQPreset? {
        guard let genre = genre?.lowercased() else { return nil }
        
        // Rock variants
        let rockKeywords = ["rock", "metal", "punk", "grunge", "alternative", "hard rock", "indie rock", "post-rock", "progressive rock", "classic rock"]
        for keyword in rockKeywords {
            if genre.contains(keyword) { return .rock }
        }
        
        // Electronic variants
        let electronicKeywords = ["electronic", "techno", "house", "trance", "edm", "dubstep", "ambient", "electro", "drum and bass", "dnb", "synthwave", "industrial"]
        for keyword in electronicKeywords {
            if genre.contains(keyword) { return .electronic }
        }
        
        // Hip-Hop variants
        let hipHopKeywords = ["hip-hop", "hip hop", "hiphop", "rap", "r&b", "rnb", "soul", "funk", "trap", "grime"]
        for keyword in hipHopKeywords {
            if genre.contains(keyword) { return .hipHop }
        }
        
        // Jazz variants
        let jazzKeywords = ["jazz", "swing", "bebop", "fusion", "smooth jazz", "bossa nova", "blues"]
        for keyword in jazzKeywords {
            if genre.contains(keyword) { return .jazz }
        }
        
        // Classical variants
        let classicalKeywords = ["classical", "orchestra", "symphony", "opera", "baroque", "chamber", "romantic"]
        for keyword in classicalKeywords {
            if genre.contains(keyword) { return .classical }
        }
        
        // Pop variants (check last as it's a common fallback)
        let popKeywords = ["pop", "dance-pop", "synth-pop", "k-pop", "indie pop", "electropop", "disco"]
        for keyword in popKeywords {
            if genre.contains(keyword) { return .pop }
        }
        
        // No match found
        return nil
    }
}

// MARK: - classic skin EEQ File Support

extension EQPreset {
    /// Load preset from classic skin .eqf file
    static func fromEQF(url: URL) throws -> [EQPreset] {
        let data = try Data(contentsOf: url)
        var presets: [EQPreset] = []
        
        // EQF format: header + preset entries
        // Each preset: name (257 bytes) + preamp (1 byte) + bands (10 bytes)
        
        guard data.count >= 31 else {
            throw NSError(domain: "EQPreset", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid EQF file"])
        }
        
        // Check header "classic skin EQ library file v1.1"
        let headerLength = 31
        var offset = headerLength
        
        while offset + 268 <= data.count {
            // Read name (null-terminated, max 257 bytes)
            var nameBytes: [UInt8] = []
            for i in 0..<257 {
                let byte = data[offset + i]
                if byte == 0 { break }
                nameBytes.append(byte)
            }
            let name = String(bytes: nameBytes, encoding: .ascii) ?? "Preset"
            offset += 257
            
            // Read preamp
            let preampByte = data[offset]
            let preamp = Float(preampByte) / 64.0 * 24.0 - 12.0  // Convert 0-63 to -12..+12
            offset += 1
            
            // Read bands
            var bands: [Float] = []
            for i in 0..<10 {
                let bandByte = data[offset + i]
                let gain = Float(bandByte) / 64.0 * 24.0 - 12.0
                bands.append(gain)
            }
            offset += 10
            
            let mappedBands = activeLayout.gainValues(remapping: bands, from: presetSourceLayout)
            presets.append(EQPreset(name: name, preamp: preamp, bands: mappedBands))
        }
        
        return presets
    }
}
