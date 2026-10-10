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

/// Whether a pluckable item's drag is attached for the pinch under way:
/// let in at its lift, as the tuning holds it back until then
/// (`PluckLiftedTracking`), and out again as the pinch ends. Observed apart,
/// so it draws the item's gestures again only then.
@MainActor @Observable
final class PluckDragAttachment {
    var isAttached = false
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

    /// Whether its drag is attached for the pinch under way, which its
    /// gestures alone read.
    let attachment = PluckDragAttachment()

    /// When the item's button was last pressed, which the hand it came from
    /// is told by.
    private var pressAt: ContinuousClock.Instant?
    /// How the pinch under way is followed once lifted, as its tuning chose,
    /// from the lift; nil before it, or with the drag from the touch.
    private var liftedTracking: PluckLiftedTracking?
    /// Where the drag's first word after the lift stood, from the touch, in
    /// the item's points, which its words after are measured from, standing
    /// for where the pinch was as its item lifted; nil until then, or should
    /// that word come at the held-back start, the drag's start not brought
    /// down.
    private var dragOrigin: SIMD3<Double>?
    /// The drag's words since the lift, and its first's time and distance
    /// from the touch.
    private var dragWordsSinceLift = 0
    private var firstDragAfterLift: (at: ContinuousClock.Instant, distance: Double)?
    /// The hand followed from the lift: which, the follower's token, and
    /// where it stood at the lift, in the item's points.
    private var handFollow: (side: HandSide, token: UUID, atLift: Point3D)?
    /// The hand's words since the lift, and the drag's while the hand led.
    private var handWords = 0
    private var dragWordsUnderTheHand = 0
    /// Why the hand isn't followed, should hand tracking have been chosen.
    private var handNotFollowed: String?

    private var pinches = PluckPinches()
    /// The setting the last word came with, which the counts and the
    /// container's words use.
    private var setting: Setting?
    /// The geometry of the item, for where its points are in the space.
    private var proxy: GeometryProxy3D?
    private var holdCount: Task<Void, Never>?
    private var armCount: Task<Void, Never>?
    private var quietCount: Task<Void, Never>?
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

    /// The pinch as last told to the container's watch.
    private var reportedPinch: PluckHoldWatch<AnyHashable>.Pinch?

    /// The item's id, as the last word gave it.
    var itemID: AnyHashable? { setting?.id }

