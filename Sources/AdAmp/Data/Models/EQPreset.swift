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
    
    static let flat = EQPreset(name: "Flat")
    
    static let rock = EQPreset(
        name: "Rock",
        preamp: 0,
        bands: [4, 3, 2, 0, -1, -1, 0, 2, 3, 4]
    )
    
    static let pop = EQPreset(
        name: "Pop",
        preamp: 0,
        bands: [-1, 2, 4, 5, 4, 2, 0, -1, -1, -1]
    )
    
    static let jazz = EQPreset(
        name: "Jazz",
        preamp: 0,
        bands: [3, 2, 1, 2, -2, -2, 0, 1, 2, 3]
    )
    
    static let classical = EQPreset(
        name: "Classical",
        preamp: 0,
        bands: [4, 3, 2, 1, 0, 0, 0, 1, 2, 3]
    )
    
    static let electronic = EQPreset(
        name: "Electronic",
        preamp: 0,
        bands: [5, 4, 2, 0, -2, -1, 0, 2, 4, 5]
    )
    
    static let hiphop = EQPreset(
        name: "Hip-Hop",
        preamp: 0,
        bands: [5, 4, 2, 0, -1, -1, 1, 0, 2, 3]
    )
    
    static let vocal = EQPreset(
        name: "Vocal",
        preamp: 0,
        bands: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]
    )
    
    static let bass = EQPreset(
        name: "Bass Boost",
        preamp: 0,
        bands: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0]
    )
    
    static let treble = EQPreset(
        name: "Treble Boost",
        preamp: 0,
        bands: [0, 0, 0, 0, 0, 0, 2, 4, 5, 6]
    )
    
    static let allPresets: [EQPreset] = [
        .flat, .rock, .pop, .jazz, .classical,
        .electronic, .hiphop, .vocal, .bass, .treble
    ]
}

// MARK: - Winamp EEQ File Support

extension EQPreset {
    /// Load preset from Winamp .eqf file
    static func fromEQF(url: URL) throws -> [EQPreset] {
        let data = try Data(contentsOf: url)
        var presets: [EQPreset] = []
        
        // EQF format: header + preset entries
        // Each preset: name (257 bytes) + preamp (1 byte) + bands (10 bytes)
        
        guard data.count >= 31 else {
            throw NSError(domain: "EQPreset", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid EQF file"])
        }
        
        // Check header "Winamp EQ library file v1.1"
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
