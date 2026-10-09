#if os(visionOS)
import GestureCore
import os
import Spatial
import SwiftUI

private let pluckItemLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "PluckItemDriver")

/// One pluckable item's pinches, kept in a reference so telling them during
/// a drag doesn't redraw the item: `PluckPinches` told each word of its
/// press, its tap, its drag, its counts, and its container, with the time;
/// the counts it asks for, run on the main actor; what it tells the item to
/// do, done through the container's model and reported to the app; and each
/// pinch traced, from its touch to its end, with why each word did what it
/// did.
@MainActor
final class PluckItemDriver {
    /// What a word needs to know of the item where it came from: its id and
    /// title, the tuning, its container, its trace, the app's closure, and
    /// how its points measure in the space.
    struct Setting {
        let id: AnyHashable
        let title: String
        let tuning: PluckTuning
        let model: PluckContainerModel?
        let recorder: TraceRecorder?
        let perform: (PluckEvent) -> Void
        let metrics: PhysicalMetricsConverter
    }

    private var pinches = PluckPinches()
    /// The setting the last word came with, which the counts and the
    /// container's words use.
    private var setting: Setting?
    /// The geometry of the item, for where its points are in the space.
    private var proxy: GeometryProxy3D?
    private var holdCount: Task<Void, Never>?
    private var armCount: Task<Void, Never>?
    /// The trace of the pinch under way.
    private var trace: InteractionTrace?
    /// Whether the app was told the item lifted, and not yet that it
    /// settled.
    private var reportedLift = false
    /// Where the drag last was, in the item's points, which a pull's
    /// position comes from.
    private var lastLocation: Point3D?
    /// The last drag word the trace noted: its reason's name and its time.
    private var lastDragNote: (name: String, at: ContinuousClock.Instant)?

    /// The item's id, as the last word gave it.
    var itemID: AnyHashable? { setting?.id }

    /// Whether its pinch has its item kept up past its press, neither of its
    /// gestures having it.
    var isKeptUpPastItsPress: Bool { pinches.isKeptUpPastItsPress }

    /// Keeps the item's geometry, as its reader lays out.
    func remember(_ proxy: GeometryProxy3D) {
        self.proxy = proxy
    }

    // MARK: The item's words

    /// The item's button was pressed, `isPressed`, or let go.
    func pressChanged(_ isPressed: Bool, _ setting: Setting) {
        adopt(setting)
        if isPressed {
            apply(pinches.pressBegan(at: .now), word: "press down")
        } else {
            apply(pinches.pressEnded(at: .now), word: "press up")
        }
    }

    /// The item's button fired: a tap, or the release of a pinch that lifted
    /// it, which is no tap.
    func tapped(_ setting: Setting) {
        adopt(setting)
        handle(pinches.tapped(at: .now), synthesized: false)
    }

    /// The pull's drag moved.
    func dragChanged(_ value: DragGesture.Value, _ setting: Setting) {
        adopt(setting)
        let moved = value.translation3D
        let translation = SIMD3(moved.x, moved.y, moved.z)
        lastLocation = value.location3D
        let pointsPerMeter = Double(setting.metrics.convert(CGFloat(1), from: .meters))
        apply(pinches.dragMoved(translation, pointsPerMeter: pointsPerMeter, at: .now), word: "drag", translation: translation)
    }

    /// The pull's drag ended, let go.
    func dragEnded(_ value: DragGesture.Value, _ setting: Setting) {
        adopt(setting)
        lastLocation = value.location3D
        apply(pinches.dragEnded(at: .now), word: "drag end")
        // An item with no button hears its tap as the drag's end of a pinch
        // nothing else told.
        if setting.tuning.holdsFromTheDrag, pinches.press != nil, !pinches.isDragging, !pinches.isHolding {
            handle(pinches.tapped(at: .now), synthesized: true)
        }
    }

    /// The pull's drag stopped without ending, as when the container's
    /// scroll view takes the pinch: a cancel, should the drag still have it.
    func dragStopped(_ setting: Setting) {
        guard pinches.isDragging else { return }
        adopt(setting)
        apply(pinches.dragCancelled(at: .now), word: "drag cancelled")
    }

    /// The item left its container, mid-pinch or not.
    func itemWent() {
        holdCount?.cancel()
        armCount?.cancel()
        apply(pinches.itemWent(at: .now), word: "item went")
    }

    // MARK: The container's words

    /// The container's scroll view's phase changed: the trace notes it, and
    /// a scroll beginning is told to the pinch; should the container have
    /// settled the item, the app hears so.
    func containerPhaseChanged(to phase: PluckScrollPhase, scrollBegan: Bool, settledIt: Bool) {
        trace?.event("scroll phase", phase.rawValue)
        if scrollBegan {
            apply(pinches.containerScrolled(at: .now), word: "container scrolled")
        }
        if settledIt {
            containerSettledIt(because: "the container's scroll")
        }
    }

    /// The container settled the item, `because` of what: the app hears so,
    /// once.
    func containerSettledIt(because reason: String) {
        trace?.event("settled by the container", reason)
        reportSettled()
    }

