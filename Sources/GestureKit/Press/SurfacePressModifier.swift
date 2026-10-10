#if os(visionOS)
import GestureCore
import os
import Spatial
import SwiftUI

private let surfacePressLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "SurfacePressModifier")

/// One thing a pinch on a surface was told to do, as `.surfacePress` hands
/// it to the app: the action, the pinch as told once it was, how long after
/// its touch, and, for a carry that begins, a way to refuse it.
@MainActor
public struct SurfacePressEvent {
    /// What the surface does (`SurfacePress.Action`).
    public let action: SurfacePress.Action
    /// The pinch as told, once this action was: how far it has moved, which
    /// way, whether it's picked up, and its tuning, for the app's log.
    public let press: SurfacePress
    /// How long after the pinch touched this came, in seconds.
    public let elapsed: Double

    fileprivate let carryRefusal: SurfacePressCarryRefusal

    /// Refuses the carry this event begins (`.beginCarry`), as for something
    /// that can't be carried now: the rest of the pinch does nothing, and its
    /// end is no tap (`SurfacePress.refuseCarry()`). Nothing for any other
    /// action.
    public func refuseCarry(because reason: String) {
        guard case .beginCarry = action else { return }
        carryRefusal.reason = reason
    }
}

/// What the app said of a carry as it began, which the press reads once the
/// app's handler returns.
@MainActor
fileprivate final class SurfacePressCarryRefusal {
    var reason: String?
}

/// A two-handed pinch on a surface, which a press gives way to as it begins,
/// as `.surfacePress(onMagnify:)` hands it to the app.
public enum SurfaceMagnify: Equatable, Sendable {
    /// It began where the first hand touched, this far along the surface, in
    /// meters from its leading edge.
    case began(at: Double)
    /// The hands spread or closed: their distance is `magnification` times
    /// what it was as it began.
    case changed(magnification: Double)
    /// It ended, released or cancelled.
    case ended
}

extension View {
    /// Takes every pinch on this view as one press, from its touch, told as a
    /// tap, a drag along, a scroll, a drag across, a pickup and a carry, or a
    /// hold as it goes (`SurfacePress`), handing each action to `perform`;
    /// and, held still, lifts what this view draws as `HoldLift` says.
    ///
    /// Two plain drags from 0 pt, begun together, feed it, so it has every
    /// pinch from its touch and no gesture stands in front of another: one
    /// in this view's points, for where the pinch is along it and how far it
    /// has moved, and one in the immersive space's, for the hand's moves as
    /// it scrolls or carries, since the view moves under the hand then. Only
    /// what's drawn lifts, inside the view the pinch is taken on, so a still
    /// pinch stays still in the points it's measured in as it lifts.
    ///
    ///     StripView()
    ///         .surfacePress(tuning: tuning, recorder: recorder, canHold: true) { event in
    ///             switch event.action {
    ///             case .tap(let along): dropMarker(at: along)
    ///             case .beginCarry(_, let handMoved):
    ///                 if !beginCarry(by: handMoved) { event.refuseCarry(because: "it's locked") }
    ///             case .moveCarry(let handMoved): carry(by: handMoved)
    ///             case .endCarry: dropCarried()
    ///             case .cancelCarry: putCarriedBack()
    ///             default: break
    ///             }
    ///         }
    ///
    /// - Parameters:
    ///   - tuning: the numbers it goes by, read as each pinch touches.
    ///   - recorder: where each pinch is traced, from its touch to its end,
    ///     its summary the console's line; nil, or one not recording, traces
    ///     nothing, and the console gets a line only for a pickup or a carry
    ///     the app refused.
    ///   - traceTitle: what each pinch's trace is called.
    ///   - canHold: whether a pinch here holds, held still for
    ///     `holdDuration`.
    ///   - canPickUp: whether a pinch here picks up, held still for
    ///     `pickUpDelay`, and then carries.
    ///   - dragAlongScrolls: whether a drag along scrolls, by the hand's moves
    ///     in the space, rather than dragging along, by its place on the view.
    ///   - alongOffset: how far along the surface this view's leading edge
    ///     stands, in meters, added to every place along it the press gives.
    ///   - liftAnchor: where what's drawn grows about as it lifts.
    ///   - showsLift: whether what's drawn lifts at all.
    ///   - catchCoast: asked as a pinch touches: whether it caught a coast,
    ///     which the app stops then, so it's that catch, and no tap.
    ///   - pickUpRefusal: asked as a pickup comes due: why it can't pick up
    ///     now, or nil to let it. A refused pinch goes on as one that never
    ///     could, its hold included.
    ///   - onPinchUnderWay: told true as a pinch touches and false once it's
    ///     over, ended or cancelled.
    ///   - onMagnify: given, a two-handed pinch here is the app's to zoom by,
    ///     and the press its first hand began gives way to it, as a cancel
    ///     does, never a tap.
    ///   - perform: each action, as it's told.
    public func surfacePress(
        tuning: SurfacePress.Tuning = .defaults,
        recorder: TraceRecorder? = nil,
        traceTitle: String = "Pinch on a surface",
        canHold: Bool = false,
        canPickUp: Bool = true,
        dragAlongScrolls: Bool = false,
        alongOffset: Double = 0,
        liftAnchor: UnitPoint = .center,
        showsLift: Bool = true,
        catchCoast: @escaping @MainActor () -> Bool = { false },
        pickUpRefusal: @escaping @MainActor () -> String? = { nil },
        onPinchUnderWay: @escaping @MainActor (Bool) -> Void = { _ in },
        onMagnify: (@MainActor (SurfaceMagnify) -> Void)? = nil,
        perform: @escaping @MainActor (SurfacePressEvent) -> Void
    ) -> some View {
        surfacePress(
            hitShape: Rectangle(),
            tuning: tuning,
            recorder: recorder,
            traceTitle: traceTitle,
            canHold: canHold,
            canPickUp: canPickUp,
            dragAlongScrolls: dragAlongScrolls,
            alongOffset: alongOffset,
            liftAnchor: liftAnchor,
            showsLift: showsLift,
            catchCoast: catchCoast,
            pickUpRefusal: pickUpRefusal,
            onPinchUnderWay: onPinchUnderWay,
            onMagnify: onMagnify,
            perform: perform
        )
    }

