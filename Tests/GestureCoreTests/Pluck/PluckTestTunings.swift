@testable import GestureCore

extension PluckTuning {
    /// The tuning the pluck first shipped with: a hold of half a second; the
    /// drag's first word before the hold a scroll, at a stillness equal to
    /// its 15 pt start; a pull 2 cm toward the viewer, 1 deep for every 2
    /// across, measured from the touch; the lifted item following nothing,
    /// and keeping every move; and the press's end settling a lifted item.
    /// What the moved tests prove the rules still do.
    static let firstShipped = PluckTuning(
        holdDuration: 0.5,
        holdStillness: 15,
        breakFreeDistance: 0.02,
        followShare: 0,
        pullsAnyDirection: false,
        measuresPullFromLift: false,
        givesLiftBackToScroll: false,
        pressEndSettlesLiftedItem: true
    )

    /// The pluck as Alex tried it in the lab on October 9, loose both ways: a
    /// hold of half a second, given up by its scroll view's phase or a move
    /// of 40 pt any way, along the scroll or not, its scroll offset
    /// unwatched; and a pull of 6 mm any way from where the pinch stood as
    /// its item lifted, the lifted item following nothing and keeping every
    /// move; the rest at today's defaults. Its item spawned the instant it
    /// lifted, and slow scrolls lifted their items; it's six values away, as
    /// the headset's trace replays prove.
    static let loose = PluckTuning(
        holdDuration: 0.5,
        holdStillnessAlongScroll: 40,
        holdWatchesScrollOffset: false,
        breakFreeDistance: 0.006,
        followShare: 0,
        givesLiftBackToScroll: false
    )

    /// The pull as the pluck first shipped it, 2 cm toward the viewer, 1 deep
    /// for every 2 across, from the touch, a held item keeping every move,
    /// with the hold and the rest at today's defaults.
    static let towardTheViewerFromTheTouch = PluckTuning(
        breakFreeDistance: 0.02,
        pullsAnyDirection: false,
        measuresPullFromLift: false,
        givesLiftBackToScroll: false
    )
}
