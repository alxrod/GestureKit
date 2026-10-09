/// One pinch on a surface, from the moment it touches to its end, told as a
/// tap, a drag along, a scroll, a drag across, a pickup and a carry, or a hold
/// as it goes, by how far it moves, which way, and whether it's still when its
/// pickup's and its hold's times come. The surface takes every pinch as one
/// drag from its touch, which feeds this, so none of these waits on another
/// gesture to fail: a long press standing in front of a drag and a tap, as
/// a high-priority gesture, once took every pinch on the headset from them,
/// so a surface that could hold could never be tapped or dragged.
///
/// - **A tap**: it ends within `Tuning.dragDistance` of where it began,
///   before it picked up, or any hold fired: a tap where it began. But a
///   pinch that caught a coast as it touched (`caughtACoast`), what's on the
///   surface still going on from a scroll let go, is that catch, and no tap,
///   as a list flicked on iOS stops under a finger without the tap selecting
///   what's under it.
/// - **A drag along**: once it has moved `Tuning.dragDistance` from where it
///   began, before it picked up, it drags along if that move runs along the
///   surface (`runsAlong(_:)`), from where it began to where it is, then on
///   as it moves, whichever way, until it ends. A drag is told once, so one
///   that turns sideways later never jumps back.
/// - **A scroll**: on a pinch whose drag along scrolls
///   (`dragAlongScrolls`), it scrolls instead, by the hand's move in the
///   space since the pinch began, so what scrolls catches up with the hand,
///   then by every move from there, until it ends, when it may coast
///   (`Coast`). Its moves are the space's, not the surface's, since the
///   surface moves under the hand as it scrolls.
/// - **A drag across**: moved that far any other way, across the surface, up
///   or down in its plane, or in depth, before it picked up, it does nothing
///   however far it goes, and it's no tap. Letting one carry plucked things
///   out of where they stood too easily.
/// - **A pickup**: held still within `Tuning.stillDistance` for
///   `Tuning.pickUpDelay`, which the caller times (`pickUpTimerFired()`), it
///   picks up what's under it, if it `canPickUp`, showing it lifting
///   (`HoldLift`). Moved farther before then, it gives the pickup up for
///   good, as it gives up a hold (`Action.giveUpHold`), and is a drag along,
///   a scroll, a drag across, or a tap, as above. The caller may refuse the
///   pickup (`refusePickUp()`), as for something that can't be carried now;
///   the pinch then goes on as one that never could.
/// - **A carry**: once it has picked up, a move of more than
///   `Tuning.carryDistance` any way, depth counting in full, carries what it
///   picked up, before any hold fires (`CarryReason.movedOncePickedUp`). The
///   carried thing follows the hand, by the hand's move in the space since
///   the pinch began, so it catches up with the hand, then by every move from
///   there; let go, it drops where it's held, and cancelled, it goes back.
///   Picked up, it neither drags along nor scrolls; let go, or cancelled,
///   short of a carry, it's put down where it was (`Action.putDown`), and no
///   tap. The caller may refuse the carry (`refuseCarry()`), and the rest of
///   the pinch then does nothing.
/// - **A hold**: on a surface that `canHold`, still within
///   `Tuning.stillDistance` of where it began as its hold's time comes,
///   `Tuning.holdDuration` after it touched, which the caller times, it holds,
///   whether or not it picked up on the way. It carries nothing after that:
///   its moves do nothing, and its end ends the hold, never a tap too. Moved
///   farther before its time is up, it gives the hold up for good, staying
///   picked up if it had.
///
/// A cancel ends what the pinch began, as its release would, a drag along
/// landing and a hold ending, but is never a tap, and a carry it cancels goes
/// back. Once it has ended, or been cancelled, it does nothing more.
///
/// Distances from where it began are in the surface's own points, in all
/// three dimensions, so a push in depth counts as a move: x along the
/// surface, y across it, and z toward the viewer. Places along the surface
/// are in whatever unit the caller gives them, which the press only passes
/// back. The hand's place in the space is in meters, with y up.
public struct SurfacePress: Equatable, Sendable {
    /// Why a pinch carries what it picked up, for the log.
    public enum CarryReason: Equatable, Sendable, CustomStringConvertible {
        /// It was held still until it picked up, then moved more than
        /// `Tuning.carryDistance`, any way, before any hold fired.
        case movedOncePickedUp

