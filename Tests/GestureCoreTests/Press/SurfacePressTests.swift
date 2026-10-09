import Testing
@testable import GestureCore

/// Where a pinch on a surface is: `x` meters along the surface, having
/// moved `moved` points from where it began, with the hand at `hand` in the
/// space, if the space's drag has said.
private func sample(_ x: Double, moved: SIMD3<Double>, hand: SIMD3<Double>? = nil) -> SurfacePress.Sample {
    SurfacePress.Sample(along: x, moved: moved, hand: hand)
}

/// One pinch on a surface, told as a tap, a drag along, or a hold as it
/// goes, from one drag that begins as it touches, so that none of them
/// waits on another's gesture to fail. The pinches here begin 0.2 m along
/// a surface; 16 pt at 1360 pt to the meter is about 0.0118 m. Every pinch
/// here could pick up, held still (`SurfacePressCarryTests`), so a move
/// past 10 pt gives that up (`giveUpHold`), on a surface that can't hold
/// too.
@Suite struct SurfacePressTests {
    /// About 7 mm to hold, and about 1.1 cm to drag, at 1360 pt to the
    /// meter; the hold's second is the caller's to time.
    @Test func itHoldsWithinTenPointsAndDragsFromFifteen() {
        let tuning = SurfacePress.Tuning()
        #expect(tuning.stillDistance == 10)
        #expect(tuning.dragDistance == 15)
        #expect(tuning.depthWeight == 0.5)
        #expect(tuning.holdDuration == 1.0)
        #expect(tuning.holdDurationLabel == "1 s")
        #expect(SurfacePress(at: 0.2, canHold: true).tuning == tuning)
    }

    // MARK: Taps

    /// A pinch let go where it touched is a tap there.
    @Test func aQuickTapIsATapWhereItBegan() {
        var press = SurfacePress(at: 0.2, canHold: false)
        #expect(press.stage == .undecided)
        #expect(press.end() == [.tap(at: 0.2)])
        #expect(press.stage == .over)
    }

