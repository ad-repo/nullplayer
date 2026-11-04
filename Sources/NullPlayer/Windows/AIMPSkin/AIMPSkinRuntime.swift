import AppKit

/// One loaded skin, running: its scripts' state, what the player shows, and the scripts and timers
/// that move between them. The window controller owns one per skin and every view showing one of
/// the skin's forms (the deck, its speakers, its playlist) draws from it and changes it, so there is
/// one state rather than a copy per window kept in step.
@MainActor
final class AIMPSkinRuntime {
    let skin: AIMPSkin

    /// The player as the engine last reported it (`update(player:)`).
    private(set) var player: AIMPSkinPlayerSnapshot
    private var playlistMatches: AIMPSkinHostState.PlaylistMatches?

    /// What a script reads outside a frame (a click's handler, a key's counter, the load scripts):
    /// the player, with no window's feedback.
    var host: AIMPSkinHostState { host(feedback: .init()) }

    /// The skin's state and the player as bindings read them, outside a frame.
    var flow: AIMPSkinDataflow { AIMPSkinDataflow(skin: skin, host: host, state: state) }

    /// What `view`'s frame reads at `clock`: the player, with the skin's meters and the window's
    /// pointer, gauges and last frame's measurements.
    func host(drawnBy view: AIMPSkinMainView, clock: Double) -> AIMPSkinHostState {
        host(feedback: AIMPSkinFrameFeedback(clock: clock, levelL: levels.left, levelR: levels.right, spectrum: spectrum,
                                             pointer: view.pointer, hoverRects: view.hoverRects,
                                             playlistRowsShown: view.playlistRowsShown,
                                             gaugeLevels: gaugesBy[ObjectIdentifier(view)]?.levels ?? [:]))
    }

    private func host(feedback: AIMPSkinFrameFeedback) -> AIMPSkinHostState {
        AIMPSkinHostState(player: player, feedback: feedback, playlistMatches: playlistMatches)
    }

    /// The skin's own state (tab pages, counters, script variables).
    var state = AIMPSkinState() {
        didSet {
            guard state != oldValue else { return }
            if state.lists.playlistSearch != oldValue.lists.playlistSearch { matchPlaylist() }
            onStateChange?()
            // Timers, animators and lamps move every frame; only the rest can change what shows,
            // so only then does the next frame measure it again.
            if state.layoutMoved(from: oldValue) { views.forEach { $0.invalidateContent() } }
            // A change a tick makes is drawn by that tick; any other runs one on the next turn.
            if !ticking { scheduleTick() }
        }
    }

    /// The latest output levels and spectrum, drawn on the next animation frame.
    var levels = (left: 0.0, right: 0.0)
    var spectrum: [Double] = []

    /// What the skin asks of the player: from a key, a control, a timer or a script.
    var onAction: ((AIMPSkinCommand) -> Void)?
    /// The state moved (the controller shows and hides the skin's windows by it).
    var onStateChange: (() -> Void)?
    /// The clock started (true) or stopped: the skin's meters are measured only while it runs.
    var onClockChange: ((Bool) -> Void)?

    /// `player`: the player now (a new skin's scripts load against it).
    init(skin: AIMPSkin, player: AIMPSkinPlayerSnapshot) {
        self.skin = skin
        self.player = player
        matchPlaylist()
    }

    /// What the player shows now. A changed playlist (a new build of it) chooses no row; a new
    /// track scrolls the skin's own playlist to it, a couple of rows down, among the rows its quick
    /// search leaves.
    func update(player new: AIMPSkinPlayerSnapshot) {
        let old = player
        guard new != old else { return }
        player = new
        let playlistMoved = new.playlist != old.playlist
        if playlistMoved { matchPlaylist() }
        var state = self.state
        if playlistMoved { state.lists.playlistSelected = nil }
        if new.playlistIndex != old.playlistIndex, new.playlistIndex >= 0,
           let row = host.playlistIndices(matching: state.lists.playlistSearch).firstIndex(of: new.playlistIndex) {
            state.lists.playlistTop = max(0, row - 2)
        }
        self.state = state
        scheduleTick()
        updateClock()
    }

    /// The quick search's matches, worked out once per playlist and search: the window asks every
    /// frame. The stale ones go first, as `host` answers from them.
    private func matchPlaylist() {
        playlistMatches = nil
        playlistMatches = .init(search: state.lists.playlistSearch, indices: host.playlistIndices(matching: state.lists.playlistSearch))
    }