    /// `surfacePress(tuning:…perform:)`, taking its pinches only over
    /// `hitShape`, in this view's points, as where only part of the view
    /// shows; the shape stays where it is as what's drawn lifts.
    public func surfacePress<HitShape: Shape>(
        hitShape: HitShape,
        tuning: SurfacePress.Tuning = .defaults,
        recorder: TraceRecorder? = nil,
        traceTitle: String = "Pinch on a surface",
        canHold: Bool = false,
        canPickUp: Bool = true,
        dragAlongScrolls: Bool = false,
        alongOffset: Double = 0,
        liftAnchor: UnitPoint = .center,
        showsLift: Bool = true,
        catchCoast: @escaping @MainActor () -> Bool = { false },
        pickUpRefusal: @escaping @MainActor () -> String? = { nil },
        onPinchUnderWay: @escaping @MainActor (Bool) -> Void = { _ in },
        onMagnify: (@MainActor (SurfaceMagnify) -> Void)? = nil,
        perform: @escaping @MainActor (SurfacePressEvent) -> Void
    ) -> some View {
        modifier(SurfacePressModifier(
            hitShape: hitShape,
            tuning: tuning,
            recorder: recorder,
            traceTitle: traceTitle,
            canHold: canHold,
            canPickUp: canPickUp,
            dragAlongScrolls: dragAlongScrolls,
            alongOffset: alongOffset,
            liftAnchor: liftAnchor,
            showsLift: showsLift,
            catchCoast: catchCoast,
            pickUpRefusal: pickUpRefusal,
            onPinchUnderWay: onPinchUnderWay,
            onMagnify: onMagnify,
            perform: perform
        ))
    }
}

/// The settle of a lifted surface: a spring of the lift's settle duration
/// with no bounce, so it never dips behind where it stood. The same spring
/// as the pluck's lifted item comes down on (its `springDown`, a 0.32 s
/// spring with no bounce, in GestureKit's Lift area); kept apart here until
/// the two are joined, so neither area waits on the other.
@MainActor
private func surfacePressSettleSpring(_ lift: HoldLift.Tuning) -> Animation {
    .spring(duration: max(lift.settleDuration, 0.01), bounce: 0)
}

