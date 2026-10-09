/// The handle under a panel that stands in the space with no window bar of
/// its own, as an attachment does: a pill, as visionOS's window bar is,
/// `tuning.handleSize`, centered `tuning.handleGap` under the panel, taking
/// looks and pinches over more than it draws (`reach(tuning:)`), from the
/// panel's bottom edge down. A pinch on it carries the panel by its middle
/// (`CarryPinch`), 1:1 with the hand, never nearer the head than
/// `CarryTuning.nearestToHead`, turned to face the head as it goes
/// (`HandCarry.pose(carriedTo:clearOf:from:keeping:tuning:facing:)`), and
/// the panel stays where it's let go.
///
/// In points, as the panel is drawn, before any scale it's drawn at
/// (`PlacementTuning.scale`), from the panel's middle, up for more than 0.
public enum PanelHandle {
    /// How big the handle takes looks and pinches, in points: from the
    /// panel's bottom edge, so never over the panel, whose own controls take
    /// theirs, `tuning.handleReachHeight` down, 60 pt, to 32 pt below the
    /// pill's foot; and `tuning.handleReachBeyondEnds`, 22 pt, beyond either
    /// end of the pill.
    public static func reach(tuning: PlacementTuning = .standard) -> SIMD2<Double> {
        SIMD2(tuning.handleSize.x + 2 * tuning.handleReachBeyondEnds, tuning.handleReachHeight)
    }

    /// How far the middle of its reach stands from the pill's middle, in
    /// points, up for more than 0: 10 pt below it, as its reach begins at
    /// the panel's bottom edge, `tuning.handleGap` above the pill's top.
    public static func reachOffset(tuning: PlacementTuning = .standard) -> Double {
        tuning.handleSize.y / 2 + tuning.handleGap - reach(tuning: tuning).y / 2
    }

    /// Where the pill's middle stands below the middle of a panel `height`
    /// points tall, in points, up for more than 0: its top
    /// `tuning.handleGap` below the panel's bottom edge. A height not
    /// measured yet, or that isn't one, counts as none.
    public static func middle(belowPanelOfHeight height: Double, tuning: PlacementTuning = .standard) -> Double {
        let panel = height.isFinite && height > 0 ? height : 0
        return -(panel / 2 + tuning.handleGap + tuning.handleSize.y / 2)
    }
}
