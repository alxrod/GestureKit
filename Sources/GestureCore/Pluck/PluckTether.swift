import simd

/// How a lifted item follows the pinch that lifted it until it breaks free:
/// a damped share of the hand's move, easing toward a cap, as a scroll
/// view's content follows a pinch past its end, so the item feels held to
/// its place in its container, and the farther the hand goes, the harder it
/// pulls, until it breaks free and spawns into the room (`PluckPress`).
///
/// For a hand `d` points from where the item lifted, the item is drawn
/// `share · d · cap / (share · d + cap)` points along the same way: `share`
/// of the move at first, and never quite `cap`. At the defaults, half and
/// 20 pt, a hand 5 pt along draws it 2.2 pt, 15 pt along 5.5 pt, and 34 pt,
/// where it breaks free, 9.2 pt, by then moving it a seventh as fast as the
/// hand. Distances are in the item's points, x across, y down, z toward the
/// viewer, as its drag reports them and as it's drawn.
public struct PluckTether: Equatable, Sendable {
    /// How much of the hand's move the item follows at first.
    public var share: Double
    /// How far it follows at most, in its points, which it eases toward.
    public var cap: Double

    public init(share: Double, cap: Double) {
        self.share = share
        self.cap = cap
    }

    /// Whether it follows at all: a share and a cap, each more than 0.
    public var follows: Bool {
        share.isFinite && cap.isFinite && share > 0 && cap > 0
    }

    /// How far the item is drawn from its lifted place for a hand `distance`
    /// points from where it lifted: `share` of it at first, easing toward
    /// `cap`. None for no move, or one that isn't a number, or with the
    /// tether following nothing.
    public func followDistance(forMove distance: Double) -> Double {
        guard follows, distance.isFinite, distance > 0 else { return 0 }
        let free = share * distance
        return free * cap / (free + cap)
    }

    /// Where the item is drawn from its lifted place for a hand `move` from
    /// where it lifted: along the move, `followDistance(forMove:)` of it.
    public func follow(forMove move: SIMD3<Double>) -> SIMD3<Double> {
        let distance = (move * move).sum().squareRoot()
        guard distance.isFinite, distance > 0 else { return .zero }
        return move * (followDistance(forMove: distance) / distance)
    }
}

/// How far a lifted pinch has stretched toward breaking its item free, and
/// where the item is drawn for it, as its last move was judged: what a trace
/// says, "12 pt of 34 to break free", and what the item's drawing follows.
public struct PluckStretch: Equatable, Sendable {
    /// How far the pinch has gone toward breaking free, by the pull rule's
    /// own measure (`PluckPullRule.reach(of:)`), in the item's points.
    public var reach: Double
    /// How far it must go to break free, in the item's points.
    public var needs: Double
    /// Where the item is drawn from where it stands lifted, in its points:
    /// x across, y down, z toward the viewer (`PluckTether`).
    public var follow: SIMD3<Double>

    public init(reach: Double, needs: Double, follow: SIMD3<Double>) {
        self.reach = reach
        self.needs = needs
        self.follow = follow
    }
}
