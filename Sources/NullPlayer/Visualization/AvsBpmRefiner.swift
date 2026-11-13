import Foundation

/// The Winamp AVS frontend's "advanced" beat detection: a port of `refineBeat` and its helpers
/// from upstream `vis_avs/bpm.cpp` (BSD-3, Nullsoft), minus the dialog's sliders. It learns
/// the tempo from the detector's beats, then fires beats on the predicted tempo, filling in
/// the ones the detector misses and dropping the ones off the beat. Once the tempo has held
/// with high confidence it sticks until `reset()` (a new song), as upstream's does; predicted
/// beats fire whatever the confidence, which only gates their entry into the history.
///
/// Upstream's defaults are fixed: sticky on, "only use when sticky" off, reset on a new song.
/// Ticks are milliseconds, as `GetTickCount`; arithmetic keeps upstream's integer and float
/// steps so the learned tempo matches.
struct AvsBpmRefiner {
    private static let historySize = 8
    private static let maxBpm = 170
    private static let minBpm = 60
    private static let topConfidenceAdopt = 8
    private static let minSticky = 8
    private static let stickyThreshold = 70
    private static let stickyThresholdLow = 85

    private struct Beat {
        var tick = 0
        var guessed = false
    }

    private var started = false
    private var sticked = false
    private var bpm = 0
    private var confidence = 0
    private var lastTick = 0
    private var history = [Beat](repeating: Beat(), count: historySize)
    private var smoother = [Int](repeating: 0, count: 8)
    private var halfDiscriminated = [Bool](repeating: false, count: historySize)
    private var discriminatedPos = 0
    private var smootherPos = 0
    private var lastBpm = 0
    private var insertionCount = 0
    private var predictionLastTick = 0
    private var average = 0
    private var halfCount = 0
    private var doubleCount = 0
    private var predictionBpm = 0
    private var bestConfidence = 0
    private var forceNewBeat = false
    private var topConfidenceCount = 0
    private var stickyConfidenceCount = 0
    private var resyncBpm = false

    /// The learned tempo, 0 while learning.
    var tempo: Int { predictionBpm }

    /// Forgets the learned tempo (`ResetAdapt`), as upstream does on a new song.
    mutating func reset(now: Int) {
        let kept = (lastBpm, resyncBpm, forceNewBeat)  // the three ResetAdapt leaves alone
        self = AvsBpmRefiner()
        (lastBpm, resyncBpm, forceNewBeat) = kept
        started = true
        lastTick = now
    }

    /// One rendered frame at `now` ms: `isBeat` is the standard detector's verdict; the result
    /// is the beat AVS should see.
    mutating func refine(isBeat: Bool, now: Int) -> Bool {
        if !started {
            started = true
            lastTick = now
        }
        var accepted = false
        var resyncIn = false
        var resyncOut = false

        let predicted = bpm != 0 && now > predictionLastTick + 60000 / bpm
        if isBeat {
            accepted = historyStep(tick: now, guessed: false)
        }
        calculateBpm(now: now)

        if (accepted || predicted) && !sticked
            && (predictionBpm == 0 || predictionBpm > Self.maxBpm || predictionBpm < Self.minBpm) {
            if confidence >= bestConfidence {
                forceNewBeat = true
            }
            if confidence >= 50 {
                topConfidenceCount += 1
                if topConfidenceCount == Self.topConfidenceAdopt {
                    forceNewBeat = true
                    topConfidenceCount = 0
                }
            }
            if forceNewBeat {
                forceNewBeat = false
                bestConfidence = confidence
                predictionBpm = bpm
            }
        }
        if !sticked {
            predictionBpm = bpm
        }
        bpm = predictionBpm

        if predictionBpm != 0 && accepted && !predicted {
            var adjusted = predictionBpm
            let period = Double(60000 / predictionBpm)
            if Double(now) > Double(predictionLastTick) + period * 0.7 {
                resyncIn = true
                adjusted = Int(Float(predictionBpm) * 1.01)
            }
            if Double(now) < Double(predictionLastTick) + period * 0.3 {
                resyncOut = true
                adjusted = Int(Float(predictionBpm) * 0.98)
            }
            if !sticked && resyncBpm && (resyncIn || resyncOut) {
                addToSmoother(adjusted)
                predictionBpm = smoothedBpm()
            }
        }

        if resyncIn {
            predictionLastTick = now
            resyncBpm = true
            return true
        }
        if predicted {
            predictionLastTick = now
            if confidence > 25 {
                _ = historyStep(tick: now, guessed: true)
            }
            resyncBpm = false
            return true
        }
        if resyncOut {
            predictionLastTick = now
            resyncBpm = true
            return false
        }
        return predictionBpm != 0 ? false : isBeat
    }

    // MARK: - bpm.cpp helpers

    private var readyToLearn: Bool { history.allSatisfy { $0.tick != 0 } }
    private var readyToGuess: Bool { insertionCount == Self.historySize * 2 }

