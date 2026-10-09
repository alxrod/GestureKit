import Foundation
import Testing
@testable import GestureCore

/// How something held still lifts as its press picks it up, and on toward
/// its hold, as an item lifts off its grid.
@Suite struct HoldLiftTests {
    private let press = SurfacePress.Tuning()
    private let lift = HoldLift.Tuning()

    /// Nothing until the pinch picks up, at half a second, so a tap or a
    /// drag never shows it, nor a pinch that hasn't picked up; then it pops
    /// up to five sixths of its lift in a fifth of a second.
    @Test func itPopsUpAsThePinchPicksUp() {
        #expect(press.pickUpDelay == 0.5)
        for elapsed in [0.0, 0.25, 0.499, 0.5] {
            #expect(HoldLift.progress(after: elapsed, isPickedUp: true, canStillHold: true) == 0)
        }
        #expect(HoldLift.progress(after: 0.8, isPickedUp: false, canStillHold: true) == 0)
        #expect(HoldLift.progress(after: 0.52, isPickedUp: true, canStillHold: false) > 0)
        let poppedAt = press.pickUpDelay + lift.popDuration
        #expect(abs(HoldLift.progress(after: poppedAt, isPickedUp: true, canStillHold: false) - lift.pickedUpShare) < 1e-12)
        #expect(abs(lift.pickedUpShare - 5.0 / 6) < 1e-15)
        #expect(lift.popDuration == 0.2)
    }

    /// The pop overshoots a little on the way, a tenth past picked up, as a
    /// spring with a little bounce does, never past the whole lift, so the
    /// moment it's picked up reads plainly.
    @Test func thePopOvershootsATenth() {
        var highest = 0.0
        for step in 0...400 {
            let elapsed = press.pickUpDelay + Double(step) * lift.popDuration / 400
            highest = max(highest, HoldLift.progress(after: elapsed, isPickedUp: true, canStillHold: false))
        }
        #expect(highest > lift.pickedUpShare * 1.09)
        #expect(highest < lift.pickedUpShare * 1.11)
        #expect(highest < 1)
        #expect(HoldLift.popCurve(0) == 0)
        #expect(abs(HoldLift.popCurve(1) - 1) < 1e-12)
        #expect(HoldLift.popCurve(-1) == 0)
        #expect(HoldLift.popCurve(2) == 1)
    }

    /// Picked up, a pinch still counting down to its hold rises on, quickly
    /// at first, to all of it as the hold fires, at a second, and no more
    /// after; one that can't hold, or that moved off, stays picked up.
    @Test func aPinchCountingDownRisesOnToItsHoldAndAnyOtherStaysPickedUp() {
        let poppedAt = press.pickUpDelay + lift.popDuration
        #expect(HoldLift.progress(after: press.holdDuration, isPickedUp: true, canStillHold: true) == 1)
        #expect(HoldLift.progress(after: 3, isPickedUp: true, canStillHold: true) == 1)
        var last = lift.pickedUpShare
        for step in 0...300 {
            let elapsed = poppedAt + Double(step) * (press.holdDuration - poppedAt) / 300
            let progress = HoldLift.progress(after: elapsed, isPickedUp: true, canStillHold: true)
            #expect(progress >= last - 1e-12)
            last = progress
        }
        let halfway = poppedAt + (press.holdDuration - poppedAt) / 2
        #expect(HoldLift.progress(after: halfway, isPickedUp: true, canStillHold: true) > lift.pickedUpShare + (1 - lift.pickedUpShare) * 0.6)
        for elapsed in [poppedAt, 0.8, 1.0, 5.0] {
            #expect(abs(HoldLift.progress(after: elapsed, isPickedUp: true, canStillHold: false) - lift.pickedUpShare) < 1e-12)
        }
    }

    /// A time that isn't one lifts nothing.
    @Test func aTimeThatIsntOneLiftsNothing() {
        #expect(HoldLift.progress(after: .nan, isPickedUp: true, canStillHold: true) == 0)
        #expect(HoldLift.progress(after: -1, isPickedUp: true, canStillHold: true) == 0)
        #expect(HoldLift.progress(after: .infinity, isPickedUp: true, canStillHold: true) == 0)
    }

    /// Read from a pinch, it follows the pinch's pickup and its hold: none
    /// before the pickup, the pop once picked up, the rise while its hold
    /// counts down, and picked up once it's moved off.
    @Test func itFollowsThePinch() {
        var holding = SurfacePress(at: 0.2, canHold: true)
        #expect(HoldLift.progress(after: 0.6, of: holding) == 0)
        #expect(holding.pickUpTimerFired() == [.pickUp])
        #expect(HoldLift.progress(after: 0.9, of: holding) > lift.pickedUpShare)
        _ = holding.move(SurfacePress.Sample(along: 0.21, moved: SIMD3(12, 0, 0)))
        #expect(abs(HoldLift.progress(after: 0.9, of: holding) - lift.pickedUpShare) < 1e-12)
    }

