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
        /// (`HoldLift`).
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
