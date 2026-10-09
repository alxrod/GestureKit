import Foundation
import Testing
@testable import GestureCore

/// A scroll let go on the move coasts on, as a list flicked on iOS does:
/// from the hand's full speed as it let go, over the last tenth of a second,
/// slowing exponentially, by e every 0.8 s, until it's down to a centimeter a
/// second; and where an end of what scrolls would stop it, it slows sooner,
/// to come to rest exactly there.
@Suite struct CoastTests {
    private func isClose(_ a: Double, _ b: Double, within tolerance: Double = 1e-9) -> Bool {
        abs(a - b) < tolerance
    }

    @Test func itLooksBackATenthOfASecondAndSlowsByEEveryEightTenths() {
        let tuning = Coast.Tuning()
        #expect(tuning.sampleSpan == 0.1)
        #expect(tuning.slowestRelease == 0.05)
        #expect(tuning.slowestCatch == 0.05)
        #expect(tuning.timeConstant == 0.8)
        #expect(tuning.stoppingSpeed == 0.01)
        #expect(tuning.shortestCoast == 0.0005)
        #expect(ReleaseVelocity().sampleSpan == 0.1)
    }

    /// The release's speed is the hand's over the last tenth of a second,
    /// from the last place it had before then.
    @Test func theReleasesSpeedIsTheLastTenthOfASecondsMove() {
        var release = ReleaseVelocity()
        release.record(0, at: 0)
        release.record(0.1, at: 0.5)
        release.record(0.2, at: 0.9)
        release.record(0.25, at: 0.95)
        release.record(0.3, at: 1)
        #expect(isClose(release.velocity(at: 1), 1))
        // The other way, as fast.
        var backward = ReleaseVelocity()
        backward.record(0.5, at: 2)
        backward.record(0.4, at: 2.1)
        #expect(isClose(backward.velocity(at: 2.1), -1))
    }

    /// A hand held still before it lets go has no speed left: the moves
    /// stopped coming a while before the release, or came without moving.
    @Test func aHandHeldStillBeforeItLetsGoHasNoSpeed() {
        var release = ReleaseVelocity()
        release.record(0, at: 0)
        release.record(0.3, at: 0.3)
        release.record(0.3, at: 0.5)
        #expect(release.velocity(at: 0.5) == 0)
        var stopped = ReleaseVelocity()
        stopped.record(0, at: 0)
        stopped.record(0.2, at: 0.1)
        #expect(stopped.velocity(at: 0.4) == 0)
        #expect(ReleaseVelocity().velocity(at: 1) == 0)
    }

    /// Times or places that aren't numbers are left out.
    @Test func samplesThatAreNotNumbersAreLeftOut() {
        var release = ReleaseVelocity()
        release.record(0, at: 0.9)
        release.record(.nan, at: 0.95)
        release.record(0.5, at: .infinity)
        release.record(0.1, at: 1)
        #expect(isClose(release.velocity(at: 1), 1))
    }

    /// A time before the last starts afresh, as a clock that jumped back
    /// would leave the places before it meaningless.
    @Test func aTimeBeforeTheLastStartsAfresh() {
        var release = ReleaseVelocity()
        release.record(0, at: 5)
        release.record(1, at: 5.1)
        release.record(0, at: 1)
        release.record(0.1, at: 1.1)
        #expect(isClose(release.velocity(at: 1.1), 1))
    }

    // MARK: The coast

    /// A release coasts from its full speed: its speed falls by e every
    /// 0.8 s, halving every 0.55 s, so a meter a second carries what scrolls
    /// 0.79 m, as far as a hand going on at that speed for 0.8 s, less what's
    /// left once it's down to a centimeter a second, 3.7 s on.
    @Test func aReleaseCoastsFromItsFullSpeedSlowingExponentially() throws {
        let coast = try #require(Coast(releasedAt: 1))
        #expect(coast.startingVelocity == 1)
        #expect(coast.startingSpeed == 1)
        #expect(coast.timeConstant == 0.8)
        #expect(isClose(coast.velocity(at: 0), 1))
        #expect(isClose(coast.velocity(at: 0.8), exp(-1)))
        #expect(isClose(coast.velocity(at: 0.8 * log(2)), 0.5))
        #expect(isClose(coast.distance(at: 0.8), 0.8 * (1 - exp(-1))))
        #expect(isClose(coast.distance, 0.99 * 0.8))
        #expect(isClose(coast.duration, 0.8 * log(100)))
        #expect(isClose(coast.velocity(at: coast.duration), 0.01))
        // The other way, the same.
        let backward = try #require(Coast(releasedAt: -0.5))
        #expect(backward.startingVelocity == -0.5)
        #expect(isClose(backward.distance, -0.49 * 0.8))
        #expect(isClose(backward.velocity(at: 0.8), -0.5 * exp(-1)))
        #expect(isClose(backward.distance(at: 0.8), -0.5 * 0.8 * (1 - exp(-1))))
    }