    /// The caller counts frames while the lift may still change: while the
    /// pinch may still pick up, through its pop, and while, picked up, its
    /// hold counts down; not once it gave the pickup up, nor once it stays
    /// picked up.
    @Test func itMayChangeUntilItSettles() {
        var waiting = SurfacePress(at: 0.2, canHold: false)
        #expect(HoldLift.mayChange(after: 0.1, of: waiting))
        #expect(HoldLift.mayChange(after: 0.6, of: waiting))
        #expect(waiting.pickUpTimerFired() == [.pickUp])
        #expect(HoldLift.mayChange(after: 0.6, of: waiting))
        #expect(!HoldLift.mayChange(after: press.pickUpDelay + lift.popDuration, of: waiting))

        var holding = SurfacePress(at: 0.2, canHold: true)
        #expect(holding.pickUpTimerFired() == [.pickUp])
        #expect(HoldLift.mayChange(after: 0.9, of: holding))
        #expect(!HoldLift.mayChange(after: press.holdDuration, of: holding))
        _ = holding.move(SurfacePress.Sample(along: 0.21, moved: SIMD3(12, 0, 0)))
        #expect(!HoldLift.mayChange(after: 0.9, of: holding))

        var movedOff = SurfacePress(at: 0.2, canHold: true)
        _ = movedOff.move(SurfacePress.Sample(along: 0.21, moved: SIMD3(12, 0, 0)))
        #expect(!HoldLift.mayChange(after: 0.1, of: movedOff))

        var refused = SurfacePress(at: 0.2, canHold: false)
        refused.refusePickUp()
        #expect(!HoldLift.mayChange(after: 0.6, of: refused))
        #expect(!HoldLift.mayChange(after: .nan, of: SurfacePress(at: 0.2, canHold: false)))
    }

    /// All of it scales 6% larger and brings it 3 cm toward the viewer;
    /// picked up, 5% and 2.5 cm; none leaves it as it is; in between, in
    /// proportion.
    @Test func theLiftScalesAndRaisesInProportion() {
        #expect(lift.fullScale == 1.06)
        #expect(lift.fullDepth == 0.03)
        #expect(HoldLift.scale(at: 0) == 1)
        #expect(abs(HoldLift.scale(at: 1) - 1.06) < 1e-12)
        #expect(abs(HoldLift.scale(at: 0.5) - 1.03) < 1e-12)
        #expect(abs(HoldLift.scale(at: lift.pickedUpShare) - 1.05) < 1e-12)
        #expect(HoldLift.depth(at: 0) == 0)
        #expect(abs(HoldLift.depth(at: 1) - 0.03) < 1e-12)
        #expect(abs(HoldLift.depth(at: 0.5) - 0.015) < 1e-12)
        #expect(abs(HoldLift.depth(at: lift.pickedUpShare) - 0.025) < 1e-12)
        #expect(HoldLift.scale(at: 2) == HoldLift.scale(at: 1))
        #expect(HoldLift.depth(at: -1) == 0)
        #expect(HoldLift.scale(at: .nan) == 1)
    }

    // MARK: Tuned

    /// Tuned, the lift follows its tuning and its press's: it picks up when
    /// the press does, pops for as long as it's told, overshoots as far, and
    /// rises to all of it as the tuned hold fires.
    @Test func aTunedLiftFollowsItsTuning() {
        let tuned = SurfacePress.Tuning(
            pickUpDelay: 0.3,
            holdDuration: 1.5,
            lift: HoldLift.Tuning(pickedUpShare: 0.5, popDuration: 0.1, popOvershoot: 0, fullScale: 1.2, fullDepth: 0.05)
        )
        #expect(HoldLift.progress(after: 0.3, isPickedUp: true, canStillHold: true, tunedAs: tuned) == 0)
        // With no overshoot the pop never passes picked up.
        var highest = 0.0
        for step in 0...100 {
            let elapsed = 0.3 + Double(step) * 0.1 / 100
            highest = max(highest, HoldLift.progress(after: elapsed, isPickedUp: true, canStillHold: false, tunedAs: tuned))
        }
        #expect(abs(highest - 0.5) < 1e-12)
        #expect(HoldLift.progress(after: 1.4, isPickedUp: true, canStillHold: true, tunedAs: tuned) < 1)
        #expect(HoldLift.progress(after: 1.5, isPickedUp: true, canStillHold: true, tunedAs: tuned) == 1)
        #expect(abs(HoldLift.scale(at: 1, tunedAs: tuned.lift) - 1.2) < 1e-12)
        #expect(abs(HoldLift.depth(at: 0.5, tunedAs: tuned.lift) - 0.025) < 1e-12)

        var pinch = SurfacePress(at: 0, canHold: true, tuning: tuned)
        #expect(pinch.pickUpTimerFired() == [.pickUp])
        #expect(HoldLift.mayChange(after: 1.4, of: pinch))
        #expect(!HoldLift.mayChange(after: 1.5, of: pinch))
        #expect(abs(HoldLift.progress(after: 0.4, of: pinch) - 0.5) < 1e-12)
    }

    /// A hold no longer than the pickup and its pop leaves nothing to rise
    /// through: picked up, it stays picked up, rather than dividing by a
    /// rise of none.
    @Test func aHoldTooSoonToRiseThroughStaysPickedUp() {
        let tuned = SurfacePress.Tuning(pickUpDelay: 0.5, holdDuration: 0.6)
        #expect(abs(HoldLift.progress(after: 0.9, isPickedUp: true, canStillHold: true, tunedAs: tuned) - 5.0 / 6) < 1e-12)
    }
}