    /// The item's title, as the last word gave it.
    var title: String { setting?.title ?? "an item" }

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
        if isPressed { pressAt = .now }
        setting.model?.heard(isPressed ? "press down" : "press up", from: self)
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
        setting.model?.heard("tap", from: self)
        handle(pinches.tapped(at: .now), synthesized: false)
    }

    /// The pull's drag moved.
    func dragChanged(_ value: DragGesture.Value, _ setting: Setting) {
        let moved = value.translation3D
        dragMoved(SIMD3(moved.x, moved.y, moved.z), at: value.location3D, setting)
    }

    /// The pull's drag moved `translation` from where the pinch touched, to
    /// `location`, both in the item's points.
    func dragMoved(_ translation: SIMD3<Double>, at location: Point3D, _ setting: Setting) {
        adopt(setting)
        if handFollow != nil {
            dragHeardUnderTheHand()
            return
        }
        var translation = translation
        if pinches.liftedAt != nil, let liftedTracking {
            if dragWordsSinceLift == 0 { firstDragWordAfterTheLift(translation, liftedTracking, setting) }
            dragWordsSinceLift += 1
            if let dragOrigin { translation -= dragOrigin }
        }
        lastLocation = location
        let isFirstWord = !pinches.isDragging
        // The drag's first word of a pinch is kept; the rest note the time.
        setting.model?.heard(isFirstWord ? "drag spoke" : nil, from: self)
        apply(pinches.dragMoved(translation, pointsPerMeter: pointsPerMeter(setting), at: .now), word: "drag", translation: translation)
        if isFirstWord { notePanAtTheDragsFirstWord(setting) }
    }

    /// What the scroll view's pan was doing as the drag first spoke, and a
    /// turn of the main actor later, for the trace and the console: the
    /// pan failing in step with the drag says the drag took the pinch from
    /// the scroll. Only where a debug build's probe reads the scroll view.
    private func notePanAtTheDragsFirstWord(_ setting: Setting) {
        guard let reader = setting.model?.scrollViewReader, let now = reader() else { return }
        let title = setting.title
        Task { @MainActor [weak self] in
            await Task.yield()
            let after = reader()
            let line = "the scroll view as the drag first spoke: \(now.description); a moment later: \(after?.description ?? "unread")"
            self?.trace?.event("pan", line)
            pluckItemLogger.info("The pinch on \(title): \(line, privacy: .public)")
        }
    }

    /// The pull's drag ended, let go.
    func dragEnded(_ value: DragGesture.Value, _ setting: Setting) {
        dragEnded(at: value.location3D, setting)
    }

    /// The pull's drag ended, let go at `location`, in the item's points.
    func dragEnded(at location: Point3D, _ setting: Setting) {
        adopt(setting)
        if handFollow != nil {
            dragHeardUnderTheHand()
            return
        }
        setting.model?.heard("drag end", from: self)
        lastLocation = location
        apply(pinches.dragEnded(at: .now), word: "drag end")
        // An item with no button hears its tap as the drag's end of a pinch
        // nothing else told.
        if setting.tuning.holdsFromTheDrag, pinches.press != nil, !pinches.isDragging, !pinches.isHolding {
            handle(pinches.tapped(at: .now), synthesized: true)
        }
    }

    /// The pull's drag ended where it last moved to, as a drag's end does,
    /// or at `location`, in the item's points, should it never have moved.
    func dragEndedWhereItLastMoved(orAt location: Point3D, _ setting: Setting) {
        dragEnded(at: lastLocation ?? location, setting)
    }

    /// Whether a pinch is under way on the item, or a count it began still
    /// runs.
    var isBusy: Bool {
        pinches.press != nil || holdCount != nil || armCount != nil || quietCount != nil
    }

    /// The pull's drag stopped without ending, as when the container's
    /// scroll view takes the pinch: a cancel, should the drag still have it.
    func dragStopped(_ setting: Setting) {
        guard handFollow == nil, pinches.isDragging else { return }
        adopt(setting)
        setting.model?.heard("drag cancelled", from: self)
        apply(pinches.dragCancelled(at: .now), word: "drag cancelled")
    }

    /// The item left its container, mid-pinch or not.
    func itemWent() {
        holdCount?.cancel()
        armCount?.cancel()
        quietCount?.cancel()
        setting?.model?.heard("item went", from: self)
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

    /// The container settled the item, `because` of what: its pinch hears
    /// so, and is over if no gesture has it, and the app hears so, once.
    func containerSettledIt(because reason: String) {
        trace?.event("settled by the container", reason)
        let told = pinches.containerSettledIt(at: .now)
        if told.why == .settledByTheContainer {
            apply(told, word: "settled by the container")
        }
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

    /// A pinch began on another item: this one, kept up past its press, or
    /// gone quiet, its ends unheard, is over; any other goes on, untold.
    func pinchBeganElsewhere() {
        let told = pinches.pinchBeganElsewhere(at: .now)
        guard !told.actions.isEmpty || told.ended != nil else { return }
        apply(told, word: "pinch elsewhere")
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
        case .startQuiet(let duration):
            quietCount?.cancel()
            quietCount = Task { [weak self] in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                self?.quietCountIsUp()
            }
        }
    }

    /// The quiet of a lift kept up past its press is up: should nothing have
    /// been heard since, the pinch is taken as let go.
    private func quietCountIsUp() {
        quietCount = nil
        let told = pinches.quietPassed(at: .now)
        guard !told.actions.isEmpty || told.ended != nil else { return }
        apply(told, word: "quiet")
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
            parts.append(pluckItemSilentDrag(tuning))
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
                reportPinchGoingOn()
                for action in told.actions { perform(action, why: told.why) }
            }
            // Where the content stands at the touch, which its moves are
            // measured from.
            readScrollOffset()
            showFollow()
            reportPinch()
            return
        }
        note(word, told, translation: translation, extra: extra)
        for countdown in told.countdowns { run(countdown) }
        reportPinchGoingOn()
        for action in told.actions { perform(action, why: told.why) }
        noteHeld()
        if let ended = told.ended { finish(ended) }
        showFollow()
        reportPinch()
    }

    /// Handles the item's tap: no tap for a release, the app's tap otherwise.
    private func handle(_ tap: PluckPinches.Tap, synthesized: Bool) {
        let since = tap.sinceTouch.map { "+" + pluckItemSeconds($0) + " s after the touch" } ?? "no pinch"
        let what = tap.isRelease ? "the release of a lift, no tap" : (synthesized ? "a tap, as the drag ended" : "a tap")
        trace?.event("tap", "\(what), \(since)")
        for countdown in tap.countdowns { run(countdown) }
        reportPinchGoingOn()
        for action in tap.actions { perform(action, why: .releasedByItsTap) }
        if !tap.isRelease { setting?.perform(.tapped) }
        if let ended = tap.ended { finish(ended) }
        showFollow()
        reportPinch()
    }

    /// Tells the container's watch what a pinch that goes on is now, before
    /// what its word does, so the watch knows whether its drag still has it
    /// as its item settles; a pinch the word ended is told after, once its
    /// item has settled, so the watch never sees a lifted item with no pinch.
    private func reportPinchGoingOn() {
        guard pinches.press != nil else { return }
        reportPinch()
    }

    /// Tells the container's watch what the pinch is now, should that have
    /// changed: whether its press is down, its drag has it, and its item is
    /// lifted; or that it's over. A drag's moves change none of it.
    private func reportPinch() {
        let pinch = pinches.press.map { press in
            PluckHoldWatch<AnyHashable>.Pinch(
                title: title,
                pressIsDown: pinches.isHolding,
                dragHasIt: pinches.isDragging,
                holdsItsItem: press.isLifted
            )
        }
        guard pinch != reportedPinch else { return }
        reportedPinch = pinch
        setting?.model?.pinchChanged(of: self, to: pinch)
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
            if let change = setting.model?.lift(setting.id, title: setting.title, by: self) {
                trace?.event("lift", change.scrollHoldChanged ? "the scroll held off" : "the scroll goes on")
            } else {
                trace?.event("lift", "no container")
            }
            beginLiftedTracking(setting)
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
            let change = setting.model?.settle(setting.id, because: why.description)
            if case .givenBackToTheScroll = why {
                // No scroll ruling: the scroll stays held off until this
                // pinch lets go, so the scroll view can't take it.
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
            // A move along the scroll past where the scroll view's pan
            // starts is one the scroll view should take; a move across, or
            // a scroll it took already, asks nothing of it.
            if case .stayDown(.movedFirst) = action, pinches.farthestAlongScrollBeforeHold >= setting.tuning.holdStillnessAlongScroll {
                setting.model?.ruledAScroll(by: self)
            }
            let reason = switch why {
            case .containerScrolled: "its scroll view scrolled since the touch, a scroll"
            default: why.description
            }
            trace?.event("stays down", "the hold given up: " + reason)
            #if DEBUG
            GestureAutomation.shared.heard("pluck", on: setting.title, "stayed down", .string(reason))
            #endif
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
            return needs + " from the touch: the drag silent as it \(moment), " + (tuning.liftedTracking.letsDragInAtTheLift
                ? "its first word after the lift to stand for where the pinch was"
                : pluckItemSilentDrag(tuning))
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
            if let line = liftedTrackingLine() { trace.event("after the lift", line) }
            trace.event("account", summary)
            trace.finish(outcome)
        } else if let title = setting?.title {
            pluckItemLogger.info("The pinch on \(title) was \(outcome, privacy: .public): \(summary, privacy: .public)")
        }
        trace = nil
        lastDragNote = nil
        measured = nil
        handoff = nil
        quietCount?.cancel()
        quietCount = nil
        endLiftedTracking()
        setting?.model?.pinchEnded(by: self)
    }

    // MARK: The lifted pinch's tracking

    /// The item lifted: should its tuning hold the drag back, the drag is
    /// attached, let in or its start brought down; should it follow the
    /// hand, the hand the press came from is followed from here.
    private func beginLiftedTracking(_ setting: Setting) {
        let tracking = (pinches.press?.tuning ?? setting.tuning).liftedTracking
        guard tracking.heldBack != nil else { return }
        liftedTracking = tracking
        if !attachment.isAttached { attachment.isAttached = true }
        trace?.event("tracking", tracking.description)
        if tracking.followsTheHand { followTheHand(setting) }
    }

    /// The drag's first word after the lift, `translation` from the touch:
    /// traced, with whether its start came down; and, should it come before
    /// the held-back start where the drag was let in at the lift, taken as
    /// where the pinch stood as its item lifted, which its words after are
    /// measured from.
    private func firstDragWordAfterTheLift(_ translation: SIMD3<Double>, _ tracking: PluckLiftedTracking, _ setting: Setting) {
        let distance = (translation * translation).sum().squareRoot()
        let since = pinches.liftedAt.map { pluckItemSeconds(.now - $0) } ?? "?"
        firstDragAfterLift = (.now, distance)
        let heldBackStart = (pinches.press?.tuning ?? setting.tuning).heldBackDragStart
        let cameDown = distance < heldBackStart
        // Only where the drag was silent until the lift: one that spoke
        // before it gave the pull where the pinch stood as it lifted.
        if tracking.letsDragInAtTheLift, cameDown, pinches.press?.liftPoint == nil { dragOrigin = translation }
        let what = switch tracking.heldBack {
        case .byItsStart(lowered: true): cameDown
            ? "its start came down: it hears the pinch from here"
            : "at its held-back start: its start didn't come down mid-pinch"
        case .byItsStart(lowered: false): "at its held-back start, as tuned"
        case .byItsGestureMask: "let in by its mask mid-pinch: it hears the pinch from here"
        case nil: ""
        }
        trace?.event("drag after the lift", String(format: "+%@ s after it, %.1f pt from the touch, %@", since, distance, what))
    }

    /// Follows the hand the item's press came from, by hand tracking, from
    /// the lift; or says why not, the drag then following the pinch.
    private func followTheHand(_ setting: Setting) {
        let tracker = PinchTracker.shared
        guard tracker.state.follows else {
            notFollowingTheHand(tracker.state.description)
            return
        }
        guard let side = tracker.hand(pinchedNearest: pressAt ?? .now),
              let pinch = tracker.hands[side], let position = pinch.position
        else {
            notFollowingTheHand("no hand is pinched")
            return
        }
        guard let atLift = itemPoint(ofHandAt: position, setting) else {
            notFollowingTheHand("the space isn't open, so the hand can't be placed on the item")
            return
        }
        let token = tracker.follow(side) { [weak self] sample in self?.handSampled(sample) }
        handFollow = (side, token, atLift)
        lastLocation = atLift
        var detail = "follows the \(side.rawValue) hand"
        if let closedAt = pinch.closedAt, let pressAt {
            let apart = closedAt < pressAt ? pressAt - closedAt : closedAt - pressAt
            detail += ", its pinch closed \(pluckItemSeconds(apart)) s \(closedAt < pressAt ? "before" : "after") the press"
        }
        trace?.event("hand", detail)
    }

    private func notFollowingTheHand(_ reason: String) {
        handNotFollowed = reason
        trace?.event("hand", "not followed, \(reason): the drag follows the pinch")
    }

    /// An update of the followed hand: a move, told to the pinch as the
    /// drag's would be, from where the hand stood at the lift; or its pinch
    /// opening, or the hand lost, told as the drag's end.
    private func handSampled(_ sample: PinchTracker.Sample) {
        guard let setting, let follow = handFollow else { return }
        if let change = sample.change, change != .closed {
            stopFollowingTheHand()
            setting.model?.heard("hand \(change.rawValue)", from: self)
            apply(pinches.dragEnded(at: .now), word: change == .lost ? "hand lost" : "hand opened")
            return
        }
        guard let position = sample.pinch.position, let point = itemPoint(ofHandAt: position, setting) else { return }
        lastLocation = point
        let translation = SIMD3(point.x - follow.atLift.x, point.y - follow.atLift.y, point.z - follow.atLift.z)
        handWords += 1
        setting.model?.heard(handWords == 1 ? "hand spoke" : nil, from: self)
        apply(pinches.dragMoved(translation, pointsPerMeter: pointsPerMeter(setting), at: .now), word: "hand", translation: translation)
    }

    /// A word of the drag while the hand leads, which it doesn't follow,
    /// counted and traced once, to say whether the drag let in at the lift
    /// hears the pinch.
    private func dragHeardUnderTheHand() {
        dragWordsUnderTheHand += 1
        if dragWordsUnderTheHand == 1 {
            trace?.event("drag after the lift", "the drag spoke, the hand leading")
        }
    }

    private func stopFollowingTheHand() {
        guard let handFollow else { return }
        PinchTracker.shared.stopFollowing(handFollow.token)
        self.handFollow = nil
    }

    /// The pinch is over: what followed it after the lift is traced, the
    /// hand let go, and the drag out again.
    private func endLiftedTracking() {
        stopFollowingTheHand()
        if attachment.isAttached { attachment.isAttached = false }
        liftedTracking = nil
        dragOrigin = nil
        dragWordsSinceLift = 0
        firstDragAfterLift = nil
        handWords = 0
        dragWordsUnderTheHand = 0
        handNotFollowed = nil
    }

    /// What followed the lifted pinch, for the trace's last lines: the hand's
    /// words, the drag's, and whether the drag spoke after the lift at all.
    private func liftedTrackingLine() -> String? {
        guard let liftedTracking else { return nil }
        var parts = [liftedTracking.description]
        if handWords > 0 || dragWordsUnderTheHand > 0 {
            parts.append("the hand spoke \(handWords) times, the drag \(dragWordsUnderTheHand) times beneath it")
        }
        if let handNotFollowed { parts.append("the hand not followed: \(handNotFollowed)") }
        if let firstDragAfterLift {
            parts.append(String(format: "the drag spoke %d times after the lift, first %.1f pt from the touch", dragWordsSinceLift, firstDragAfterLift.distance))
        } else if handWords == 0 {
            parts.append("no drag word came after the lift")
        }
        return parts.joined(separator: "; ")
    }

    /// The hand's place, `position` in meters in the immersive space, as a
    /// point of the item, through its transform into the space, which a
    /// drag's location is in; nil with the space closed.
    private func itemPoint(ofHandAt position: SIMD3<Float>, _ setting: Setting) -> Point3D? {
        guard let transform = proxy?.transform(in: .immersiveSpace), let inverse = transform.inverse else { return nil }
        let meters = Point3D(x: Double(position.x), y: Double(-position.y), z: Double(position.z))
        return setting.metrics.convert(meters, from: .meters).applying(inverse)
    }
}

// MARK: Words for the trace

/// A duration in seconds, to two decimals: "0.50".
private func pluckItemSeconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.2f", Double(seconds) + Double(attoseconds) / 1e18)
}

/// Why the drag was silent, in words, as the tuning holds it: within its
/// start of the touch, or left out by its mask.
private func pluckItemSilentDrag(_ tuning: PluckTuning) -> String {
    let made = tuning.liftedTracking.drag(attached: false, tuning: tuning)
    guard made.isLetIn else { return "the drag silent, left out by its mask until the lift" }
    return String(format: "the drag silent, the pinch within its %.0f pt start of the touch", made.startDistance)
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
