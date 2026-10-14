import AppKit

/// The Studio's session: the profile being edited, LINK, BYPASS, the mode and faceplate shown, and
/// the analyser feed. It runs from the user's open to the user's close, whichever host shows it —
/// the standalone window, or a `.wal` skin's frame — and each host draws it with a view of its own,
/// so a switch of skin or family moves the Studio without losing the edit. Edits are heard live (the
/// profile controller's `audition`) and discarded unless saved.
final class EqualizerStudioSession {
    static let shared = EqualizerStudioSession()
    /// Posted on every change a view draws: an edit, a setting, an analyser frame.
    static let didChangeNotification = Notification.Name("EqualizerStudioSessionDidChange")

    /// Which stage's controls are shown. Not part of the profile: both stages are always heard.
    enum Mode: String, CaseIterable { case graphic, parametric }

    /// A band fader (`band` 0…30) or the preamp (`band` nil) of one channel.
    struct Fader: Equatable {
        let channel: Int
        let band: Int?
    }

    /// One channel's curve heard — both stages, no preamp — in dB, as drawn.
    struct ChannelResponse {
        /// On `gridFrequencies`.
        let grid: [Double]
        /// At the band centres.
        let centres: [Double]
        /// The parametric strip alone at the band centres. A band fader shows its graphic share on
        /// top of this, so the faders sit on the curve; dragging moves only the share.
        let stripAtCentres: [Float]
        let peak: Double

        static let flat = ChannelResponse(.flat, channel: 0)

        init(_ curve: EQCurve, channel: Int) {
            let rate = EqualizerStudioSession.displayRate
            let sections = EQProfileDesign.sections(for: curve, channel: channel, sampleRate: rate)
            let strip = curve[channel].parametric.sections(sampleRate: rate)
            grid = EqualizerStudioSession.gridFrequencies.map { EQProfileDesign.responseDB(sections, frequency: $0, sampleRate: rate) }
            centres = EQProfileDesign.frequencies.map { EQProfileDesign.responseDB(sections, frequency: $0, sampleRate: rate) }
            stripAtCentres = EQProfileDesign.frequencies.map { Float(EQProfileDesign.responseDB(strip, frequency: $0, sampleRate: rate)) }
            peak = grid.max() ?? 0
        }
    }

    private static let linkedKey = "equalizerStudioLinked"
    private static let modeKey = "equalizerStudioMode"
    /// Response and peaks are shown at this rate; the stream's own rate differs only above 20 kHz.
    private static let displayRate = 48000.0
    static let gridFrequencies: [Double] = (0...180).map { 20 * pow(1000, Double($0) / 180) }
    /// What an unsaved profile is called until it is saved under a name of its own.
    private static let newName = "New EQ Profile"

    private let store = EQProfileStore.shared
    private var controller: EQProfileController { WindowManager.shared.audioEngine.eqProfileController }
    private let rta = StudioRTA()
    private var isOpen = false

    private(set) var edit = EQCurve.flat
    private(set) var profileID: UUID?
    private(set) var name = EqualizerStudioSession.newName
    /// Per channel: heard flat, for this session. A monitoring switch, not an edit, but LINK lit
    /// sets both channels to the clicked one's new state, as it does FLAT.
    private(set) var bypass = [false, false]
    private(set) var linked = true
    private(set) var mode = Mode.graphic
    private(set) var faceplateKind = StudioFaceplate.Kind.console
    private(set) var responses = [ChannelResponse.flat, .flat]
    private(set) var levels = [[Float]](repeating: [Float](repeating: StudioRTA.floorDB, count: EQProfileDesign.bandCount), count: 2)
    private(set) var peaks = [[Float]](repeating: [Float](repeating: StudioRTA.floorDB, count: EQProfileDesign.bandCount), count: 2)

    private init() {}

    // MARK: - Open / close

    /// A host shown or hidden. Showing opens the session; hiding ends it only if the Studio is in
    /// neither host a turn later, since moving between them closes one and opens the other in one
    /// turn, whoever does it. A skin teardown reports neither, so the session outlives it.
    func hostVisibilityDidChange(_ visible: Bool) {
        guard !visible else { open(); return }
        DispatchQueue.main.async { [self] in
            guard isOpen, !WindowManager.shared.isEqualizerStudioVisible else { return }
            close()
        }
    }

    private func open() {
        guard !isOpen else { return }
        isOpen = true
        linked = UserDefaults.standard.object(forKey: Self.linkedKey) as? Bool ?? true
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(Mode.init) ?? .graphic
        faceplateKind = StudioFaceplate.storedKind
        bypass = [false, false]
        if let track = WindowManager.shared.audioEngine.currentTrack, let profile = EQProfileResolver.shared.resolve(track.eqProfileScopes)?.profile {
            load(profile)
        } else {
            loadNew()
        }
        rta.onUpdate = { [weak self] levels, peaks in
            self?.levels = levels
            self?.peaks = peaks
            self?.notifyChange()
        }
        rta.start()
    }

