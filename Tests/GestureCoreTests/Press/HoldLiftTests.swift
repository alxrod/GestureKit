import Foundation
import Testing
@testable import GestureCore

/// How something held still lifts as its press picks it up, and on toward
/// its hold, as an item lifts off its grid.
@Suite struct HoldLiftTests {
    private let press = SurfacePress.Tuning()
    private let lift = HoldLift.Tuning()

    private func isClose(_ a: HoldLift.Look, _ b: HoldLift.Look, within tolerance: Double = 1e-12) -> Bool {
        abs(a.scale - b.scale) < tolerance && abs(a.depth - b.depth) < tolerance
    }

    private var pickedUp: HoldLift.Look { HoldLift.Look(scale: lift.pickedUpScale, depth: lift.pickedUpDepth) }
    private var held: HoldLift.Look { HoldLift.Look(scale: lift.heldScale, depth: lift.heldDepth) }

    /// Picked up, 5% larger and 2.5 cm nearer; held, 6% and 3 cm; popping
    /// in a fifth of a second, overshooting by a tenth, and settling over
    /// 0.32 s.
    @Test func itsDefaultsAreTheHeadsets() {
        #expect(lift.pickedUpScale == 1.05)
        #expect(lift.pickedUpDepth == 0.025)
        #expect(lift.heldScale == 1.06)
        #expect(lift.heldDepth == 0.03)
        #expect(lift.popDuration == 0.2)
        #expect(lift.popOvershoot == 0.1)
        #expect(lift.settleDuration == 0.32)
        #expect(press.lift == lift)
        #expect(HoldLift.Tuning.parameterProblems.isEmpty)
    }

    /// Nothing until the pinch picks up, at half a second, so a tap or a
    /// drag never shows it, nor a pinch that hasn't picked up; then it pops
    /// up to its picked-up look in a fifth of a second.
    @Test func itPopsUpAsThePinchPicksUp() {
        #expect(press.pickUpDelay == 0.5)
        for elapsed in [0.0, 0.25, 0.499, 0.5] {
            #expect(HoldLift.look(after: elapsed, isPickedUp: true, canStillHold: true) == .rest)
        }
        #expect(HoldLift.look(after: 0.8, isPickedUp: false, canStillHold: true) == .rest)
        #expect(HoldLift.look(after: 0.52, isPickedUp: true, canStillHold: false).scale > 1)
        #expect(HoldLift.look(after: 0.52, isPickedUp: true, canStillHold: false).depth > 0)
        let poppedAt = press.pickUpDelay + lift.popDuration
        #expect(isClose(HoldLift.look(after: poppedAt, isPickedUp: true, canStillHold: false), pickedUp))
    }

    /// The pop overshoots a little on the way, a tenth past picked up, as a
    /// spring with a little bounce does, never past the held look, so the
    /// moment it's picked up reads plainly.
    @Test func thePopOvershootsATenth() {
        var highest = HoldLift.Look.rest
        for step in 0...400 {
            let elapsed = press.pickUpDelay + Double(step) * lift.popDuration / 400
            let look = HoldLift.look(after: elapsed, isPickedUp: true, canStillHold: false)
            if look.depth > highest.depth { highest = look }
        }
        #expect(highest.depth > lift.pickedUpDepth * 1.09)
        #expect(highest.depth < lift.pickedUpDepth * 1.11)
        #expect(highest.scale > 1 + (lift.pickedUpScale - 1) * 1.09)
        #expect(highest.scale < 1 + (lift.pickedUpScale - 1) * 1.11)
        #expect(highest.depth < lift.heldDepth)
        #expect(highest.scale < lift.heldScale)
        #expect(HoldLift.popCurve(0) == 0)
        #expect(abs(HoldLift.popCurve(1) - 1) < 1e-12)
        #expect(HoldLift.popCurve(-1) == 0)
        #expect(HoldLift.popCurve(2) == 1)
    }

    /// The overshoot is the peak's, as tuned, through the back easing's
    /// constant: a tenth is the usual back easing's 1.70158, to within a
    /// ten-thousandth; none is an ease out that never passes 1.
    @Test func theOvershootIsThePeaks() {
        #expect(abs(HoldLift.backing(forOvershoot: 0.1) - 1.70158) < 1e-4)
        #expect(HoldLift.backing(forOvershoot: 0) == 0)
        #expect(HoldLift.backing(forOvershoot: -1) == 0)
        #expect(HoldLift.backing(forOvershoot: .nan) == 0)
        for overshoot in [0.0, 0.05, 0.1, 0.3] {
            var peak = 0.0
            for step in 0...4000 {
                peak = max(peak, HoldLift.popCurve(Double(step) / 4000, overshoot: overshoot))
            }
            #expect(abs(peak - (1 + overshoot)) < 1e-6)
        }
    }

