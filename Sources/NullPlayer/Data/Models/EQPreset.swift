import Foundation

/// Represents an equalizer preset
struct EQPreset: Identifiable, Codable {
    let id: UUID
    var name: String
    var preamp: Float
    var bands: [Float]  // 10 bands, -12 to +12 dB
    
    init(name: String, preamp: Float = 0, bands: [Float] = Array(repeating: 0, count: 10)) {
        self.id = UUID()
        self.name = name
        self.preamp = preamp
        self.bands = bands
    }
    
    // MARK: - Built-in Presets
    // Bands: 60Hz, 170Hz, 310Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz
    
    static let flat = EQPreset(name: "Flat")
    
    static let imOld = EQPreset(
        name: "I'm Old",
        preamp: 0,
        bands: [-2, -1, 0, 0, 1, 2, 4, 6, 7, 8]  // Progressive treble boost for high-frequency hearing loss
    )
    
    static let imYoung = EQPreset(
        name: "I'm Young",
        preamp: -2,
        bands: [8, 6, 4, 2, 0, -1, 0, 1, 1, 0]  // Heavy bass boost, slight sub-bass rolloff protection
    )
    
    static let allPresets: [EQPreset] = [
        .flat, .imOld, .imYoung, .rock, .pop, .electronic, .hipHop, .jazz, .classical
    ]
    
    // MARK: - Genre-Based Auto EQ Presets
    // Bands: 60Hz, 170Hz, 310Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz
    
    static let rock = EQPreset(
        name: "Rock",
        preamp: 0,
        bands: [4, 3, 1, -1, 0, 2, 3, 4, 3, 3]
    )
    
    static let pop = EQPreset(
        name: "Pop",
        preamp: 0,
        bands: [2, 3, 2, 0, 1, 2, 2, 1, 1, 1]
    )
    
    static let electronic = EQPreset(
        name: "Electronic",
        preamp: -1,
        bands: [5, 4, 2, 0, -1, 0, 2, 3, 3, 2]
    )
    
    static let hipHop = EQPreset(
        name: "Hip-Hop",
        preamp: -1,
        bands: [5, 4, 2, 0, 1, 2, 1, 1, 1, 1]
    )
    
    static let jazz = EQPreset(
        name: "Jazz",
        preamp: 0,
        bands: [3, 2, 1, 0, 0, 1, 2, 3, 2, 2]
    )
    
    static let classical = EQPreset(
        name: "Classical",
        preamp: 0,
        bands: [2, 1, 0, 0, 0, 0, 1, 1, 1, 0]
    )
    
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
            
            presets.append(EQPreset(name: name, preamp: preamp, bands: bands))
        }
        
        return presets
    }
}
