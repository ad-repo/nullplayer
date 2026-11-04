import Foundation

extension AIMPSkinScript {
    /// One tick's or one event's script work: the skin, what the player shows, the skin's state as
    /// the scripts leave it, and what they asked of the player, in order. Every script the tick or
    /// event runs, nested ones included (a counter a script moves, a handler it executes), runs on
    /// this one engine and its budget: there is nothing to merge back.
    ///
    /// A run that stops (an unsupported call, the budget spent) leaves nothing behind: what it set
    /// and asked for is undone, and its caller goes on (`atomically`).
    ///
    /// On the main actor: the runtime's tick and the window's events run scripts there, between
    /// frames, and the frames drawn off main read only the state they leave (`Budget` bounds a tick).
    @MainActor
    final class Engine {
        let skin: AIMPSkin
        let host: AIMPSkinHostState
        /// Set by the scripts as they run (`AIMPSkinScript.Run` and its host bridge).
        var state: AIMPSkinState
        private(set) var actions: [AIMPSkinCommand] = []
        let budget: Budget
        /// Scripted counters whose scripts are running: one that sets itself only moves.
        private var runningCounters: Set<String> = []
        /// What the scripts wrote to AIMP's EQ bands, in dB, by the NullPlayer band each lands on:
        /// AIMP bands that share one are averaged (`AIMPSkinCommand.equalizerBand`).
        private var eqWrites: [Int: [Int: Double]] = [:]

        init(skin: AIMPSkin, host: AIMPSkinHostState, state: AIMPSkinState, budget: Budget = Budget()) {
            self.skin = skin
            self.host = host
            self.state = state
            self.budget = budget
        }

        /// The dataflow over the state as it stands, so a value a script set reads back as set.
        var flow: AIMPSkinDataflow { AIMPSkinDataflow(skin: skin, host: host, state: state) }

        /// A script by name: compiled as the skin loaded (`AIMPSkinScript.Library`).
        func program(_ name: String) -> Program? { skin.scripts.programs[name.lowercased()] }

        // MARK: - What a tick or an event runs

        /// Runs, once, as the skin is shown: each script named after a form, as AIMP runs it when it
        /// makes the form (GX-77 4K's `AIMPMainForm` hides its position preview and zeroes its
        /// counters), the main form's first; then the main form's `OnLoaded` handler (Nakamichi BX's
        /// switches its seek timers off; left running, they wound forward ten times a second).
        func loaded() {
            for form in ["AIMPMainForm"] + skin.companions.map(\.name) where program(form) != nil {
                handle(form, sender: form)
            }
            if let onLoaded = skin.schema?.descendants().first(where: { $0.tag == "form" && $0["name"] == "AIMPMainForm" })?
                .properties["OnLoaded"]?["value"] {
                handle(onLoaded, sender: "AIMPMainForm")
            }
        }

        /// One frame, as the window runs it: due timers fire, visualization handlers run and
        /// animators step, then the scripts whose input moved.
        func frame() {
            fireTimers()
            visualize()
            settle()
        }

        /// Fires every `LogicalOperatorTimer` whose `Interval` has passed since it last fired, on
        /// `host.feedback.clock`, while its `Accessibility` binding is on (or it has none): each `Action`
        /// link sets its source counter to the link's `Expression` of its position, running the
        /// counter's script (Pioneer CT-F1000's tape counter turns this way).
        func fireTimers() {
            for (name, timer) in skin.index.timers {
                // A timer's `Accessibility` binding pushes its value whenever it changes, taking the
                // timer back from a script that switched it off: Sony TC-RX80 switches its REW/FF
                // timers off when it loads, and its REW/FF keys' counter turns them on through the
                // binding alone.
                if let gate = timer.bindings["Accessibility"] {
                    let value = flow.value(of: gate)
                    if let last = state.script.timerGates[name], last != value { state.script.timerEnabled[name] = nil }
                    state.script.timerGates[name] = value
                }
                // Nakamichi BX switches its seek timers off when it loads and on while winding.
                if state.script.timerEnabled[name] == false { continue }
                // On Windows' 15.6 ms timer ticks, as the skin's author saw it.
                let interval = tickedInterval(state.script.timerIntervals[name] ?? timer.interval ?? 1_000)
                let last = state.animation.timerFired[name] ?? -.infinity
                guard host.feedback.clock - last >= interval else { continue }
                state.animation.timerFired[name] = host.feedback.clock
                // Every link reads the counters as the timer fired.
                let flow = self.flow
                if let gate = timer.bindings["Accessibility"], flow.value(of: gate) == 0 { continue }
                for link in timer.bindings.all("Action") {
                    guard let source = link.source else { continue }
                    // A timer on an action repeats it (Technics' REW/FF held down seek every 100 ms).
                    if let action = AIMPAction(source) {
                        actions.append(.action(action))
                        continue
                    }
                    setCounter(source, to: flow.wrapped(Int(flow.value(of: link)), counter: source))
                }
            }
        }