        public var description: String {
            switch self {
            case .movedOncePickedUp: "it was held still until it picked up, then moved"
            }
        }
    }

    /// Where the pinch is at one of its moves, as the surface's two drags
    /// have it: one in the surface's own points, one in the space's.
    public struct Sample: Equatable, Sendable {
        /// Where along the surface, in the caller's unit.
        public var along: Double
        /// How far it has moved from where it began, in the surface's points:
        /// along the surface, up or down, and toward or away from the viewer.
        public var moved: SIMD3<Double>
        /// Where the hand is in the space, in meters, with y up; nil while the
        /// drag in the space's points hasn't said.
        public var hand: SIMD3<Double>?

        public init(along: Double, moved: SIMD3<Double>, hand: SIMD3<Double>? = nil) {
            self.along = along
            self.moved = moved
            self.hand = hand
        }
    }

    /// What the pinch has been told to be so far.
    public enum Stage: Equatable, Sendable {
        /// Nothing yet: it's a tap if it ends now, within
        /// `Tuning.dragDistance`.
        case undecided
        /// A drag along the surface.
        case draggingAlong
        /// A drag that didn't run along the surface, before it picked up,
        /// which does nothing; or one whose carry was refused, which does
        /// nothing.
        case draggingAcross
        /// Held still for its hold, which its moves leave alone and its end
        /// ends.
        case held
        /// A scroll, which the hand's moves in the space move.
        case scrolling
        /// A carry of what it picked up, which the hand's moves in the space
        /// move.
        case carrying
        /// Ended, or cancelled.
        case over
    }

    /// What the surface does as the pinch is told.
    public enum Action: Equatable, Sendable {
        /// A tap `at` this place along the surface, where the pinch began.
        case tap(at: Double)
        /// A drag along begins where the pinch began, `from`, and moves to
        /// where it is now, `to`.
        case beginDragAlong(from: Double, to: Double)
        /// The drag along moves `to` this place along the surface.
        case moveDragAlong(to: Double)
        /// The drag along lands, released or cancelled.
        case endDragAlong
        /// The pinch moved `Tuning.dragDistance` another way than along the
        /// surface, before it picked up: it does nothing.
        case ignoreDragAcross
        /// The pinch moved farther than `Tuning.stillDistance` while it still
        /// could pick up, or hold: it gives up the pickup and the hold before
        /// it picked up, or, once it had, the hold alone, staying picked up
        /// (`isPickedUp`). Nothing to do, but worth saying.
        case giveUpHold
        /// The pinch was held still until it picked up, `Tuning.pickUpDelay`:
        /// from now on a move of `Tuning.carryDistance` any way carries, and
        /// it neither drags along nor scrolls.
        case pickUp
        /// The pinch, which had picked up, was let go or cancelled without
        /// carrying or holding: what it picked up is put down where it was,
        /// and it's no tap.
        case putDown
        /// The hold fires.
        case fireHold
        /// The hold ends, released or cancelled, having carried nothing.
        case endHold
        /// A scroll begins, the hand having moved `handMoved` since the pinch
        /// began, in meters in the space, with y up: what scrolls moves as
        /// far, catching up with the hand.
        case beginScroll(handMoved: SIMD3<Double>)
        /// The scroll moves, the hand having moved `handMoved` since the pinch
        /// began.
        case moveScroll(handMoved: SIMD3<Double>)
        /// The scroll ends: let go, `coasting` on as far as its momentum
        /// carries it, or cancelled, stopping where it is.
        case endScroll(coasting: Bool)
        /// The pinch, which caught a coast as it touched, was let go where it
        /// began: it was the catch, and no tap.
        case endCatch
        /// A carry begins, for `reason`, the hand having moved `handMoved`
        /// since the pinch began, in meters in the space, with y up: what's
        /// carried moves as far, catching up with the hand.
        case beginCarry(CarryReason, handMoved: SIMD3<Double>)
        /// The carry moves, the hand having moved `handMoved` since the pinch
        /// began.
        case moveCarry(handMoved: SIMD3<Double>)
        /// The carry ends, let go: what's carried drops where it's held.
        case endCarry
        /// The carry is cancelled: what's carried goes back where it was.
        case cancelCarry
    }

