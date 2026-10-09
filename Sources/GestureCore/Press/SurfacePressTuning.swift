import Foundation

extension SurfacePress {
    /// Every number a press is told by, so the lab can tune them live. The
    /// defaults are what settled over rounds on the headset: a pinch held
    /// still for half a second picks up what's under it, held on to a second
    /// it holds, and once picked up a move of about 2 cm carries it.
    ///
    /// Distances are in the surface's own points, as SwiftUI measures a drag
    /// on a view; at visionOS's 1360 points to the meter, 10 points is about
    /// 7 mm. Times are in seconds.
    public struct Tuning: Hashable, Sendable, Codable {
        /// How far a pinch may move from where it began, in points, and still
        /// count as held still, to pick up and to hold: about 7 mm.
        public var stillDistance: Double
        /// How far a pinch must move from where it began, in points, before
        /// it's a drag rather than a tap: about 1.1 cm, so a pinch that
        /// wavers as it taps stays a tap.
        public var dragDistance: Double
        /// How much a move in depth counts toward `stillDistance` and
        /// `dragDistance`, against one along or across the surface. A pinch's
        /// own closing moves where it's tracked toward or away from the
        /// surface more than across it, so half: a centimeter of that alone
        /// doesn't stop a still pinch being a tap, or holding, and a push of
        /// 3 cm or more still is a drag, and never one along.
        public var depthWeight: Double
        /// How far a pinch that has picked up must move from where it began,
        /// in points, to carry what it picked up: about 2 cm, past where a
        /// drag is told from a tap, so a pinch that wavers as it's let go puts
        /// it down where it was rather than carrying it a centimeter off.
        /// Depth counts in full here: a pull of 2 cm toward the viewer
        /// carries.
        public var carryDistance: Double
        /// How long a pinch is held still before it picks up, in seconds:
        /// half the hold, so a pickup comes well before the hold and reads as
        /// its own step.
        public var pickUpDelay: Double
        /// How long a pinch is held still before it holds, on a surface that
        /// can hold, in seconds: a second, a third shorter than the second
        /// and a half it was, which kept a deliberate hold waiting too long.
        public var holdDuration: Double
        /// How what the press is on lifts as it's picked up and held
        /// (`HoldLift`). It's a tuning of its own, with its own panel in the
        /// lab, rather than among this one's parameters, which are flat.
        public var lift: HoldLift.Tuning

        /// A press's tuning, each number its default unless given.
        public init(
            stillDistance: Double = 10,
            dragDistance: Double = 15,
            depthWeight: Double = 0.5,
            carryDistance: Double = 27,
            pickUpDelay: Double = 0.5,
            holdDuration: Double = 1,
            lift: HoldLift.Tuning = HoldLift.Tuning()
        ) {
            self.stillDistance = stillDistance
            self.dragDistance = dragDistance
            self.depthWeight = depthWeight
            self.carryDistance = carryDistance
            self.pickUpDelay = pickUpDelay
            self.holdDuration = holdDuration
            self.lift = lift
        }

        /// GestureKit's press.
        public static let defaults = Tuning()

        /// `pickUpDelay` as a log says it: "0.5 s".
        public var pickUpDelayLabel: String {
            Self.label(seconds: pickUpDelay)
        }

        /// `holdDuration` as a log says it: "1 s".
        public var holdDurationLabel: String {
            Self.label(seconds: holdDuration)
        }

        /// `seconds` in a log's words, as few digits as it takes: "0.5 s".
        static func label(seconds: Double) -> String {
            String(format: "%g s", seconds)
        }
    }
}

extension SurfacePress.Tuning: Tunable {
    /// The press's numbers as the lab tunes them; its lift has a panel of
    /// its own (`HoldLift.Tuning`).
    public static let parameters: [TuningParameter<SurfacePress.Tuning>] = [
        .number(\.stillDistance, key: "stillDistance", title: "Still within", unit: "pt", range: 0...40, step: 0.5),
        .number(\.dragDistance, key: "dragDistance", title: "A drag from", unit: "pt", range: 1...60, step: 0.5),
        .number(\.depthWeight, key: "depthWeight", title: "Depth counts", unit: "×", range: 0...2, step: 0.05),
        .number(\.carryDistance, key: "carryDistance", title: "Carries from", unit: "pt", range: 5...100, step: 1),
        .number(\.pickUpDelay, key: "pickUpDelay", title: "Picks up after", unit: "s", range: 0.1...2, step: 0.05),
        .number(\.holdDuration, key: "holdDuration", title: "Holds after", unit: "s", range: 0.2...4, step: 0.05),
    ]
}

extension HoldLift.Tuning: Tunable {
    /// The lift's numbers as the lab tunes them.
    public static let parameters: [TuningParameter<HoldLift.Tuning>] = [
        .number(\.pickedUpScale, key: "pickedUpScale", title: "Picked-up scale", unit: "×", range: 1...1.3, step: 0.005),
        .number(\.pickedUpDepth, key: "pickedUpDepth", title: "Picked-up depth", unit: "m", range: 0...0.1, step: 0.0025),
        .number(\.heldScale, key: "heldScale", title: "Held scale", unit: "×", range: 1...1.3, step: 0.005),
        .number(\.heldDepth, key: "heldDepth", title: "Held depth", unit: "m", range: 0...0.1, step: 0.0025),
        .number(\.popDuration, key: "popDuration", title: "Pop lasts", unit: "s", range: 0...1, step: 0.01),
        .number(\.popOvershoot, key: "popOvershoot", title: "Pop overshoots by", range: 0...0.5, step: 0.01),
        .number(\.settleDuration, key: "settleDuration", title: "Settles over", unit: "s", range: 0.05...1.5, step: 0.01),
    ]
}
