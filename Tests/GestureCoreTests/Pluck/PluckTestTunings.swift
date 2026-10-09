@testable import GestureCore

extension PluckTuning {
    /// The tuning the pluck first shipped with: the drag's first word
    /// before the hold a scroll, at a stillness equal to its 15 pt start; a
    /// pull 2 cm toward the viewer, 1 deep for every 2 across, measured from
    /// the touch; and the press's end settling a lifted item. What the moved
    /// tests prove the rules still do.
    static let firstShipped = PluckTuning(
        holdStillness: 15,
        pullDistance: 0.02,
        pullsAnyDirection: false,
        measuresPullFromArming: false,
        pressEndSettlesLiftedItem: true
    )

    /// The pull as the pluck first shipped it, 2 cm toward the viewer, 1 deep
    /// for every 2 across, from the touch, with the hold and the rest at
    /// today's defaults.
    static let towardTheViewerFromTheTouch = PluckTuning(
        pullDistance: 0.02,
        pullsAnyDirection: false,
        measuresPullFromArming: false
    )
}
