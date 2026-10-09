import Testing
@testable import GestureCore

/// An item's pinches, one at a time, as its two gestures and its tap tell
/// them, at the default tuning: one account for each pinch as it ends, from
/// its first word to its last; a pinch whose press went before anything
/// else spoke kept until its tap, or the next pinch, says how it ended; the
/// pull armed `pullArmDelay` after the lift, by the caller's count or the
/// drag's next word, whichever comes first; and the item's tap swallowed as
/// the release of a pinch that lifted its item, within a second of its end,
/// once.
@Suite struct PluckPinchesTests {
    let start = ContinuousClock.now
    /// The points the tests measure to a meter, so the pull's 2 cm is 27 pt.
    let pointsPerMeter = 1350.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func moved(_ pinches: inout PluckPinches, _ x: Double, _ y: Double, _ z: Double, at seconds: Double) -> PluckPinches.Told {
        pinches.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: at(seconds))
    }

    /// A press begins a pinch, and the hold counts from it, half a second;
    /// any count to an arming left from the pinch before stops.
    @Test func aPressBeginsAPinchAndItsHoldsCount() {
        var pinches = PluckPinches()
        let told = pinches.pressBegan(at: at(0))
        #expect(told == PluckPinches.Told(why: .began, countdowns: [.stopArming, .startHold(.seconds(0.5))], beganAPinch: true))
        #expect(pinches.touchedAt == at(0))
        #expect(pinches.isHolding)
    }

    /// A quick pinch: its press goes as it's let go, and its tap comes then,
    /// in either order. It's a tap, which goes through.
    @Test func aQuickPinchIsATapThatGoesThrough() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        let tap = pinches.tapped(at: at(0.12))
        #expect(!tap.isRelease)
        #expect(tap.ended == nil)
        let told = pinches.pressEnded(at: at(0.13))
        #expect(told.actions == [])
        #expect(told.why == .pressEnded)
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.outcome == .tap)
        #expect(account.ending == .letGo)
        #expect(account.lasted == .seconds(0.13))
        #expect(account.heldAfter == nil)
        #expect(account.pressEndedAfter == .seconds(0.13))
        #expect(account.dragReportedAfter == nil)
        #expect(account.moved == nil)
        #expect(pinches.press == nil)
    }

    /// The press goes first, as a pinch drifts off the item short of the
    /// drag's 15 pt, and the pinch goes on: it's kept until its tap comes as
    /// it's let go, which tells how long it lasted, and stops the counts.
    @Test func aPinchWhosePressWentFirstEndsWithItsTap() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        #expect(pinches.pressEnded(at: at(0.15)) == PluckPinches.Told(why: .pressEnded))
        #expect(pinches.press != nil)
        let tap = pinches.tapped(at: at(0.6))
        #expect(!tap.isRelease)
        #expect(tap.sinceTouch == .seconds(0.6))
        #expect(tap.countdowns == [.stopHold, .stopArming])
        let account = try #require(tap.ended)
        #expect(account.outcome == .tap)
        #expect(account.lasted == .seconds(0.6))
        #expect(account.pressEndedAfter == .seconds(0.15))
        #expect(pinches.press == nil)
    }

    /// The hold's count, coming up after its press went, finds neither
    /// gesture holding the pinch, and lifts nothing.
    @Test func aHoldAfterThePressWentLiftsNothing() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.pressEnded(at: at(0.15))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)) == PluckPinches.Told(why: .letGoBeforeTheHold))
        #expect(pinches.press?.isLifted == false)
    }

    /// One kept that way whose tap never comes is told as the next pinch
    /// begins, its end unseen.
    @Test func aPinchWhoseEndWentUnseenIsToldAsTheNextBegins() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.pressEnded(at: at(0.15))
        let next = pinches.pressBegan(at: at(5))
        #expect(next.actions == [])
        #expect(next.beganAPinch)
        #expect(next.countdowns == [.stopArming, .startHold(.seconds(0.5))])
        let account = try #require(next.ended)
        #expect(account.outcome == .nothing)
        #expect(account.ending == .unseen)
        #expect(account.lasted == nil)
        #expect(account.pressEndedAfter == .seconds(0.15))
        #expect(pinches.press != nil)
        // The next, let go before its hold, its press going and its tap
        // coming together.
        #expect(pinches.pressEnded(at: at(5.125)).ended == nil)
        let ended = try #require(pinches.tapped(at: at(5.125)).ended)
        #expect(ended.outcome == .tap)
        #expect(ended.lasted == .seconds(0.125))
    }

    /// A press that never said it ended, its item lifted, is over once the
    /// next press begins: its item settles, so the container scrolls again,
    /// and the new pinch begins afresh.
    @Test func aNewPressEndsALiftWhosePressEndWentUnseen() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        let held = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(held == PluckPinches.Told(actions: [.lift], why: .heldStill, countdowns: [.startArming(.seconds(0.2))]))
        let next = pinches.pressBegan(at: at(9))
        #expect(next.actions == [.settle])
        let account = try #require(next.ended)
        #expect(account.outcome == .lift)
        #expect(account.ending == .unseen)
        #expect(account.settledAfter == nil)
        #expect(pinches.press?.isLifted == false)
        #expect(pinches.isHolding)
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(9.5)).actions == [.lift])
    }

    /// A hold let go without a pull is a lift, and its item's tap, even once
    /// the press's end has forgotten the pinch, is its release, no tap, and
    /// only the first.
    @Test func aHoldLetGoIsALiftWhoseTapIsSwallowedOnce() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
        let told = pinches.pressEnded(at: at(0.9))
        #expect(told.actions == [.settle])
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.outcome == .lift)
        #expect(account.ending == .letGo)
        #expect(account.heldAfter == .seconds(0.5))
        #expect(account.armedAfter == nil)
        #expect(account.settledAfter == .seconds(0.9))
        #expect(account.lasted == .seconds(0.9))
        #expect(pinches.press == nil)
        let tap = pinches.tapped(at: at(0.92))
        #expect(tap.isRelease)
        #expect(tap.ended == nil)
        #expect(!pinches.tapped(at: at(0.95)).isRelease)
    }

    /// Its tap may come while the hold is under way: it's the release
    /// there, and none is expected after.
    @Test func aTapWhileTheHoldIsUnderWayIsItsReleaseThere() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        let tap = pinches.tapped(at: at(0.8))
        #expect(tap.isRelease)
        #expect(tap.actions == [])
        _ = pinches.pressEnded(at: at(0.81))
        #expect(!pinches.tapped(at: at(0.9)).isRelease)
    }

    @Test func theReleaseGraceLastsASecond() {
        #expect(PluckTuning().releaseTapTime == .seconds(1))
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.pressEnded(at: at(0.9))
        #expect(!pinches.tapped(at: at(1.95)).isRelease)
    }

    /// Held, then pulled: the item lifts at the hold, a move before the pull
    /// arms pulls nothing, the caller's count arms it two tenths of a second
    /// after the lift, the next move pulls, and the pinch is one, from its
    /// touch to its release, its tap its release.
    @Test func aHoldThenAPullIsOnePinch() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
        #expect(moved(&pinches, 0, 0, 15, at: 0.6) == PluckPinches.Told(why: .notArmedYet))
        #expect(moved(&pinches, 2, 3, 35, at: 0.65) == PluckPinches.Told(why: .notArmedYet))
        #expect(pinches.armPull(at: at(0.7)) == PluckPinches.Told(actions: [.pullArmed], why: .armed))
        #expect(moved(&pinches, 2, 3, 36, at: 0.72).actions == [.beginPull])
        #expect(moved(&pinches, 40, -90, 120, at: 1).actions == [.movePull])
        #expect(pinches.tapped(at: at(1.3)).isRelease)
        let told = pinches.dragEnded(at: at(1.31))
        #expect(told.actions == [.endPull, .settle])
        #expect(told.ended == nil)
        #expect(told.countdowns == [])
        let account = try #require(pinches.pressEnded(at: at(1.32)).ended)
        #expect(account.outcome == .pull)
        #expect(account.ending == .letGo)
        #expect(account.lasted == .seconds(1.32))
        #expect(account.heldAfter == .seconds(0.5))
        #expect(account.armedAfter == .seconds(0.7))
        #expect(account.pulledAfter == .seconds(0.72))
        #expect(account.pressEndedAfter == .seconds(1.32))
        #expect(account.settledAfter == .seconds(1.31))
        #expect(account.dragReportedAfter == .seconds(0.6))
        #expect(account.moved == SIMD3(40, -90, 120))
        let farthest: Double = (1600 + 8100 + 14400 as Double).squareRoot()
        #expect(abs(account.farthest - farthest) < 1e-9)
        #expect(account.farthestBeforeHold == 0)
        #expect(!pinches.tapped(at: at(1.4)).isRelease)
    }

    /// The drag's word arms the pull should the caller's count be late, and
    /// pulls at once if the move already counts.
    @Test func theDragArmsThePullWhenTheCountIsLate() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(moved(&pinches, 0, 0, 40, at: 0.75).actions == [.pullArmed, .beginPull])
        #expect(pinches.armPull(at: at(0.76)) == PluckPinches.Told(why: .armingNotDue))
    }

    /// Before its two tenths are up, neither the count nor the drag arms the
    /// pull.
    @Test func nothingArmsThePullEarly() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.armPull(at: at(0.65)) == PluckPinches.Told(why: .armingNotDue))
        #expect(moved(&pinches, 0, 0, 40, at: 0.69) == PluckPinches.Told(why: .notArmedYet))
        #expect(pinches.press?.isArmed == false)
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
    }

    /// A yank toward the viewer before the hold is a scroll, which lifts and
    /// pulls nothing, and stops the hold's count.
    @Test func aYankBeforeTheHoldIsAScroll() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        let yank = moved(&pinches, 0, 0, 15, at: 0.08)
        #expect(yank == PluckPinches.Told(actions: [.stayDown(.movedFirst)], why: .movedFirst(distance: 15), countdowns: [.stopHold]))
        #expect(moved(&pinches, 2, 3, 60, at: 0.2) == PluckPinches.Told(why: .scrolling(.movedFirst)))
        #expect(pinches.pressEnded(at: at(0.25)) == PluckPinches.Told(why: .dragHasThePinch))
        let told = pinches.dragEnded(at: at(0.4))
        #expect(told.actions == [])
        let account = try #require(told.ended)
        #expect(account.outcome == .scroll)
        #expect(account.stayedDown == .movedFirst)
        #expect(account.heldAfter == nil)
        let farthest: Double = (4 + 9 + 3600 as Double).squareRoot()
        #expect(account.farthestBeforeHold == farthest)
    }

    /// A flat drag the container's scroll view takes over, cancelling the
    /// item's, is a scroll.
    @Test func aScrollIsAScroll() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.pressEnded(at: at(0.06))
        #expect(moved(&pinches, 0, 40, 2, at: 0.1).actions == [.stayDown(.movedFirst)])
        _ = moved(&pinches, 0, 300, 20, at: 0.4)
        let told = pinches.dragCancelled(at: at(0.41))
        #expect(told.actions == [])
        #expect(told.why == .dragCancelled)
        let account = try #require(told.ended)
        #expect(account.outcome == .scroll)
        #expect(account.ending == .cancelled)
        #expect(account.moved == SIMD3(0, 300, 20))
        #expect(!pinches.tapped(at: at(0.5)).isRelease)
    }

    /// A hold that comes after the container scrolled is a scroll, which
    /// lifts nothing and isn't swallowed.
    @Test func aHoldAfterTheContainerScrolledIsAScroll() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        let held = pinches.holdFired(asTheContainerScrolled: true, at: at(0.5))
        #expect(held == PluckPinches.Told(actions: [.stayDown(.containerScrolled)], why: .containerScrolled))
        let account = try #require(pinches.pressEnded(at: at(0.6)).ended)
        #expect(account.outcome == .scroll)
        #expect(account.stayedDown == .containerScrolled)
        #expect(account.heldAfter == .seconds(0.5))
        #expect(!pinches.tapped(at: at(0.62)).isRelease)
    }

    /// A pinch held until its item lifts, then swept up as a scroll would
    /// be, pulls nothing, and its item stays up until it's let go: its
    /// container's scroll is off under it. Its tap is no tap.
    @Test func aLiftedPinchSweptUpStaysUpAndPullsNothing() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        let swept = moved(&pinches, 0, -40, 3, at: 0.8)
        #expect(swept.actions == [])
        #expect(swept.why == .notAPull(PluckPullJudgement(depth: 3, drift: 40, threshold: 27, verdict: .tooShallow)))
        #expect(moved(&pinches, 0, -260, 25, at: 0.9).actions == [])
        #expect(pinches.press?.isLifted == true)
        #expect(pinches.dragEnded(at: at(1)).actions == [.settle])
        let account = try #require(pinches.pressEnded(at: at(1)).ended)
        #expect(account.outcome == .lift)
        #expect(account.dragReportedAfter == .seconds(0.8))
        #expect(pinches.tapped(at: at(1.05)).isRelease)
    }

    /// The hold's press may end mid-drag, as the hand moves off the item,
    /// and come back: that's no new pinch, the item stays up, and the drag's
    /// end settles it.
    @Test func aPressComingBackMidDragIsNoNewPinch() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = moved(&pinches, 80, 0, 5, at: 0.6)
        #expect(pinches.pressEnded(at: at(0.65)) == PluckPinches.Told(why: .dragHasThePinch))
        #expect(pinches.press?.isLifted == true)
        #expect(pinches.pressBegan(at: at(0.9)) == PluckPinches.Told(why: .pressJoined))
        #expect(pinches.press?.isLifted == true)
        #expect(pinches.dragEnded(at: at(1.2)).actions == [.settle])
        let account = try #require(pinches.pressEnded(at: at(1.2)).ended)
        #expect(account.outcome == .lift)
        #expect(account.heldAfter == .seconds(0.5))
        #expect(account.lasted == .seconds(1.2))
    }

    /// An item that goes mid-pull, as it leaves its container, takes its
    /// pull away and lets itself down; no tap is expected after.
    @Test func anItemGoingMidPullTakesItsPullAway() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, 0, 0, 40, at: 0.75).actions == [.beginPull])
        let told = pinches.itemWent(at: at(0.9))
        #expect(told.actions == [.cancelPull, .settle])
        #expect(told.why == .itemWent)
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.ending == .itemWent)
        #expect(account.outcome == .pull)
        #expect(pinches.press == nil)
        #expect(!pinches.isDragging)
        #expect(!pinches.isHolding)
        #expect(!pinches.tapped(at: at(1)).isRelease)
    }

    @Test func anItemGoingWithNothingUnderWayDoesNothing() {
        var pinches = PluckPinches()
        #expect(pinches.itemWent(at: at(1)) == PluckPinches.Told(why: .noPinch))
    }

    /// Words with no pinch under way change nothing, and say so.
    @Test func wordsWithNoPinchChangeNothing() {
        var pinches = PluckPinches()
        let nothing = PluckPinches.Told(why: .noPinch)
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)) == nothing)
        #expect(pinches.armPull(at: at(0.7)) == nothing)
        #expect(pinches.pressEnded(at: at(0.8)) == nothing)
        #expect(pinches.dragEnded(at: at(0.9)) == nothing)
        #expect(pinches.dragCancelled(at: at(1)) == nothing)
        #expect(pinches.press == nil)
    }
}
