/// The numbers placing a panel below the viewer's gaze goes by
/// (`GazePlacement`), and the handle under it that carries it
/// (`PanelHandle`).
///
/// The defaults are the numbers the placement was tried and settled on
/// with, on the headset: a panel 0.7 m out, 20° below the gaze, never
/// steeper than 60° from the head's level, drawn at 0.7, with a pill 128 by
/// 16 pt, as visionOS's window bar is, 12 pt under it.
public struct PlacementTuning: Equatable, Sendable, Codable {
    /// How far the panel's middle stands from the head, in meters: within
    /// reach, nearer than a window usually stands.
    public var distance: Float

    /// How far below the gaze the panel's middle stands, in degrees: 20°, low
    /// enough to leave the middle of the view to what's in it, and near
    /// enough to it to glance down at.
    public var belowTheGazeDegrees: Float

    /// The steepest the panel's middle stands below or above the head's
    /// level, in degrees: 60°. A gaze at the floor puts it no nearer straight
    /// below the head than that, rather than under the chin, and a gaze at
    /// the sky no nearer straight above it.
    public var steepestDegrees: Float

    /// How far out the panel, drawn at `scale`, looks as big as it does
    /// drawn whole, in meters: a meter, so that `distance` out it looks as
    /// big as an attachment does a meter out.
    public var looksAsBigAsAt: Float

    /// How much of a unit gaze must lie level for it to point somewhere
    /// across: 0.1. Within about 6° of straight up or down, it points nowhere
    /// meaningful across, and which way the face is turned is taken from the
    /// top of the head instead.
    public var leastLevelGaze: Float

    /// How big the handle's pill is drawn, in points: 128 by 16, as
    /// visionOS's window bar is.
    public var handleSize: SIMD2<Double>

    /// How far below the panel's bottom edge the pill's top stands, in
    /// points: 12.
    public var handleGap: Double

    /// How far beyond either end of the pill the handle takes looks and
    /// pinches, in points: 22.
    public var handleReachBeyondEnds: Double

    /// How tall the handle takes looks and pinches, in points, from the
    /// panel's bottom edge down: 60, the least a target should be.
    public var handleReachHeight: Double

    public init(
        distance: Float = 0.7,
        belowTheGazeDegrees: Float = 20,
        steepestDegrees: Float = 60,
        looksAsBigAsAt: Float = 1,
        leastLevelGaze: Float = 0.1,
        handleSize: SIMD2<Double> = SIMD2(128, 16),
        handleGap: Double = 12,
        handleReachBeyondEnds: Double = 22,
        handleReachHeight: Double = 60
    ) {
        self.distance = distance
        self.belowTheGazeDegrees = belowTheGazeDegrees
        self.steepestDegrees = steepestDegrees
        self.looksAsBigAsAt = looksAsBigAsAt
        self.leastLevelGaze = leastLevelGaze
        self.handleSize = handleSize
        self.handleGap = handleGap
        self.handleReachBeyondEnds = handleReachBeyondEnds
        self.handleReachHeight = handleReachHeight
    }

    /// The numbers the placement was settled on with.
    public static let standard = PlacementTuning()

    /// How far below the gaze the panel's middle stands, in radians.
    public var angleBelowTheGaze: Float {
        belowTheGazeDegrees * .pi / 180
    }

    /// The steepest the panel's middle stands below or above the head's
    /// level, in radians.
    public var steepest: Float {
        steepestDegrees * .pi / 180
    }

    /// How the panel is scaled, so that `distance` out it looks as big as it
    /// does drawn whole `looksAsBigAsAt` out: 0.7. Drawn whole 0.7 m out, an
    /// 860 pt panel, at 1360 pt to the meter, would be 0.63 m wide, 48°
    /// across.
    public var scale: Float {
        distance / looksAsBigAsAt
    }
}
