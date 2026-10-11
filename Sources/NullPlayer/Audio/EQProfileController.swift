import AVFoundation

/// Drives the profile nodes — the local graph's (replaced with the rest of a failed graph, as
/// `PitchTuningController` replaces its pitch node) and one per AudioStreaming player — from the
/// current track's resolved profile, or the Studio's edit while it is open.
///
/// ponytail: every node follows `currentTrack`, so a Sweet Fades overlap hears the incoming track's
/// profile on both sides; per-player curves if anyone notices.
final class EQProfileController {
    private lazy var nodes = AudioUnitFanout<EQProfileAudioUnit>(makeNode: EQProfileAudioUnit.makeNode) {
        [unowned self] unit in unit.setCurve(appliedCurve)
    }
    private var track: Track?
    /// Kept current by track changes and store changes, whether or not the Studio is open.
    private var resolved: EQCurve?
    private var observer: NSObjectProtocol?
    private let resolver: EQProfileResolver

    /// Non-nil while the Studio is open: its edit, or flat under BYPASS. Wins over the track's
    /// profile and over the global toggle — the Studio is the editor.
    var audition: EQCurve? {
        didSet { if audition != oldValue { nodes.configureAll() } }
    }

    init(resolver: EQProfileResolver = .shared) {
        self.resolver = resolver
        observer = NotificationCenter.default.addObserver(forName: .eqProfilesDidChange, object: resolver.store,
                                                          queue: .main) { [weak self] _ in self?.resolve() }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    var localNode: AVAudioUnitEffect { nodes.localNode }

    /// The curve the nodes run now.
    var appliedCurve: EQCurve? { audition ?? resolved }

    func trackDidChange(_ track: Track?) {
        self.track = track
        resolve()
    }

    func replaceLocalNode() { nodes.replaceLocalNode() }

    func makeStreamingNode() -> AVAudioUnitEffect { nodes.makeStreamingNode() }

    private func resolve() {
        let match = track.flatMap { resolver.store.isEnabled ? resolver.resolve($0) : nil }
        resolved = match?.profile?.curve
        // Logged only when a profile applies; a track with none, Off, or profiles disabled is silent.
        if let track, let match, let profile = match.profile {
            NSLog("[eqprofile] %@ → %@ (%@)%@", track.title, profile.name, match.level.rawValue,
                  audition != nil ? " — Studio open, auditioning its edit" : "")
        }
        nodes.configureAll()
    }
}