    /// Picked up, a pinch still counting down to its hold rises on, quickly
    /// at first, to its held look as the hold fires, at a second, and no
    /// more after; one that can't hold, or that moved off, stays picked up.
    @Test func aPinchCountingDownRisesOnToItsHoldAndAnyOtherStaysPickedUp() {
        let poppedAt = press.pickUpDelay + lift.popDuration
        #expect(isClose(HoldLift.look(after: press.holdDuration, isPickedUp: true, canStillHold: true), held))
        #expect(isClose(HoldLift.look(after: 3, isPickedUp: true, canStillHold: true), held))
        var last = pickedUp
        for step in 0...300 {
            let elapsed = poppedAt + Double(step) * (press.holdDuration - poppedAt) / 300
            let look = HoldLift.look(after: elapsed, isPickedUp: true, canStillHold: true)
            #expect(look.scale >= last.scale - 1e-12)
            #expect(look.depth >= last.depth - 1e-12)
            last = look
        }
        let halfway = poppedAt + (press.holdDuration - poppedAt) / 2
        let rising = HoldLift.look(after: halfway, isPickedUp: true, canStillHold: true)
        #expect(rising.depth > lift.pickedUpDepth + (lift.heldDepth - lift.pickedUpDepth) * 0.6)
        #expect(rising.scale > lift.pickedUpScale + (lift.heldScale - lift.pickedUpScale) * 0.6)
        for elapsed in [poppedAt, 0.8, 1.0, 5.0] {
            #expect(isClose(HoldLift.look(after: elapsed, isPickedUp: true, canStillHold: false), pickedUp))
        }
    }

    /// A time that isn't one lifts nothing.
    @Test func aTimeThatIsntOneLiftsNothing() {
        #expect(HoldLift.look(after: .nan, isPickedUp: true, canStillHold: true) == .rest)
        #expect(HoldLift.look(after: -1, isPickedUp: true, canStillHold: true) == .rest)
        #expect(HoldLift.look(after: .infinity, isPickedUp: true, canStillHold: true) == .rest)
    }

    /// Read from a pinch, it follows the pinch's pickup and its hold: at rest
    /// before the pickup, the pop once picked up, the rise while its hold
    /// counts down, and picked up once it's moved off.
    @Test func itFollowsThePinch() {
        var holding = SurfacePress(at: 0.2, canHold: true)
        #expect(HoldLift.look(after: 0.6, of: holding) == .rest)
        #expect(holding.pickUpTimerFired() == [.pickUp])
        #expect(HoldLift.look(after: 0.9, of: holding).depth > lift.pickedUpDepth)
        _ = holding.move(SurfacePress.Sample(along: 0.21, moved: SIMD3(12, 0, 0)))
        #expect(isClose(HoldLift.look(after: 0.9, of: holding), pickedUp))
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

    // MARK: Tuned

    /// Tuned, the lift follows its tuning and its press's: it picks up when
    /// the press does, pops for as long as it's told, overshoots as far, and
    /// rises to its held look as the tuned hold fires.
    @Test func aTunedLiftFollowsItsTuning() {
        let tuned = SurfacePress.Tuning(
            pickUpDelay: 0.3,
            holdDuration: 1.5,
            lift: HoldLift.Tuning(pickedUpScale: 1.1, pickedUpDepth: 0.04, heldScale: 1.2, heldDepth: 0.05, popDuration: 0.1, popOvershoot: 0)
        )
        #expect(HoldLift.look(after: 0.3, isPickedUp: true, canStillHold: true, tunedAs: tuned) == .rest)
        // With no overshoot the pop never passes picked up.
        var highest = 0.0
        for step in 0...100 {
            let elapsed = 0.3 + Double(step) * 0.1 / 100
            highest = max(highest, HoldLift.look(after: elapsed, isPickedUp: true, canStillHold: false, tunedAs: tuned).depth)
        }
        #expect(abs(highest - 0.04) < 1e-12)
        #expect(HoldLift.look(after: 1.4, isPickedUp: true, canStillHold: true, tunedAs: tuned).depth < 0.05)
        #expect(isClose(HoldLift.look(after: 1.5, isPickedUp: true, canStillHold: true, tunedAs: tuned), HoldLift.Look(scale: 1.2, depth: 0.05)))

        var pinch = SurfacePress(at: 0, canHold: true, tuning: tuned)
        #expect(pinch.pickUpTimerFired() == [.pickUp])
        #expect(HoldLift.mayChange(after: 1.4, of: pinch))
        #expect(!HoldLift.mayChange(after: 1.5, of: pinch))
        #expect(isClose(HoldLift.look(after: 0.4, of: pinch), HoldLift.Look(scale: 1.1, depth: 0.04)))
    }

    /// A hold no longer than the pickup and its pop leaves nothing to rise
    /// through: picked up, it stays picked up, rather than dividing by a
    /// rise of none; and a pop of no time is picked up at once.
    @Test func aHoldTooSoonToRiseThroughStaysPickedUp() {
        let tuned = SurfacePress.Tuning(pickUpDelay: 0.5, holdDuration: 0.6)
        #expect(isClose(HoldLift.look(after: 0.9, isPickedUp: true, canStillHold: true, tunedAs: tuned), pickedUp))
        let noPop = SurfacePress.Tuning(lift: HoldLift.Tuning(popDuration: 0))
        #expect(isClose(HoldLift.look(after: 0.5001, isPickedUp: true, canStillHold: false, tunedAs: noPop), pickedUp))
    }
}