    /// A tap on a surface that can hold is a tap, with no hold to wait for
    /// or fail: the hold that stood in front of it swallowed it on the
    /// headset.
    @Test func aTapOnASurfaceThatCanHoldIsATap() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0, 1.5, -1))
        #expect(press.move(sample(0.2015, moved: SIMD3(2, 1, 0), hand: SIMD3(0.001, 1.5, -1))) == [])
        #expect(press.end() == [.tap(at: 0.2)])
    }

    /// However long it lasts, a pinch on a surface that can't hold, nor
    /// pick up, let go within 15 pt, is a tap: its hold's time passing does
    /// nothing.
    @Test func aLongStillPressOnASurfaceThatCantHoldIsATap() {
        var press = SurfacePress(at: 0.2, canHold: false, canPickUp: false)
        #expect(press.move(sample(0.2, moved: SIMD3(1, 0, 0))) == [])
        #expect(press.holdTimerFired() == [])
        #expect(press.stage == .undecided)
        #expect(press.move(sample(0.2, moved: SIMD3(2, 1, 1))) == [])
        #expect(press.end() == [.tap(at: 0.2)])
    }

    /// A slow drift that stays within 10 pt, let go before the hold, is a
    /// tap where the pinch began, not where it was let go.
    @Test func aSlowDriftUnderTenPointsThenReleaseIsATap() {
        var press = SurfacePress(at: 0.2, canHold: true)
        for moved in [SIMD3<Double>(3, 0, 0), SIMD3(6, 2, 0), SIMD3(8, 5, 1), SIMD3(9.9, 0, 0)] {
            #expect(press.move(sample(0.2 + moved.x / 1360, moved: moved)) == [])
        }
        #expect(press.farthest == 9.9)
        #expect(press.end() == [.tap(at: 0.2)])
    }

    /// A drift past 10 pt gives up the hold for good, even back within it,
    /// but short of 15 pt it's still a tap as it ends.
    @Test func aDriftPastTenPointsThatStaysUnderFifteenIsATapNotAHold() {
        var press = SurfacePress(at: 0.2, canHold: true)
        #expect(press.move(sample(0.2044, moved: SIMD3(6, 0, 0))) == [])
        #expect(press.canStillHold)
        #expect(press.move(sample(0.2077, moved: SIMD3(10.5, 0, 0))) == [.giveUpHold])
        #expect(!press.canStillHold)
        #expect(press.move(sample(0.2096, moved: SIMD3(13, 5, 0))) == [])
        #expect(press.move(sample(0.2059, moved: SIMD3(8, 0, 0))) == [])
        #expect(press.holdTimerFired() == [])
        #expect(press.stage == .undecided)
        #expect(press.end() == [.tap(at: 0.2)])
    }

    // MARK: Drags

    /// Once it has moved 15 pt along the surface, it drags along from where
    /// it began to where it is, and on as it moves, whichever way it turns
    /// later, until it ends; the hold's time passing then does nothing.
    @Test func aDragAlong() {
        var press = SurfacePress(at: 0.2, canHold: false)
        #expect(press.move(sample(0.2037, moved: SIMD3(5, 1, 0))) == [])
        #expect(press.move(sample(0.2118, moved: SIMD3(16, 2, 1))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2118)])
        #expect(press.stage == .draggingAlong)
        #expect(press.move(sample(0.25, moved: SIMD3(68, 30, 0))) == [.moveDragAlong(to: 0.25)])
        #expect(press.move(sample(0.125, moved: SIMD3(-102, 90, 12))) == [.moveDragAlong(to: 0.125)])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [.endDragAlong])
        #expect(press.stage == .over)
    }

    /// On a surface that can hold, a drag along gives up the hold as it
    /// passes 10 pt, then begins at 15.
    @Test func aDragAlongGivesUpItsHold() {
        var press = SurfacePress(at: 0.2, canHold: true)
        #expect(press.move(sample(0.2088, moved: SIMD3(12, 0, 0))) == [.giveUpHold])
        #expect(press.move(sample(0.2125, moved: SIMD3(17, -3, 0))) == [.beginDragAlong(from: 0.2, to: 0.2125)])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [.endDragAlong])

        // Both at once, when a single move passes both.
        var jumped = SurfacePress(at: 0.2, canHold: true)
        #expect(jumped.move(sample(0.2147, moved: SIMD3(20, 0, 0))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2147)])
    }

    /// A drag that starts out up, down, or in depth doesn't drag along: it
    /// does nothing, however far it goes, and it's no tap either. Only a
    /// pinch that picked up first carries (`SurfacePressCarryTests`).
    @Test func aDragAcrossTheSurfaceDoesNothing() {
        var upward = SurfacePress(at: 0.2, canHold: false)
        #expect(upward.move(sample(0.2022, moved: SIMD3(3, 16, 0))) == [.giveUpHold, .ignoreDragAcross])
        #expect(upward.stage == .draggingAcross)
        #expect(upward.move(sample(0.3, moved: SIMD3(140, 20, 0))) == [])
        #expect(upward.end() == [])

        var inDepth = SurfacePress(at: 0.2, canHold: true)
        #expect(inDepth.move(sample(0.2, moved: SIMD3(0, 2, -32))) == [.giveUpHold, .ignoreDragAcross])
        #expect(inDepth.holdTimerFired() == [])
        #expect(inDepth.end() == [])
    }

    /// A pinch's own closing moves where it's tracked in depth more than
    /// across the surface, so depth counts half: a still pinch that jitters
    /// a centimeter in depth is still a tap, and still holds. A push of 3 cm
    /// into the surface is a drag across, which does nothing.
    @Test func depthCountsHalfTowardAPinchsStillness() {
        var tapping = SurfacePress(at: 0.2, canHold: false)
        #expect(tapping.move(sample(0.2, moved: SIMD3(1, 2, -16))) == [])
        #expect(tapping.end() == [.tap(at: 0.2)])

        var holding = SurfacePress(at: 0.2, canHold: true)
        #expect(holding.move(sample(0.2015, moved: SIMD3(2, 1, 14))) == [])
        #expect(holding.holdTimerFired() == [.fireHold])

        var pushedFar = SurfacePress(at: 0.2, canHold: false)
        #expect(pushedFar.move(sample(0.2, moved: SIMD3(0, 0, -30))) == [.giveUpHold, .ignoreDragAcross])
    }

    /// It keeps how far the pinch has moved along, across, and in depth, at
    /// its latest move, for the logs to say which it was.
    @Test func itKeepsItsLatestMoveForTheLogs() {
        var press = SurfacePress(at: 0.2, canHold: false)
        #expect(press.moved == SIMD3(0, 0, 0))
        _ = press.move(sample(0.2, moved: SIMD3(3, -1, 7)))
        #expect(press.moved == SIMD3(3, -1, 7))
    }

    /// Exactly 10 pt still holds, and exactly 15 pt drags.
    @Test func tenPointsStillHoldsAndFifteenDrags() {
        var holding = SurfacePress(at: 0.2, canHold: true)
        #expect(holding.move(sample(0.2074, moved: SIMD3(10, 0, 0))) == [])
        #expect(holding.holdTimerFired() == [.fireHold])

        var dragging = SurfacePress(at: 0.2, canHold: false)
        #expect(dragging.move(sample(0.211, moved: SIMD3(15, 0, 0))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.211)])
    }

    // MARK: Holds

    /// Still within 10 pt as the hold's time passes, a pinch on a surface
    /// that can hold holds; the same pinch carries nothing after that,
    /// however far the hand moves, and its end ends the hold, never a tap.
    @Test func aHeldPinchCarriesNothing() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.move(sample(0.2022, moved: SIMD3(3, -2, 1), hand: SIMD3(0.5, 1.5, -1))) == [])
        #expect(press.move(sample(0.2044, moved: SIMD3(6, 4, 0), hand: SIMD3(0.5, 1.5, -0.75))) == [])
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.stage == .held)
        #expect(press.move(sample(0.2044, moved: SIMD3(6, 4, 0), hand: SIMD3(0.5, 1.25, -0.75))) == [])
        #expect(press.move(sample(0.3, moved: SIMD3(150, 0, 0), hand: SIMD3(0.75, 1.25, -1))) == [])
        #expect(press.end() == [.endHold])
        #expect(press.stage == .over)
    }

    /// Let go without moving on, a hold ends: it's never a tap too.
    @Test func aHoldThenReleaseIsNoTap() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.end() == [.endHold])
        #expect(press.holdTimerFired() == [])
    }

    /// A drift under 10 pt doesn't give up the hold.
    @Test func aDriftUnderTenPointsStillHolds() {
        var press = SurfacePress(at: 0.2, canHold: true)
        #expect(press.move(sample(0.2066, moved: SIMD3(7, 5, 3))) == [])
        #expect(press.canStillHold)
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.holdTimerFired() == [])
    }

    // MARK: Cancels

    /// A cancel ends what the pinch began, as a release would, but is
    /// never a tap: undecided, nothing happens.
    @Test func aCancelBeforeItIsAnythingIsNoTap() {
        var press = SurfacePress(at: 0.2, canHold: true)
        #expect(press.move(sample(0.2015, moved: SIMD3(2, 0, 0))) == [])
        #expect(press.cancel() == [])
        #expect(press.stage == .over)
        #expect(press.end() == [])
        #expect(press.holdTimerFired() == [])
    }

    /// A cancelled drag along lands, as a released one does.
    @Test func aCancelledDragAlongEnds() {
        var press = SurfacePress(at: 0.2, canHold: false)
        #expect(press.move(sample(0.2125, moved: SIMD3(17, 0, 0))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2125)])
        #expect(press.cancel() == [.endDragAlong])
        #expect(press.end() == [])
    }

    /// A cancelled drag across the surface does nothing.
    @Test func aCancelledDragAcrossDoesNothing() {
        var press = SurfacePress(at: 0.2, canHold: false)
        #expect(press.move(sample(0.2, moved: SIMD3(0, -20, 0))) == [.giveUpHold, .ignoreDragAcross])
        #expect(press.cancel() == [])
        #expect(press.stage == .over)
    }

    /// A cancelled hold ends, as a released one does: what it began stays
    /// begun.
    @Test func aCancelledHoldEnds() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.move(sample(0.2, moved: .zero, hand: SIMD3(0.5, 1.375, -1))) == [])
        #expect(press.cancel() == [.endHold])
        #expect(press.end() == [])
    }

    /// Once ended, it does nothing more, cancelled or not.
    @Test func onceOverItDoesNothingMore() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.end() == [.tap(at: 0.2)])
        #expect(press.cancel() == [])
        #expect(press.move(sample(0.3, moved: SIMD3(140, 0, 0), hand: SIMD3(1, 1.5, -1))) == [])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [])
        #expect(!press.canStillHold)
    }

    // MARK: What isn't a number

    /// A move that isn't a number moves nothing, and doesn't count toward
    /// how far the pinch has gone; nor does a hand that isn't a place.
    @Test func movesThatAreNotNumbersAreIgnored() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1))
        #expect(press.move(sample(0.2, moved: SIMD3(.nan, 0, 0))) == [])
        #expect(press.move(sample(.infinity, moved: SIMD3(40, 0, 0))) == [])
        #expect(press.farthest == 0)
        #expect(press.canStillHold)
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.move(sample(0.2, moved: .zero, hand: SIMD3(.nan, 1.5, -1))) == [])
        #expect(press.move(sample(0.2, moved: .zero, hand: SIMD3(0.5, 1.5, -0.5))) == [])
        #expect(press.end() == [.endHold])

        var dragging = SurfacePress(at: 0.2, canHold: false)
        #expect(dragging.move(sample(0.2125, moved: SIMD3(17, 0, 0))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2125)])
        #expect(dragging.move(sample(.nan, moved: SIMD3(30, 0, 0))) == [])
        #expect(dragging.end() == [.endDragAlong])
    }
}