    /// A pinch began on another item: this one, kept up past its press, is
    /// over.
    func pinchBeganElsewhere() {
        apply(pinches.pinchBeganElsewhere(at: .now), word: "pinch elsewhere")
    }

    // MARK: The counts

    private func run(_ countdown: PluckPinches.Countdown) {
        switch countdown {
        case .startHold(let duration):
            holdCount?.cancel()
            holdCount = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.holdCountIsUp()
            }
        case .stopHold:
            holdCount?.cancel()
            holdCount = nil
        case .startArming(let duration):
            armCount?.cancel()
            armCount = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.armCountIsUp()
            }
        case .stopArming:
            armCount?.cancel()
            armCount = nil
        }
    }

    private func holdCountIsUp() {
        holdCount = nil
        let touched = pinches.touchedAt ?? .now
        let scrolled = setting?.model?.scrolled(since: touched) ?? false
        apply(
            pinches.holdFired(asTheContainerScrolled: scrolled, at: .now),
            word: "hold",
            extra: scrolled ? "the container scrolled since the touch" : "the container still since the touch"
        )
    }

    private func armCountIsUp() {
        armCount = nil
        apply(pinches.armPull(at: .now), word: "arming")
    }

    // MARK: Doing what the pinch says

    /// Takes the setting a word came with; new pinches take its tuning.
    private func adopt(_ setting: Setting) {
        self.setting = setting
        pinches.tuning = setting.tuning
    }

    /// Does what one word told: begins and ends traces, runs the counts,
    /// and carries out the actions.
    private func apply(_ told: PluckPinches.Told, word: String, translation: SIMD3<Double>? = nil, extra: String? = nil) {
        if told.beganAPinch {
            // The pinch it ended, its end unseen, first: its item settles.
            if let ended = told.ended {
                for action in told.actions { perform(action, why: told.why) }
                finish(ended)
            }
            beginTrace(with: word)
            setting?.model?.pinchBegan(by: self)
            note(word, told, translation: translation, extra: extra)
            for countdown in told.countdowns { run(countdown) }
            if told.ended == nil {
                for action in told.actions { perform(action, why: told.why) }
            }
            return
        }
        note(word, told, translation: translation, extra: extra)
        for countdown in told.countdowns { run(countdown) }
        for action in told.actions { perform(action, why: told.why) }
        if let ended = told.ended { finish(ended) }
    }

    /// Handles the item's tap: no tap for a release, the app's tap otherwise.
    private func handle(_ tap: PluckPinches.Tap, synthesized: Bool) {
        let since = tap.sinceTouch.map { "+" + pluckItemSeconds($0) + " s after the touch" } ?? "no pinch"
        let what = tap.isRelease ? "the release of a lift, no tap" : (synthesized ? "a tap, as the drag ended" : "a tap")
        trace?.event("tap", "\(what), \(since)")
        for countdown in tap.countdowns { run(countdown) }
        for action in tap.actions { perform(action, why: .releasedByItsTap) }
        if !tap.isRelease { setting?.perform(.tapped) }
        if let ended = tap.ended { finish(ended) }
    }

    private func perform(_ action: PluckPress.Action, why: PluckReason) {
        guard let setting else { return }
        switch action {
        case .lift:
            if let change = setting.model?.lift(setting.id, by: self) {
                trace?.event("lift", change.scrollHoldChanged ? "the scroll held off" : "the scroll goes on")
            } else {
                trace?.event("lift", "no container")
            }
            if !reportedLift {
                reportedLift = true
                setting.perform(.lifted)
            }
        case .pullArmed:
            trace?.event("armed", "a pull may come out")
        case .beginPull:
            let position = place(setting)
            trace?.event("pull began", pluckItemPosition(position))
            pluckItemLogger.info("The pull of \(setting.title) began at \(pluckItemPosition(position), privacy: .public)")
            setting.perform(.pullBegan(position))
        case .movePull:
            setting.perform(.pullMoved(place(setting)))
        case .endPull:
            let position = place(setting)
            trace?.event("pull ended", pluckItemPosition(position))
            pluckItemLogger.info("The pull of \(setting.title) landed at \(pluckItemPosition(position), privacy: .public)")
            setting.perform(.pullEnded(position))
        case .cancelPull:
            trace?.event("pull cancelled")
            setting.perform(.pullCancelled)
        case .settle:
            let change = setting.model?.settle(setting.id)
            trace?.event("settle", why.description + (change?.scrollHoldChanged == true ? "; the scroll on again" : ""))
            reportSettled()
        case .stayDown(let stayDown):
            trace?.event("stays down", stayDown == .movedFirst ? "moved first: a scroll" : "the container scrolled: a scroll")
        }
    }

    /// Tells the app the item settled, once for each lift it was told of.
    private func reportSettled() {
        guard reportedLift else { return }
        reportedLift = false
        setting?.perform(.settled)
    }

    /// Where what the item pulls out stands in the space: the drag's last
    /// location, pushed toward the viewer, through the item's transform into
    /// the immersive space, in meters, y up; nil while it has none, as with
    /// the space closed.
    private func place(_ setting: Setting) -> SIMD3<Float>? {
        guard let location = lastLocation, let transform = proxy?.transform(in: .immersiveSpace) else { return nil }
        let pushed = Point3D(x: location.x, y: location.y, z: location.z + setting.tuning.pushTowardViewer)
        let meters = setting.metrics.convert(pushed.applying(transform), to: .meters)
        return SIMD3(Float(meters.x), Float(-meters.y), Float(meters.z))
    }

    // MARK: The trace

    private func beginTrace(with word: String) {
        guard let setting else { return }
        lastDragNote = nil
        trace = setting.recorder?.begin("Pluck", title: "Pinch on \(setting.title)")
        trace?.event("tuning", pluckItemTuningLine(setting.tuning))
    }

    /// Notes a word in the trace, with why it did what it did. A drag's
    /// words are noted as they begin a pinch, do something, or give another
    /// kind of reason, and otherwise a tenth of a second apart, so the
    /// timeline stays readable.
    private func note(_ word: String, _ told: PluckPinches.Told, translation: SIMD3<Double>?, extra: String?) {
        guard let trace else { return }
        var detail = told.why.description
        if let translation {
            let now = ContinuousClock.now
            let name = told.why.name
            let isNews = told.beganAPinch || !told.actions.isEmpty || lastDragNote?.name != name
            if !isNews, let last = lastDragNote, now - last.at < .milliseconds(100) { return }
            lastDragNote = (name, now)
            detail = "\(pluckItemVector(translation)): \(detail)"
        }
        if let extra { detail += "; \(extra)" }
        trace.event(word, detail)
    }

    /// Finishes the pinch's trace with its account, and tells the container
    /// it's over.
    private func finish(_ account: PluckPinches.Account) {
        let outcome = account.ending == .letGo
            ? account.outcome.rawValue
            : "\(account.outcome.rawValue), \(account.ending == .unseen ? "its end unseen" : account.ending.rawValue)"
        let summary = pluckItemAccountLine(account)
        if let trace {
            trace.event("account", summary)
            trace.finish(outcome)
        } else if let title = setting?.title {
            pluckItemLogger.info("The pinch on \(title) was \(outcome, privacy: .public): \(summary, privacy: .public)")
        }
        trace = nil
        lastDragNote = nil
        setting?.model?.pinchEnded(by: self)
    }
}

