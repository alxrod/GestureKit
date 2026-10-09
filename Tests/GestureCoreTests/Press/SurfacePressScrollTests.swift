import Testing
@testable import GestureCore

/// Where a pinch on a surface is: `x` meters along the surface, having
/// moved `moved` points from where it began, with the hand at `hand` in the
/// space, if the space's drag has said.
private func sample(_ x: Double, moved: SIMD3<Double>, hand: SIMD3<Double>? = nil) -> SurfacePress.Sample {
    SurfacePress.Sample(along: x, moved: moved, hand: hand)
}

/// On a surface whose drag along scrolls, as on content longer than the
/// window it shows through, a drag along scrolls, following the hand in the
/// space, where on any other it drags along. Taps and holds are as they
/// were, but a pinch that caught a coast is no tap. Every pinch here could
/// pick up, held still, so a move past 10 pt gives that up (`giveUpHold`).
/// The hand's places here are in eighths and sixty-fourths of a meter, so
/// the moves between them come out exact.
@Suite struct SurfacePressScrollTests {
    /// Once it has moved 15 pt along the surface, it scrolls by the hand's
    /// move in the space since the pinch began, so what scrolls catches up
    /// with it, then by every move from there, whichever way it turns later,
    /// until it ends, when it may coast; the hold's time passing does
    /// nothing.
    @Test func aDragAlongASurfaceThatScrollsScrolls() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true)
        #expect(press.move(sample(0.2037, moved: SIMD3(5, 1, 0), hand: SIMD3(0.00390625, 1.5, -1))) == [])
        #expect(press.move(sample(0.2118, moved: SIMD3(16, 2, 1), hand: SIMD3(0.015625, 1.5, -1))) == [
            .giveUpHold, .beginScroll(handMoved: SIMD3(0.015625, 0, 0)),
        ])
        #expect(press.stage == .scrolling)
        #expect(press.move(sample(0.25, moved: SIMD3(68, 30, 0), hand: SIMD3(0.0625, 1.4375, -1.0078125))) == [
            .moveScroll(handMoved: SIMD3(0.0625, -0.0625, -0.0078125)),
        ])
        #expect(press.move(sample(0.125, moved: SIMD3(-102, 90, 12), hand: SIMD3(-0.125, 1.5, -1))) == [.moveScroll(handMoved: SIMD3(-0.125, 0, 0))])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [.endScroll(coasting: true)])
        #expect(press.stage == .over)
    }

    /// On a surface that can hold, it gives up the hold as it passes 10 pt,
    /// then scrolls at 15.
    @Test func aScrollGivesUpItsHold() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1), dragAlongScrolls: true)
        #expect(press.move(sample(0.2088, moved: SIMD3(12, 0, 0), hand: SIMD3(0.5078125, 1.5, -1))) == [.giveUpHold])
        #expect(press.move(sample(0.2125, moved: SIMD3(17, -3, 0), hand: SIMD3(0.515625, 1.5, -1))) == [.beginScroll(handMoved: SIMD3(0.015625, 0, 0))])
        #expect(press.holdTimerFired() == [])
        #expect(press.end() == [.endScroll(coasting: true)])
    }

    /// Where the drag along doesn't scroll, it drags along as before.
    @Test func whereTheDragDoesntScrollItDragsAlong() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1))
        #expect(press.move(sample(0.2118, moved: SIMD3(16, 2, 1), hand: SIMD3(0.015625, 1.5, -1))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2118)])
        #expect(press.end() == [.endDragAlong])
    }

    /// A drag that starts out up, down, or in depth neither scrolls nor
    /// drags along, as before.
    @Test func aDragAcrossStillDoesNothing() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true)
        #expect(press.move(sample(0.2022, moved: SIMD3(3, 16, 0), hand: SIMD3(0, 1.4375, -1))) == [.giveUpHold, .ignoreDragAcross])
        #expect(press.stage == .draggingAcross)
        #expect(press.move(sample(0.3, moved: SIMD3(140, 20, 0), hand: SIMD3(0.125, 1.4375, -1))) == [])
        #expect(press.end() == [])
    }

    /// Taps and holds are as they were: a held pinch carries nothing.
    @Test func tapsAndHoldsAreAsBefore() {
        var tap = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true)
        #expect(tap.move(sample(0.2015, moved: SIMD3(2, 1, 0), hand: SIMD3(0.001, 1.5, -1))) == [])
        #expect(tap.end() == [.tap(at: 0.2)])

        var hold = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0.5, 1.5, -1), dragAlongScrolls: true)
        #expect(hold.holdTimerFired() == [.fireHold])
        #expect(hold.move(sample(0.3, moved: SIMD3(150, 0, 0), hand: SIMD3(0.75, 1.5, -1))) == [])
        #expect(hold.end() == [.endHold])
    }

    /// A scroll that begins before the space's drag has said where the hand
    /// was measures from where it first says.
    @Test func aScrollMeasuresFromTheHandsFirstPlaceIfItHadNone() {
        var press = SurfacePress(at: 0.2, canHold: false, dragAlongScrolls: true)
        #expect(press.move(sample(0.2118, moved: SIMD3(16, 0, 0))) == [.giveUpHold, .beginScroll(handMoved: .zero)])
        #expect(press.move(sample(0.22, moved: SIMD3(30, 0, 0), hand: SIMD3(0.5, 1.5, -1))) == [.moveScroll(handMoved: .zero)])
        #expect(press.move(sample(0.23, moved: SIMD3(44, 0, 0), hand: SIMD3(0.625, 1.5, -1))) == [.moveScroll(handMoved: SIMD3(0.125, 0, 0))])
        // A move the space's drag hasn't placed, or a hand that isn't a
        // place, moves nothing.
        #expect(press.move(sample(0.24, moved: SIMD3(58, 0, 0))) == [])
        #expect(press.move(sample(0.24, moved: SIMD3(58, 0, 0), hand: SIMD3(.nan, 1.5, -1))) == [])
        #expect(press.end() == [.endScroll(coasting: true)])
    }

    /// A cancelled scroll stops where it is, without coasting, and is no
    /// tap.
    @Test func aCancelledScrollStopsWithoutCoasting() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true)
        #expect(press.move(sample(0.2125, moved: SIMD3(17, 0, 0), hand: SIMD3(0.015625, 1.5, -1))) == [
            .giveUpHold, .beginScroll(handMoved: SIMD3(0.015625, 0, 0)),
        ])
        #expect(press.cancel() == [.endScroll(coasting: false)])
        #expect(press.end() == [])
        #expect(press.stage == .over)
    }

    // MARK: Catching a coast

    /// A pinch that caught a coast, as it touched, is that catch: let go
    /// where it touched, it's no tap, as a list flicked on iOS stops under a
    /// finger without the tap selecting what's under it.
    @Test func aPinchThatCaughtACoastIsNoTap() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true, caughtACoast: true)
        #expect(press.caughtACoast)
        #expect(press.move(sample(0.2015, moved: SIMD3(2, 1, 0), hand: SIMD3(0.001, 1.5, -1))) == [])
        #expect(press.end() == [.endCatch])
        #expect(press.stage == .over)
        // Cancelled, it's nothing, as an undecided pinch's cancel is.
        var cancelled = SurfacePress(at: 0.2, canHold: false, dragAlongScrolls: true, caughtACoast: true)
        #expect(cancelled.cancel() == [])
    }

    /// Moved on along the surface, the pinch that caught a coast scrolls on
    /// from where it caught it, as any drag along a surface that scrolls
    /// does; on one that doesn't, it drags along.
    @Test func aPinchThatCaughtACoastScrollsOrDragsAlongAsAnyDrag() {
        var scroll = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true, caughtACoast: true)
        #expect(scroll.move(sample(0.2118, moved: SIMD3(16, 2, 1), hand: SIMD3(0.015625, 1.5, -1))) == [
            .giveUpHold, .beginScroll(handMoved: SIMD3(0.015625, 0, 0)),
        ])
        #expect(scroll.end() == [.endScroll(coasting: true)])
        var along = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), caughtACoast: true)
        #expect(along.move(sample(0.2118, moved: SIMD3(16, 2, 1), hand: SIMD3(0.015625, 1.5, -1))) == [.giveUpHold, .beginDragAlong(from: 0.2, to: 0.2118)])
        #expect(along.end() == [.endDragAlong])
    }

    /// Held still for its second on a surface that can hold, the pinch that
    /// caught a coast still holds: a hold is deliberate, as a tap after a
    /// flick isn't.
    @Test func aPinchThatCaughtACoastStillHolds() {
        var press = SurfacePress(at: 0.2, canHold: true, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true, caughtACoast: true)
        #expect(press.holdTimerFired() == [.fireHold])
        #expect(press.end() == [.endHold])
    }

    /// A pinch that caught nothing is a tap, as ever.
    @Test func aPinchThatCaughtNothingIsATap() {
        var press = SurfacePress(at: 0.2, canHold: false, hand: SIMD3(0, 1.5, -1), dragAlongScrolls: true)
        #expect(!press.caughtACoast)
        #expect(press.end() == [.tap(at: 0.2)])
    }
}