    /// No small cap: a hard flick goes as far as its speed carries it, a
    /// window and more, where every coast once stopped within 0.6 m.
    @Test func aHardFlickIsNotCapped() throws {
        let flung = try #require(Coast(releasedAt: 4))
        #expect(isClose(flung.distance, 3.99 * 0.8))
        #expect(flung.distance > 3)
        #expect(isClose(flung.duration, 0.8 * log(400)))
    }

    /// A release slower than 5 cm a second was setting what scrolled down,
    /// not flicking it: it doesn't coast, nor one that isn't a speed.
    @Test func aSlowReleaseDoesntCoast() {
        #expect(Coast(releasedAt: 0.04) == nil)
        #expect(Coast(releasedAt: -0.04) == nil)
        #expect(Coast(releasedAt: .nan) == nil)
        #expect(Coast(releasedAt: .infinity) == nil)
        #expect(Coast(releasedAt: 0.05) != nil)
    }

    /// The coast's curve, which whatever follows it eases by: from nothing,
    /// rising as it goes on, never back, to all of it by its end, where it
    /// stays; its distance at each time is that share of the whole.
    @Test func theCoastsCurveRisesSmoothlyToItsEnd() throws {
        let coast = try #require(Coast(releasedAt: 0.7))
        #expect(coast.progress(at: 0) == 0)
        #expect(coast.progress(at: -1) == 0)
        var last = 0.0
        for step in 1...200 {
            let t = coast.duration * Double(step) / 200
            let progress = coast.progress(at: t)
            #expect(progress > last)
            #expect(isClose(coast.distance(at: t), progress * coast.distance))
            last = progress
        }
        #expect(isClose(coast.progress(at: coast.duration), 1))
        #expect(coast.progress(at: coast.duration + 5) == 1)
        #expect(isClose(coast.distance(at: coast.duration + 5), coast.distance))
        #expect(coast.velocity(at: coast.duration + 0.01) == 0)
        // Its speed at the start is the release's, the hand's speed as it
        // let go, so what scrolled goes on as it went.
        let start = (coast.distance(at: 0.001) - coast.distance(at: 0)) / 0.001
        #expect(isClose(start, 0.7, within: 0.001))
    }

    /// A coast that doesn't move goes nowhere, and is all done at once.
    @Test func aCoastThatDoesntMoveGoesNowhere() {
        let still = Coast(startingVelocity: 0.005, timeConstant: 0.8)
        #expect(still.duration == 0)
        #expect(still.distance == 0)
        #expect(still.distance(at: 1) == 0)
        #expect(still.velocity(at: 0) == 0)
        #expect(still.progress(at: 0) == 1)
        #expect(!still.pinchCatches(at: 0))
    }

    /// Where an end lies closer than the coast would go, it slows sooner, to
    /// come to rest there: from the same speed, so nothing jolts as the hand
    /// lets go, decaying faster, its distance exactly the room, which it
    /// never passes, its speed down to a centimeter a second as it arrives.
    /// A hard clip would carry it to the end at speed and stop it dead.
    @Test func aCoastAnEndCutsShortComesToRestThereFromTheSameSpeed() throws {
        let coast = try #require(Coast(releasedAt: 1))
        let cut = try #require(coast.limited(toRoom: 0.1))
        #expect(cut.startingVelocity == 1)
        #expect(isClose(cut.distance, 0.1))
        #expect(isClose(cut.timeConstant, 0.1 / 0.99))
        #expect(isClose(cut.velocity(at: cut.duration), 0.01))
        #expect(cut.duration < coast.duration)
        for step in 0...100 {
            #expect(cut.distance(at: cut.duration * Double(step) / 100) <= 0.1 + 1e-12)
        }
        // Room for all of it: it's as it was.
        #expect(coast.limited(toRoom: 0.8) == coast)
        // The other way, as far.
        let backward = try #require(Coast(releasedAt: -1)?.limited(toRoom: 0.1))
        #expect(isClose(backward.distance, -0.1))
        #expect(backward.startingVelocity == -1)
        // No room, or none worth coasting: no coast.
        #expect(coast.limited(toRoom: 0) == nil)
        #expect(coast.limited(toRoom: 0.0004) == nil)
        #expect(coast.limited(toRoom: -0.2) == nil)
        #expect(coast.limited(toRoom: .nan) == nil)
    }