        /// Runs each `ScriptableVisualizationHandler` on the spectrum, as AIMP does every visual
        /// frame, then steps the animators that keep their own frame: a speaker's handler kicks a
        /// cone back to frame 0 on a beat, and the cone plays to where its own gate stops it. A
        /// handler only animates: what it asks of the player is dropped.
        func visualize() {
            if host.player.playState == .playing, !host.feedback.spectrum.isEmpty {
                let asked = (actions, eqWrites)
                defer { (actions, eqWrites) = asked }
                for (_, provider) in skin.index.visualizationHandlers {
                    guard let script = provider.script, let program = program(script) else { continue }
                    do {
                        try atomically { _ = try run(program) }
                    } catch {
                        if AIMPSkinTrace.items || AIMPSkinTrace.visualize { print("  VISUAL_FAIL \(script) \(error)") }
                    }
                }
            }
            stepAnimators()
        }

        /// Runs every script whose bound input changed, until nothing changes (a few passes at most).
        /// The first run of each, as a skin loads, only sets its state up: what it asks of the
        /// player is dropped (the GX-F90's EQ scripts would otherwise rewrite the EQ).
        func settle() {
            for _ in 0..<4 {
                // A pass reads every input as it began.
                let flow = self.flow
                let providers = skin.index.providers.sorted { $0.key < $1.key }
                var changed = false
                for (name, provider) in providers where provider.kind == .counter(scripted: true) {
                    guard let link = provider.bindings["Position"], let script = provider.script else { continue }
                    let inputs = flow.inputs(of: link)
                    let previous = state.animation.scriptInputs[name]
                    guard previous != inputs else { continue }
                    // Out of budget, the input stays unseen, so its script runs on a later tick.
                    guard !budget.isSpent else { break }
                    state.animation.scriptInputs[name] = inputs
                    changed = true
                    guard let program = program(script) else { continue }
                    let asked = (actions, eqWrites)
                    if (try? runCounter(name, program, at: flow.value(of: link))) == nil, budget.isSpent {
                        state.animation.scriptInputs[name] = previous
                    }
                    if previous == nil { (actions, eqWrites) = asked }
                }
                // Event handlers bound to a value run when it moves: `prvPlayerState`'s `OnTrackStarted`
                // and `OnTrackFinished` (a count the host keeps), or a provider (Mayak-232's
                // `SetSliderTrigger`, the volume and balance: its knobs follow them).
                for (name, provider) in providers where provider.kind == .eventHandler {
                    guard let link = provider.bindings["Handler"] else { continue }
                    let input = flow.inputs(of: link)
                    let previous = state.animation.scriptInputs[name]
                    guard previous != input else { continue }
                    guard !budget.isSpent else { break }
                    state.animation.scriptInputs[name] = input
                    changed = true
                    // As the skin loads, a value trigger sets it up from where things stand; of the events
                    // (`On…`, and a provider's `Action`: the user moved it), only a track start has
                    // happened, if something is playing (SL-1200 drops its arm and wipes the cover art in;
                    // Soot's volume ring waits for the volume to move).
                    if previous == nil, let event = link.pin, event.hasPrefix("On") || event == "Action",
                       event != "OnTrackStarted" || host.player.playState != .playing { continue }
                    let asked = (actions, eqWrites)
                    handle(name, sender: name)
                    if budget.isSpent { state.animation.scriptInputs[name] = previous }
                    if previous == nil { (actions, eqWrites) = asked }
                }
                if !changed { break }
            }
        }

        /// Sets counter `name` to `value`. A `ScriptableOperatorCounter` runs its script with `State`
        /// the new value (Pioneer's play key sets `RemoteControllScript` to 1, and the script
        /// plays), and `State` after the run is the counter's position. Out of budget, the counter
        /// stays where it was, so its script runs on the next move.
        func setCounter(_ name: String, to value: Int) {
            let before = state
            state.script.counters[name] = value
            guard let provider = skin.index.providers[name], provider.kind == .counter(scripted: true),
                  let script = provider.script, let program = program(script) else { return }
            if (try? runCounter(name, program, at: Double(value))) == nil, budget.isSpent { state = before }
        }

