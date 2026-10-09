#if os(visionOS)
import GestureCore
import os
import Spatial
import SwiftUI

private let pluckItemLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "PluckItemDriver")

/// Where a lifted item is drawn from where it stands lifted, as its pinch's
/// tether says (`PluckPinches.follow`), observed apart from everything else
/// about the item, so the hand's every step draws the item's follow and
/// nothing more.
@MainActor @Observable
final class PluckItemFollow {
    /// In the item's points: x across, y down, z toward the viewer.
    var offset: SIMD3<Double> = .zero
}

/// One pluckable item's pinches, kept in a reference so telling them during
/// a drag doesn't redraw the item: `PluckPinches` told each word of its
/// press, its tap, its drag, its counts, and its container, with the time;
/// the counts it asks for, run on the main actor; what it tells the item to
/// do, done through the container's model and reported to the app; where
/// the lifted item is drawn as the hand tugs it (`follow`); from the spawn
/// on, the hand's moves handed to the carry of what spawned
/// (`PluckHandoff`); and each pinch traced, from its touch to its end, with
/// why each word did what it did.
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
        /// The axes its container scrolls along.
        let scrollAxes: PluckScrollAxes
        let perform: (PluckEvent) -> Void
        let metrics: PhysicalMetricsConverter

        /// The window's own points to a meter, as its physical metrics give
        /// them: 1,360 on visionOS.
        @MainActor var ownPointsPerMeter: Double {
            Double(metrics.convert(CGFloat(1), from: .meters))
        }
    }

    /// Where the lifted item is drawn as the hand tugs it, which its drawing
    /// alone reads.
    let follow = PluckItemFollow()

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
    /// The item's points to a meter of the hand's move, measured once for
    /// the pinch under way, with the window's scale then; nil until it is.
    private var measured: (pointsPerMeter: Double, windowScale: Double?)?
    /// The carry of what the pinch under way spawned, from the spawn until
    /// it's let go.
    private var handoff: PluckHandoff<String>?
    /// Whether the trace has said the pinch under way's item is held,
    /// following the hand.
    private var notedHeld = false
    /// The farthest the pinch under way stretched toward breaking its item
    /// free, and how far it needed, as last seen, for the settle's line.
    private var heldFarthest: (reach: Double, needs: Double)?
    /// Whether the pinch under way broke its item free.
    private var brokeFree = false

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
        apply(pinches.dragMoved(translation, pointsPerMeter: pointsPerMeter(setting), at: .now), word: "drag", translation: translation)
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

    // MARK: The item's points to a meter of the hand

    /// The item's points to a meter of the hand's move, measured once a
    /// pinch: the window's own, as its physical metrics give them, divided
    /// by the scale the window is drawn at in the space, as visionOS draws a
    /// window larger the farther away it stands, since the drag reports the
    /// hand's move in the item's own points, before that scale. So the
    /// break-free distance is the hand's 2.5 cm wherever the window stands.
    /// The window's own, with no space to measure the scale in.
    private func pointsPerMeter(_ setting: Setting) -> Double {
        if let measured { return measured.pointsPerMeter }
        let own = setting.ownPointsPerMeter
        let scale = windowScale()
        let pointsPerMeter = scale.map { own / $0 } ?? own
        measured = (pointsPerMeter, scale)
        return pointsPerMeter
    }

    /// How much larger than its own size the item's window is drawn in the
    /// immersive space: its transform's scale across; nil with the space
    /// closed, or a scale outside a quarter to four times, which no window
    /// is drawn at, so a reading gone wrong never shrinks the break-free
    /// distance to nothing, as the 6 mm one spawned the item at once.
    private func windowScale() -> Double? {
        guard let transform = proxy?.transform(in: .immersiveSpace) else { return nil }
        let scale = Double(transform.scale.width)
        return scale.isFinite && (0.25...4).contains(scale) ? scale : nil
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

    /// The container's scroll offset changed to `offset`: the pinch under
    /// way, before its hold, gives its hold up should the content have moved
    /// past its stillness since the touch. Only that is traced, the offset
    /// changing at every frame of a scroll.
    func containerOffsetChanged(to offset: SIMD2<Double>) {
        let told = pinches.scrollOffset(offset, at: .now)
        guard !told.actions.isEmpty else { return }
        apply(told, word: "scroll offset")
    }

    /// Reads where the container's scroll offset stands for the pinch under
    /// way: at its touch, where it's measured from; at its hold, in case a
    /// change went unheard.
    private func readScrollOffset() {
        guard let offset = setting?.model?.scrollOffset else { return }
        containerOffsetChanged(to: offset)
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

    /// The hold's count is up: the item lifts unless the container scrolled
    /// since the touch, as its scroll view or its offset says, and the trace
    /// says plainly why it lifted or didn't.
    private func holdCountIsUp() {
        holdCount = nil
        readScrollOffset()
        let touched = pinches.touchedAt ?? .now
        let scrolled = setting?.model?.scrolled(since: touched) ?? false
        let note = holdNote(scrollViewScrolled: scrolled)
        apply(pinches.holdFired(asTheContainerScrolled: scrolled, at: .now), word: "hold", extra: note)
    }

    /// Why the hold lifted its item or didn't, in plain words: the scroll
    /// view, the scroll offset's move since the touch, and how far the pinch
    /// moved along the scroll and any way, each against what the hold
    /// allows.
    private func holdNote(scrollViewScrolled: Bool) -> String {
        guard let press = pinches.press else { return "no pinch" }
        let tuning = press.tuning
        var parts: [String] = []
        parts.append(scrollViewScrolled ? "its scroll view scrolled since the touch" : "its scroll view still since the touch")
        if let moved = pinches.scrollOffsetMovedBeforeHold {
            parts.append(tuning.holdWatchesScrollOffset
                ? String(format: "its scroll offset moved %.1f pt, %.1f allowed", moved, tuning.scrollOffsetStillness)
                : String(format: "its scroll offset moved %.1f pt, unwatched", moved))
        } else {
            parts.append("its scroll offset unread")
        }
        if press.dragTranslation == nil {
            parts.append(String(format: "the drag silent, the pinch within its %.0f pt start of the touch", tuning.dragStartDistance))
        } else {
            parts.append(String(
                format: "the pinch moved %.1f pt along the scroll, %.0f allowed, and %.1f any way, %.0f allowed",
                pinches.farthestAlongScrollBeforeHold, tuning.holdStillnessAlongScroll, pinches.farthestBeforeHold, tuning.holdStillness
            ))
        }
        return parts.joined(separator: "; ")
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
        pinches.scrollAxes = setting.scrollAxes
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
            // Where the content stands at the touch, which its moves are
            // measured from.
            readScrollOffset()
            showFollow()
            return
        }
        note(word, told, translation: translation, extra: extra)
        for countdown in told.countdowns { run(countdown) }
        for action in told.actions { perform(action, why: told.why) }
        noteHeld()
        if let ended = told.ended { finish(ended) }
        showFollow()
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
        showFollow()
    }

    /// Draws the lifted item where its tether says, should that have
    /// changed: following the hand while it's held, at its place otherwise.
    private func showFollow() {
        let offset = pinches.follow
        if follow.offset != offset { follow.offset = offset }
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
            trace?.event("armed", armedNote(setting))
        case .breakFree:
            let spawn = place(setting, pushedTowardViewer: true)
            if let spawn, let hand = place(setting, pushedTowardViewer: false) {
                handoff = PluckHandoff(carrying: setting.title, spawnedAt: spawn, handAt: hand)
            }
            brokeFree = true
            trace?.event("broke free", brokeFreeNote(spawn))
            pluckItemLogger.info("\(setting.title) broke free, spawning at \(pluckItemPosition(spawn), privacy: .public); the carry takes the pinch from here")
            setting.perform(.spawned(at: spawn))
        case .carrySpawned:
            carryOn(setting)
        case .releaseSpawned:
            carryOn(setting)
            var middle: SIMD3<Float>?
            var detail = pluckItemPosition(nil)
            if var carried = handoff {
                _ = carried.end()
                middle = carried.middle
                detail = String(format: "%@, %.2f m from where it spawned", pluckItemPosition(carried.middle), simd_distance(carried.middle, carried.spawnedAt))
            }
            handoff = nil
            trace?.event("released", detail)
            pluckItemLogger.info("The carry of what \(setting.title) spawned was let go at \(pluckItemPosition(middle), privacy: .public)")
            setting.perform(.released(at: middle))
        case .cancelSpawn:
            handoff = nil
            trace?.event("spawn cancelled", "what spawned is taken away")
            setting.perform(.spawnCancelled)
        case .settle:
            let change = setting.model?.settle(setting.id)
            if case .givenBackToTheScroll = why {
                pluckItemLogger.info("The pinch on \(setting.title) was given back to the scroll: \(why.description, privacy: .public)")
            }
            var detail = why.description
            if let held = heldFarthest, !brokeFree {
                detail += String(format: "; held to %.1f pt of %.1f, not broken free", held.reach, held.needs)
            }
            if change?.scrollHoldChanged == true { detail += "; the scroll on again" }
            trace?.event("settle", detail)
            reportSettled()
        case .stayDown:
            let reason = switch why {
            case .containerScrolled: "its scroll view scrolled since the touch, a scroll"
            default: why.description
            }
            trace?.event("stays down", "the hold given up: " + reason)
        }
    }

    /// What breaking free needs, and from where, for the trace: the
    /// break-free distance in the item's points and its rule, from where the
    /// pinch stood as its item lifted, or as its pull armed, or the touch.
    private func armedNote(_ setting: Setting) -> String {
        guard let press = pinches.press else { return "it may break free" }
        let tuning = press.tuning
        let needs = String(format: "breaks free at %.1f pt %@", tuning.breakFreeThreshold(pointsPerMeter: pointsPerMeter(setting)), pluckItemPullWay(tuning))
        let point: SIMD3<Double>?
        let moment: String
        switch tuning.pullOrigin {
        case .touch: return needs + " from the touch"
        case .lift: (point, moment) = (press.liftPoint, "lifted")
        case .arming: (point, moment) = (press.armingPoint, "armed")
        }
        guard let point else {
            return needs + String(format: " from the touch: the drag silent as it %@, the pinch within its %.0f pt start of it", moment, tuning.dragStartDistance)
        }
        return needs + " from \(pluckItemVector(point)), where it \(moment)"
    }

    /// The moment the item broke free, for the trace: how long after the
    /// lift, how far the hand had gone of what it needed, and where it
    /// spawns.
    private func brokeFreeNote(_ spawn: SIMD3<Float>?) -> String {
        var parts: [String] = []
        if let lifted = pinches.liftedAt {
            parts.append("+\(pluckItemSeconds(.now - lifted)) s after the lift")
        }
        if let press = pinches.press, let needs = press.breakFreeAt {
            parts.append(String(format: "%.1f pt of %.1f", press.farthestStretch, needs))
        }
        parts.append("spawns at " + pluckItemPosition(spawn))
        return parts.joined(separator: ", ")
    }

    /// Notes, once a pinch, that its lifted item is held, following the
    /// hand, and keeps how far it has stretched, for the settle's line.
    private func noteHeld() {
        guard let stretch = pinches.stretch else { return }
        let farthest = max(heldFarthest?.reach ?? 0, stretch.reach)
        heldFarthest = (farthest, stretch.needs)
        guard !notedHeld else { return }
        notedHeld = true
        let drawn = (stretch.follow * stretch.follow).sum().squareRoot()
        trace?.event("held", String(format: "%.1f pt of %.1f to break free, the item drawn %.1f pt along", stretch.reach, stretch.needs, drawn))
    }

    /// Hands the drag's last place to the carry of what spawned, and tells
    /// the app where the carry puts its middle.
    private func carryOn(_ setting: Setting) {
        guard var handoff, let hand = place(setting, pushedTowardViewer: false) else { return }
        for case .carry(_, let middle, let handMoved) in handoff.handMoved(to: hand) {
            setting.perform(.carried(middle: middle, handMoved: handMoved))
        }
        self.handoff = handoff
    }

    /// Tells the app the item settled, once for each lift it was told of.
    private func reportSettled() {
        guard reportedLift else { return }
        reportedLift = false
        setting?.perform(.settled)
    }

    /// The drag's last location in the space, through the item's transform
    /// into the immersive space, in meters, y up: pushed toward the viewer,
    /// where what the item pulls out spawns; or not, where the hand is,
    /// whose moves the carry of what spawned follows. Nil while it has none,
    /// as with the space closed.
    private func place(_ setting: Setting, pushedTowardViewer: Bool) -> SIMD3<Float>? {
        guard let location = lastLocation, let transform = proxy?.transform(in: .immersiveSpace) else { return nil }
        let push = pushedTowardViewer ? setting.tuning.pushTowardViewer : 0
        let pushed = Point3D(x: location.x, y: location.y, z: location.z + push)
        let meters = setting.metrics.convert(pushed.applying(transform), to: .meters)
        return SIMD3(Float(meters.x), Float(-meters.y), Float(meters.z))
    }

    // MARK: The trace

    private func beginTrace(with word: String) {
        guard let setting else { return }
        lastDragNote = nil
        notedHeld = false
        heldFarthest = nil
        brokeFree = false
        let pointsPerMeter = pointsPerMeter(setting)
        trace = setting.recorder?.begin("Pluck", title: "Pinch on \(setting.title)")
        trace?.event("tuning", pluckItemTuningLine(setting.tuning, pointsPerMeter: pointsPerMeter, windowScale: measured?.windowScale))
    }

    /// Notes a word in the trace, with why it did what it did. A drag's
    /// words are noted as they begin a pinch, do something, or give another
    /// kind of reason, and otherwise a tenth of a second apart, so the
    /// timeline stays readable; a move handed to the carry of what spawned
    /// does nothing of the pluck's own, so it's noted no more often.
    private func note(_ word: String, _ told: PluckPinches.Told, translation: SIMD3<Double>?, extra: String?) {
        guard let trace else { return }
        var detail = told.why.description
        if let translation {
            let now = ContinuousClock.now
            let name = told.why.name
            let doesSomething = told.actions.contains { $0 != .carrySpawned }
            let isNews = told.beganAPinch || doesSomething || lastDragNote?.name != name
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
        measured = nil
        handoff = nil
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

/// Which way a pull goes, in words: "any way", or toward the viewer.
private func pluckItemPullWay(_ tuning: PluckTuning) -> String {
    switch tuning.pullRule {
    case .anyDirection: "any way"
    case .towardTheViewer: "toward you, any drift"
    case .outOfThePlane(let depthPerDrift): String(format: "toward you, 1 deep per %.2f across", 1 / depthPerDrift)
    }
}

/// Where a pull is measured from, in words.
private func pluckItemPullOrigin(_ origin: PluckPullOrigin) -> String {
    switch origin {
    case .touch: "the touch"
    case .lift: "where it lifted"
    case .arming: "where it armed"
    }
}

/// The tuning a pinch began with, on one line: what gives the hold up, how
/// the lifted item follows, when and how far it breaks free, in centimeters
/// and the item's points, and the points to a meter of the hand it was
/// measured at.
private func pluckItemTuningLine(_ tuning: PluckTuning, pointsPerMeter: Double, windowScale: Double?) -> String {
    let moved = tuning.holdStillness <= tuning.dragStartDistance
        ? "the drag's first word"
        : String(format: "%.0f pt along the scroll or %.0f any way", tuning.holdStillnessAlongScroll, tuning.holdStillness)
    let offset = tuning.holdWatchesScrollOffset
        ? String(format: ", its offset moving %.1f pt,", tuning.scrollOffsetStillness)
        : ""
    let holdGivenUp = "its scroll view scrolling\(offset) or \(moved)"
    let follows = tuning.tether.follows
        ? String(format: "follows %.2f of the hand toward %.0f pt", tuning.followShare, tuning.followCap)
        : "follows nothing"
    let scale = windowScale.map { String(format: "the window at %.2f×", $0) } ?? "the window's scale unknown, taken as its own size"
    return String(
        format: "hold %.2f s, given up by %@; drag from %.0f pt; lifted, %@; arms %.2f s after the lift; breaks free at %.1f cm, %.1f pt, %@ from %@; scroll %@; press end %@; hold from the %@; %.0f pt to a meter of the hand, %@",
        tuning.holdDuration, holdGivenUp, tuning.dragStartDistance, follows, tuning.pullArmDelay,
        tuning.breakFreeDistance * 100, tuning.breakFreeThreshold(pointsPerMeter: pointsPerMeter), pluckItemPullWay(tuning),
        pluckItemPullOrigin(tuning.pullOrigin),
        tuning.stopsScrollUnderLiftedItem
            ? (tuning.givesLiftBackToScroll ? "stops under a lift, given back a move along it" : "stops under a lift")
            : "goes on",
        tuning.pressEndSettlesLiftedItem ? "settles a lift" : "keeps a lift up",
        tuning.holdsFromTheDrag ? "drag" : "press",
        pointsPerMeter, scale
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
    add("broke free", account.pulledAfter)
    add("press up", account.pressEndedAfter)
    add("settled", account.settledAfter)
    add("drag spoke", account.dragReportedAfter)
    if let stayed = account.stayedDown { parts.append("stayed down: \(stayed.rawValue)") }
    if let needs = account.breakFreeAt {
        parts.append(String(format: "stretched %.1f of %.1f pt", account.farthestStretch, needs))
    }
    parts.append(String(
        format: "farthest %.1f pt, %.1f before the hold, %.1f of it along the scroll",
        account.farthest, account.farthestBeforeHold, account.farthestAlongScrollBeforeHold
    ))
    if let offset = account.scrollOffsetMovedBeforeHold {
        parts.append(String(format: "scroll offset moved %.1f pt before the hold", offset))
    }
    return parts.joined(separator: ", ")
}
#endif