    /// The views drawing this skin's forms; the deck's (`formName` nil) gives the clock its pointer.
    private var views: [AIMPSkinMainView] { attached.compactMap(\.view) }
    private var attached: [WeakView] = []
    private struct WeakView { weak var view: AIMPSkinMainView? }

    func attach(_ view: AIMPSkinMainView) {
        attached.removeAll { $0.view == nil || $0.view === view }
        attached.append(WeakView(view: view))
        updateClock()
    }

    func detach(_ view: AIMPSkinMainView) {
        attached.removeAll { $0.view == nil || $0.view === view }
        autoHiddenBy[ObjectIdentifier(view)] = nil
        gaugesBy[ObjectIdentifier(view)] = nil
        updateClock()
    }

    /// What `AutoHide` hid in each view's form as last drawn. The skin's bindings read the items
    /// hidden in the windows on screen (`AIMPSkinState.Script.autoHidden`): a docked form's own window,
    /// closed, measures nothing.
    private var autoHiddenBy: [ObjectIdentifier: Set<String>] = [:]

    func noteAutoHidden(_ hidden: Set<String>, by view: AIMPSkinMainView) {
        autoHiddenBy[ObjectIdentifier(view)] = hidden
        let onScreen = Set(views.filter(\.isOnScreen).map(ObjectIdentifier.init))
        let union = autoHiddenBy.filter { onScreen.contains($0.key) }.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        if union != state.script.autoHidden { state.script.autoHidden = union }
    }

    /// Each view's gauges, eased frame by frame toward what it last drew.
    private var gaugesBy: [ObjectIdentifier: AIMPSkinGauges] = [:]

    /// `view` drew `gauges` at `clock`: its levels move toward them.
    func easeGauges(_ gauges: [AIMPSkinControl.ID: AIMPSkinGauges.Gauge], drawnBy view: AIMPSkinMainView, clock: Double) {
        gaugesBy[ObjectIdentifier(view), default: AIMPSkinGauges()].ease(gauges, playing: player.playState == .playing, clock: clock)
    }

    /// The skin's load scripts, once, with the actions they ask for.
    func start() {
        let scripts = engine()
        scripts.loaded()
        adopt(scripts)
    }

    /// Stops the clock; the skin is going.
    func stop() {
        tickScheduled = false
        guard let clock else { return }
        clock.invalidate()
        self.clock = nil
        onClockChange?(false)
    }

    // MARK: - The clock

    /// The one clock every window of the skin runs on: 30 frames a second while playing and on
    /// screen; nothing otherwise, where a change runs a single tick instead.
    private var clock: Timer?
    /// Set while a tick advances the scripts: the state they settle is drawn by that tick.
    private var ticking = false
    private var tickScheduled = false

    /// Starts or stops the clock as playing and being seen say: a skin sent to the tray, minimized,
    /// or covered by other windows draws nothing, runs no scripts and measures no levels.
    func updateClock() {
        let wanted = player.playState == .playing && views.contains {
            guard let window = $0.window else { return false }
            return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        }
        guard wanted != (clock != nil) else { return }
        clock?.invalidate()
        clock = nil
        if wanted {
            // In the common modes, so it keeps running while a button is held: AppKit tracks a held
            // mouse in its event-tracking mode, where a default-mode timer waits, and the skin's own
            // timers run here (Sony TC-RX80's REW/FF seek every 100 ms while held).
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            clock = timer
        } else {
            levels = (0, 0)
            scheduleTick()
        }
        onClockChange?(wanted)
    }

