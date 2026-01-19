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
        name: "i'm old",
        preamp: 0,
        bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 6]  // +6dB at 16kHz
    )
    
    static let imYoung = EQPreset(
        name: "i'm young",
        preamp: 0,
        bands: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0]  // +6dB at 60Hz
    )
    
    static let allPresets: [EQPreset] = [
        .imOld, .imYoung, .flat
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
