import Foundation

/// A coast: what a scroll moved going on after the hand lets go on the move,
/// inertially, as a list flicked on iOS does, from the hand's velocity as it
/// let go (`ReleaseVelocity`), slowing exponentially until it's too slow to
/// see. Times are seconds since it set out; distances are along the axis it
/// scrolls, in meters, positive one way and negative the other.
///
/// It sets out at the hand's full speed as it let go, so what scrolled goes
/// on as it went, and slows exponentially: its speed falls by e every
/// `timeConstant`, 0.8 s by default, halving every 0.55 s, until it's down to
/// `Tuning.stoppingSpeed`, a centimeter a second, where it stops. So a release
/// at v carries it about 0.8 v meters: 0.4 m at half a meter a second, 0.8 m
/// at a meter a second. Why 0.8 s: iOS's lists slow by e every 0.5 s or so,
/// flicked by a finger on glass, where a flick sweeps a screen or more; a
/// hand pinching in the air flicks slower against a window a meter or so
/// wide, and, as its pinch opens, begins to slow before it lets go, so the
/// same half second carried a fraction of the window; 0.8 s carries a brisk
/// flick about a window, still settling within a couple of seconds, where
/// 0.9 s drifts on noticeably longer. A coast slowed evenly over half a
/// second, going a quarter as far as its speed, hardly coasted on the
/// headset.
///
/// There's no cap but the ends of what scrolls: where one lies closer than
/// the coast would go, the coast slows sooner, from the same speed, to come
/// to rest exactly there (`limited(toRoom:)`), rather than reaching it at
/// speed and stopping dead.
public struct Coast: Hashable, Sendable {
    /// Every number a coast is told by, so the lab can tune them live; the
    /// defaults are what settled on the headset.
    public struct Tuning: Hashable, Sendable, Codable {
        /// How far back from the release the hand's speed is measured, in
        /// seconds: a tenth of a second (`ReleaseVelocity`).
        public var sampleSpan: Double
        /// The slowest release that coasts, in meters a second: 5 cm a
        /// second. A hand slower than that was setting what it scrolled
        /// down, not flicking it.
        public var slowestRelease: Double
        /// The slowest coast a pinch catches, in meters a second: 5 cm a
        /// second. A pinch on a coast slower than that, almost at rest, is a
        /// tap, as any other (`pinchCatches(at:)`).
        public var slowestCatch: Double
        /// How fast a coast from a release slows: its speed falls by e every
        /// this many seconds, 0.8 s, halving every 0.55 s.
        public var timeConstant: Double
        /// The speed a coast stops at, in meters a second: a centimeter a
        /// second, about a tenth of a millimeter a frame, too slow to see
        /// stop.
        public var stoppingSpeed: Double
        /// The shortest coast worth making, in meters: half a millimeter.
        public var shortestCoast: Double

        /// A coast's tuning, each number its default unless given.
        public init(
            sampleSpan: Double = 0.1,
            slowestRelease: Double = 0.05,
            slowestCatch: Double = 0.05,
            timeConstant: Double = 0.8,
            stoppingSpeed: Double = 0.01,
            shortestCoast: Double = 0.0005
        ) {
            self.sampleSpan = sampleSpan
            self.slowestRelease = slowestRelease
            self.slowestCatch = slowestCatch
            self.timeConstant = timeConstant
            self.stoppingSpeed = stoppingSpeed
            self.shortestCoast = shortestCoast
        }

        /// GestureKit's coast.
        public static let defaults = Tuning()
    }

    /// How fast it goes as it sets out, in meters a second, positive one way
    /// and negative the other: the hand's as it let go.
    public let startingVelocity: Double
    /// How fast it slows: its speed falls by e every this many seconds. The
    /// tuning's for a coast from a release; less for one an end cut short.
    public let timeConstant: Double
    /// The numbers it's told by, its stopping speed and the slowest coast a
    /// pinch catches among them.
    public let tuning: Tuning

    /// A coast setting out at `startingVelocity`, slowing by e every
    /// `timeConstant` seconds, told by `tuning`.
    public init(startingVelocity: Double, timeConstant: Double, tuning: Tuning = Tuning()) {
        self.startingVelocity = startingVelocity
        self.timeConstant = timeConstant
        self.tuning = tuning
    }

    /// The coast a release at `velocity` makes, in meters a second along the
    /// axis it scrolls: setting out at that velocity, the hand's, and slowing
    /// by e every `Tuning.timeConstant`, until it's down to
    /// `Tuning.stoppingSpeed`; none for one slower than
    /// `Tuning.slowestRelease`, or that isn't a speed.
    public init?(releasedAt velocity: Double, tuning: Tuning = Tuning()) {
        guard velocity.isFinite, abs(velocity) >= tuning.slowestRelease else { return nil }
        self.init(startingVelocity: velocity, timeConstant: tuning.timeConstant, tuning: tuning)
    }