    /// The numbers the press is told by.
    public let tuning: Tuning
    /// Where the pinch began along the surface, where a tap is, and where a
    /// drag along begins.
    public let start: Double
    /// Whether the pinch can hold, held still for `Tuning.holdDuration`.
    public let canHold: Bool
    /// Whether a drag along the surface scrolls rather than dragging along
    /// it.
    public let dragAlongScrolls: Bool
    /// Whether the pinch caught a coast as it touched, which it stopped: let
    /// go where it began, it's that catch, not a tap; a drag, a carry, or a
    /// hold goes on as from any pinch.
    public let caughtACoast: Bool
    /// Whether the pinch can pick up what's under it, held still for
    /// `Tuning.pickUpDelay`, and then carry it.
    public let canPickUp: Bool
    /// What it has been told to be so far.
    public private(set) var stage = Stage.undecided
    /// The farthest it has moved from where it began, in points, with depth
    /// counting as `Tuning.depthWeight` says.
    public private(set) var farthest = 0.0
    /// How far it had moved from where it began at its latest move, in
    /// points: x along the surface, y across it, z in depth, for a log to say
    /// which way it went.
    public private(set) var moved = SIMD3<Double>(0, 0, 0)
    /// Whether it has picked up, held still for `Tuning.pickUpDelay`
    /// (`pickUpTimerFired()`): from then on it carries once it has moved
    /// `Tuning.carryDistance` any way, and neither drags along nor scrolls.
    public private(set) var isPickedUp = false

    /// Whether it has moved farther than `Tuning.stillDistance`, which gives
    /// up the pickup, and the hold, for good.
    private var movedTooFarToHold = false
    /// Whether the caller refused its pickup (`refusePickUp()`).
    private var pickUpRefused = false
    /// Where the hand was last, in the space.
    private var hand: SIMD3<Double>?
    /// Where the hand was as the pinch began, which a scroll and a carry
    /// measure from; or, if the space's drag hadn't said then, where it first
    /// says.
    private var handOrigin: SIMD3<Double>?

    /// A pinch that begins `at` this place along the surface, with the hand
    /// at `hand` in the space, if the space's drag has said; which holds,
    /// held still, if it `canHold`; whose drag along scrolls, if it
    /// `dragAlongScrolls`, or else drags along; which caught a coast as it
    /// touched, if it `caughtACoast`; and which picks up what's under it,
    /// held still, and carries it, if it `canPickUp`; told by `tuning`.
    public init(
        at start: Double,
        canHold: Bool,
        hand: SIMD3<Double>? = nil,
        dragAlongScrolls: Bool = false,
        caughtACoast: Bool = false,
        canPickUp: Bool = true,
        tuning: Tuning = Tuning()
    ) {
        self.tuning = tuning
        self.start = start
        self.canHold = canHold
        self.dragAlongScrolls = dragAlongScrolls
        self.caughtACoast = caughtACoast
        self.canPickUp = canPickUp
        self.hand = hand.flatMap(Self.place)
        handOrigin = self.hand
    }

    /// Whether a drag that has moved `moved`, along the surface, up or down,
    /// and toward or away from the viewer, all in one unit, runs along the
    /// surface: at least as far along it as up or down, and as in depth. A
    /// diagonal runs along, since the surface's own drag gets the benefit of
    /// the doubt. No move, or one that isn't a number, doesn't.
    public static func runsAlong(_ moved: SIMD3<Double>) -> Bool {
        guard moved.x.isFinite, moved.y.isFinite, moved.z.isFinite, moved.x != 0 else { return false }
        return abs(moved.x) >= abs(moved.y) && abs(moved.x) >= abs(moved.z)
    }

    /// Whether its hold can still fire: it can hold, and it's still
    /// undecided, never having moved farther than `Tuning.stillDistance`.
    public var canStillHold: Bool {
        canHold && stage == .undecided && !movedTooFarToHold
    }

    /// Whether it can still pick up: it can, and it's still undecided, never
    /// having moved farther than `Tuning.stillDistance`, not picked up yet,
    /// nor refused.
    public var canStillPickUp: Bool {
        canPickUp && stage == .undecided && !movedTooFarToHold && !isPickedUp && !pickUpRefused
    }