/// `.surfacePress`'s modifier: the press under way, its clock, and its
/// trace, kept in a reference (`SurfacePressPinch`), and its lift, which
/// only the lift's own modifier reads (`SurfacePressLiftEffect`).
private struct SurfacePressModifier<HitShape: Shape>: ViewModifier {
    let hitShape: HitShape
    let tuning: SurfacePress.Tuning
    let recorder: TraceRecorder?
    let traceTitle: String
    let canHold: Bool
    let canPickUp: Bool
    let dragAlongScrolls: Bool
    let alongOffset: Double
    let liftAnchor: UnitPoint
    let showsLift: Bool
    let catchCoast: @MainActor () -> Bool
    let pickUpRefusal: @MainActor () -> String?
    let onPinchUnderWay: @MainActor (Bool) -> Void
    let onMagnify: (@MainActor (SurfaceMagnify) -> Void)?
    let perform: @MainActor (SurfacePressEvent) -> Void

    @Environment(\.physicalMetrics) private var physicalMetrics

    /// The pinch under way, its clock, and its trace, kept in a reference
    /// made once for the view: each of a drag's words changes them, and as
    /// `@State` each change made SwiftUI run this modifier's body again, its
    /// gestures and all, as a hand moved; through a reference, nothing
    /// SwiftUI watches changes but how what's drawn lifts.
    @State private var pinch = SurfacePressPinch()
    /// How what's drawn looks lifted (`HoldLift`), which only the lift's
    /// own modifier reads (`SurfacePressLiftEffect`), so a frame of the lift
    /// draws the lift again and nothing else.
    @State private var lift = SurfacePressLift()
    /// True while a pinch is under way, from its touch. SwiftUI resets it as
    /// the pinch ends and as it's cancelled, and only the end calls
    /// `onEnded`, so its going false with a pinch left over, still a turn
    /// later, means a cancel.
    @GestureState private var isPressing = false
    /// True while a two-handed pinch is under way.
    @GestureState private var isMagnifying = false

    func body(content: Content) -> some View {
        content
            // Held still, what's drawn lifts toward the viewer and grows
            // about its anchor; the pinch is taken outside the lift, so its
            // points don't move as it lifts.
            .modifier(SurfacePressLiftEffect(lift: lift, anchor: liftAnchor))
            .contentShape(.interaction, hitShape)
            .gesture(pressGesture)
            .simultaneousGesture(magnifyGesture, including: onMagnify == nil ? .none : .all)
            // A release calls onEnded as well as ending the gesture state; a
            // cancel only ends the state. SwiftUI doesn't promise which of
            // the two a release calls first, so the cancel waits a turn of
            // the main actor, and happens only if the pinch is still under
            // way then, unended by a release.
            .onChange(of: isPressing) { _, pressing in
                guard !pressing else { return }
                guard pinch.press != nil else {
                    pinch.gaveWayToMagnify = false
                    return
                }
                let waiting = pinch.serial
                Task { @MainActor in
                    await Task.yield()
                    guard pinch.serial == waiting, pinch.press != nil else { return }
                    pinch.cancelledTouchPoint = pinch.touchPoint
                    pressCancelled(because: "the system cancelled its gesture")
                }
            }
            .onChange(of: isMagnifying) { _, magnifying in
                guard !magnifying else { return }
                magnifyEnded()
            }
            // The view going ends a pinch on it, as a cancel does.
            .onDisappear {
                guard pinch.press != nil else { return }
                pressCancelled(because: "its view went")
            }
            #if DEBUG
            .modifier(PinchStandInListener(adapter: .surfacePress) { standInStep($0) })
            #endif
    }

    // MARK: The press