        /// Runs the event handler `handler` (a `ScriptableEventHandler` provider, or a script by
        /// name) for `sender`, with a mouse event's `arguments`.
        func handle(_ handler: String, sender: String, arguments: [String: Double] = [:]) {
            guard let program = program(skin.index.providers[handler]?.script ?? handler) else { return }
            try? atomically { _ = try run(program, sender: sender, arguments: arguments) }
        }

        // MARK: - Running

        /// Counter `name`'s script on `position`, guarded against the counter's own moves while it
        /// runs; its `State` after is the counter's position.
        private func runCounter(_ name: String, _ program: Program, at position: Double) throws {
            guard !runningCounters.contains(name) else { return }
            runningCounters.insert(name)
            defer { runningCounters.remove(name) }
            let after = try atomically { try run(program, statePosition: position) }
            state.script.counters[name] = Int(after)
        }

        /// `program` once: its block, then `Execute` with the event's parameters (`State` at
        /// `statePosition`, `Sender`, `Arguments`). Returns `State` after the run. A nested run (a
        /// handler a script executes) is one call deeper on the budget.
        @discardableResult
        func run(_ program: Program, sender: String = "", arguments: [String: Double] = [:],
                 statePosition: Double = 0) throws -> Double {
            try Run(engine: self, program: program, sender: sender, arguments: arguments).execute(statePosition: statePosition)
        }

        /// `body`, all or nothing: when it throws, what it set and asked for is undone.
        private func atomically<T>(_ body: () throws -> T) throws -> T {
            let saved = (state, actions, eqWrites)
            do {
                return try body()
            } catch {
                (state, actions, eqWrites) = saved
                throw error
            }
        }

        // MARK: - What the scripts ask of the player

        func ask(_ command: AIMPSkinCommand) { actions.append(command) }

        /// AIMP's preamp, in dB: the latest a script set is the one asked for.
        func setPreamp(dB: Double) {
            actions.removeAll { if case .preamp = $0 { true } else { false } }
            actions.append(.preamp(dB: dB))
        }

        /// AIMP's EQ band `aimp`, in dB, on NullPlayer band `band`: the band is asked for once, at
        /// the mean of the AIMP bands written to it.
        func setEqualizer(band: Int, aimp: Int, dB: Double) {
            eqWrites[band, default: [:]][aimp] = dB
            let values = eqWrites[band]?.values.map { $0 } ?? []
            actions.removeAll { if case .equalizerBand(band, _) = $0 { true } else { false } }
            actions.append(.equalizerBand(band, dB: values.reduce(0, +) / Double(values.count)))
        }

        // MARK: - Animators

        /// Animators that gate on their own frame, or that a script set, advance on their interval
        /// while their gate is open (a cone runs from 0 until `Value < 3` closes it).
        private func stepAnimators() {
            let flow = self.flow
            for animator in skin.index.animatorList {
                guard let name = animator.name else { continue }
                let bindings = animator.bindings
                guard state.animation.animatorFrames[name] != nil || bindings.links.contains(where: { $0.source == name }) else { continue }
                // One bound to a counter is on the counter's position, and its steps move the counter
                // (Technics SL-1200's tonearm: `Frames_Counter` drops it in, then a script sets it).
                let counter = bindings.all("AnimationFrameIndex").first { $0.expression == nil }
                    .flatMap(\.source).flatMap { skin.index.counterModule($0) != nil ? $0 : nil }
                let frame = counter.map { Int(flow.value($0, "Position")) } ?? state.animation.animatorFrames[name] ?? 0
                state.animation.animatorFrames[name] = frame
                // A gate on its own frame reads the frame it is on now.
                if let gate = bindings["Accessibility"] {
                    let open = gate.source == name ? gate.shaped(Double(frame)) : flow.value(of: gate)
                    if open == 0 { continue }
                }
                let frames = max(1, skin.image(animator.picture, links: state.script.resourceLinks)?.frameCount ?? 1)
                guard let asked = animator.animator?.interval,
                      host.feedback.clock - (state.animation.animatorStepped[name] ?? 0) >= tickedInterval(max(1, asked)) else { continue }
                state.animation.animatorStepped[name] = host.feedback.clock
                state.animation.animatorFrames[name] = (frame + 1) % frames
                if let counter { state.script.counters[counter] = (frame + 1) % frames }
            }
        }
    }
}
