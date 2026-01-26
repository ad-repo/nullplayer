import Foundation

/// Represents an equalizer preset
public struct EQPreset: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var preamp: Float
    public var bands: [Float]  // 10 bands, -12 to +12 dB
    
    public init(name: String, preamp: Float = 0, bands: [Float] = Array(repeating: 0, count: 10)) {
        self.id = UUID()
        self.name = name
        self.preamp = preamp
        self.bands = bands
    }
    
    // MARK: - Built-in Presets
    // Bands: 60Hz, 170Hz, 310Hz, 600Hz, 1kHz, 3kHz, 6kHz, 12kHz, 14kHz, 16kHz
    
    public static let flat = EQPreset(name: "Flat")
    
    public static let imOld = EQPreset(
        name: "i'm old",
        preamp: 0,
        bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 6]  // +6dB at 16kHz
    )
    
    public static let imYoung = EQPreset(
        name: "i'm young",
        preamp: 0,
        bands: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0]  // +6dB at 60Hz
    )
    
    public static let allPresets: [EQPreset] = [
        .imOld, .imYoung, .flat
    ]
}