    /// Whether its pickup's time has come, `elapsed` seconds after the pinch
    /// began, on the caller's clock: it's `Tuning.pickUpDelay` or more, and
    /// it can still pick up. The caller then asks whether it may, and calls
    /// `pickUpTimerFired()` or `refusePickUp()`.
    public func isPickUpDue(after elapsed: Double) -> Bool {
        elapsed >= tuning.pickUpDelay && canStillPickUp
    }

    /// Whether its hold's time has come, `elapsed` seconds after the pinch
    /// began, on the caller's clock: it's `Tuning.holdDuration` or more, and
    /// it can still hold. The caller then calls `holdTimerFired()`.
    public func isHoldDue(after elapsed: Double) -> Bool {
        elapsed >= tuning.holdDuration && canStillHold
    }

    /// Its pickup's time is up, `Tuning.pickUpDelay` after the pinch began,
    /// as the caller times it: it picks up if it still can
    /// (`canStillPickUp`), and from now on carries once it has moved
    /// `Tuning.carryDistance` any way, before any hold fires, and neither
    /// drags along nor scrolls.
    public mutating func pickUpTimerFired() -> [Action] {
        guard canStillPickUp else { return [] }
        isPickedUp = true
        return [.pickUp]
    }

    /// The pickup the pinch could make, as its time came, can't be made now,
    /// as the caller found, as for something that can't be carried now: it
    /// picks nothing up for the rest of the pinch, which goes on as one that
    /// never could, its hold included. Nothing for a pinch that can't pick
    /// up any more.
    public mutating func refusePickUp() {
        guard canStillPickUp else { return }
        pickUpRefused = true
    }

    /// The carry the pinch began couldn't begin, as the caller found: the
    /// rest of the pinch does nothing, asking for no carry again, and its end
    /// is no tap. Nothing for a pinch that isn't carrying.
    public mutating func refuseCarry() {
        guard stage == .carrying else { return }
        stage = .draggingAcross
    }

    /// The pinch moved to `sample`. Undecided, it gives up its pickup and its
    /// hold once it's farther than `Tuning.stillDistance` from where it
    /// began, and once `Tuning.dragDistance` from it, begins a drag along, or
    /// a scroll, or else is a drag across, which does nothing; picked up, it
    /// carries once it's past `Tuning.carryDistance` any way. A drag along
    /// moves; a scroll and a carry move by the hand's move in the space since
    /// the pinch began; a drag across and a hold carry nothing. A move that
    /// isn't a number, or a hand that isn't a place, moves nothing.
    public mutating func move(_ sample: Sample) -> [Action] {
        let reported = sample.hand.flatMap(Self.place)
        if let reported {
            hand = reported
        }
        switch stage {
        case .undecided:
            return tell(from: sample)
        case .draggingAlong:
            guard sample.along.isFinite else { return [] }
            return [.moveDragAlong(to: sample.along)]
        case .scrolling:
            guard let handMoved = handMoved(reported: reported) else { return [] }
            return [.moveScroll(handMoved: handMoved)]
        case .carrying:
            guard let handMoved = handMoved(reported: reported) else { return [] }
            return [.moveCarry(handMoved: handMoved)]
        case .draggingAcross, .held, .over:
            return []
        }
    }

    /// The hold's time is up, `Tuning.holdDuration` after the pinch began, as
    /// the caller times it: it holds if it still can (`canStillHold`).
    public mutating func holdTimerFired() -> [Action] {
        guard canStillHold else { return [] }
        stage = .held
        return [.fireHold]
    }

    /// The pinch was released: undecided, it puts down what it picked up,
    /// had it picked up; or else it's a tap where it began, if it stayed
    /// within `Tuning.dragDistance`, or, had it caught a coast as it touched,
    /// the catch's end; a drag along lands, a scroll ends, coasting on as far
    /// as its momentum carries it, a carry drops what it carries where it's
    /// held, and a hold ends.
    public mutating func end() -> [Action] {
        let was = stage
        stage = .over
        switch was {
        case .undecided:
            if isPickedUp { return [.putDown] }
            if caughtACoast { return [.endCatch] }
            return farthest < tuning.dragDistance ? [.tap(at: start)] : []
        case .draggingAlong: return [.endDragAlong]
        case .scrolling: return [.endScroll(coasting: true)]
        case .carrying: return [.endCarry]
        case .held: return [.endHold]
        case .draggingAcross, .over: return []
        }
    }