    /// `TCHistStep`: accepts a beat into the history unless it falls between learned beats.
    private mutating func historyStep(tick: Int, guessed: Bool) -> Bool {
        let learning = readyToLearn
        let length = tick - lastTick
        if Double(length) < Double(average / 2) - Double(average) * 0.2 {
            if learning, abs(average - (tick - history[1].tick)) < abs(average - (history[0].tick - history[1].tick)) {
                history[0] = Beat(tick: tick, guessed: guessed)
                return true
            }
            return false
        }
        if learning {
            for divisor in 2..<8 {  // half, a third … of the learned period
                let part = average / divisor
                if Float(abs(part - length)) < Float(part) * 0.2 {
                    halfDiscriminated[discriminatedPos] = true
                    discriminatedPos = (discriminatedPos + 1) % 8
                    return false
                }
            }
        }
        halfDiscriminated[discriminatedPos] = false
        discriminatedPos = (discriminatedPos + 1) % 8
        lastTick = tick
        insert(Beat(tick: tick, guessed: guessed))
        return true
    }

    /// `InsertHistStep` at position 0.
    private mutating func insert(_ beat: Beat) {
        if insertionCount < Self.historySize * 2 {
            insertionCount += 1
        }
        history.removeLast()
        history.insert(beat, at: 0)
    }

    private mutating func addToSmoother(_ value: Int) {
        smoother[smootherPos] = value
        smootherPos = (smootherPos + 1) % smoother.count
    }

    private func smoothedBpm() -> Int {
        let set = smoother.filter { $0 > 0 }
        return set.isEmpty ? 0 : set.reduce(0, +) / set.count
    }

    private mutating func doubleBeat() {
        if sticked && bpm > Self.minBpm { return }
        let intervals = (0..<(Self.historySize - 1)).map { history[$0].tick - history[$0 + 1].tick }
        for i in 1..<Self.historySize {
            history[i].tick = history[i - 1].tick - intervals[i - 1] / 2
        }
        average /= 2
        bpm *= 2
        doubleCount = 0
        smoother = smoother.map { _ in 0 }
        halfDiscriminated = halfDiscriminated.map { _ in false }
    }

    private mutating func halfBeat() {
        if sticked && bpm < Self.minBpm { return }
        let intervals = (0..<(Self.historySize - 1)).map { history[$0].tick - history[$0 + 1].tick }
        for i in 1..<Self.historySize {
            history[i].tick = history[i - 1].tick - intervals[i - 1] * 2
        }
        average *= 2
        bpm /= 2
        halfCount = 0
        smoother = smoother.map { _ in 0 }
        halfDiscriminated = halfDiscriminated.map { _ in false }
    }

    /// `CalcBPM`: the tempo and its confidence from the beat history.
    private mutating func calculateBpm(now: Int) {
        guard readyToLearn else { return }
        let n = Self.historySize
        let intervals = (0..<(n - 1)).map { history[$0].tick - history[$0 + 1].tick }
        average = intervals.reduce(0, +) / (n - 1)

        let real = history.filter { !$0.guessed }.count
        let realConfidence = min(Float(real) / Float(n) * 2, 1)
        let maxInterval = intervals.max() ?? 0
        let sumSquares = intervals.reduce(0.0) { $0 + Double($1 * $1) }
        let drift = Float(sqrt(sumSquares / Double(n - 1) - Double(average * average)))
        let driftConfidence = 1 - drift / Float(maxInterval)
        let raw = Double(realConfidence * driftConfidence) * 100.0 - 50
        confidence = raw.isFinite ? max(0, Int(raw) * 2) : 0

        // Second layer: average only the intervals within the typical drift.
        var total = 0, used = 0, run = 0
        for interval in intervals {
            run += interval
            if Float(abs(average - run)) < drift {
                total += run
                used += 1
                run = 0
            } else if Float(run) > Float(average) {
                run = 0
            }
        }
        if used > 0 {
            average = total / used
        }

        guard readyToGuess else { return }
        if average != 0 {
            bpm = 60000 / average
        }
        if bpm != lastBpm {
            addToSmoother(bpm)
            lastBpm = bpm
            if predictionBpm != 0
                && confidence >= (predictionBpm < 90 ? Self.stickyThresholdLow : Self.stickyThreshold) {
                stickyConfidenceCount += 1
                if stickyConfidenceCount >= Self.minSticky {
                    sticked = true
                }
            } else {
                stickyConfidenceCount = 0
            }
        }
        bpm = smoothedBpm()

        if halfDiscriminated.filter({ $0 }).count >= n / 2, bpm * 2 < Self.maxBpm {
            doubleBeat()
            halfDiscriminated = halfDiscriminated.map { _ in false }
        }
        if bpm > 500 || bpm < 0 {
            reset(now: now)
        }
        if bpm < Self.minBpm {
            doubleCount += 1
            if doubleCount > 4 { doubleBeat() }
        } else {
            doubleCount = 0
        }
        if bpm > Self.maxBpm {
            halfCount += 1
            if halfCount > 4 { halfBeat() }
        } else {
            halfCount = 0
        }
    }
}
