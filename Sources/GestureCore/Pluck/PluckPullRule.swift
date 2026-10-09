/// Which moves of an armed pinch pull its item out of its container, each
/// judged from where the pinch touched, in the item's points, with +z toward
/// the viewer, so a hand already on its way out catches up as the pull arms.
public enum PluckPullRule: Equatable, Sendable, Codable {
    /// At least the pull's distance toward the viewer, and at least
    /// `depthPerDrift` deep for each unit it drifts across the container's
    /// plane, x and y measured as one distance. At the default 0.5, 1 deep
    /// for every 2 across, a move must leave the plane at about 27° or more.
    ///
    /// Held until its item lifts, a pinch has said it means the item, and
    /// its container no longer scrolls under it, so a pull may come out on
    /// a slant, as hands drift sideways and down as they come in. But a
    /// lifted pinch swept across the container, as a scroll, or pushed into
    /// it, still pulls nothing.
    case outOfThePlane(depthPerDrift: Double)

    /// At least the pull's distance toward the viewer, however far it
    /// drifts across: for trying whether the slant `outOfThePlane` asks for
    /// turns natural pulls away.
    case towardTheViewer

    /// At least the pull's distance from where the pinch touched, any way,
    /// across or in depth, toward the viewer or away: for telling whether an
    /// armed pinch's moves are heard at all.
    case anyDirection

    /// Judges a move `translation` from where the pinch touched, in the
    /// item's points with +z toward the viewer, against `threshold`, the
    /// pull's distance in the same points.
    public func judge(_ translation: SIMD3<Double>, threshold: Double) -> PluckPullJudgement {
        let (x, y, z) = (translation.x, translation.y, translation.z)
        let drift = (x * x + y * y).squareRoot()
        func judged(_ verdict: PluckPullJudgement.Verdict) -> PluckPullJudgement {
            PluckPullJudgement(depth: z, drift: drift, threshold: threshold, verdict: verdict)
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

    /// Whether a move `translation` from where the pinch touched pulls, at
    /// `threshold`: the judgement's verdict alone.
    public func isPull(_ translation: SIMD3<Double>, threshold: Double) -> Bool {
        judge(translation, threshold: threshold).isPull
    }
}

/// What the pull rule made of one move of an armed pinch, for a trace: how
/// deep and how far across it went, what it needed, and whether it pulls,
/// or why not.
public struct PluckPullJudgement: Equatable, Sendable, Codable {
    /// What the move was.
    public enum Verdict: String, Equatable, Sendable, Codable {
        /// It pulls the item out.
        case pulls
        /// It came toward the viewer less than the pull's distance, or went
        /// away from the viewer.
        case tooShallow
        /// It came far enough toward the viewer, but drifted across the
        /// container's plane more than its depth allows.
        case tooSlanted
        /// It moved less than the pull's distance any way: `anyDirection`'s
        /// only refusal.
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
    /// The pull's distance, in the item's points.
    public var threshold: Double
    /// Whether it pulls, or why not.
    public var verdict: Verdict

    public init(depth: Double, drift: Double, threshold: Double, verdict: Verdict) {
        self.depth = depth
        self.drift = drift
        self.threshold = threshold
        self.verdict = verdict
    }

    /// Whether the move pulls the item out.
    public var isPull: Bool {
        verdict == .pulls
    }
}
