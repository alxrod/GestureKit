/// How fast the hand moved as it let go of a scroll, which a coast sets out
/// at (`Coast(releasedAt:tuning:)`). It's told where the hand was along the
/// axis it scrolls as the scroll moved, with when, on whatever clock the
/// caller keeps, in seconds (`record(_:at:)`), and gives the hand's velocity
/// over the last `sampleSpan` before the release (`velocity(at:)`): a hand
/// held still before it lets go has none left, so what it set down stays.
public struct ReleaseVelocity: Equatable, Sendable {
    /// One place of the hand along the axis, at a time.
    private struct Sample: Equatable, Sendable {
        var along: Double
        var time: Double
    }

    /// How far back from the release the hand's speed is measured, in
    /// seconds: the coast's tuning's, a tenth of a second by default.
    public let sampleSpan: Double

    /// The hand's places, the oldest kept from before the last `sampleSpan`.
    private var samples: [Sample] = []

    /// A tracker that measures the hand's speed over `tuning`'s sample span.
    public init(tuning: Coast.Tuning = Coast.Tuning()) {
        sampleSpan = tuning.sampleSpan
    }

    /// The hand was `along` the axis at `time`. A time or a place that isn't
    /// a number is left out; a time before the last starts afresh.
    public mutating func record(_ along: Double, at time: Double) {
        guard along.isFinite, time.isFinite else { return }
        if let last = samples.last, time < last.time {
            samples.removeAll()
        }
        samples.append(Sample(along: along, time: time))
        // Only one place from before the span is needed.
        while samples.count > 2, samples[1].time <= time - sampleSpan {
            samples.removeFirst()
        }
    }

    /// How fast the hand moved along the axis as it let go at `time`, in its
    /// unit a second: from its last place before `sampleSpan` before then, or
    /// its first, to its last. None if it had stopped coming more than
    /// `sampleSpan` before, as a hand held still before it lets go does, or
    /// had no places.
    public func velocity(at time: Double) -> Double {
        guard let last = samples.last, let first = samples.first, time.isFinite, time - last.time <= sampleSpan else { return 0 }
        let reference = samples.last { $0.time <= time - sampleSpan } ?? first
        let elapsed = last.time - reference.time
        guard elapsed > 0 else { return 0 }
        return (last.along - reference.along) / elapsed
    }
}
