/// The numbers a carry by a grab handle goes by: how far a pinch on the
/// handle moves before it carries anything (`CarryPinch`), and how near the
/// viewer's head a carried thing may come (`HandCarry`).
///
/// The defaults are the numbers the carry was tried and settled on with, on
/// the headset.
public struct CarryTuning: Equatable, Sendable, Codable {
    /// How far a pinch must move from where it touched, in its gesture's
    /// points, before it carries anything: 8 pt, about 6 mm at 1360 pt to
    /// the meter. A drag is all a handle takes, so a pinch needn't wait
    /// longer to tell itself from a tap, and one that only touched moves
    /// nothing.
    public var startDistance: Double

    /// The nearest a carried thing's middle comes to the viewer's head, in
    /// meters: 0.3, so something pulled in toward the eyes stops short of
    /// them.
    public var nearestToHead: Float

    public init(startDistance: Double = 8, nearestToHead: Float = 0.3) {
        self.startDistance = startDistance
        self.nearestToHead = nearestToHead
    }

    /// The numbers the carry was settled on with.
    public static let standard = CarryTuning()
}

extension CarryTuning: Tunable {
    public static var defaults: CarryTuning { .standard }

    public static let parameters: [TuningParameter<CarryTuning>] = [
        .number(\.startDistance, key: "startDistance", title: "Start distance",
                unit: "pt", range: 0...40, step: 1),
        .number(\.nearestToHead, key: "nearestToHead", title: "Nearest to the head",
                unit: "m", range: 0.1...1, step: 0.01),
    ]
}
