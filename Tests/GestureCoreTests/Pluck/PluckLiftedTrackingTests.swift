import Testing
@testable import GestureCore

/// How a lifted pinch is followed, as the tuning's switches choose, in
/// order, and how the item's drag is made for it.
@Suite struct PluckLiftedTrackingTests {
    /// By default, the hand once lifted, the drag held back by its gesture
    /// mask; and in order: the hold counted from the drag keeps the drag
    /// from the touch; the hand; the drag once lifted; the drag from the
    /// touch.
    @Test func theSwitchesChooseInOrder() {
        #expect(PluckTuning().liftedTracking == .handOnceLifted(.byItsGestureMask))
        #expect(PluckTuning(holdsFromTheDrag: true).liftedTracking == .dragFromTheTouch)
        #expect(PluckTuning(tracksLiftedPinchByHand: false).liftedTracking == .dragOnceLifted(.byItsGestureMask))
        #expect(PluckTuning(tracksLiftedPinchByHand: false, holdsDragBackByItsStart: true).liftedTracking == .dragOnceLifted(.byItsStartDistance))
        #expect(PluckTuning(tracksLiftedPinchByHand: false, attachesDragOnceLifted: false).liftedTracking == .dragFromTheTouch)
        #expect(PluckTuning(attachesDragOnceLifted: false, holdsDragBackByItsStart: true).liftedTracking == .handOnceLifted(.byItsStartDistance))
    }

    /// The drag from the touch hears the pinch from the tuning's start, let
    /// in all along; held back by its mask, it's let in once attached, from
    /// nothing; held back by its start, it's let in all along, from a start
    /// no pinch reaches until attached.
    @Test func theDragIsMadeAsTheChoiceSays() {
        let tuning = PluckTuning(dragStartDistance: 15)
        let fromTheTouch = PluckLiftedTracking.dragFromTheTouch
        #expect(fromTheTouch.drag(attached: false, tuning: tuning) == (15, true))
        #expect(fromTheTouch.dragHearsThePinchBeforeTheLift)
        #expect(!fromTheTouch.followsTheHand)

        let mask = PluckLiftedTracking.dragOnceLifted(.byItsGestureMask)
        #expect(mask.drag(attached: false, tuning: tuning) == (0, false))
        #expect(mask.drag(attached: true, tuning: tuning) == (0, true))
        #expect(!mask.dragHearsThePinchBeforeTheLift)

        let start = PluckLiftedTracking.handOnceLifted(.byItsStartDistance)
        #expect(start.drag(attached: false, tuning: tuning) == (PluckLiftedTracking.unreachableStart, true))
        #expect(start.drag(attached: true, tuning: tuning) == (0, true))
        #expect(start.followsTheHand)
        #expect(start.heldBack == .byItsStartDistance)
    }

    @Test func eachChoiceSaysWhatItIs() {
        #expect(PluckLiftedTracking.dragFromTheTouch.description == "the drag from the touch")
        #expect(PluckLiftedTracking.dragOnceLifted(.byItsStartDistance).description == "the drag once lifted, held back by an unreachable start")
        #expect(PluckLiftedTracking.handOnceLifted(.byItsGestureMask).description == "the hand once lifted, by hand tracking, else the drag once lifted, held back by its gesture mask")
    }
}