    private func close() {
        isOpen = false
        rta.stop()
        rta.onUpdate = nil
        bypass = [false, false]
        controller.audition = nil
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - Profiles

    func load(_ profile: EQProfile) {
        profileID = profile.id
        name = profile.name
        edit = profile.curve
        editDidChange()
    }

    func loadNew() {
        profileID = nil
        name = Self.newName
        edit = .flat
        editDidChange()
    }

    private var savedCurve: EQCurve { profileID.flatMap { store.profile($0)?.curve } ?? .flat }
    var isDirty: Bool { edit != savedCurve }

    func save() {
        guard let profileID else { return }
        store.update(profileID, curve: edit)
        notifyChange()
    }

    func saveAs(_ newName: String) {
        guard let profile = store.add(name: newName, curve: edit) else { return }
        load(profile)
    }

    func rename(_ newName: String) {
        guard let profileID else { return }
        name = newName
        store.update(profileID, name: newName)
        notifyChange()
    }

    func delete() {
        guard let profileID else { return }
        store.delete(profileID)
        loadNew()
    }

    func revert() {
        edit = savedCurve
        editDidChange()
    }

    private func editDidChange() {
        responses = (0..<2).map { ChannelResponse(edit, channel: $0) }
        pushAudition()
    }

    private func pushAudition() {
        var heard = edit
        for channel in 0..<2 where bypass[channel] { heard[channel] = .flat }
        controller.audition = heard
        notifyChange()
    }

    // MARK: - Settings

    func toggleLink() {
        linked.toggle()
        UserDefaults.standard.set(linked, forKey: Self.linkedKey)
        notifyChange()
    }

    func toggleMode() {
        mode = mode == .graphic ? .parametric : .graphic
        UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey)
        notifyChange()
    }

    func toggleFaceplate() {
        faceplateKind = faceplateKind == .console ? .boutique : .console
        UserDefaults.standard.set(faceplateKind.rawValue, forKey: StudioFaceplate.defaultsKey)
        notifyChange()
    }

    func toggleBypass(_ channel: Int) {
        let on = !bypass[channel]
        for channel in targets(channel) { bypass[channel] = on }
        pushAudition()
    }

    // MARK: - Editing

    /// The channel an edit is made on, then — LINK lit — the other.
    private func targets(_ channel: Int) -> [Int] { linked ? [channel, 1 - channel] : [channel] }

    private func value(_ fader: Fader) -> Float {
        fader.band.map { edit[fader.channel].bands[$0] } ?? edit[fader.channel].preamp
    }

    private func set(_ fader: Fader, _ value: Float) {
        let value = EQCurve.clamp(value)
        if let band = fader.band { edit[fader.channel].bands[band] = value } else { edit[fader.channel].preamp = value }
    }

    /// LINK lit moves the other channel's fader by the same amount, so channels that differ keep
    /// their difference.
    func move(_ fader: Fader, to newValue: Float) {
        let moved = EQCurve.clamp(newValue) - value(fader)
        guard moved != 0 else { return }
        for channel in targets(fader.channel) {
            let target = Fader(channel: channel, band: fader.band)
            set(target, value(target) + moved)
        }
        editDidChange()
    }

    func reset(_ fader: Fader) {
        for channel in targets(fader.channel) { set(Fader(channel: channel, band: fader.band), 0) }
        editDidChange()
    }

    /// LINK lit turns the other channel's dial by the same travel, as with faders.
    func turn(_ knob: EQParametric.Knob, channel: Int, by travel: Float) {
        let old = edit[channel].parametric[knob]
        edit[channel].parametric[knob] = knob.value(at: knob.position(of: old) + travel)
        let moved = knob.position(of: edit[channel].parametric[knob]) - knob.position(of: old)
        guard moved != 0 else { return }
        for channel in targets(channel).dropFirst() {
            let value = edit[channel].parametric[knob]
            edit[channel].parametric[knob] = knob.value(at: knob.position(of: value) + moved)
        }
        editDidChange()
    }

    func reset(_ knob: EQParametric.Knob, channel: Int) {
        for channel in targets(channel) { edit[channel].parametric[knob] = EQParametric.flat[knob] }
        editDidChange()
    }

    /// A switch is an edit, so LINK lit sets both channels to the clicked one's new state.
    func flip(_ toggle: EQParametric.Switch, channel: Int) {
        let on = !edit[channel].parametric[toggle]
        for channel in targets(channel) { edit[channel].parametric[toggle] = on }
        editDidChange()
    }

    /// FLAT is an edit, so LINK lit flattens both channels, as double-clicking a fader resets both.
    /// It flattens the whole curve — both stages — whichever controls are shown.
    func flatten(_ channel: Int) {
        for channel in targets(channel) { edit[channel] = .flat }
        editDidChange()
    }

    /// The preamp that puts a channel's response peak at 0 dB.
    private func headroomPreamp(_ channel: Int) -> Float {
        EQCurve.clamp(Float(-responses[channel].peak))
    }

    /// Whether a preamp is off its headroom setting, so HEADROOM would change something.
    var isOffHeadroom: Bool { (0..<2).contains { abs(edit[$0].preamp - headroomPreamp($0)) >= 0.05 } }

    func applyHeadroom() {
        for channel in 0..<2 { edit[channel].preamp = headroomPreamp(channel) }
        editDidChange()
    }
}
