/// A pinch on a handle or a control, watched for a hold beside the
/// control's own drag and tap: held still for `Tuning.duration`, within
/// `Tuning.stillDistance` of where it began, it asks the caller whether the
/// hold means anything here (`timeIsUp(asking:)`), and if it does, the rest
/// of the pinch is the hold's, neither dragging nor tapping. A pinch that
/// moves farther first, or whose drag has begun (`dragBegan()`), is the
/// control's drag or tap, as ever, and so is one whose hold asks nothing, as
/// where the hold has nothing to offer.
///
/// The caller times the hold beside the control's own gestures, never in
/// front of them: a long press standing in front of other gestures once took
/// the headset's pinches from them.
///
/// Distances from where it began are in the control's points, in all three
/// dimensions, a move in depth counting as `Tuning.depthWeight` says, half
/// by default, since a pinch's own closing moves it in depth more than
/// across.
public struct HoldWatch: Equatable, Sendable {
    /// Every number a hold watch is told by, so the lab can tune them live;
    /// the defaults are what settled on the headset.
    public struct Tuning: Hashable, Sendable, Codable {
        /// How long a pinch is held still before it asks, in seconds: 0.6 s,
        /// sooner than a surface's second-long hold, as a handle's hold is
        /// a quick question rather than a change of mode.
        public var duration: Double
        /// How far a pinch may move from where it began, in points, and
        /// still hold: about 7 mm, at 1360 points to the meter.
        public var stillDistance: Double
        /// How much a move in depth counts toward that distance: half as
        /// much as one along or across the control.
        public var depthWeight: Double

        /// A hold watch's tuning, each number its default unless given.
        public init(duration: Double = 0.6, stillDistance: Double = 10, depthWeight: Double = 0.5) {
            self.duration = duration
            self.stillDistance = stillDistance
            self.depthWeight = depthWeight
        }
    }

    /// What the pinch has come to so far.
    public enum Stage: Equatable, Sendable {
        /// Still within reach of a hold, its time not yet up.
        case waiting
        /// The control's, as ever: it moved too far, or began a drag, before
        /// its time was up, or its hold asked nothing.
        case gaveUp
        /// Held: it asked, and the rest of it neither drags nor taps.
        case held
    }

    /// The numbers the watch is told by.
    public let tuning: Tuning

    /// What the pinch has come to so far.
    public private(set) var stage = Stage.waiting

    /// The farthest it has moved from where it began, in points, depth
    /// counting as `Tuning.depthWeight` says.
    public private(set) var farthest = 0.0

    /// A watch on a pinch that has just touched, told by `tuning`.
    public init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Whether its time has come, `elapsed` seconds after the pinch began, on
    /// the caller's clock, while it still waits: the caller then calls
    /// `timeIsUp(asking:)`.
    public func isDue(after elapsed: Double) -> Bool {
        stage == .waiting && elapsed >= tuning.duration
    }

    /// It has moved `moved` points from where it began: along, across, and in
    /// depth. Farther than `Tuning.stillDistance` while it waits, it gives
    /// the hold up for good. Returns whether this move gave it up.
    @discardableResult
    public mutating func move(_ moved: SIMD3<Double>) -> Bool {
        let weighted = SIMD3(moved.x, moved.y, moved.z * tuning.depthWeight)
        let distance = (weighted * weighted).sum().squareRoot()
        if distance.isFinite, distance > farthest {
            farthest = distance
        }
        guard stage == .waiting, !(distance <= tuning.stillDistance) else { return false }
        stage = .gaveUp
        return true
    }

    /// The control's own drag began: the pinch is the drag's, and never
    /// holds.
    public mutating func dragBegan() {
        if stage == .waiting {
            stage = .gaveUp
        }
    }

    /// Its time is up: if it's still waiting, it asks, by `ask`, and holds if
    /// that said the hold means something here, or else gives up, the rest of
    /// the pinch the control's, as ever. Returns whether it holds.
    public mutating func timeIsUp(asking ask: () -> Bool) -> Bool {
        if stage == .waiting {
            stage = ask() ? .held : .gaveUp
        }
        return holds
    }

    /// Whether the rest of the pinch is the hold's: it neither drags nor
    /// taps.
    public var holds: Bool {
        stage == .held
    }
}
