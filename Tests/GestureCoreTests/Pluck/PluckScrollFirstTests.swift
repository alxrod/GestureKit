import Testing
@testable import GestureCore

/// A pinch on an item is its container's scroll unless it's a hold, as
/// Alex asked on October 9: "Scrolling always needs to take precedent over
/// pluck." Before the hold, a move of 10 pt along the scroll, a move of the
/// container's scroll offset past a point, or its scroll view scrolling,
/// makes the pinch a scroll for good; across the scroll and in depth the
/// hold allows 40 pt, for a fresh pinch's settling. Lifted, a move mostly
/// along the scroll gives the pinch back to it. The quarter-second lift, the
/// sticky stage, the break-free any other way, and the hand-off are as they
/// were.
@Suite struct PluckScrollFirstTests {
    let start = ContinuousClock.now
    let pointsPerMeter = 1360.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func moved(_ pinches: inout PluckPinches, _ x: Double, _ y: Double, _ z: Double, at seconds: Double) -> PluckPinches.Told {
        pinches.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: at(seconds))
    }

    /// Pinches pressed at 0 with the container's scroll offset read there,
    /// 400 pt down.
    func pressed(_ tuning: PluckTuning = PluckTuning()) -> PluckPinches {
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.scrollOffset(SIMD2(0, 400), at: at(0))
        return pinches
    }

    // MARK: Along the scroll

    /// A move 12 pt along the scroll before the hold, short of the 40 pt any
    /// way, is a scroll: the hold stops counting, and lifts nothing should
    /// it come anyway, nor does the rest of the pinch.
    @Test func aMoveAlongTheScrollGivesTheHoldUp() throws {
        var pinches = pressed()
        let told = moved(&pinches, 3, 12, 0, at: 0.15)
        #expect(told == PluckPinches.Told(actions: [.stayDown(.movedFirst)], why: .movedAlongTheScroll(distance: 12, stillness: 10), countdowns: [.stopHold]))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.25)).actions == [])
        #expect(moved(&pinches, 3, 60, 0, at: 0.4).why == .scrolling(.movedFirst))
        _ = pinches.pressEnded(at: at(0.45))
        let account = try #require(pinches.dragEnded(at: at(0.6)).ended)
        #expect(account.outcome == .scroll)
        // The hold's count came at 0.25 s, lifting nothing.
        #expect(account.farthestAlongScrollBeforeHold == 12)
    }

    /// The drag says nothing before 15 pt, so its first word gives the hold
    /// up when two thirds of it or more lie along the scroll.
    @Test func aFirstWordTwoThirdsAlongTheScrollIsAScroll() {
        var along = pressed()
        #expect(moved(&along, 11.19, 10, 0, at: 0.15).actions == [.stayDown(.movedFirst)])
        var across = pressed()
        #expect(moved(&across, 11.3, 9.9, 0, at: 0.15).actions == [])
        #expect(across.holdFired(asTheContainerScrolled: false, at: at(0.25)).actions == [.lift])
    }

    /// Across the scroll and in depth the hold allows what it did, 40 pt, for
    /// a pinch's settling.
    @Test func acrossTheScrollTheLooseAllowanceStays() {
        var pinches = pressed()
        #expect(moved(&pinches, 30, 9, 12, at: 0.15).actions == [])
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.25)).actions == [.lift])
        var far = pressed()
        #expect(moved(&far, 38, 0, 14, at: 0.15).why == .movedFirst(distance: (38 * 38 + 14 * 14 as Double).squareRoot(), stillness: 40))
    }

    /// The scroll's axis is the container's: a grid scrolling across watches
    /// moves across.
    @Test func aContainerScrollingAcrossWatchesMovesAcross() {
        var pinches = PluckPinches()
        pinches.scrollAxes = .horizontal
        _ = pinches.pressBegan(at: at(0))
        #expect(pinches.press?.scrollAxes == .horizontal)
        #expect(moved(&pinches, 12, 3, 0, at: 0.15).why == .movedAlongTheScroll(distance: 12, stillness: 10))

        var down = PluckPinches()
        down.scrollAxes = .horizontal
        _ = down.pressBegan(at: at(0))
        #expect(moved(&down, 3, 12, 0, at: 0.15).actions == [])
    }

    @Test func theAxesTakeAMoveApart() {
        let move = SIMD3<Double>(3, 4, 12)
        #expect(PluckScrollAxes.vertical.distance(along: move) == 4)
        #expect(PluckScrollAxes.vertical.distance(across: move) == (9 + 144 as Double).squareRoot())
        #expect(PluckScrollAxes.horizontal.distance(along: move) == 3)
        #expect(PluckScrollAxes([.horizontal, .vertical]).distance(along: move) == 5)
        #expect(PluckScrollAxes([.horizontal, .vertical]).distance(across: move) == 12)
    }

    // MARK: The scroll offset

    /// The container's scroll offset moving a point and a half from where it
    /// stood at the touch, before the hold, makes the pinch a scroll,
    /// whatever its scroll view's phase says; 0.75 pt doesn't.
    @Test func theScrollOffsetMovingGivesTheHoldUp() throws {
        var container = PluckContainer<Int>()
        _ = container.scrollPhaseChanged(to: .tracking, at: at(0.02))
        var pinches = pressed()
        #expect(pinches.scrollOffset(SIMD2(0, 400.75), at: at(0.05)) == PluckPinches.Told(why: .scrollOffsetWithin(distance: 0.75, stillness: 1)))
        let moved = pinches.scrollOffset(SIMD2(0, 401.5), at: at(0.1))
        #expect(moved.actions == [.stayDown(.containerScrolled)])
        #expect(moved.why == .scrollOffsetMoved(distance: 1.5, stillness: 1))
        #expect(moved.countdowns == [.stopHold])
        // The scroll view still says it's only tracking.
        #expect(!container.scrolled(since: at(0)))
        #expect(pinches.holdFired(asTheContainerScrolled: container.scrolled(since: at(0)), at: at(0.25)).actions == [])
        #expect(pinches.press?.isLifted == false)
        let account = try #require(pinches.pressEnded(at: at(0.3)).ended)
        #expect(account.outcome == .scroll)
        #expect(account.stayedDown == .containerScrolled)
        #expect(account.scrollOffsetMovedBeforeHold == 1.5)
    }

    /// A still pinch, its offset where it was, lifts at the quarter second,
    /// with its scroll view tracking it: tracking a pinch that hasn't moved
    /// the content is no scroll, since it tracks every pinch from its touch.
    @Test func aStillPinchLiftsWhileItsScrollViewTracksIt() throws {
        var container = PluckContainer<Int>()
        _ = container.scrollPhaseChanged(to: .tracking, at: at(0.02))
        var pinches = pressed()
        _ = pinches.scrollOffset(SIMD2(0, 400), at: at(0.25))
        #expect(pinches.holdFired(asTheContainerScrolled: container.scrolled(since: at(0)), at: at(0.25)).actions == [.lift])
        _ = pinches.dragEnded(at: at(0.5))
        let account = try #require(pinches.pressEnded(at: at(0.5)).ended)
        #expect(account.scrollOffsetMovedBeforeHold == 0)
    }

    /// The scroll view taking a pinch cancels its press; its offset moving
    /// then ends the pinch, a scroll, with no tap to wait for.
    @Test func theOffsetEndsAPinchTheScrollViewTook() throws {
        var pinches = pressed()
        _ = pinches.pressEnded(at: at(0.1))
        let told = pinches.scrollOffset(SIMD2(0, 412), at: at(0.12))
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.outcome == .scroll)
        #expect(account.ending == .cancelled)
        #expect(!pinches.tapped(at: at(0.2)).isRelease)
    }

    /// Past the hold, the offset changes nothing: the lift holds the scroll
    /// off, and only code moves it.
    @Test func anOffsetAfterTheLiftChangesNothing() {
        var pinches = pressed()
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        #expect(pinches.scrollOffset(SIMD2(0, 420), at: at(0.3)).actions == [])
        #expect(pinches.press?.isLifted == true)
    }

    /// Unwatched, as until October 9, the offset gives nothing up.
    @Test func anUnwatchedOffsetGivesNothingUp() {
        var pinches = pressed(PluckTuning(holdWatchesScrollOffset: false))
        #expect(pinches.scrollOffset(SIMD2(0, 430), at: at(0.1)).actions == [])
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.25)).actions == [.lift])
    }

    /// An offset that isn't a number, or one with no pinch, changes nothing.
    @Test func whatIsntAnOffsetChangesNothing() {
        var none = PluckPinches()
        #expect(none.scrollOffset(SIMD2(0, 1), at: at(0)) == PluckPinches.Told(why: .noPinch))
        var pinches = pressed()
        #expect(pinches.scrollOffset(SIMD2(.nan, 0), at: at(0.1)) == PluckPinches.Told(why: .notANumber))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.25)).actions == [.lift])
    }

    // MARK: The old hold, through the tuning

    /// The hold as it was, along the scroll the same as any way and the
    /// offset unwatched, lets a slow scroll's first 15 pt along it and a
    /// moving offset by, and lifts: what Alex found eating scrolls.
    @Test func theOldHoldIsATuningAway() {
        var pinches = pressed(.loose)
        #expect(moved(&pinches, 3, 15, 0, at: 0.2).actions == [])
        #expect(pinches.scrollOffset(SIMD2(0, 404), at: at(0.3)).actions == [])
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
    }

    // MARK: Giving a held item's pinch back to the scroll

    /// With the switch off, as until October 9, a held item keeps a move
    /// along the scroll, stretching toward breaking free as across.
    @Test func withTheSwitchOffAHeldItemKeepsAMoveAlongTheScroll() {
        var pinches = pressed(PluckTuning(givesLiftBackToScroll: false))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        #expect(moved(&pinches, 0, 20, 0, at: 0.35).actions == [])
        #expect(pinches.press?.isLifted == true)
        #expect(pinches.stretch?.reach == 20)
    }

    /// By default, a held item's pinch moved 12 pt along the scroll from
    /// where it lifted, 3 across and in depth, is given back: the item
    /// settles, so the container's scroll comes back on, and the pinch is a
    /// scroll for the rest of it, its release no tap.
    @Test func aHeldItemGivesAMoveAlongTheScrollBack() throws {
        #expect(PluckTuning().givesLiftBackToScroll)
        var pinches = pressed()
        _ = moved(&pinches, 5, 0, 0, at: 0.2)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        let back = moved(&pinches, 5, 12, 3, at: 0.3)
        #expect(back.actions == [.settle])
        #expect(back.why == .givenBackToTheScroll(along: 12, across: 3))
        #expect(pinches.press?.stayedDown == .givenBackToTheScroll)
        #expect(pinches.follow == .zero)
        #expect(moved(&pinches, 5, 80, 3, at: 0.5).why == .scrolling(.givenBackToTheScroll))
        #expect(pinches.armPull(at: at(0.5)).actions == [])
        #expect(pinches.dragEnded(at: at(0.7)).actions == [])
        let account = try #require(pinches.pressEnded(at: at(0.7)).ended)
        #expect(account.outcome == .scroll)
        #expect(pinches.tapped(at: at(0.72)).isRelease)
    }

    /// Only a move mostly along the scroll is given back: a pull toward the
    /// viewer drifting down, or one across, stays the item's, and breaks it
    /// free.
    @Test func aPullThatsMostlyNotAlongTheScrollStaysTheItems() {
        var toward = pressed()
        _ = toward.holdFired(asTheContainerScrolled: false, at: at(0.25))
        _ = toward.armPull(at: at(0.45))
        #expect(moved(&toward, 0, 12, 10, at: 0.5).actions == [])
        #expect(toward.press?.isLifted == true)
        #expect(moved(&toward, 0, 16, 31, at: 0.6).actions == [.breakFree])

        var across = pressed()
        _ = across.holdFired(asTheContainerScrolled: false, at: at(0.25))
        _ = across.armPull(at: at(0.45))
        #expect(moved(&across, 34, 5, 0, at: 0.6).actions == [.breakFree])
    }

    // MARK: The trace's words

    @Test func theReasonsSayWhyItStayedAScroll() {
        #expect(PluckReason.movedAlongTheScroll(distance: 12, stillness: 10).description == "moved 12.0 pt along the scroll before the hold, its stillness along it 10.0 pt: a scroll")
        #expect(PluckReason.scrollOffsetMoved(distance: 1.5, stillness: 1).description == "the scroll offset moved 1.5 pt since the touch, past its 1.0 pt, before the hold: a scroll")
        #expect(PluckReason.scrollOffsetWithin(distance: 0.44, stillness: 1).description == "the scroll offset 0.4 pt from the touch, within its 1.0 pt")
        #expect(PluckReason.givenBackToTheScroll(along: 12, across: 3).description == "held, moved 12.0 pt along the scroll and 3.0 pt across it and in depth: given back to the scroll")
        #expect(PluckReason.scrolling(.givenBackToTheScroll).description == "a scroll (given back to it)")
    }
}