    /// One tick on the next turn, however many changes ask for it before then; while the clock runs,
    /// its next tick draws them.
    func scheduleTick() {
        guard clock == nil, !tickScheduled else { return }
        tickScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.tickScheduled else { return }
                self.tick()
            }
        }
    }

    /// One frame of the skin: due timers fire, visualization handlers run, then scripts whose input
    /// moved, over what the deck shows at `clock`; then every window draws once. The actions the
    /// scripts ask for go out last, so what they change is drawn by the next tick, never inside this one.
    func tick(at clock: Double? = nil) {
        tickScheduled = false
        let views = self.views
        let deck = views.first { $0.formName == nil }
        let now = clock ?? deck?.scheduler.probeClock ?? CACurrentMediaTime()
        let drawn = deck.map { host(drawnBy: $0, clock: now) } ?? host(feedback: .init(clock: now))
        ticking = true
        let scripts = engine(host: drawn)
        scripts.frame()
        state = scripts.state
        ticking = false
        // A window off screen (a docked form's own) draws only to measure its content.
        for view in views where view.isOnScreen || view.contentDirty { view.render(clock: now) }
        send(scripts.actions)
    }

    /// Sends what the scripts ask of the player.
    private func send(_ actions: [AIMPSkinCommand]) {
        actions.forEach { onAction?($0) }
    }

    /// The scripts of one tick or event, over the skin's state as it stands.
    private func engine(host: AIMPSkinHostState? = nil) -> AIMPSkinScript.Engine {
        AIMPSkinScript.Engine(skin: skin, host: host ?? self.host, state: state, budget: budget())
    }

    /// What `scripts` left: the skin's state, and what they asked of the player, sent.
    private func adopt(_ scripts: AIMPSkinScript.Engine) {
        state = scripts.state
        send(scripts.actions)
    }

    /// One tick's or one event's script budget. The first that runs out is logged: the scripts it
    /// stopped run again when their input next moves, rather than stalling the window now.
    private func budget() -> AIMPSkinScript.Budget {
        if let eventBudget { return eventBudget }
        if let last = lastBudget, last.isSpent, !reportedSpentBudget {
            reportedSpentBudget = true
            NSLog("AIMPSkin: '%@' scripts ran out of their per-frame budget", skin.name)
        }
        let budget = AIMPSkinScript.Budget()
        lastBudget = budget
        return budget
    }
    private var lastBudget: AIMPSkinScript.Budget?
    private var eventBudget: AIMPSkinScript.Budget?

    /// Runs `body` as one event: every script it runs shares one budget (a pointer move over several
    /// controls' handlers).
    func asOneEvent(_ body: () -> Void) {
        guard eventBudget == nil else { return body() }
        eventBudget = budget()
        defer { eventBudget = nil }
        body()
    }
    private var reportedSpentBudget = false

    // MARK: - Changing the state

    /// Moves a skin counter to `position` and runs what its scripts ask for.
    func setCounter(_ name: String, to position: Int) {
        let scripts = engine()
        scripts.setCounter(name, to: position)
        adopt(scripts)
    }

    /// Runs a skin event handler with `sender` as `Sender`, and the actions it asks for; false when
    /// it did nothing.
    @discardableResult
    func runHandler(_ handler: String, sender: String, arguments: [String: Double] = [:]) -> Bool {
        let scripts = engine()
        scripts.handle(handler, sender: sender, arguments: arguments)
        guard scripts.state != state || !scripts.actions.isEmpty else { return false }
        adopt(scripts)
        return true
    }

    /// Moves a skin counter as `step` says from its position, wrapped by its `Module`: a click on a
    /// counter key, or `notches` of the wheel.
    func stepCounter(_ name: String, by step: AIMPSkinStep, notches: Int = 1) {
        let flow = self.flow
        let current = flow.value(name, "Position")
        let next = step.next(from: current, notches: notches) ?? current
        setCounter(name, to: flow.wrapped(Int(next), counter: name))
    }

    /// Turns a tabbed group to the page `step` gives from the current one, wrapped to its tab count.
    func turnPage(_ group: String, by step: AIMPSkinStep) {
        let flow = self.flow
        let count = flow.skin.index.groups[group]?.count ?? 0
        guard count > 0 else { return }
        let current = Double(flow.activePage(group))
        let next = step.next(from: current) ?? current
        state.script.activePages[group] = ((Int(next) % count) + count) % count
    }

    /// Shows a hidden item, or hides a shown one.
    func toggle(_ item: String) {
        state.script.visible[item] = flow.value(item, "Visibility") == 0
    }
}

/// One window's gauges, eased toward their values at the skin's reaction speeds, per thirtieth of a
/// second gone by; while not playing they show their values as they are.
struct AIMPSkinGauges {
    /// A gauge's value in a frame and how fast it may rise and fall toward it, in its units per
    /// thirtieth of a second (`AIMPSkinFrame.gauges`).
    typealias Gauge = (value: Double, up: Double, down: Double)

    private(set) var levels: [AIMPSkinControl.ID: Double] = [:]
    /// The clock they were last eased at.
    private var clock: Double?

    mutating func ease(_ gauges: [AIMPSkinControl.ID: Gauge], playing: Bool, clock: Double) {
        defer { self.clock = clock }
        guard playing, !gauges.isEmpty else { return levels = [:] }
        let steps = min(10, max(0, (clock - (self.clock ?? clock)) * 30))
        var eased: [AIMPSkinControl.ID: Double] = [:]
        for (id, gauge) in gauges {
            let level = levels[id] ?? gauge.value
            eased[id] = level + min(gauge.up * steps, max(-gauge.down * steps, gauge.value - level))
        }
        levels = eased
    }
}
