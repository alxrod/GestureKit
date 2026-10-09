import Testing
@testable import GestureCore

/// Where a pinch on a surface is: `x` meters along the surface, having
/// moved `moved` points from where it began, with the hand at `hand` in the
/// space, if the space's drag has said.
private func sample(_ x: Double, moved: SIMD3<Double>, hand: SIMD3<Double>? = nil) -> SurfacePress.Sample {
    SurfacePress.Sample(along: x, moved: moved, hand: hand)
}

/// A press that picks up what's under it, held still for half a second,
/// and then carries it, as asked of the headset: still having to press and
/// hold, but for half as long as a hold. A pinch that carried once it moved
/// 2 cm across plucked things out of where they stood too easily. Nothing
/// carries until the pinch has picked up; a drag along before then still
/// drags along or scrolls, a drag across does nothing, a hold still holds,
/// and a tap is still a tap. The hand's places here are in eighths and
/// sixty-fourths of a meter, so the moves between them come out exact; a
/// surface's points are 1360 to the meter.
@Suite struct SurfacePressCarryTests {
    /// About 2 cm, past the 15 pt that tells a drag from a tap; half the
    /// hold's second to pick up.
    @Test func itPicksUpAtHalfTheHoldAndCarriesFromAboutTwoCentimeters() {
        let tuning = SurfacePress.Tuning()
        #expect(tuning.carryDistance == 27)
        #expect(abs(tuning.carryDistance / 1360 - 0.02) < 0.0005)
        #expect(tuning.carryDistance > tuning.dragDistance)
        #expect(tuning.pickUpDelay == tuning.holdDuration / 2)
        #expect(tuning.pickUpDelay == 0.5)
        #expect(tuning.pickUpDelayLabel == "0.5 s")
    }

    // MARK: Before the pickup