    /// Every pinch, from its touch: two drags begun together, one in this
    /// view's points and one in the immersive space's.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .simultaneously(with: DragGesture(minimumDistance: 0, coordinateSpace: .immersiveSpace))
            .updating($isPressing) { _, isPressing, _ in isPressing = true }
            .onChanged { pressChanged(SurfacePressWord($0)) }
            .onEnded { pressEnded(SurfacePressWord($0)) }
    }

    /// Begins the pinch on its first change, where it touched, then tells it
    /// where the pinch is at each.
    private func pressChanged(_ word: SurfacePressWord?) {
        guard let word, !pinch.gaveWayToMagnify else { return }
        if pinch.press == nil {
            pinch.touchPoint = word.start
            pressBegan(at: along(word.start.x), hand: word.handStart.map { handPlace($0) })
        }
        let moved = word.translation
        let sample = SurfacePress.Sample(
            along: along(word.location.x),
            moved: SIMD3(moved.x, moved.y, moved.z),
            hand: word.hand.map { handPlace($0) }
        )
        guard let actions = pinch.press?.move(sample) else { return }
        handle(actions)
    }

    /// A pinch touched `along` the surface, with the hand at `hand` in the
    /// space, if the space's drag has said: its clock starts, which picks up
    /// and holds as their times come.
    private func pressBegan(at along: Double, hand: SIMD3<Double>?) {
        let caughtACoast = catchCoast()
        pinch.press = SurfacePress(
            at: along,
            canHold: canHold,
            hand: hand,
            dragAlongScrolls: dragAlongScrolls,
            caughtACoast: caughtACoast,
            canPickUp: canPickUp,
            tuning: tuning
        )
        pinch.serial += 1
        pinch.touchedAt = .now
        pinch.cancelledTouchPoint = nil
        pinch.carryWasRefused = false
        pinch.trace = recorder?.begin("Press", title: traceTitle)
        if let trace = pinch.trace {
            var traits = [surfacePressMeters(along) + " along"]
            if canPickUp { traits.append("picks up at \(tuning.pickUpDelayLabel)") }
            if canHold { traits.append("holds at \(tuning.holdDurationLabel)") }
            if dragAlongScrolls { traits.append("a drag along scrolls") }
            if caughtACoast { traits.append("caught a coast") }
            trace.event("touch", traits.joined(separator: "; "))
        }
        onPinchUnderWay(true)
        runClock(serial: pinch.serial)
    }

    /// Counts the pinch's frames from its touch, on the continuous clock:
    /// picks up as its pickup comes due, unless refused, holds as its hold
    /// does, and lifts what's drawn as `HoldLift` says, for as long as
    /// either may still change. A pinch that moved off once picked up eases
    /// back from what its hold had raised to its picked-up look.
    private func runClock(serial counting: Int) {
        pinch.clock?.cancel()
        pinch.clock = Task { @MainActor in
            while !Task.isCancelled, pinch.serial == counting, let touchedAt = pinch.touchedAt, pinch.press != nil {
                let elapsed = (ContinuousClock.now - touchedAt) / .seconds(1)
                if pinch.press?.isPickUpDue(after: elapsed) == true {
                    pickUp(after: elapsed)
                }
                if pinch.press?.isHoldDue(after: elapsed) == true, let actions = pinch.press?.holdTimerFired() {
                    handle(actions)
                }
                guard !Task.isCancelled, let told = pinch.press else { return }
                let mayChange = HoldLift.mayChange(after: elapsed, of: told)
                if showsLift {
                    let target = HoldLift.look(after: elapsed, of: told)
                    if mayChange {
                        if target != lift.look { lift.look = target }
                    } else if target != lift.look {
                        withAnimation(surfacePressSettleSpring(told.tuning.lift)) { lift.look = target }
                    }
                }
                guard mayChange || told.canStillHold else { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// The pickup came due, `elapsed` seconds in: it picks up, unless the app
    /// says why it can't now, which the trace and the log say, and the pinch
    /// goes on as one that never could.
    private func pickUp(after elapsed: Double) {
        if let reason = pickUpRefusal() {
            pinch.press?.refusePickUp()
            if let trace = pinch.trace {
                trace.event("pickup refused", reason)
            } else {
                surfacePressLogger.info("""
                    \(traceTitle): held still \(elapsed, format: .fixed(precision: 2), privacy: .public) s, \
                    but it doesn't pick up, since \(reason)
                    """)
            }
            return
        }
        guard let actions = pinch.press?.pickUpTimerFired() else { return }
        handle(actions)
    }

    /// The pinch was released: one whose first change never came begins
    /// here, so its tap isn't lost, but the release of a pinch already
    /// cancelled is ignored.
    private func pressEnded(_ word: SurfacePressWord?) {
        guard !pinch.gaveWayToMagnify else {
            pinch.gaveWayToMagnify = false
            return
        }
        if pinch.press == nil, let word {
            if let cancelledTouchPoint = pinch.cancelledTouchPoint, word.start == cancelledTouchPoint {
                pinch.cancelledTouchPoint = nil
                return
            }
            pressChanged(word)
        }
        guard var ended = pinch.press else { return }
        let stage = ended.stage
        let actions = ended.end()
        pinch.press = ended
        handle(actions)
        finish(outcome: outcome(of: actions, from: stage, of: ended, cancelled: false))
    }

    /// The pinch was cancelled, `why`: what it picked up is put down, a drag
    /// along lands, a scroll stops, a carry goes back, and a hold ends, but
    /// it's no tap.
    private func pressCancelled(because why: String) {
        guard var cancelled = pinch.press else { return }
        pinch.trace?.event("cancel", why)
        let stage = cancelled.stage
        let actions = cancelled.cancel()
        pinch.press = cancelled
        handle(actions)
        finish(outcome: outcome(of: actions, from: stage, of: cancelled, cancelled: true))
    }

    /// Forgets the pinch, its clock, and its trace, settling what's drawn.
    private func finish(outcome: String) {
        pinch.press = nil
        pinch.touchPoint = nil
        settle()
        pinch.trace?.finish(outcome)
        pinch.trace = nil
        onPinchUnderWay(false)
    }

    /// Stops the clock and brings what's drawn back down from its lift.
    private func settle() {
        pinch.clock?.cancel()
        pinch.clock = nil
        guard lift.look != .rest else { return }
        withAnimation(surfacePressSettleSpring(tuning.lift)) {
            lift.look = .rest
        }
    }

    /// Hands each action to the app, as one event, tracing it; a carry the
    /// app refuses is refused here, and the lift settles as the pinch moves
    /// off before it picked up, carries, or holds.
    private func handle(_ actions: [SurfacePress.Action]) {
        guard let told = pinch.press else { return }
        let elapsed = pinch.touchedAt.map { (ContinuousClock.now - $0) / .seconds(1) } ?? 0
        for action in actions {
            traceEvent(for: action, of: told, after: elapsed)
            let refusal = SurfacePressCarryRefusal()
            perform(SurfacePressEvent(action: action, press: pinch.press ?? told, elapsed: elapsed, carryRefusal: refusal))
            switch action {
            case .giveUpHold where !told.isPickedUp:
                settle()
            case .fireHold:
                settle()
            case .beginCarry:
                settle()
                if let reason = refusal.reason {
                    pinch.press?.refuseCarry()
                    pinch.carryWasRefused = true
                    if let trace = pinch.trace {
                        trace.event("carry refused", reason)
                    } else {
                        surfacePressLogger.info("\(traceTitle): its carry was refused, since \(reason)")
                    }
                }
            default:
                break
            }
        }
    }

    /// Writes what the pinch was told to its trace, with how far it had
    /// moved, which way, and when.
    private func traceEvent(for action: SurfacePress.Action, of told: SurfacePress, after elapsed: Double) {
        guard let trace = pinch.trace else { return }
        let when = surfacePressSeconds(elapsed)
        switch action {
        case .tap(let along):
            trace.event("tap", "at \(surfacePressMeters(along)), within \(movedText(of: told, way: false)), after \(when)")
        case .beginDragAlong(let from, let to):
            trace.event("drag along", "from \(surfacePressMeters(from)) to \(surfacePressMeters(to)), \(movedText(of: told)), after \(when)")
        case .ignoreDragAcross:
            trace.event("drag across", "\(movedText(of: told)), after \(when): does nothing")
        case .giveUpHold:
            let given = told.isPickedUp ? "the hold" : "the pickup\(told.canHold ? " and the hold" : "")"
            trace.event("moved off", "\(movedText(of: told)), after \(when): gives up \(given)")
        case .pickUp:
            trace.event("pick up", "held still \(when) within \(movedText(of: told, way: false))")
        case .putDown:
            trace.event("put down", "after \(when), \(movedText(of: told))")
        case .fireHold:
            trace.event("hold", "held still \(when) within \(movedText(of: told, way: false))")
        case .endHold:
            trace.event("hold ends", "after \(when)")
        case .beginScroll(let handMoved):
            trace.event("scroll", "\(movedText(of: told)); the hand \(surfacePressCentimeters(handMoved)), after \(when)")
        case .endScroll(let coasting):
            trace.event(coasting ? "let go" : "scroll stops", "after \(when)\(coasting ? ", may coast" : "")")
        case .endCatch:
            trace.event("catch", "let go after \(when), no tap")
        case .beginCarry(let reason, let handMoved):
            trace.event("carry", "\(told.describe(reason)): \(movedText(of: told)); the hand \(surfacePressCentimeters(handMoved)), after \(when)")
        case .endCarry:
            trace.event("drop", "after \(when)")
        case .cancelCarry:
            trace.event("carry goes back", "after \(when)")
        case .endDragAlong:
            trace.event("drag ends", "after \(when)")
        case .moveDragAlong, .moveScroll, .moveCarry:
            break
        }
    }

    /// What a pinch that ended or was cancelled came to, for its trace.
    private func outcome(of actions: [SurfacePress.Action], from stage: SurfacePress.Stage, of told: SurfacePress, cancelled: Bool) -> String {
        let ending = actions.lazy.compactMap { action -> String? in
            switch action {
            case .tap(let along): "tap at \(surfacePressMeters(along))"
            case .endDragAlong: "drag along"
            case .endScroll: "scroll"
            case .endCatch: "catch"
            case .endCarry: "carry"
            case .cancelCarry: "carry"
            case .putDown: "pickup, put down"
            case .endHold: "hold"
            default: nil
            }
        }.first
        let came: String
        if let ending {
            came = ending
        } else if pinch.carryWasRefused {
            came = "carry refused"
        } else if stage == .draggingAcross {
            came = "drag across"
        } else {
            came = told.farthest < told.tuning.dragDistance ? "nothing" : "a drag that never told"
        }
        return cancelled ? "cancelled: \(came)" : came
    }

    /// How far the pinch has moved, in points and centimeters, and, unless
    /// `way` is false, which way it last went.
    private func movedText(of told: SurfacePress, way: Bool = true) -> String {
        let farthest = told.farthest
        var text = String(format: "%.1f pt", farthest) + " (" + centimeters(ofPoints: farthest) + ")"
        if way {
            let moved = told.moved
            text += String(format: ", last %.1f along, %.1f across, %.1f deep", moved.x, moved.y, moved.z)
        }
        return text
    }

    /// `points` of this view as centimeters, for a trace: "2.0 cm".
    private func centimeters(ofPoints points: Double) -> String {
        String(format: "%.1f cm", Double(physicalMetrics.convert(CGFloat(points), to: .meters)) * 100)
    }

    #if DEBUG
    /// A step of the hand's stand-in (`PinchStandIn`), as the press's drags
    /// would tell it: touched 100 pt along, 20 pt down, and moved as it says.
    private func standInStep(_ step: PinchStandIn.Step) {
        switch step {
        case .moved(let points, _, _):
            pressChanged(SurfacePressWord(standingInFor: points))
        case .released:
            pressEnded(pinch.press == nil ? nil : SurfacePressWord(standingInFor: .zero))
        }
    }
    #endif

    // MARK: Two hands

    /// A two-handed pinch, which a single hand never makes, beside the press,
    /// never in front of it; as it begins, the press its first hand began
    /// gives way to it.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($isMagnifying) { _, magnifying, _ in magnifying = true }
            .onChanged { value in
                if !pinch.magnifyUnderWay {
                    pinch.magnifyUnderWay = true
                    giveWayToMagnify()
                    onMagnify?(.began(at: along(value.startLocation.x)))
                }
                onMagnify?(.changed(magnification: Double(value.magnification)))
            }
            .onEnded { _ in magnifyEnded() }
    }

    /// The press under way gives way to the two-handed pinch its first hand
    /// has become: what it began ends, as a cancel ends it, never a tap.
    private func giveWayToMagnify() {
        pinch.gaveWayToMagnify = true
        guard pinch.press != nil else { return }
        pressCancelled(because: "it gave way to a two-handed pinch")
    }

    /// The two-handed pinch ended: the app hears it once, and unless the
    /// press that gave way to it is still under way, whose end ends its
    /// giving way, the next pinch is taken afresh. One that began where no
    /// press began would otherwise leave the press giving way to nothing.
    private func magnifyEnded() {
        if pinch.gaveWayToMagnify, !isPressing {
            pinch.gaveWayToMagnify = false
        }
        guard pinch.magnifyUnderWay else { return }
        pinch.magnifyUnderWay = false
        onMagnify?(.ended)
    }

    // MARK: Measures

    /// How far along the surface `points` across this view is, in meters
    /// from the surface's leading edge.
    private func along(_ points: CGFloat) -> Double {
        Double(physicalMetrics.convert(points, to: .meters)) + alongOffset
    }

    /// Where the hand is at `point`, in the immersive space's points, in
    /// meters with y up.
    private func handPlace(_ point: Point3D) -> SIMD3<Double> {
        let meters = physicalMetrics.convert(point, to: .meters)
        return SIMD3(meters.x, -meters.y, meters.z)
    }
}

/// A press's pinch under way on its view, and what it has done: the press
/// as told, the clock counting its frames, its trace, and how it touched,
/// was cancelled, and gave way to two hands.
@MainActor
private final class SurfacePressPinch {
    /// The pinch under way, told as it goes; nil between pinches.
    var press: SurfacePress?
    /// Counts the pinches, so a timer or a cancel waiting its turn never acts
    /// on a later pinch than its own.
    var serial = 0
    /// When the pinch under way touched.
    var touchedAt: ContinuousClock.Instant?
    /// Where the pinch under way touched, in the view's points.
    var touchPoint: CGPoint?
    /// Where the last pinch the gesture's reset cancelled touched, so its own
    /// release, should it come after the cancel, isn't taken for a pinch
    /// whose first change never came; nil once another touches.
    var cancelledTouchPoint: CGPoint?
    /// The pinch's trace, while one is under way and there's a recorder
    /// recording.
    var trace: InteractionTrace?
    /// Whether the pinch under way had its carry refused.
    var carryWasRefused = false
    /// Counts the pinch's frames, picking up and holding as their times come
    /// and lifting what's drawn, while anything may still change.
    var clock: Task<Void, Never>?
    /// Whether the pinch under way gave way to a two-handed one: the rest of
    /// it is that one's.
    var gaveWayToMagnify = false
    /// Whether a two-handed pinch from the view is under way.
    var magnifyUnderWay = false
}

/// How what a press's view draws looks lifted, the one thing of a pinch a
/// view draws from, observed by the lift's own modifier alone.
@MainActor @Observable
private final class SurfacePressLift {
    var look = HoldLift.Look.rest
}

/// What a press's view draws, lifted as its pinch's lift says: grown about
/// its anchor and brought toward the viewer. Reading the lift here, apart
/// from the press's gestures, has a frame of the lift draw it again and run
/// nothing else.
private struct SurfacePressLiftEffect: ViewModifier {
    let lift: SurfacePressLift
    let anchor: UnitPoint
    @Environment(\.physicalMetrics) private var physicalMetrics

    func body(content: Content) -> some View {
        content
            .scaleEffect(lift.look.scale, anchor: anchor)
            .offset(z: physicalMetrics.convert(lift.look.depth, from: .meters))
    }
}

/// One word of a press's two drags, as the press reads it: where the pinch
/// touched and is in the view's points, how far it has moved, and where the
/// hand began and is in the immersive space's points, once the space's drag
/// has said.
private struct SurfacePressWord {
    let start: CGPoint
    let location: CGPoint
    let translation: Vector3D
    let handStart: Point3D?
    let hand: Point3D?

    /// The word the two drags' value says; nil before the view's drag has
    /// said anything.
    init?(_ value: SimultaneousGesture<DragGesture, DragGesture>.Value) {
        guard let local = value.first else { return nil }
        start = local.startLocation
        location = local.location
        translation = local.translation3D
        handStart = value.second?.startLocation3D
        hand = value.second?.location3D
    }

    #if DEBUG
    /// A stand-in's word: touched 100 pt along and 20 pt down, the hand at
    /// the space's origin, and moved `points` since.
    init(standingInFor points: SIMD3<Double>) {
        start = CGPoint(x: 100, y: 20)
        location = CGPoint(x: 100 + points.x, y: 20 + points.y)
        translation = Vector3D(x: points.x, y: points.y, z: points.z)
        handStart = .zero
        hand = Point3D(x: points.x, y: points.y, z: points.z)
    }
    #endif
}

/// `meters` for a trace: "0.214 m".
private func surfacePressMeters(_ meters: Double) -> String {
    String(format: "%.3f m", meters)
}

/// `seconds` for a trace: "0.50 s".
private func surfacePressSeconds(_ seconds: Double) -> String {
    String(format: "%.2f s", seconds)
}

/// How far the hand moved, in centimeters, for a trace: "2.3 cm".
private func surfacePressCentimeters(_ moved: SIMD3<Double>) -> String {
    String(format: "%.1f cm", (moved * moved).sum().squareRoot() * 100)
}
#endif
