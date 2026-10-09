/// A coast under way: where it set out from, along the axis it scrolls, and
/// when, on the caller's clock, in seconds, so the caller reads where it is
/// at any time (`position(at:)`), whether it's over, and whether a pinch
/// touching then catches it, and stops it there, rather than tapping.
///
/// A pinch that catches a coast stops it where it shows: the caller takes
/// `position(at:)` at the touch as where it stands, and drops the run.
public struct CoastRun: Hashable, Sendable {
    /// The coast, cut short where an end stops it.
    public let coast: Coast
    /// Where it set out from, along the axis, in meters.
    public let start: Double
    /// When it set out, on the caller's clock, in seconds.
    public let startTime: Double

    /// A run of `coast` setting out from `start` at `startTime`.
    public init(coast: Coast, from start: Double, at startTime: Double) {
        self.coast = coast
        self.start = start
        self.startTime = startTime
    }

    /// The run a release at `velocity` makes, setting out from `start` at
    /// `time`, kept within `bounds`, so it comes to rest at an end rather than
    /// passing it (`Coast.limited(toRoom:)`); none for a release too slow to
    /// coast, a place or a time that isn't one, or no room to go.
    public init?(
        releasedAt velocity: Double,
        from start: Double,
        at time: Double,
        within bounds: ClosedRange<Double> = -Double.infinity...Double.infinity,
        tuning: Coast.Tuning = .defaults
    ) {
        guard start.isFinite, time.isFinite, let coast = Coast(releasedAt: velocity, tuning: tuning) else { return nil }
        let room = coast.startingVelocity > 0 ? bounds.upperBound - start : start - bounds.lowerBound
        let limited = room.isFinite ? coast.limited(toRoom: room) : coast
        guard let limited else { return nil }
        self.init(coast: limited, from: start, at: time)
    }

    /// Where it is at `time`: where it set out from, and as far as the coast
    /// has gone by then.
    public func position(at time: Double) -> Double {
        start + coast.distance(at: time - startTime)
    }

    /// Where it comes to rest.
    public var end: Double {
        start + coast.distance
    }

    /// Whether it's over at `time`, come to rest.
    public func isOver(at time: Double) -> Bool {
        !(time - startTime < coast.duration)
    }

    /// Whether a pinch touching at `time` catches it, and is that catch,
    /// rather than a tap (`Coast.pinchCatches(at:)`).
    public func pinchCatches(at time: Double) -> Bool {
        coast.pinchCatches(at: time - startTime)
    }
}
