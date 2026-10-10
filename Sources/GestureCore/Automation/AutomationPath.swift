#if DEBUG
import Foundation

/// The steps of a hand's move, as the automation says them to an adapter
/// through the hand's stand-in: when each comes, from the move's start, and
/// where the hand is then, from where it touched.
///
/// A command gives a move in meters, as a hand moves in the room: x to the
/// right, y up, z toward the viewer. An adapter hears a drag in its view's
/// points: x across, y down, z toward the viewer, 1,360 to the meter, as
/// visionOS draws a view in a space (`points(ofMeters:)`).
@_spi(GestureAutomation)
public enum AutomationPath {
    /// A view's points to a meter, as visionOS draws a view in a space, and
    /// as an attachment in an immersive space is drawn.
    public static let pointsPerMeter = 1360.0

    /// How often a hand's stand-in speaks while it moves: 90 times a second,
    /// as a drag's words come on the headset.
    public static let rate = 90.0

    /// One step of a move: when it comes, in seconds from the move's start,
    /// and where the hand is then.
    public struct Step: Sendable, Equatable {
        public var time: Double
        public var point: SIMD3<Double>

        public init(time: Double, point: SIMD3<Double>) {
            self.time = time
            self.point = point
        }
    }

    /// A move from `start` to `end` over `duration` seconds, a step every
    /// `1 / rate` seconds, eased in and out as a hand's is, the last step at
    /// `end` exactly; one step, at `end`, for a move that takes no time.
    public static func steps(from start: SIMD3<Double>, to end: SIMD3<Double>, over duration: Double, rate: Double = rate) -> [Step] {
        let count = max(1, Int((max(0, duration) * rate).rounded()))
        guard duration > 0 else { return [Step(time: 0, point: end)] }
        return (1...count).map { index in
            let share = Double(index) / Double(count)
            let eased = share * share * (3 - 2 * share)
            return Step(time: duration * share, point: start + (end - start) * eased)
        }
    }

    /// A hand held still for `duration` seconds, wavering within `amplitude`
    /// of `at` as a still hand does, a step every `1 / rate` seconds.
    public static func held(at point: SIMD3<Double>, for duration: Double, wavering amplitude: Double, rate: Double = rate) -> [Step] {
        let count = Int((max(0, duration) * rate).rounded(.down))
        guard count > 0 else { return [] }
        return (1...count).map { index in
            let time = Double(index) / rate
            let waver = SIMD3(sin(time * 9), cos(time * 7) - 1, 0) * (amplitude / 2)
            return Step(time: time, point: point + waver)
        }
    }

    /// A move in meters, x right, y up, z toward the viewer, as a view's
    /// points: x across, y down, z toward the viewer.
    public static func points(ofMeters meters: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(meters.x, -meters.y, meters.z) * pointsPerMeter
    }

    /// A move in a view's points as meters, x right, y up, z toward the
    /// viewer.
    public static func meters(ofPoints points: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(points.x, -points.y, points.z) / pointsPerMeter
    }

    /// Whether a drag of `minimumDistance` points says a word with the hand
    /// `points` from where it touched: once it has spoken, every move; before
    /// that, only once the hand has gone that far, as SwiftUI's `DragGesture`
    /// begins.
    public static func dragSpeaks(at points: SIMD3<Double>, minimumDistance: Double, hasSpoken: Bool) -> Bool {
        hasSpoken || (points * points).sum().squareRoot() >= minimumDistance
    }
}
#endif
