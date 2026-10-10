/// Which hand.
public enum HandSide: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
    case left
    case right
}

/// The numbers a hand's pinch is told by, from hand tracking's thumb and
/// index fingertips: how near they come to close it, how far apart to open
/// it, and how long a pinched hand may go untracked before it's taken as
/// let go.
///
/// Hand tracking places each joint at its middle, so tips pressed together
/// stand a finger's thickness apart: about 1.5 cm. A pinch closes below
/// 2 cm and opens past 3.5 cm, the gap between them keeping a pinch the
/// hand carries from flickering open and shut as the tracking jitters a
/// few millimeters.
public struct HandPinchTuning: Equatable, Sendable, Codable {
    /// How near the fingertips come to close a pinch, in meters: 2 cm.
    public var closesBelow: Double
    /// How far apart they go to open it, in meters: 3.5 cm.
    public var opensAbove: Double
    /// How long a pinched hand may go untracked, in seconds, before its
    /// pinch is taken as let go: three tenths, a hand that has left the
    /// tracking's view.
    public var lostAfter: Double

    public init(closesBelow: Double = 0.02, opensAbove: Double = 0.035, lostAfter: Double = 0.3) {
        self.closesBelow = closesBelow
        self.opensAbove = opensAbove
        self.lostAfter = lostAfter
    }

    /// How long a pinched hand may go untracked.
    public var lostTime: Duration { .seconds(lostAfter) }
}

extension HandPinchTuning: Tunable {
    public static var defaults: HandPinchTuning { HandPinchTuning() }

    public static let parameters: [TuningParameter<HandPinchTuning>] = [
        .number(\.closesBelow, key: "closesBelow", title: "A hand's pinch closes below", unit: "m", range: 0.005...0.05, step: 0.001),
        .number(\.opensAbove, key: "opensAbove", title: "A hand's pinch opens past", unit: "m", range: 0.01...0.08, step: 0.001),
        .number(\.lostAfter, key: "lostAfter", title: "A pinched hand untracked is let go after", unit: "s", range: 0.05...2, step: 0.05),
    ]
}

/// One hand's pinch as hand tracking tells it, update by update: whether
/// its thumb and index fingertips are pinched, since when, and where the
/// pinch is, their midpoint, in meters in the space hand tracking reports
/// in, an immersive space's own.
public struct HandPinch: Equatable, Sendable {
    /// What an update did to the pinch.
    public enum Change: String, Equatable, Sendable {
        /// The fingertips came together: a pinch closed.
        case closed
        /// They came apart: the pinch opened, let go.
        case opened
        /// The hand went untracked, pinched, for longer than the tuning
        /// allows: taken as let go.
        case lost
    }

    /// Whether the hand is pinched.
    public private(set) var isPinched = false
    /// When its pinch closed; nil while it isn't pinched.
    public private(set) var closedAt: ContinuousClock.Instant?
    /// Where the pinch is, the fingertips' midpoint, as last seen; nil
    /// before the hand is seen.
    public private(set) var position: SIMD3<Float>?
    /// How far apart the fingertips were as last seen, in meters.
    public private(set) var gap: Double?
    /// When the hand was last seen.
    public private(set) var lastSeen: ContinuousClock.Instant?

    public init() {}

    /// The hand was seen at `now`, its thumb tip at `thumbTip` and its index
    /// tip at `indexTip`, in meters: its pinch closes as they come within
    /// the tuning's closing gap, and opens as they go past its opening gap.
    @discardableResult
    public mutating func saw(thumbTip: SIMD3<Float>, indexTip: SIMD3<Float>, at now: ContinuousClock.Instant, tuning: HandPinchTuning) -> Change? {
        let difference = thumbTip - indexTip
        let gap = Double((difference * difference).sum().squareRoot())
        guard gap.isFinite else { return nil }
        self.gap = gap
        position = (thumbTip + indexTip) / 2
        lastSeen = now
        if !isPinched, gap < tuning.closesBelow {
            isPinched = true
            closedAt = now
            return .closed
        }
        if isPinched, gap > tuning.opensAbove {
            isPinched = false
            closedAt = nil
            return .opened
        }
        return nil
    }

    /// The hand isn't tracked at `now`: a pinched hand unseen for longer
    /// than the tuning allows is taken as let go.
    @discardableResult
    public mutating func unseen(at now: ContinuousClock.Instant, tuning: HandPinchTuning) -> Change? {
        guard isPinched, let lastSeen, now - lastSeen > tuning.lostTime else { return nil }
        isPinched = false
        closedAt = nil
        return .lost
    }

    /// Which hand a press on an item came from, of `hands` at `now`: the one
    /// pinched now whose pinch closed nearest `press`, the press's time,
    /// since a button's press comes as a pinch closes, or a moment after, as
    /// a scroll view delays its content's touches; nil should neither be
    /// pinched.
    public static func hand(pinchedNearest press: ContinuousClock.Instant, among hands: [HandSide: HandPinch]) -> HandSide? {
        hands
            .compactMap { side, pinch -> (HandSide, Duration)? in
                guard pinch.isPinched, let closedAt = pinch.closedAt else { return nil }
                let apart = closedAt < press ? press - closedAt : closedAt - press
                return (side, apart)
            }
            .min { $0.1 < $1.1 }?
            .0
    }
}
