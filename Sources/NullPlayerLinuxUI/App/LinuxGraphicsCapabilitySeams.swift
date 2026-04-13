#if os(Linux)
import Foundation
import NullPlayerPlayback

struct LinuxGraphicsCapabilities: Sendable, Equatable {
    let supportsSpectrumWindow: Bool
    let supportsWaveformWindow: Bool
    let supportsProjectMWindow: Bool
    let supportsVisClassicMode: Bool
}

protocol LinuxGraphicsCapabilityProviding: AnyObject {
    func currentCapabilities() -> LinuxGraphicsCapabilities
}

final class LinuxGraphicsCapabilityService: LinuxGraphicsCapabilityProviding {
    private let backendCapabilities: AudioBackendCapabilities

    init(backendCapabilities: AudioBackendCapabilities) {
        self.backendCapabilities = backendCapabilities
    }

    func currentCapabilities() -> LinuxGraphicsCapabilities {
        LinuxGraphicsCapabilities(
            supportsSpectrumWindow: true,
            supportsWaveformWindow: backendCapabilities.supportsWaveformFrames,
            supportsProjectMWindow: false,
            supportsVisClassicMode: false
        )
    }
}
#endif
