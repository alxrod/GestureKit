import Foundation
import Testing
@testable import GestureCore

/// A coast under way, read on the caller's clock: where it is, whether it's
/// over, and whether a pinch then catches it.
@Suite struct CoastRunTests {
    private func isClose(_ a: Double, _ b: Double, within tolerance: Double = 1e-9) -> Bool {
        abs(a - b) < tolerance
    }

    /// It sets out from where it was let go, at the time it was, and goes
    /// as its coast does from then.
    @Test func itGoesAsItsCoastDoesFromWhereAndWhenItSetOut() throws {
        let run = try #require(CoastRun(releasedAt: 1, from: 0.3, at: 10))
        #expect(run.position(at: 10) == 0.3)
        #expect(run.position(at: 9) == 0.3)
        #expect(isClose(run.position(at: 10.8), 0.3 + 0.8 * (1 - exp(-1))))
        #expect(isClose(run.end, 0.3 + 0.99 * 0.8))
        #expect(isClose(run.position(at: 100), run.end))
        #expect(!run.isOver(at: 10))
        #expect(!run.isOver(at: 10 + run.coast.duration - 0.01))
        #expect(run.isOver(at: 10 + run.coast.duration))
        #expect(run.pinchCatches(at: 11))
        #expect(!run.pinchCatches(at: 13))
    }

    /// Within bounds, it comes to rest at the end it heads for, rather than
    /// passing it, either way; with room for all of it, it's as it was.
    @Test func withinBoundsItComesToRestAtAnEnd() throws {
        let forward = try #require(CoastRun(releasedAt: 1, from: 0.9, at: 0, within: 0...1))
        #expect(isClose(forward.end, 1))
        #expect(forward.coast.startingVelocity == 1)
        let backward = try #require(CoastRun(releasedAt: -1, from: 0.05, at: 0, within: 0...1))
        #expect(isClose(backward.end, 0))
        let roomy = try #require(CoastRun(releasedAt: 0.5, from: 0, at: 0, within: -5...5))
        #expect(roomy.coast == Coast(releasedAt: 0.5))
    }

    /// None for a release too slow to coast, no room to go, or a place or a
    /// time that isn't one.
    @Test func itMakesNoRunWhereThereIsNone() {
        #expect(CoastRun(releasedAt: 0.01, from: 0, at: 0) == nil)
        #expect(CoastRun(releasedAt: 1, from: 1, at: 0, within: 0...1) == nil)
        #expect(CoastRun(releasedAt: -1, from: 0, at: 0, within: 0...1) == nil)
        #expect(CoastRun(releasedAt: 1, from: .nan, at: 0) == nil)
        #expect(CoastRun(releasedAt: 1, from: 0, at: .infinity) == nil)
    }

    /// It takes its tuning: a slower decay goes farther from the same flick.
    @Test func itTakesItsTuning() throws {
        let run = try #require(CoastRun(releasedAt: 1, from: 0, at: 0, tuning: Coast.Tuning(timeConstant: 1.6)))
        #expect(isClose(run.end, 0.99 * 1.6))
    }
}
