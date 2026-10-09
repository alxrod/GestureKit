import Foundation
import Testing
@testable import GestureCore

/// A pinch on a control, watched for a hold beside the control's drag and
/// tap.
@Suite struct HoldWatchTests {
    /// 0.6 s still, within about 7 mm, depth counting half, and a held
    /// pinch's tap ignored for a quarter second after its release.
    @Test func itWaitsSixTenthsOfASecondWithinTenPoints() {
        let tuning = HoldWatch.Tuning()
        #expect(tuning.duration == 0.6)
        #expect(tuning.stillDistance == 10)
        #expect(tuning.depthWeight == 0.5)
        #expect(tuning.heldTapGrace == 0.25)
        #expect(HoldWatch().tuning == tuning)
        #expect(HoldWatch.Tuning.defaults == tuning)
    }

    /// The lab's panel describes every number soundly.
    @Test func itsParametersAreSound() {
        #expect(HoldWatch.Tuning.parameterProblems.isEmpty)
        #expect(HoldWatch.Tuning.parameters.map(\.key) == ["duration", "stillDistance", "depthWeight", "heldTapGrace"])
    }

    @Test func aStillPinchHoldsOnceItsTimeIsUpAndItAsked() {
        var hold = HoldWatch()
        #expect(hold.stage == .waiting)
        #expect(!hold.holds)
        var asked = 0
        let held = hold.timeIsUp { asked += 1; return true }
        #expect(held)
        #expect(asked == 1)
        #expect(hold.stage == .held)
        #expect(hold.holds)
    }

    /// A hold that asks nothing, as where the hold has nothing to offer,
    /// leaves the pinch the control's.
    @Test func aHoldThatAskedNothingIsTheControlsAsEver() {
        var hold = HoldWatch()
        let held = hold.timeIsUp { false }
        #expect(!held)
        #expect(hold.stage == .gaveUp)
        #expect(!hold.holds)
    }

    @Test func aPinchWithinTenPointsStillHolds() {
        var hold = HoldWatch()
        let first = hold.move(SIMD3(6, 6, 0))
        let second = hold.move(SIMD3(9.9, 0, 0))
        #expect(!first && !second)
        let held = hold.timeIsUp { true }
        #expect(held)
    }

    /// Farther than 10 pt before its time is up, it gives the hold up for
    /// good, even back where it began, and asks nothing.
    @Test func aPinchThatMovesFartherFirstNeverHolds() {
        var hold = HoldWatch()
        let gaveUp = hold.move(SIMD3(0, 10.5, 0))
        #expect(gaveUp)
        #expect(hold.stage == .gaveUp)
        let farther = hold.move(SIMD3(30, 0, 0))
        let back = hold.move(.zero)
        #expect(!farther && !back)
        var asked = false
        let held = hold.timeIsUp { asked = true; return true }
        #expect(!held)
        #expect(!asked)
        #expect(!hold.holds)
    }

    /// A move in depth counts half: 18 pt toward the viewer is 9.
    @Test func aMoveInDepthCountsHalf() {
        var hold = HoldWatch()
        let nine = hold.move(SIMD3(0, 0, 18))
        #expect(!nine)
        #expect(hold.farthest == 9)
        let eleven = hold.move(SIMD3(0, 0, 22))
        #expect(eleven)
    }

    /// A move that isn't a number gives the hold up, rather than leaving a
    /// pinch no one can measure waiting to hold, and counts toward nothing.
    @Test func aMoveThatIsntANumberGivesTheHoldUp() {
        var hold = HoldWatch()
        let gaveUp = hold.move(SIMD3(.nan, 0, 0))
        #expect(gaveUp)
        #expect(hold.farthest == 0)
        #expect(!hold.holds)
    }

    @Test func aDragBegunNeverHolds() {
        var hold = HoldWatch()
        hold.dragBegan()
        #expect(hold.stage == .gaveUp)
        var asked = false
        let held = hold.timeIsUp { asked = true; return true }
        #expect(!held)
        #expect(!asked)
    }

    /// Once held, the rest of the pinch is the hold's, however far it
    /// moves, and it asks once.
    @Test func aHeldPinchStaysHeld() {
        var hold = HoldWatch()
        let held = hold.timeIsUp { true }
        #expect(held)
        let moved = hold.move(SIMD3(40, 0, 0))
        #expect(!moved)
        hold.dragBegan()
        #expect(hold.holds)
        var asked = false
        let stillHeld = hold.timeIsUp { asked = true; return false }
        #expect(stillHeld)
        #expect(!asked)
        #expect(hold.farthest == 40)
    }

    // MARK: Tuned

    /// Its time comes at its tuned duration, on the caller's clock, and only
    /// while it waits.
    @Test func itsTimeComesAtItsTunedDuration() {
        var standard = HoldWatch()
        #expect(!standard.isDue(after: 0.59))
        #expect(standard.isDue(after: 0.6))
        let quick = HoldWatch(tuning: HoldWatch.Tuning(duration: 0.3))
        #expect(quick.isDue(after: 0.3))
        #expect(!quick.isDue(after: 0.29))
        standard.dragBegan()
        #expect(!standard.isDue(after: 1))
    }

    /// A wider still distance, or depth weighed in full, moves where it
    /// gives up.
    @Test func itsStillDistanceAndDepthWeightAreTuned() {
        var wide = HoldWatch(tuning: HoldWatch.Tuning(stillDistance: 20))
        let fifteen = wide.move(SIMD3(15, 0, 0))
        #expect(!fifteen)
        let held = wide.timeIsUp { true }
        #expect(held)

        var fullDepth = HoldWatch(tuning: HoldWatch.Tuning(depthWeight: 1))
        let twelve = fullDepth.move(SIMD3(0, 0, 12))
        #expect(twelve)
        #expect(fullDepth.farthest == 12)
    }

    /// A tuning goes to and from JSON whole, so the lab can keep one.
    @Test func aTuningRoundTripsThroughJSON() throws {
        let tuning = HoldWatch.Tuning(duration: 0.8, stillDistance: 14)
        let data = try JSONEncoder().encode(tuning)
        #expect(try JSONDecoder().decode(HoldWatch.Tuning.self, from: data) == tuning)
    }
}