// MARK: Words for the trace

/// A duration in seconds, to two decimals: "0.50".
private func pluckItemSeconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.2f", Double(seconds) + Double(attoseconds) / 1e18)
}

/// A drag's translation in the item's points: "(3.0 across, -12.0 down, 30.0 toward you) pt".
private func pluckItemVector(_ vector: SIMD3<Double>) -> String {
    String(format: "(%.1f across, %.1f down, %.1f toward you) pt", vector.x, vector.y, vector.z)
}

/// A position in the space, in meters, or that there's none.
private func pluckItemPosition(_ position: SIMD3<Float>?) -> String {
    guard let position else { return "nowhere: no transform into the space" }
    return String(format: "(%.2f, %.2f, %.2f) m in the space", position.x, position.y, position.z)
}

/// The tuning a pinch began with, on one line.
private func pluckItemTuningLine(_ tuning: PluckTuning) -> String {
    let rule = tuning.pullsAnyDirection
        ? "any way"
        : (tuning.pullDepthPerDrift > 0 ? String(format: "1 deep per %.2f across", 1 / tuning.pullDepthPerDrift) : "toward you, any drift")
    return String(
        format: "hold %.2f s within %.0f pt, drag from %.0f pt, arms %.2f s after, pull %.1f cm %@; scroll %@; press end %@; hold from the %@",
        tuning.holdDuration, tuning.holdStillness, tuning.dragStartDistance, tuning.pullArmDelay,
        tuning.pullDistance * 100, rule,
        tuning.stopsScrollUnderLiftedItem ? "stops under a lift" : "goes on",
        tuning.pressEndSettlesLiftedItem ? "settles a lift" : "keeps a lift up",
        tuning.holdsFromTheDrag ? "drag" : "press"
    )
}

/// A pinch's account on one line: when each stage came, from the touch,
/// and how far it moved.
private func pluckItemAccountLine(_ account: PluckPinches.Account) -> String {
    var parts: [String] = []
    func add(_ name: String, _ duration: Duration?) {
        if let duration { parts.append("\(name) +\(pluckItemSeconds(duration))") }
    }
    add("held", account.heldAfter)
    add("armed", account.armedAfter)
    add("pulled", account.pulledAfter)
    add("press up", account.pressEndedAfter)
    add("settled", account.settledAfter)
    add("drag spoke", account.dragReportedAfter)
    if let stayed = account.stayedDown { parts.append("stayed down: \(stayed.rawValue)") }
    parts.append(String(format: "farthest %.1f pt, %.1f before the hold", account.farthest, account.farthestBeforeHold))
    return parts.joined(separator: ", ")
}
#endif
