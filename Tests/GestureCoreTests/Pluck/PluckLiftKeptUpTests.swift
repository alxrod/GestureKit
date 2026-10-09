import Testing
@testable import GestureCore

/// At the default tuning, a lifted item stays up as its press ends with the
/// drag not having the pinch, and settles as the pinch is otherwise known to
/// be let go: the item's tap, before the press's end or after, the drag's
/// end, or the next pinch here or anywhere else in the container. And the
/// container's scroll, told to the pinch under way, makes it a scroll before
/// its hold, and settles a lifted item as tuned.
@Suite struct PluckLiftKeptUpTests {
    let start = ContinuousClock.now
    let pointsPerMeter = 1350.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// Pinches at the default tuning, pressed at 0 and lifted at 0.5.
    func lifted(_ tuning: PluckTuning = PluckTuning()) -> PluckPinches {
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        return pinches
    }

    // MARK: Let go, with the lift kept past the press

    /// The press ending first, then the tap: the tap settles it.
    @Test func thePressThenTheTapSettles() throws {
        var pinches = lifted()
        #expect(pinches.pressEnded(at: at(0.9)) == PluckPinches.Told(why: .liftOutlivesItsPress))
        #expect(pinches.isKeptUpPastItsPress)
        let tap = pinches.tapped(at: at(0.91))
        #expect(tap.isRelease)
        #expect(tap.actions == [.settle])
        #expect(try #require(tap.ended).outcome == .lift)
    }

    /// The tap first, then the press ending: the press's end settles it,
    /// the tap having said the pinch was let go.
    @Test func theTapThenThePressSettles() throws {
        var pinches = lifted()
        let tap = pinches.tapped(at: at(0.9))
        #expect(tap.isRelease)
        #expect(tap.actions == [])
        let told = pinches.pressEnded(at: at(0.91))
        #expect(told.actions == [.settle])
        #expect(told.why == .releasedByItsTap)
        let account = try #require(told.ended)
        #expect(account.outcome == .lift)
        #expect(account.settledAfter == .seconds(0.91))
        #expect(!pinches.tapped(at: at(0.95)).isRelease)
    }

    /// A press cancelled at the lift, with no tap, keeps the item up until a
    /// pinch begins on another item, which settles it, its end unseen.
    @Test func aPinchElsewhereSettlesALiftKeptPastItsPress() throws {
        var pinches = lifted()
        _ = pinches.pressEnded(at: at(0.52))
        let told = pinches.pinchBeganElsewhere(at: at(4))
        #expect(told.actions == [.settle])
        #expect(told.why == .pinchElsewhere)
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.outcome == .lift)
        #expect(account.ending == .unseen)
        #expect(account.pressEndedAfter == .seconds(0.52))
        #expect(pinches.press == nil)
    }

    /// A pinch elsewhere leaves alone one a gesture still has, and does
    /// nothing with no pinch here.
    @Test func aPinchElsewhereLeavesAHeldPinchAlone() {
        var held = lifted()
        #expect(held.pinchBeganElsewhere(at: at(1)) == PluckPinches.Told(why: .toldAlready))
        #expect(held.press?.isLifted == true)

        var dragged = lifted()
        _ = dragged.pressEnded(at: at(0.52))
        _ = dragged.dragMoved(SIMD3(20, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.8))
        #expect(!dragged.isKeptUpPastItsPress)
        #expect(dragged.pinchBeganElsewhere(at: at(1)) == PluckPinches.Told(why: .toldAlready))

        var none = PluckPinches()
        #expect(none.pinchBeganElsewhere(at: at(1)) == PluckPinches.Told(why: .noPinch))
    }

    // MARK: The container's scroll

    /// A scroll before the hold makes the pinch a scroll, and its hold stops
    /// counting; its hold's time, should it come, lifts nothing.
    @Test func aScrollBeforeTheHoldIsAScroll() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        let told = pinches.containerScrolled(at: at(0.2))
        #expect(told == PluckPinches.Told(actions: [.stayDown(.containerScrolled)], why: .containerScrolled, countdowns: [.stopHold]))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [])
    }

    /// A scroll that took the press, the pinch waiting for a tap that won't
    /// come, ends it: a scroll, cancelled.
    @Test func aScrollThatTookThePressEndsThePinch() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.pressEnded(at: at(0.15))
        let told = pinches.containerScrolled(at: at(0.16))
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.outcome == .scroll)
        #expect(account.ending == .cancelled)
        #expect(account.stayedDown == .containerScrolled)
    }

    /// A scroll settles a lifted item; the pinch goes on, nothing to pull.
    @Test func aScrollSettlesALiftedItem() {
        var pinches = lifted()
        let told = pinches.containerScrolled(at: at(0.6))
        #expect(told == PluckPinches.Told(actions: [.settle], why: .containerScrolled))
        #expect(pinches.press?.isLifted == false)
        #expect(pinches.containerScrolled(at: at(0.7)) == PluckPinches.Told(why: .toldAlready))
    }

    /// A scroll leaves a pull under way, or a lift the tuning keeps, up.
    @Test func aScrollLeavesAPullOrATunedLiftUp() {
        var pulling = lifted()
        _ = pulling.armPull(at: at(0.7))
        _ = pulling.dragMoved(SIMD3(0, 0, 40), pointsPerMeter: pointsPerMeter, at: at(0.8))
        #expect(pulling.containerScrolled(at: at(0.9)) == PluckPinches.Told(why: .scrollLeftTheItemUp))
        #expect(pulling.press?.isPulling == true)

        var kept = lifted(PluckTuning(scrollSettlesLiftedItem: false))
        #expect(kept.containerScrolled(at: at(0.6)) == PluckPinches.Told(why: .scrollLeftTheItemUp))
        #expect(kept.press?.isLifted == true)
    }

    // MARK: The reasons, for a trace

    @Test func theReasonsSayWhyInPlainWords() {
        #expect(PluckReason.movedFirst(distance: 16).description == "moved 16.0 pt before the hold: a scroll")
        #expect(PluckReason.withinStillness(distance: 4.25).description == "4.3 pt from the touch, within the stillness")
        let judgement = PluckPullJudgement(depth: 30, drift: 120, threshold: 27, verdict: .tooSlanted)
        #expect(PluckReason.notAPull(judgement).description == "no pull: too slanted, 30.0 deep, 120.0 across, needs 27.0 pt")
        #expect(PluckPullJudgement(depth: -3.04, drift: 0, threshold: 27, verdict: .tooShallow).description == "too shallow, -3.0 deep, 0.0 across, needs 27.0 pt")
    }

    /// A reason's name tells one kind from another whatever its numbers.
    @Test func aReasonsNameIgnoresItsNumbers() {
        #expect(PluckReason.withinStillness(distance: 2).name == PluckReason.withinStillness(distance: 9).name)
        let shallow = PluckPullJudgement(depth: 3, drift: 0, threshold: 27, verdict: .tooShallow)
        let slanted = PluckPullJudgement(depth: 30, drift: 120, threshold: 27, verdict: .tooSlanted)
        #expect(PluckReason.notAPull(shallow).name != PluckReason.notAPull(slanted).name)
    }
}
