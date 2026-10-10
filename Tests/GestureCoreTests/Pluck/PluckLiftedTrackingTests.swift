import Testing
@testable import GestureCore

/// How a lifted pinch is followed, as the tuning's switches choose, in
/// order, and how the item's drag is made for it.
@Suite struct PluckLiftedTrackingTests {
    /// By default, the drag held back by its 60 pt start, brought down at
    /// the lift; and in order: the hold counted from the drag keeps the drag
    /// from the touch; the hand; the drag held back; the drag from the touch.
    @Test func theSwitchesChooseInOrder() {
        #expect(PluckTuning().liftedTracking == .dragHeldBack(.byItsStart(lowered: true)))
        #expect(PluckTuning(holdsFromTheDrag: true).liftedTracking == .dragFromTheTouch)
        #expect(PluckTuning(tracksLiftedPinchByHand: true).liftedTracking == .handFromTheLift(.byItsStart(lowered: true)))
        #expect(PluckTuning(holdsDragBackByItsMask: true).liftedTracking == .dragHeldBack(.byItsGestureMask))
        #expect(PluckTuning(lowersDragStartAtTheLift: false).liftedTracking == .dragHeldBack(.byItsStart(lowered: false)))
        #expect(PluckTuning(holdsDragBack: false).liftedTracking == .dragFromTheTouch)
        #expect(PluckTuning(holdsDragBack: false, tracksLiftedPinchByHand: true).liftedTracking == .handFromTheLift(.byItsStart(lowered: true)))
    }

    /// From the touch, the drag starts at the tuning's start throughout; held
    /// back by its start, at the held-back start, 60 pt, until attached, then
    /// from nothing, or at 60 pt throughout, not lowered, the known-safe
    /// fallback; held back by its mask, let in once attached, from nothing.
    @Test func theDragIsMadeAsTheChoiceSays() {
        let tuning = PluckTuning(dragStartDistance: 15)
        #expect(tuning.heldBackDragStart == 60)
        let fromTheTouch = PluckLiftedTracking.dragFromTheTouch
        #expect(fromTheTouch.drag(attached: false, tuning: tuning) == (15, true))
        #expect(fromTheTouch.drag(attached: true, tuning: tuning) == (15, true))
        #expect(!fromTheTouch.letsDragInAtTheLift)

        let lowered = PluckLiftedTracking.dragHeldBack(.byItsStart(lowered: true))
        #expect(lowered.drag(attached: false, tuning: tuning) == (60, true))
        #expect(lowered.drag(attached: true, tuning: tuning) == (0, true))
        #expect(lowered.letsDragInAtTheLift)

        let safe = PluckLiftedTracking.dragHeldBack(.byItsStart(lowered: false))
        #expect(safe.drag(attached: false, tuning: tuning) == (60, true))
        #expect(safe.drag(attached: true, tuning: tuning) == (60, true))
        #expect(!safe.letsDragInAtTheLift)

        let mask = PluckLiftedTracking.handFromTheLift(.byItsGestureMask)
        #expect(mask.drag(attached: false, tuning: tuning) == (0, false))
        #expect(mask.drag(attached: true, tuning: tuning) == (0, true))
        #expect(mask.letsDragInAtTheLift)
        #expect(mask.followsTheHand)
    }

    @Test func eachChoiceSaysWhatItIs() {
        #expect(PluckLiftedTracking.dragFromTheTouch.description == "the drag from the touch")
        #expect(PluckLiftedTracking.dragHeldBack(.byItsStart(lowered: true)).description == "the drag held back by its start, brought down at the lift")
        #expect(PluckLiftedTracking.dragHeldBack(.byItsStart(lowered: false)).description == "the drag held back by its start throughout")
        #expect(PluckLiftedTracking.handFromTheLift(.byItsGestureMask).description == "the hand from the lift, by hand tracking, over the drag held back by its gesture mask, let in at the lift")
    }
}
