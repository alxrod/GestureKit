/// The numbers turning to face the viewer goes by (`Facing`).
public struct FacingTuning: Equatable, Sendable, Codable {
    /// How near straight above or below a thing its target can be, in meters
    /// across, laid level, before which way across the thing turns to face it
    /// has no meaning: a millimeter. Nearer than that, a thing that keeps the
    /// way it faces does (`Facing.orientation(from:toward:keeping:tuning:)`).
    public var verticalTolerance: Float

    public init(verticalTolerance: Float = 0.001) {
        self.verticalTolerance = verticalTolerance
    }

    /// The numbers facing was settled on with.
    public static let standard = FacingTuning()
}

extension FacingTuning: Tunable {
    public static var defaults: FacingTuning { .standard }

    public static let parameters: [TuningParameter<FacingTuning>] = [
        .number(\.verticalTolerance, key: "verticalTolerance", title: "Straight above or below within",
                unit: "m", range: 0...0.05, step: 0.0005),
    ]
}