    /// How fast it sets out, in meters a second, either way.
    public var startingSpeed: Double { abs(startingVelocity) }

    /// Which way it goes: 1 for a positive velocity, −1 for a negative one.
    private var direction: Double { startingVelocity < 0 ? -1 : 1 }

    /// Whether it goes anywhere at all: faster than `Tuning.stoppingSpeed` as
    /// it sets out, slowing over some time.
    private var moves: Bool {
        startingSpeed > tuning.stoppingSpeed && timeConstant > 0 && timeConstant.isFinite && startingSpeed.isFinite
    }

    /// How long it lasts, in seconds: until its speed is down to
    /// `Tuning.stoppingSpeed`, the time constant times the log of how many
    /// times faster it set out; none for one that doesn't move.
    public var duration: Double {
        moves ? timeConstant * Foundation.log(startingSpeed / tuning.stoppingSpeed) : 0
    }

    /// How far it goes in all, in meters: what it sheds of its speed, down to
    /// `Tuning.stoppingSpeed`, times its time constant.
    public var distance: Double {
        moves ? direction * (startingSpeed - tuning.stoppingSpeed) * timeConstant : 0
    }

    /// How far it has gone by `time`: its starting velocity times its time
    /// constant times 1 − e^(−t/τ), from none before it sets out to all of
    /// `distance` from its end on.
    public func distance(at time: Double) -> Double {
        guard moves, !time.isNaN else { return 0 }
        guard time < duration else { return distance }
        return startingVelocity * timeConstant * -Foundation.expm1(-max(time, 0) / timeConstant)
    }

    /// How fast it goes at `time`, in meters a second: its starting velocity
    /// times e^(−t/τ), and none once it has stopped.
    public func velocity(at time: Double) -> Double {
        guard moves, !time.isNaN, time <= duration else { return 0 }
        return startingVelocity * Foundation.exp(-max(time, 0) / timeConstant)
    }

    /// How much of its distance it has gone by `time`, from 0 to 1: the
    /// curve whatever follows the coast eases by, as what scrolled and any
    /// fades along with it, so they keep in step.
    public func progress(at time: Double) -> Double {
        let whole = distance
        guard whole != 0 else { return 1 }
        return min(max(distance(at: time) / whole, 0), 1)
    }

    /// Whether a pinch that touches at `time` catches the coast, and is that
    /// catch rather than a tap (`SurfacePress.caughtACoast`): it still goes
    /// at least `Tuning.slowestCatch`. A pinch on a coast almost at rest is a
    /// tap, as any other.
    public func pinchCatches(at time: Double) -> Bool {
        abs(velocity(at: time)) >= tuning.slowestCatch
    }

    /// This coast where what it moves has only `room` to go on in its
    /// direction, in meters, as an end stops it: this coast where there's
    /// room for all of it; else one setting out at the same velocity, so
    /// nothing jolts as the hand lets go, slowing faster, so it covers
    /// exactly `room` as it comes down to `Tuning.stoppingSpeed`, coming to
    /// rest at the end rather than reaching it at speed and stopping dead.
    /// None where there's no room, or none worth coasting.
    public func limited(toRoom room: Double) -> Coast? {
        guard room.isFinite, room > tuning.shortestCoast, moves else { return nil }
        guard abs(distance) > room else { return self }
        return Coast(startingVelocity: startingVelocity, timeConstant: room / (startingSpeed - tuning.stoppingSpeed), tuning: tuning)
    }
}

extension Coast.Tuning: Tunable {
    /// The coast's numbers as the lab tunes them.
    public static let parameters: [TuningParameter<Coast.Tuning>] = [
        .number(\.sampleSpan, key: "sampleSpan", title: "Flick measured over", unit: "s", range: 0.02...0.5, step: 0.01),
        .number(\.slowestRelease, key: "slowestRelease", title: "Slowest flick that coasts", unit: "m/s", range: 0...0.5, step: 0.01),
        .number(\.slowestCatch, key: "slowestCatch", title: "Slowest coast a pinch catches", unit: "m/s", range: 0...0.5, step: 0.01),
        .number(\.timeConstant, key: "timeConstant", title: "Slows by e every", unit: "s", range: 0.1...3, step: 0.05),
        .number(\.stoppingSpeed, key: "stoppingSpeed", title: "Stops at", unit: "m/s", range: 0.001...0.1, step: 0.001),
        .number(\.shortestCoast, key: "shortestCoast", title: "Shortest coast", unit: "m", range: 0...0.01, step: 0.0005),
    ]
}