    /// A drag across the surface, up, down, or toward the viewer, before
    /// the pickup, does nothing however far it goes, and is no tap: it gives
    /// the pickup up as it passes 10 pt, and the pickup's time coming later
    /// picks nothing up.
    @Test func aDragAcrossBeforeThePickupNeverCarries() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.canStillPickUp)
        #expect(press.move(sample(0.2015, moved: SIMD3(2, 16, 0), hand: SIMD3(0.5, 1.4921875, -1))) == [.giveUpHold, .ignoreDragAcross])
        #expect(press.stage == .draggingAcross)
        #expect(!press.canStillPickUp)
        #expect(press.move(sample(0.2029, moved: SIMD3(4, 60, 0), hand: SIMD3(0.5, 1.4375, -1))) == [])
        #expect(press.move(sample(0.2029, moved: SIMD3(4, 200, 0), hand: SIMD3(0.5, 1.375, -1))) == [])
        #expect(press.pickUpTimerFired() == [])
        #expect(!press.isPickedUp)
        #expect(press.end() == [])

        // In one fast move, on a surface that can hold too.
        var holding = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(holding.move(sample(0.2007, moved: SIMD3(1, 30, 0), hand: SIMD3(0.5, 1.4765625, -1))) == [.giveUpHold, .ignoreDragAcross])
        #expect(!holding.canStillHold)
        #expect(holding.pickUpTimerFired() == [])
        #expect(holding.holdTimerFired() == [])
        #expect(holding.end() == [])
    }

    /// A pull toward the viewer before the pickup carries nothing either: a
    /// short one, depth counting half, is still a tap; a long one a drag
    /// across, which does nothing.
    @Test func aPullTowardTheViewerBeforeThePickupNeverCarries() {
        var short = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(short.move(sample(0.2007, moved: SIMD3(1, 1, 18), hand: SIMD3(0.5, 1.5, -0.984375))) == [])
        #expect(short.stage == .undecided)
        #expect(short.end() == [.tap(at: 0.2)])

        var long = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(long.move(sample(0.2007, moved: SIMD3(1, 1, 28), hand: SIMD3(0.5, 1.5, -0.9765625))) == [.giveUpHold])
        #expect(long.move(sample(0.2007, moved: SIMD3(1, 1, 40), hand: SIMD3(0.5, 1.5, -0.96875))) == [.ignoreDragAcross])
        #expect(long.move(sample(0.2007, moved: SIMD3(1, 1, 120), hand: SIMD3(0.5, 1.5, -0.90625))) == [])
        #expect(long.end() == [])
    }

    /// A drag along the surface before the pickup still drags along, or
    /// scrolls, and never carries, however far across it goes later, nor
    /// however long it lasts.
    @Test func aDragAlongBeforeThePickupStillDragsAlongOrScrolls() {
        var along = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1))
        #expect(along.move(sample(0.2118, moved: SIMD3(16, 2, 1), hand: SIMD3(0.515625, 1.5, -1))) == [
            .giveUpHold, .beginDragAlong(from: 0.2, to: 0.2118),
        ])
        #expect(along.pickUpTimerFired() == [])
        #expect(along.move(sample(0.2118, moved: SIMD3(16, 60, 40), hand: SIMD3(0.515625, 1.4375, -0.96875))) == [.moveDragAlong(to: 0.2118)])
        #expect(along.end() == [.endDragAlong])

        var scroll = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1), dragAlongScrolls: true)
        #expect(scroll.move(sample(0.2118, moved: SIMD3(16, 2, 1), hand: SIMD3(0.515625, 1.5, -1))) == [
            .giveUpHold, .beginScroll(handMoved: SIMD3(0.015625, 0, 0)),
        ])
        #expect(scroll.move(sample(0.2118, moved: SIMD3(16, 60, 0), hand: SIMD3(0.515625, 1.4375, -1))) == [.moveScroll(handMoved: SIMD3(0.015625, -0.0625, 0))])
        #expect(scroll.end() == [.endScroll(coasting: true)])
    }

    // MARK: The pickup

    /// Held still for half a second, any pinch picks up, whether it can
    /// hold or not, once: from then on it neither drags along nor scrolls,
    /// and carries once it has moved 2 cm any way, here along the surface,
    /// where it would have dragged along; a move past 10 pt on a surface
    /// that can hold gives up its hold, staying picked up.
    @Test func heldStillHalfASecondItPicksUpThenAMoveOfTwoCentimetersAnyWayCarries() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.move(sample(0.2015, moved: SIMD3(2, 1, 0), hand: SIMD3(0.5, 1.5, -1))) == [])
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.isPickedUp)
        #expect(press.canStillHold)
        #expect(!press.canStillPickUp)
        #expect(press.pickUpTimerFired() == [])
        #expect(press.move(sample(0.2088, moved: SIMD3(12, 0, 0), hand: SIMD3(0.5078125, 1.5, -1))) == [.giveUpHold])
        #expect(press.isPickedUp)
        #expect(!press.canStillHold)
        #expect(press.move(sample(0.2147, moved: SIMD3(20, 0, 0), hand: SIMD3(0.515625, 1.5, -1))) == [])
        #expect(press.stage == .undecided)
        #expect(press.move(sample(0.2206, moved: SIMD3(28, 0, 0), hand: SIMD3(0.5234375, 1.5, -1))) == [
            .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0.0234375, 0, 0)),
        ])
        #expect(press.stage == .carrying)
        #expect(press.move(sample(0.3, moved: SIMD3(150, 0, 0), hand: SIMD3(0.625, 1.5, -1))) == [.moveCarry(handMoved: SIMD3(0.125, 0, 0))])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [.endCarry])
        #expect(press.stage == .over)
    }

    /// A surface that can't hold picks up as one that can does, with no
    /// hold to give up as it moves on: it carries once it's 2 cm off.
    @Test func aSurfaceThatCantHoldPicksUpAndCarries() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 20, 0), hand: SIMD3(0.5, 1.484375, -1))) == [])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 30, 0), hand: SIMD3(0.5, 1.4765625, -1))) == [
            .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0, -0.0234375, 0)),
        ])
        #expect(press.move(sample(0.3, moved: SIMD3(130, 140, 20), hand: SIMD3(0.625, 1.375, -0.875))) == [
            .moveCarry(handMoved: SIMD3(0.125, -0.125, 0.125)),
        ])
        #expect(press.end() == [.endCarry])
    }

    /// Picked up, it carries whichever way it moves: across, toward the
    /// viewer, a push into the surface, and along a surface whose drag
    /// along would scroll; depth counts in full.
    @Test func pickedUpItCarriesWhicheverWayItMoves() {
        var pushed = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1), dragAlongScrolls: true)
        #expect(pushed.pickUpTimerFired() == [.pickUp])
        #expect(pushed.move(sample(0.2, moved: SIMD3(0, 0, -28), hand: SIMD3(0.5, 1.5, -1.0234375))) == [
            .giveUpHold, .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0, 0, -0.0234375)),
        ])

        var pulled = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1))
        #expect(pulled.pickUpTimerFired() == [.pickUp])
        #expect(pulled.move(sample(0.2, moved: SIMD3(0, 0, 28), hand: SIMD3(0.5, 1.5, -0.9765625))) == [
            .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0, 0, 0.0234375)),
        ])

        var along = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1), dragAlongScrolls: true)
        #expect(along.pickUpTimerFired() == [.pickUp])
        #expect(along.move(sample(0.2221, moved: SIMD3(30, 0, 0), hand: SIMD3(0.5234375, 1.5, -1))) == [
            .giveUpHold, .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0.0234375, 0, 0)),
        ])

        var across = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(across.pickUpTimerFired() == [.pickUp])
        #expect(across.move(sample(0.2, moved: SIMD3(0, 28, 0), hand: SIMD3(0.5, 1.4765625, -1))) == [
            .giveUpHold, .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0, -0.0234375, 0)),
        ])
    }

    /// Only a still pinch picks up: not one that has moved past 10 pt, even
    /// back within it, nor one that drags along, drags across, holds, or has
    /// ended; nor one that can't pick up.
    @Test func onlyAStillPinchPicksUp() {
        var drifted = SurfacePress(at: 0.2, canHold: false)
        #expect(drifted.move(sample(0.2077, moved: SIMD3(10.5, 0, 0))) == [.giveUpHold])
        #expect(drifted.move(sample(0.2015, moved: SIMD3(2, 0, 0))) == [])
        #expect(drifted.pickUpTimerFired() == [])
        #expect(drifted.end() == [.tap(at: 0.2)])

        var wavered = SurfacePress(at: 0.2, canHold: true)
        #expect(wavered.move(sample(0.2066, moved: SIMD3(7, 5, 3))) == [])
        #expect(wavered.pickUpTimerFired() == [.pickUp])

        var held = SurfacePress(at: 0.2, canHold: true)
        #expect(held.holdTimerFired() == [.fireHold])
        #expect(held.pickUpTimerFired() == [])

        var over = SurfacePress(at: 0.2, canHold: true)
        #expect(over.end() == [.tap(at: 0.2)])
        #expect(over.pickUpTimerFired() == [])

        var cantCarry = SurfacePress(at: 0.2, canHold: true, canPickUp: false)
        #expect(!cantCarry.canStillPickUp)
        #expect(cantCarry.pickUpTimerFired() == [])
        #expect(cantCarry.holdTimerFired() == [.fireHold])
    }

    /// What's picked up and let go, or cancelled, short of a carry, is put
    /// down where it was, and no tap, still or moved, as a grid item let go
    /// once it lifted is no tap; one that caught a coast too.
    @Test func whatsPickedUpAndLetGoIsPutDownWithNoTap() {
        var still = SurfacePress(at: 0.2, canHold: false)
        #expect(still.pickUpTimerFired() == [.pickUp])
        #expect(still.move(sample(0.2059, moved: SIMD3(8, 0, 0))) == [])
        #expect(still.end() == [.putDown])
        #expect(still.stage == .over)

        var moved = SurfacePress(at: 0.2, canHold: true)
        #expect(moved.pickUpTimerFired() == [.pickUp])
        #expect(moved.move(sample(0.2147, moved: SIMD3(20, 0, 0))) == [.giveUpHold])
        #expect(moved.end() == [.putDown])

        var cancelled = SurfacePress(at: 0.2, canHold: true)
        #expect(cancelled.pickUpTimerFired() == [.pickUp])
        #expect(cancelled.cancel() == [.putDown])
        #expect(cancelled.end() == [])

        var caught = SurfacePress(at: 0.2, canHold: false, dragAlongScrolls: true, caughtACoast: true)
        #expect(caught.pickUpTimerFired() == [.pickUp])
        #expect(caught.end() == [.putDown])
    }

    /// A pinch that picked up and is held still on holds, on a surface that
    /// can hold, as before, and carries nothing after that.
    @Test func aPickedUpPinchHeldStillOnStillHolds() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.move(sample(0.2044, moved: SIMD3(6, 2, 0), hand: SIMD3(0.5, 1.5, -1))) == [])
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.move(sample(0.3, moved: SIMD3(150, 0, 0), hand: SIMD3(0.625, 1.5, -1))) == [])
        #expect(press.end() == [.endHold])
    }

    /// A refused pickup, as for something that couldn't be carried now,
    /// picks nothing up for the rest of the pinch, which goes on as one that
    /// never could: it drags along, does nothing across, taps let go still,
    /// and its hold still holds.
    @Test func aRefusedPickupGoesOnAsAPinchThatNeverCould() {
        var along = SurfacePress(at: 0.2, canHold: false)
        along.refusePickUp()
        #expect(!along.canStillPickUp)
        #expect(along.pickUpTimerFired() == [])
        #expect(along.move(sample(0.2118, moved: SIMD3(16, 2, 1))) == [.beginDragAlong(from: 0.2, to: 0.2118)])

        var across = SurfacePress(at: 0.2, canHold: false)
        across.refusePickUp()
        #expect(across.move(sample(0.2, moved: SIMD3(0, 30, 0))) == [.ignoreDragAcross])
        #expect(across.end() == [])

        var tap = SurfacePress(at: 0.2, canHold: false)
        tap.refusePickUp()
        #expect(tap.end() == [.tap(at: 0.2)])

        var hold = SurfacePress(at: 0.2, canHold: true)
        hold.refusePickUp()
        #expect(hold.pickUpTimerFired() == [])
        #expect(hold.holdTimerFired() == [.fireHold])
        #expect(hold.end() == [.endHold])

        // Refusing one that's picked up already changes nothing.
        var picked = SurfacePress(at: 0.2, canHold: false)
        #expect(picked.pickUpTimerFired() == [.pickUp])
        picked.refusePickUp()
        #expect(picked.isPickedUp)
        #expect(picked.end() == [.putDown])
    }

    // MARK: Its end

    /// A cancelled carry is no drop: what's carried goes back where it was.
    @Test func aCancelledCarryGoesBack() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 30, 0), hand: SIMD3(0.5, 1.4765625, -1))) == [
            .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0, -0.0234375, 0)),
        ])
        #expect(press.cancel() == [.cancelCarry])
        #expect(press.stage == .over)
        #expect(press.end() == [])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 60, 0), hand: SIMD3(0.5, 1.375, -1))) == [])
    }

    /// A carry the caller couldn't begin, as for something being deleted,
    /// does nothing for the rest of the pinch, and asks no more: no tap, no
    /// hold, no put down, and no carry.
    @Test func aRefusedCarryCarriesNothingForTheRestOfThePinch() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.move(sample(0.2206, moved: SIMD3(28, 0, 0), hand: SIMD3(0.5234375, 1.5, -1))) == [
            .giveUpHold, .beginCarry(.movedOncePickedUp, handMoved: SIMD3(0.0234375, 0, 0)),
        ])
        press.refuseCarry()
        #expect(press.stage == .draggingAcross)
        #expect(press.move(sample(0.3, moved: SIMD3(140, 60, 40), hand: SIMD3(0.625, 1.5, -1))) == [])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [])

        // Refusing one that isn't carrying changes nothing.
        var tap = SurfacePress(at: 0.2, canHold: false)
        tap.refuseCarry()
        #expect(tap.stage == .undecided)
        #expect(tap.end() == [.tap(at: 0.2)])
    }

    // MARK: The hand

    /// A carry that begins before the space's drag has said where the hand
    /// was measures from where it first says; a move it hasn't placed, or a
    /// hand that isn't a place, carries nothing.
    @Test func aCarryMeasuresTheHandFromWhereItFirstSaidIfItHadNone() {
        var press = SurfacePress(at: 0.2, canHold: false)
        #expect(press.pickUpTimerFired() == [.pickUp])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 30, 0))) == [.beginCarry(.movedOncePickedUp, handMoved: .zero)])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 40, 0), hand: SIMD3(0.5, 1.5, -1))) == [.moveCarry(handMoved: .zero)])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 50, 0), hand: SIMD3(0.625, 1.375, -1))) == [.moveCarry(handMoved: SIMD3(0.125, -0.125, 0))])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 60, 0))) == [])
        #expect(press.move(sample(0.2, moved: SIMD3(0, 60, 0), hand: SIMD3(.nan, 1.5, -1))) == [])
        #expect(press.end() == [.endCarry])
    }

    /// A press that can't pick up is as every press was before anything
    /// could be carried: a drag across does nothing however far it goes, a
    /// pull toward the viewer short of a drag is a tap, and a move past
    /// 10 pt, on a surface that can hold, gives up only the hold.
    @Test func aPressThatCantPickUpNeverPicksUp() {
        var across = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0.5, 1.5, -1), canPickUp: false)
        #expect(across.move(sample(0.2015, moved: SIMD3(2, 16, 0), hand: SIMD3(0.5, 1.4921875, -1))) == [.ignoreDragAcross])
        #expect(across.move(sample(0.2, moved: SIMD3(0, 90, 0), hand: SIMD3(0.5, 1.4375, -1))) == [])
        #expect(across.end() == [])

        var pulled = SurfacePress(at: 0.2, canHold: false, canPickUp: false)
        #expect(pulled.move(sample(0.2, moved: SIMD3(1, 1, 28))) == [])
        #expect(pulled.end() == [.tap(at: 0.2)])

        var holding = SurfacePress(at: 0.2, canHold: true, canPickUp: false)
        #expect(holding.move(sample(0.2221, moved: SIMD3(30, 0, 0))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2221)])
    }

    /// The reason says why, for the log's line on why it carried rather
    /// than dragged along, with the time the press was tuned to hold still.
    @Test func theReasonSaysWhy() {
        let reason = SurfacePress.CarryReason.movedOncePickedUp.description
        #expect(reason.contains("picked up"))
        let press = SurfacePress(at: 0.2, canHold: false)
        let explained = press.describe(.movedOncePickedUp)
        #expect(explained.contains("picked up"))
        #expect(explained.contains("0.5 s"))
        let slower = SurfacePress(at: 0.2, canHold: false, tuning: SurfacePress.Tuning(pickUpDelay: 0.75))
        #expect(slower.describe(.movedOncePickedUp).contains("0.75 s"))
    }
}