    /// A pinch on a coast catches it, and is the catch, not a tap, while it
    /// still goes on at 5 cm a second or more, as a coast starts; slower
    /// than that, almost at rest, the pinch is a tap as any other.
    @Test func aCoastStillGoingFiveCentimetersASecondIsCaughtNotTapped() throws {
        let coast = try #require(Coast(releasedAt: 1))
        #expect(coast.pinchCatches(at: 0))
        // Down to 5 cm a second 0.8 ln 20 s on, about 2.4 s.
        #expect(coast.pinchCatches(at: 2.3))
        #expect(!coast.pinchCatches(at: 2.5))
        #expect(!coast.pinchCatches(at: coast.duration + 1))
        let backward = try #require(Coast(releasedAt: -1))
        #expect(backward.pinchCatches(at: 1))
    }

    // MARK: Tuned

    /// Each number moves its rule: a longer time constant coasts farther, a
    /// slower stopping speed coasts longer, a higher slowest release lets
    /// fewer releases coast, and a lower slowest catch catches longer.
    @Test func aTunedCoastFollowsItsTuning() throws {
        let tuning = Coast.Tuning(slowestRelease: 0.2, slowestCatch: 0.02, timeConstant: 1.2, stoppingSpeed: 0.005)
        #expect(Coast(releasedAt: 0.1, tuning: tuning) == nil)
        let coast = try #require(Coast(releasedAt: 1, tuning: tuning))
        #expect(coast.timeConstant == 1.2)
        #expect(isClose(coast.distance, 0.995 * 1.2))
        #expect(isClose(coast.duration, 1.2 * log(200)))
        // Down to 2 cm a second 1.2 ln 50 s on, about 4.7 s.
        #expect(coast.pinchCatches(at: 4.6))
        #expect(!coast.pinchCatches(at: 4.8))
        // Cut short, it keeps its tuning.
        let cut = try #require(coast.limited(toRoom: 0.1))
        #expect(cut.tuning == tuning)
        #expect(isClose(cut.velocity(at: cut.duration), 0.005))
        // A shortest coast of 5 cm makes none in 4 cm of room.
        let fussy = try #require(Coast(releasedAt: 1, tuning: Coast.Tuning(shortestCoast: 0.05)))
        #expect(fussy.limited(toRoom: 0.04) == nil)
    }

    /// A longer sample span looks back farther for the hand's speed.
    @Test func aTunedReleaseLooksBackAsFarAsItsSampleSpan() {
        var release = ReleaseVelocity(tuning: Coast.Tuning(sampleSpan: 0.3))
        #expect(release.sampleSpan == 0.3)
        release.record(0, at: 0)
        release.record(0.3, at: 0.6)
        release.record(0.6, at: 0.9)
        // Measured from 0.6 s, the last place 0.3 s before the release.
        #expect(isClose(release.velocity(at: 0.9), 1))
        // Still a speed 0.25 s after the last place, past the default span.
        #expect(isClose(release.velocity(at: 1.15), 1))
        var standard = ReleaseVelocity()
        standard.record(0, at: 0)
        standard.record(0.3, at: 0.6)
        standard.record(0.6, at: 0.9)
        #expect(standard.velocity(at: 1.15) == 0)
    }

    /// A tuning goes to and from JSON whole, so the lab can keep one.
    @Test func aTuningRoundTripsThroughJSON() throws {
        let tuning = Coast.Tuning(timeConstant: 1.1, stoppingSpeed: 0.02)
        let data = try JSONEncoder().encode(tuning)
        #expect(try JSONDecoder().decode(Coast.Tuning.self, from: data) == tuning)
    }
}
