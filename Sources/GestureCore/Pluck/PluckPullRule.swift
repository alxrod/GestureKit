/// Which moves of a lifted pinch break its item free of its container, once
/// its pull has armed, each judged as a move from where the tuning measures
/// it (`PluckPullOrigin`), in the item's points, with +z toward the viewer.
public enum PluckPullRule: Equatable, Sendable, Codable {
    /// At least the break-free distance toward the viewer, and at least
    /// `depthPerDrift` deep for each unit it drifts across the container's
    /// plane, x and y measured as one distance. At 0.5, 1 deep for every 2
    /// across, a move must leave the plane at about 27° or more: the rule
    /// the pluck first shipped with.
    ///
    /// Held until its item lifts, a pinch has said it means the item, and
    /// its container no longer scrolls under it, so a pull may come out on
    /// a slant, as hands drift sideways and down as they come in. But a
    /// lifted pinch swept across the container, as a scroll, or pushed into
    /// it, still pulls nothing.
    case outOfThePlane(depthPerDrift: Double)

    /// At least the break-free distance toward the viewer, however far it
    /// drifts across: for trying whether the slant `outOfThePlane` asks for
    /// turns natural pulls away.
    case towardTheViewer

    /// At least the break-free distance any way, across or in depth, toward
    /// the viewer or away: the default. A lifted item's container no longer
    /// scrolls under it, so no move of its pinch can be a scroll, and on the
    /// headset the drag's depth comes through small and coarse, in steps of
    /// about 4 pt, while a hand coming out drifts across as far or farther,
    /// so a rule that asks for depth turns most real pulls away.
    case anyDirection

    /// Judges `move`, a lifted pinch's move from `origin`, in the item's
    /// points with +z toward the viewer, against `threshold`, the break-free
    /// distance in the same points.
    public func judge(_ move: SIMD3<Double>, threshold: Double, from origin: PluckPullOrigin) -> PluckPullJudgement {
        let (x, y, z) = (move.x, move.y, move.z)
        let drift = (x * x + y * y).squareRoot()
        func judged(_ verdict: PluckPullJudgement.Verdict) -> PluckPullJudgement {
            PluckPullJudgement(depth: z, drift: drift, threshold: threshold, verdict: verdict, origin: origin)
        }
        guard x.isFinite, y.isFinite, z.isFinite, threshold.isFinite else {
            return judged(.notANumber)
        }
        switch self {
        case .outOfThePlane(let depthPerDrift):
            guard z >= threshold else { return judged(.tooShallow) }
            guard z >= depthPerDrift * drift else { return judged(.tooSlanted) }
            return judged(.pulls)
        case .towardTheViewer:
            return judged(z >= threshold ? .pulls : .tooShallow)
        case .anyDirection:
            let distance = (drift * drift + z * z).squareRoot()
            return judged(distance >= threshold ? .pulls : .tooShort)
        }
    }

    /// Whether `move` pulls, at `threshold`: the judgement's verdict alone.
    public func isPull(_ move: SIMD3<Double>, threshold: Double) -> Bool {
        judge(move, threshold: threshold, from: .touch).isPull
    }

    /// How far `judgement`'s move went toward breaking free, by this rule's
    /// own measure, in the item's points: its distance any way, for
    /// `anyDirection`; how far it came toward the viewer, for the rules that
    /// ask for depth, none for a move away. What a trace says a held pinch
    /// has stretched, "12 pt of 34 to break free".
    public func reach(of judgement: PluckPullJudgement) -> Double {
        let reach = self == .anyDirection ? judgement.distance : judgement.depth
        return reach.isFinite ? max(reach, 0) : 0
    }
}

/// Where an armed pinch's move is measured from, as the tuning says
/// (`PluckTuning.pullOrigin`). Where the drag hadn't spoken by the lift or
/// the arming, the pinch stood within its start of the touch, and the move
/// is measured from the touch.
public enum PluckPullOrigin: String, Equatable, Sendable, Codable {
    /// Where the pinch touched the item, so a hand already on its way out
    /// catches up as the pull arms, but a hand that drifted during the hold
    /// may pull the instant it arms: as the pluck first shipped.
    case touch
    /// Where the pinch stood as its item lifted, as the drag last said: the
    /// default. A hand that drifted during the hold doesn't pull the instant
    /// it arms, and one that comes out as soon as the item lifts, in the
    /// two tenths of a second before the arming, as hands do, has that move
    /// counted, so it catches up as the pull arms.
    case lift
    /// Where the pinch stood as its pull armed, as the drag last said, so
    /// only a move made since counts, a hand's move between the lift and the
    /// arming lost.
    case arming
}

/// What the pull rule made of one move of an armed pinch, for a trace: how
/// deep and how far across it went, from where, what it needed, and
/// whether it pulls, or why not.
public struct PluckPullJudgement: Equatable, Sendable, Codable {
    /// What the move was.
    public enum Verdict: String, Equatable, Sendable, Codable {
        /// It pulls the item out.
        case pulls
        /// It came toward the viewer less than the break-free distance, or
        /// went away from the viewer.
        case tooShallow
        /// It came far enough toward the viewer, but drifted across the
        /// container's plane more than its depth allows.
        case tooSlanted
        /// It moved less than the break-free distance any way:
        /// `anyDirection`'s only refusal.
        case tooShort
        /// Something in it, or the threshold, isn't a number.
        case notANumber
    }

    /// How far toward the viewer it went, in the item's points, as the pull
    /// rule reads it: negative away from the viewer.
    public var depth: Double
    /// How far it drifted across the container's plane, in the item's
    /// points, x and y as one distance.
    public var drift: Double
    /// The break-free distance, in the item's points.
    public var threshold: Double
    /// Whether it pulls, or why not.
    public var verdict: Verdict
    /// Where the move was measured from.
    public var origin: PluckPullOrigin

    public init(depth: Double, drift: Double, threshold: Double, verdict: Verdict, origin: PluckPullOrigin) {
        self.depth = depth
        self.drift = drift
        self.threshold = threshold
        self.verdict = verdict
        self.origin = origin
    }

    /// How far it went, any way, in the item's points.
    public var distance: Double {
        (depth * depth + drift * drift).squareRoot()
    }

    /// Whether the move pulls the item out.
    public var isPull: Bool {
        verdict == .pulls
    }
}
