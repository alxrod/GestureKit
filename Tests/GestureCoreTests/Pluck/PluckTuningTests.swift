import Foundation
import Testing
@testable import GestureCore

/// The pluck's tuning: its defaults, the ones it shipped with, and each
/// rule reading it rather than a constant, so the lab's changes take, each
/// pinch judged by the tuning it began with.
@Suite struct PluckTuningTests {
    let start = ContinuousClock.now
    /// The points the tests measure to a meter, so the pull's 2 cm is 27 pt.
    let pointsPerMeter = 1350.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func moved(_ pinches: inout PluckPinches, _ x: Double, _ y: Double, _ z: Double, at seconds: Double) -> PluckPinches.Told {
        pinches.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: at(seconds))
    }

    /// Pinches with `tuning`, pressed at 0 and held until the item lifted at
    /// its hold's time, then armed at the arming's.
    func liftedAndArmed(_ tuning: PluckTuning) -> PluckPinches {
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(tuning.holdDuration))
        _ = pinches.armPull(at: at(tuning.holdDuration + tuning.pullArmDelay))
        return pinches
    }

    /// Held half a second, the item lifts; its pull arms two tenths later;
    /// the drag says nothing until 15 pt, which is the hold's stillness, so a
    /// pinch the drag has heard from has moved too far to hold; a pull is
    /// 2 cm out of the plane, 1 deep for every 2 across; the container's
    /// scroll stops under a lifted item, and a scroll beginning settles one;
    /// the press's end settles one too; and a release tap is waited for a
    /// second.
    @Test func theDefaultsAreTheOnesThePluckShippedWith() {
        let tuning = PluckTuning()
        #expect(tuning.holdDuration == 0.5)
        #expect(tuning.holdStillness == 15)
        #expect(tuning.pullArmDelay == 0.2)
        #expect(tuning.dragStartDistance == 15)
        #expect(tuning.pullDistance == 0.02)
        #expect(tuning.pullRule == .outOfThePlane(depthPerDrift: 0.5))
        #expect(tuning.depthGrowsTowardViewer)
        #expect(tuning.depthScale == 1)
        #expect(tuning.stopsScrollUnderLiftedItem)
        #expect(tuning.scrollSettlesLiftedItem)
        #expect(tuning.pressEndSettlesLiftedItem)
        #expect(tuning.releaseTapGrace == 1)
        #expect(tuning.holdTime == .seconds(0.5))
        #expect(tuning.pullArmTime == .seconds(0.2))
    }

    /// A tuning is a value a trace can keep and the lab can send.
    @Test func aTuningRoundTripsThroughJSON() throws {
        let tuning = PluckTuning(holdDuration: 0.8, holdStillness: 6, dragStartDistance: 0, pullRule: .towardTheViewer, stopsScrollUnderLiftedItem: false)
        let data = try JSONEncoder().encode(tuning)
        #expect(try JSONDecoder().decode(PluckTuning.self, from: data) == tuning)
    }

    // MARK: The hold

    /// A longer hold is counted for as long.
    @Test func theHoldCountsTheTuningsTime() {
        var pinches = PluckPinches(tuning: PluckTuning(holdDuration: 0.8))
        #expect(pinches.pressBegan(at: at(0)).countdowns == [.stopArming, .startHold(.seconds(0.8))])
    }

    /// The drag's first word before the hold is a move at any stillness no
    /// greater than its start, since it moved that far to speak at all.
    @Test func aStillnessNoLooserThanTheDragsStartTakesItsFirstWord() {
        let tuning = PluckTuning(holdStillness: 10, dragStartDistance: 15)
        #expect(tuning.breaksStillness(0))
        #expect(tuning.breaksStillness(12))
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        #expect(moved(&pinches, 3, 4, 0, at: 0.1).actions == [.stayDown(.movedFirst)])
    }

    /// A stillness looser than the drag's start lets the drag's first words
    /// go by: the hold goes on, and lifts, and a pinch that moved only that
    /// much and was let go is a tap, not a scroll.
    @Test func aLooserStillnessLetsTheDragsFirstWordsGoBy() throws {
        let tuning = PluckTuning(holdStillness: 30, dragStartDistance: 15)
        #expect(!tuning.breaksStillness(29.9))
        #expect(tuning.breaksStillness(30))

        var held = PluckPinches(tuning: tuning)
        _ = held.pressBegan(at: at(0))
        #expect(moved(&held, 0, 20, 0, at: 0.2) == PluckPinches.Told(why: .withinStillness(distance: 20)))
        #expect(held.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])

        var tapped = PluckPinches(tuning: tuning)
        _ = tapped.pressBegan(at: at(0))
        _ = moved(&tapped, 0, 20, 0, at: 0.2)
        #expect(tapped.dragEnded(at: at(0.3)).ended == nil)
        #expect(tapped.pressEnded(at: at(0.3)).ended == nil)
        let account = try #require(tapped.tapped(at: at(0.3)).ended)
        #expect(account.outcome == .tap)
        #expect(account.farthestBeforeHold == 20)

        var scrolled = PluckPinches(tuning: tuning)
        _ = scrolled.pressBegan(at: at(0))
        _ = moved(&scrolled, 0, 20, 0, at: 0.2)
        #expect(moved(&scrolled, 0, 30, 0, at: 0.3) == PluckPinches.Told(actions: [.stayDown(.movedFirst)], why: .movedFirst(distance: 30), countdowns: [.stopHold]))
    }

    /// A drag that starts at 0 pt hears the pinch from its touch: its first
    /// word begins the pinch and the hold's count, the press joins it, the
    /// hold lifts while the drag has the pinch though the press ended, and
    /// the drag's end, not the press's, settles the item.
    @Test func aDragFromZeroBeginsThePinchAndSettlesIt() throws {
        let tuning = PluckTuning(holdStillness: 8, dragStartDistance: 0)
        var pinches = PluckPinches(tuning: tuning)
        let touch = moved(&pinches, 0, 0, 0, at: 0)
        #expect(touch == PluckPinches.Told(why: .withinStillness(distance: 0), countdowns: [.stopArming, .startHold(.seconds(0.5))], beganAPinch: true))
        #expect(pinches.touchedAt == at(0))
        #expect(pinches.pressBegan(at: at(0.01)) == PluckPinches.Told(why: .pressJoined))
        _ = moved(&pinches, 2, 3, 0, at: 0.2)
        // The press goes, as the container's scroll might take it, while the
        // drag still has the pinch.
        #expect(pinches.pressEnded(at: at(0.3)) == PluckPinches.Told(why: .dragHasThePinch))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
        #expect(pinches.pressEnded(at: at(0.52)).actions == [])
        let told = pinches.dragEnded(at: at(0.9))
        #expect(told.actions == [.settle])
        let account = try #require(told.ended)
        #expect(account.outcome == .lift)
        #expect(account.settledAfter == .seconds(0.9))
    }

    /// A drag from 0 pt whose first word is already past the stillness makes
    /// its pinch a scroll at once, and counts no hold.
    @Test func aDragFromZeroThatMovesAtOnceIsAScroll() {
        var pinches = PluckPinches(tuning: PluckTuning(holdStillness: 8, dragStartDistance: 0))
        let told = moved(&pinches, 0, 12, 0, at: 0)
        #expect(told.actions == [.stayDown(.movedFirst)])
        #expect(told.countdowns == [.stopArming, .stopHold])
        #expect(told.beganAPinch)
    }

    // MARK: The arming

    /// The pull arms the tuning's delay after the lift, by the count or the
    /// drag.
    @Test func thePullArmsAfterTheTuningsDelay() {
        var pinches = PluckPinches(tuning: PluckTuning(pullArmDelay: 0.5))
        _ = pinches.pressBegan(at: at(0))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).countdowns == [.startArming(.seconds(0.5))])
        #expect(pinches.armPull(at: at(0.7)) == PluckPinches.Told(why: .armingNotDue))
        #expect(moved(&pinches, 0, 0, 40, at: 0.9) == PluckPinches.Told(why: .notArmedYet))
        #expect(moved(&pinches, 0, 0, 41, at: 1).actions == [.pullArmed, .beginPull])
    }

    /// With no delay, the pull arms as the item lifts, at the count's word.
    @Test func noDelayArmsAtOnce() {
        var pinches = PluckPinches(tuning: PluckTuning(pullArmDelay: 0))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.armPull(at: at(0.5)).actions == [.pullArmed])
    }

    // MARK: The pull

    /// A pull of 4 cm takes twice the default's points.
    @Test func thePullsDistanceIsTheTunings() {
        let tuning = PluckTuning(pullDistance: 0.04)
        #expect(tuning.pullThreshold(pointsPerMeter: pointsPerMeter) == 54)
        var pinches = liftedAndArmed(tuning)
        #expect(moved(&pinches, 0, 0, 40, at: 0.8).actions == [])
        #expect(moved(&pinches, 0, 0, 54, at: 0.9).actions == [.beginPull])
    }

    /// Toward the viewer takes a pull drifting far across, which the default
    /// turns down.
    @Test func thePullRuleIsTheTunings() {
        var slanted = liftedAndArmed(PluckTuning())
        #expect(moved(&slanted, 0, 200, 40, at: 0.8).actions == [])
        var toward = liftedAndArmed(PluckTuning(pullRule: .towardTheViewer))
        #expect(moved(&toward, 0, 200, 40, at: 0.8).actions == [.beginPull])
        var any = liftedAndArmed(PluckTuning(pullRule: .anyDirection))
        #expect(moved(&any, 0, 30, 0, at: 0.8).actions == [.beginPull])
    }

    /// A drag whose depth the tuning reads as running away from the viewer
    /// pulls as its z falls.
    @Test func theDepthsSignIsTheTunings() {
        let flipped = PluckTuning(depthGrowsTowardViewer: false)
        #expect(flipped.viewerTranslation(SIMD3(1, 2, -30)) == SIMD3(1, 2, 30))
        var pinches = liftedAndArmed(flipped)
        #expect(moved(&pinches, 0, 0, 40, at: 0.8).actions == [])
        #expect(moved(&pinches, 0, 0, -40, at: 0.9).actions == [.beginPull])
    }

    /// A drag whose depth the tuning scales up pulls sooner, its moves
    /// across as they were.
    @Test func theDepthsScaleIsTheTunings() {
        let scaled = PluckTuning(depthScale: 2)
        #expect(scaled.viewerTranslation(SIMD3(10, 20, 14)) == SIMD3(10, 20, 28))
        var pinches = liftedAndArmed(scaled)
        let told = moved(&pinches, 0, 0, 14, at: 0.8)
        #expect(told.actions == [.beginPull])
        #expect(told.why == .pulled(PluckPullJudgement(depth: 28, drift: 0, threshold: 27, verdict: .pulls)))
    }

    // MARK: The press's end

    /// Kept up past its press, as when the lift's stopping the container's
    /// scroll cancels the press, the item stays lifted, its pull arms, and a
    /// move pulls it out.
    @Test func aLiftKeptPastItsPressStillPulls() throws {
        let tuning = PluckTuning(pressEndSettlesLiftedItem: false)
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        let cancelled = pinches.pressEnded(at: at(0.51))
        #expect(cancelled == PluckPinches.Told(why: .liftOutlivesItsPress))
        #expect(pinches.press?.isLifted == true)
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        #expect(moved(&pinches, 0, 0, 30, at: 0.8).actions == [.beginPull])
        let told = pinches.dragEnded(at: at(1.2))
        #expect(told.actions == [.endPull, .settle])
        let account = try #require(told.ended)
        #expect(account.outcome == .pull)
        #expect(account.pressEndedAfter == .seconds(0.51))
    }

    /// At the default, the same press ending drops the item, and the drag
    /// that follows begins a pinch of its own, a scroll: the pull never
    /// comes.
    @Test func atTheDefaultAPressCancelledAtTheLiftDropsTheItem() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        let cancelled = pinches.pressEnded(at: at(0.51))
        #expect(cancelled.actions == [.settle])
        let account = try #require(cancelled.ended)
        #expect(account.outcome == .lift)
        #expect(account.settledAfter == .seconds(0.51))
        let move = moved(&pinches, 0, 0, 30, at: 0.8)
        #expect(move.beganAPinch)
        #expect(move.actions == [.stayDown(.movedFirst)])
    }

    /// Kept up past its press and let go still, the item's release tap lets
    /// it down and ends the pinch.
    @Test func aLiftKeptPastItsPressSettlesAtItsReleaseTap() throws {
        var pinches = PluckPinches(tuning: PluckTuning(pressEndSettlesLiftedItem: false))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.pressEnded(at: at(0.9))
        let tap = pinches.tapped(at: at(0.9))
        #expect(tap.isRelease)
        #expect(tap.actions == [.settle])
        #expect(tap.countdowns == [.stopHold, .stopArming])
        let account = try #require(tap.ended)
        #expect(account.outcome == .lift)
        #expect(account.settledAfter == .seconds(0.9))
        #expect(pinches.press == nil)
    }

    /// Kept up past its press, with no word after, the item settles as the
    /// next pinch begins.
    @Test func aLiftKeptPastItsPressSettlesAsTheNextPinchBegins() throws {
        var pinches = PluckPinches(tuning: PluckTuning(pressEndSettlesLiftedItem: false))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.pressEnded(at: at(0.51))
        let next = pinches.pressBegan(at: at(3))
        #expect(next.actions == [.settle])
        #expect(try #require(next.ended).ending == .unseen)
    }

    // MARK: The release tap

    /// A shorter grace waits less for a lift's release tap.
    @Test func theReleaseGraceIsTheTunings() {
        var pinches = PluckPinches(tuning: PluckTuning(releaseTapGrace: 0.3))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.pressEnded(at: at(0.9))
        #expect(!pinches.tapped(at: at(1.25)).isRelease)

        var quick = PluckPinches(tuning: PluckTuning(releaseTapGrace: 0.3))
        _ = quick.pressBegan(at: at(0))
        _ = quick.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = quick.pressEnded(at: at(0.9))
        #expect(quick.tapped(at: at(1.15)).isRelease)
    }

    // MARK: Live tuning

    /// The tuning changed mid-pinch reaches the next pinch, not the one
    /// under way, which is judged by the tuning it began with.
    @Test func aPinchKeepsTheTuningItBeganWith() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        pinches.tuning.pullArmDelay = 1
        pinches.tuning.holdDuration = 2
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.press?.tuning == PluckTuning())
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        _ = pinches.pressEnded(at: at(0.8))
        let next = pinches.pressBegan(at: at(5))
        #expect(next.countdowns == [.stopArming, .startHold(.seconds(2))])
        #expect(pinches.press?.tuning.pullArmDelay == 1)
    }
}
