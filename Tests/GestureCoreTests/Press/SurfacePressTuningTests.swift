import Foundation
import Testing
@testable import GestureCore

/// Where a pinch on a surface is: `x` along the surface, having moved
/// `moved` points from where it began, with the hand at `hand` in the space.
private func sample(_ x: Double, moved: SIMD3<Double>, hand: SIMD3<Double>? = nil) -> SurfacePress.Sample {
    SurfacePress.Sample(along: x, moved: moved, hand: hand)
}

/// A press reads every number from its tuning, so the lab can try others:
/// each test here gives one number another value and checks the rule moves
/// with it, where the defaults' tests (`SurfacePressTests`,
/// `SurfacePressCarryTests`) check the rule as it stands.
@Suite struct SurfacePressTuningTests {
    /// A wider still distance keeps a pinch still farther out: 14 pt still
    /// holds and picks up at 20, where it gave both up at the default 10.
    @Test func theStillDistanceIsTuned() {
        let tuning = SurfacePress.Tuning(stillDistance: 20, dragDistance: 25)
        var press = SurfacePress(at: 0.2, canHold: true, tuning: tuning)
        #expect(press.move(sample(0.21, moved: SIMD3(14, 0, 0))) == [])
        #expect(press.canStillHold)
        #expect(press.canStillPickUp)
        #expect(press.move(sample(0.215, moved: SIMD3(21, 0, 0))) == [.giveUpHold])
        #expect(!press.canStillHold)

        var standard = SurfacePress(at: 0.2, canHold: true)
        #expect(standard.move(sample(0.21, moved: SIMD3(14, 0, 0))) == [.giveUpHold])
    }

    /// A longer drag distance keeps a pinch a tap farther out, and begins
    /// its drag along there.
    @Test func theDragDistanceIsTuned() {
        let tuning = SurfacePress.Tuning(dragDistance: 30)
        var tap = SurfacePress(at: 0.2, canHold: false, tuning: tuning)
        #expect(tap.move(sample(0.215, moved: SIMD3(20, 0, 0))) == [.giveUpHold])
        #expect(tap.end() == [.tap(at: 0.2)])

        var along = SurfacePress(at: 0.2, canHold: false, tuning: tuning)
        #expect(along.move(sample(0.215, moved: SIMD3(20, 0, 0))) == [.giveUpHold])
        #expect(along.move(sample(0.222, moved: SIMD3(30, 0, 0))) == [.beginDragAlong(from: 0.2, to: 0.222)])
    }

    /// Depth weighed in full, a push of 12 pt toward the viewer is 12, past
    /// the still distance, where at half it's 6, still.
    @Test func theDepthWeightIsTuned() {
        var full = SurfacePress(at: 0.2, canHold: true, tuning: SurfacePress.Tuning(depthWeight: 1))
        #expect(full.move(sample(0.2, moved: SIMD3(0, 0, 12))) == [.giveUpHold])
        #expect(full.farthest == 12)

        var half = SurfacePress(at: 0.2, canHold: true)
        #expect(half.move(sample(0.2, moved: SIMD3(0, 0, 12))) == [])
        #expect(half.farthest == 6)
    }

    /// A shorter carry distance carries sooner once picked up, where 13 pt
    /// carries nothing at the default 27.
    @Test func theCarryDistanceIsTuned() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), tuning: SurfacePress.Tuning(carryDistance: 12))
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 13, 0), hand: SIMD3(0, 1.5, -1))) == [
            .beginCarry(.movedOncePickedUp, handMoved: .zero),
        ])

        var standard = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1))
        #expect(standard.pickUpTimerFired() == [.pickUp])
        #expect(standard.move(sample(0.2, moved: SIMD3(0, 13, 0), hand: SIMD3(0, 1.5, -1))) == [])
    }

    /// The pickup and the hold come when their tuned times do, on the
    /// caller's clock: due from their time on, and only while they still
    /// can come.
    @Test func thePickupAndTheHoldAreDueAtTheirTunedTimes() {
        let tuning = SurfacePress.Tuning(pickUpDelay: 0.25, holdDuration: 0.75)
        var press = SurfacePress(at: 0.2, canHold: true, tuning: tuning)
        #expect(!press.isPickUpDue(after: 0.2))
        #expect(press.isPickUpDue(after: 0.25))
        #expect(!press.isHoldDue(after: 0.5))
        #expect(press.isHoldDue(after: 0.75))
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(!press.isPickUpDue(after: 0.6))
        #expect(press.isHoldDue(after: 0.8))
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(!press.isHoldDue(after: 0.9))
        #expect(tuning.pickUpDelayLabel == "0.25 s")
        #expect(tuning.holdDurationLabel == "0.75 s")

        // At the defaults, half a second and a second; never for a press
        // that can't pick up or can't hold, nor one that moved off.
        let standard = SurfacePress(at: 0.2, canHold: false, canPickUp: false)
        #expect(!standard.isPickUpDue(after: 5))
        #expect(!standard.isHoldDue(after: 5))
        var movedOff = SurfacePress(at: 0.2, canHold: true)
        #expect(!movedOff.isPickUpDue(after: 0.49))
        #expect(movedOff.isPickUpDue(after: 0.5))
        #expect(movedOff.isHoldDue(after: 1))
        _ = movedOff.move(sample(0.21, moved: SIMD3(11, 0, 0)))
        #expect(!movedOff.isPickUpDue(after: 0.5))
        #expect(!movedOff.isHoldDue(after: 1))
    }

    /// A tuning goes to and from JSON whole, so the lab can keep one.
    @Test func aTuningRoundTripsThroughJSON() throws {
        let tuning = SurfacePress.Tuning(stillDistance: 12, carryDistance: 40, lift: HoldLift.Tuning(fullScale: 1.1))
        let data = try JSONEncoder().encode(tuning)
        #expect(try JSONDecoder().decode(SurfacePress.Tuning.self, from: data) == tuning)
    }

    // MARK: Which way a drag runs

    /// A drag runs along when it goes at least as far along as across, and
    /// as in depth: a diagonal runs along, and no move, or one that isn't a
    /// number, doesn't.
    @Test func aDragRunsAlongWhenAlongIsAtLeastAsFarAsEitherOtherWay() {
        #expect(SurfacePress.runsAlong(SIMD3(16, 2, 1)))
        #expect(SurfacePress.runsAlong(SIMD3(-16, 16, 0)))
        #expect(SurfacePress.runsAlong(SIMD3(10, 0, -10)))
        #expect(!SurfacePress.runsAlong(SIMD3(3, 16, 0)))
        #expect(!SurfacePress.runsAlong(SIMD3(3, 0, 16)))
        #expect(!SurfacePress.runsAlong(.zero))
        #expect(!SurfacePress.runsAlong(SIMD3(0, 5, 0)))
        #expect(!SurfacePress.runsAlong(SIMD3(.nan, 0, 0)))
        #expect(!SurfacePress.runsAlong(SIMD3(20, .infinity, 0)))
    }
}