    /// The pinch was cancelled: what it picked up is put down where it was, a
    /// drag along lands, a scroll stops where it is, without coasting, a
    /// carry goes back where it was, and a hold ends, as a release would end
    /// them, but it's no tap. A two-handed gesture beginning on the surface
    /// cancels the pinch it began with this way too.
    public mutating func cancel() -> [Action] {
        let was = stage
        stage = .over
        switch was {
        case .undecided: return isPickedUp ? [.putDown] : []
        case .draggingAlong: return [.endDragAlong]
        case .scrolling: return [.endScroll(coasting: false)]
        case .carrying: return [.cancelCarry]
        case .held: return [.endHold]
        case .draggingAcross, .over: return []
        }
    }

    /// Why the pinch carried, for `reason`, with the time it was held still
    /// for, as this press's tuning has it: "it was held still for 0.5 s until
    /// it picked up, then moved".
    public func describe(_ reason: CarryReason) -> String {
        switch reason {
        case .movedOncePickedUp:
            "it was held still for \(tuning.pickUpDelayLabel) until it picked up, then moved"
        }
    }

    /// Tells what an undecided pinch is, now it has moved to `sample`.
    private mutating func tell(from sample: Sample) -> [Action] {
        let moved = sample.moved
        guard sample.along.isFinite, moved.x.isFinite, moved.y.isFinite, moved.z.isFinite else { return [] }
        self.moved = moved
        let weighted = SIMD3(moved.x, moved.y, moved.z * tuning.depthWeight)
        let distance = (weighted * weighted).sum().squareRoot()
        farthest = max(farthest, distance)
        var actions: [Action] = []
        if distance > tuning.stillDistance, !movedTooFarToHold {
            let gaveSomethingUp = canStillHold || canStillPickUp
            movedTooFarToHold = true
            if gaveSomethingUp {
                actions.append(.giveUpHold)
            }
        }
        // Once picked up, it carries whichever way it moves, and neither
        // drags along nor scrolls.
        if isPickedUp {
            let full = (moved * moved).sum().squareRoot()
            if full > tuning.carryDistance {
                actions.append(beginCarry(.movedOncePickedUp))
            }
            return actions
        }
        let isAlong = Self.runsAlong(moved)
        if distance >= tuning.dragDistance, isAlong, dragAlongScrolls {
            stage = .scrolling
            let origin = handOrigin ?? hand
            handOrigin = origin
            let handMoved = hand.flatMap { here in origin.map { here - $0 } } ?? .zero
            actions.append(.beginScroll(handMoved: handMoved))
        } else if distance >= tuning.dragDistance, isAlong {
            stage = .draggingAlong
            actions.append(.beginDragAlong(from: start, to: sample.along))
        } else if distance >= tuning.dragDistance {
            stage = .draggingAcross
            actions.append(.ignoreDragAcross)
        }
        return actions
    }

    /// Begins a carry, for `reason`, by the hand's move since the pinch
    /// began, or none, if the space's drag has never said where the hand is:
    /// the carry then measures from where it first says.
    private mutating func beginCarry(_ reason: CarryReason) -> Action {
        stage = .carrying
        let origin = handOrigin ?? hand
        handOrigin = origin
        let handMoved = hand.flatMap { here in origin.map { here - $0 } } ?? .zero
        return .beginCarry(reason, handMoved: handMoved)
    }

    /// How far the hand has moved since the pinch began, now that it's at
    /// `reported`, for a scroll or a carry under way; the first place the
    /// space's drag reports is where it began, if it hadn't said before. Nil
    /// for a move it hasn't placed.
    private mutating func handMoved(reported: SIMD3<Double>?) -> SIMD3<Double>? {
        guard let reported else { return nil }
        let origin = handOrigin ?? reported
        handOrigin = origin
        return reported - origin
    }

    /// `point`, if it's a place: none of it infinite, or not a number.
    private static func place(_ point: SIMD3<Double>) -> SIMD3<Double>? {
        point.x.isFinite && point.y.isFinite && point.z.isFinite ? point : nil
    }
}
