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

    /// Held a quarter second, the item lifts, unless its container scrolled
    /// or it moved 40 pt first; the drag says nothing until 15 pt, well
    /// within that; lifted, the item follows half the hand's move at first,
    /// easing toward 20 pt; its pull arms two tenths after the lift; it
    /// breaks free 2.5 cm any way from where the pinch stood as it lifted;
    /// the container's scroll stops under a lifted item, and a scroll
    /// beginning settles one; a release tap is waited for a second; the
    /// item's button is the hold, beside a simultaneous drag; and what it
    /// pulls out spawns 100 pt in front of the drag, the lift 8% larger and
    /// 36 pt nearer. All as the pluck first shipped, but the hold's time and
    /// stillness, the follow, the pull's rule, where it's measured from, and
    /// its distance, and that the press's end keeps a lift up.
    @Test func theDefaults() {
        let tuning = PluckTuning()
        #expect(PluckTuning.defaults == tuning)
        #expect(tuning.holdDuration == 0.25)
        #expect(tuning.holdStillness == 40)
        #expect(tuning.pullArmDelay == 0.2)
        #expect(tuning.dragStartDistance == 15)
        #expect(tuning.breakFreeDistance == 0.025)
        #expect(tuning.followShare == 0.5)
        #expect(tuning.followCap == 20)
        #expect(tuning.tether == PluckTether(share: 0.5, cap: 20))
        #expect(tuning.pullDepthPerDrift == 0.5)
        #expect(tuning.pullsAnyDirection)
        #expect(tuning.measuresPullFromLift)
        #expect(!tuning.measuresPullFromArming)
        #expect(tuning.pullRule == .anyDirection)
        #expect(tuning.pullOrigin == .lift)
        #expect(tuning.depthGrowsTowardViewer)
        #expect(tuning.depthScale == 1)
        #expect(tuning.stopsScrollUnderLiftedItem)
        #expect(tuning.scrollSettlesLiftedItem)
        #expect(!tuning.pressEndSettlesLiftedItem)
        #expect(tuning.releaseTapGrace == 1)
        #expect(!tuning.holdsFromTheDrag)
        #expect(tuning.pullDragIsSimultaneous)
        #expect(tuning.pushTowardViewer == 100)
        #expect(tuning.liftScale == 1.08)
        #expect(tuning.liftDepth == 36)
        #expect(tuning.holdTime == .seconds(0.25))
        #expect(tuning.pullArmTime == .seconds(0.2))
        #expect(!tuning.breaksStillness(15.1))
        #expect(tuning.breaksStillness(40))
    }

    /// The tuning the moved tests run at is the pluck as it first shipped:
    /// a half-second hold, a stillness at the drag's start, 2 cm toward the
    /// viewer at 1 deep for every 2 across from the touch, no follow, and
    /// the press's end settling a lift.
    @Test func theFirstShippedTuning() {
        let tuning = PluckTuning.firstShipped
        #expect(tuning.holdDuration == 0.5)
        #expect(tuning.holdStillness == 15)
        #expect(!tuning.tether.follows)
        #expect(tuning.breaksStillness(15))
        #expect(tuning.breakFreeDistance == 0.02)
        #expect(tuning.pullRule == .outOfThePlane(depthPerDrift: 0.5))
        #expect(tuning.pullOrigin == .touch)
        #expect(tuning.pressEndSettlesLiftedItem)
        #expect(tuning.tunedValues.count == 7)
    }

    /// The pluck as Alex tried it on October 9, which spawned its item the
    /// instant it lifted, and lifted items under slow scrolls, is five values
    /// away: a half-second hold, its stillness along the scroll the same as
    /// any way's, its scroll offset unwatched, a 6 mm pull, and no follow.
    @Test func theLooseTuning() {
        let tuning = PluckTuning.loose
        #expect(tuning.tunedValues.keys.sorted() == [
            "breakFreeDistance", "followShare", "holdDuration", "holdStillnessAlongScroll", "holdWatchesScrollOffset",
        ])
        #expect(tuning.holdTime == .seconds(0.5))
        #expect(abs(tuning.breakFreeThreshold(pointsPerMeter: 1360) - 8.16) < 1e-9)
        #expect(!tuning.tether.follows)
    }

    /// The lab can show, save, and copy every value: its parameters are
    /// sound, and each is its property, in the initializer's order.
    @Test func itsParametersAreSound() {
        #expect(PluckTuning.parameterProblems.isEmpty)
        let swift = PluckTuning.defaults.swiftInitializer()
        let labels = swift.split(separator: "\n").dropFirst().dropLast().map { line in
            String(line.trimmingCharacters(in: .whitespaces).prefix { $0 != ":" })
        }
        #expect(labels == [
            "holdDuration", "holdStillness", "holdStillnessAlongScroll", "holdWatchesScrollOffset",
            "scrollOffsetStillness", "pullArmDelay", "dragStartDistance", "breakFreeDistance",
            "followShare", "followCap", "pullDepthPerDrift", "pullsAnyDirection", "measuresPullFromLift", "measuresPullFromArming",
            "depthGrowsTowardViewer", "depthScale",
            "stopsScrollUnderLiftedItem", "givesLiftBackToScroll", "scrollSettlesLiftedItem", "pressEndSettlesLiftedItem",
            "releaseTapGrace", "holdsFromTheDrag", "pullDragIsSimultaneous", "pushTowardViewer",
            "liftScale", "liftDepth",
        ])
    }

    /// A tuning with every value changed is saved and loaded whole.
    @Test func everyValueIsSavedAndLoaded() {
        let tuned = PluckTuning(
            holdDuration: 0.8, holdStillness: 8, holdStillnessAlongScroll: 4, holdWatchesScrollOffset: false,
            scrollOffsetStillness: 3, pullArmDelay: 0.3, dragStartDistance: 0, breakFreeDistance: 0.03,
            followShare: 0.3, followCap: 12, pullDepthPerDrift: 0, pullsAnyDirection: false, measuresPullFromLift: false, measuresPullFromArming: true,
            depthGrowsTowardViewer: false, depthScale: 2,
            stopsScrollUnderLiftedItem: false, givesLiftBackToScroll: true, scrollSettlesLiftedItem: false, pressEndSettlesLiftedItem: true,
            releaseTapGrace: 0.5, holdsFromTheDrag: true, pullDragIsSimultaneous: false, pushTowardViewer: 60,
            liftScale: 1.12, liftDepth: 48
        )
        #expect(tuned.tunedValues.count == PluckTuning.parameters.count)
        #expect(PluckTuning(defaultsTunedWith: tuned.tunedValues) == tuned)
    }

    /// The pull rule is any way at the switch, and off it follows the depth
    /// per drift, toward the viewer however far across at 0; where it's
    /// measured from is the lift while its switch is on, else the arming
    /// while its switch is, else the touch.
    @Test func thePullRuleFollowsItsValues() {
        #expect(PluckTuning(pullDepthPerDrift: 1).pullRule == .anyDirection)
        #expect(PluckTuning(pullDepthPerDrift: 1, pullsAnyDirection: false).pullRule == .outOfThePlane(depthPerDrift: 1))
        #expect(PluckTuning(pullDepthPerDrift: 0, pullsAnyDirection: false).pullRule == .towardTheViewer)
        #expect(PluckTuning(measuresPullFromArming: true).pullOrigin == .lift)
        #expect(PluckTuning(measuresPullFromLift: false, measuresPullFromArming: true).pullOrigin == .arming)
        #expect(PluckTuning(measuresPullFromLift: false).pullOrigin == .touch)
    }

    /// A tuning is a value a trace can keep and the lab can send.
    @Test func aTuningRoundTripsThroughJSON() throws {
        let tuning = PluckTuning(holdDuration: 0.8, holdStillness: 6, dragStartDistance: 0, pullDepthPerDrift: 0, stopsScrollUnderLiftedItem: false)
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
    /// go by, across the scroll: the hold goes on, and lifts, and a pinch
    /// that moved only that much and was let go is a tap, not a scroll.
    @Test func aLooserStillnessLetsTheDragsFirstWordsGoBy() throws {
        let tuning = PluckTuning(holdStillness: 30, dragStartDistance: 15)
        #expect(!tuning.breaksStillness(29.9))
        #expect(tuning.breaksStillness(30))

        var held = PluckPinches(tuning: tuning)
        _ = held.pressBegan(at: at(0))
        #expect(moved(&held, 20, 0, 0, at: 0.2) == PluckPinches.Told(why: .withinStillness(distance: 20, stillness: 30)))
        #expect(held.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])

        var tapped = PluckPinches(tuning: tuning)
        _ = tapped.pressBegan(at: at(0))
        _ = moved(&tapped, 20, 0, 0, at: 0.2)
        #expect(tapped.dragEnded(at: at(0.3)).ended == nil)
        #expect(tapped.pressEnded(at: at(0.3)).ended == nil)
        let account = try #require(tapped.tapped(at: at(0.3)).ended)
        #expect(account.outcome == .tap)
        #expect(account.farthestBeforeHold == 20)

        var scrolled = PluckPinches(tuning: tuning)
        _ = scrolled.pressBegan(at: at(0))
        _ = moved(&scrolled, 20, 0, 0, at: 0.2)
        #expect(moved(&scrolled, 30, 0, 0, at: 0.3) == PluckPinches.Told(actions: [.stayDown(.movedFirst)], why: .movedFirst(distance: 30, stillness: 30), countdowns: [.stopHold]))
    }

    /// A drag that starts at 0 pt hears the pinch from its touch: its first
    /// word begins the pinch and the hold's count, the press joins it, the
    /// hold lifts while the drag has the pinch though the press ended, and
    /// the drag's end, not the press's, settles the item.
    @Test func aDragFromZeroBeginsThePinchAndSettlesIt() throws {
        let tuning = PluckTuning(holdStillness: 8, dragStartDistance: 0)
        var pinches = PluckPinches(tuning: tuning)
        let touch = moved(&pinches, 0, 0, 0, at: 0)
        #expect(touch == PluckPinches.Told(why: .withinStillness(distance: 0, stillness: 8), countdowns: [.stopArming, .startHold(.seconds(0.25))], beganAPinch: true))
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
    /// drag. Measured from the lift, as by default, a move made before the
    /// arming counts, so the word that arms it breaks the item free;
    /// measured from the arming, it's measured from the word before, where
    /// the pinch stood as the arming came due, and must go 2.5 cm, 33.75 pt
    /// at the tests' 1,350 pt to the meter, from there.
    @Test func thePullArmsAfterTheTuningsDelay() {
        var pinches = PluckPinches(tuning: PluckTuning(pullArmDelay: 0.5))
        _ = pinches.pressBegan(at: at(0))
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).countdowns == [.startArming(.seconds(0.5))])
        #expect(pinches.armPull(at: at(0.7)) == PluckPinches.Told(why: .armingNotDue))
        #expect(moved(&pinches, 0, 0, 40, at: 0.9) == PluckPinches.Told(why: .notArmedYet))
        #expect(moved(&pinches, 0, 0, 41, at: 1).actions == [.pullArmed, .breakFree])

        var fromTheArming = PluckPinches(tuning: PluckTuning(pullArmDelay: 0.5, measuresPullFromLift: false, measuresPullFromArming: true))
        _ = fromTheArming.pressBegan(at: at(0))
        _ = fromTheArming.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(moved(&fromTheArming, 0, 0, 40, at: 0.9) == PluckPinches.Told(why: .notArmedYet))
        #expect(moved(&fromTheArming, 0, 0, 41, at: 1).actions == [.pullArmed])
        #expect(fromTheArming.press?.armingPoint == SIMD3(0, 0, 40))
        #expect(moved(&fromTheArming, 0, 0, 73.7, at: 1.05).actions == [])
        #expect(moved(&fromTheArming, 0, 0, 73.8, at: 1.1).actions == [.breakFree])

        var firstShipped = PluckTuning.firstShipped
        firstShipped.pullArmDelay = 0.5
        var fromTheTouch = PluckPinches(tuning: firstShipped)
        _ = fromTheTouch.pressBegan(at: at(0))
        _ = fromTheTouch.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(moved(&fromTheTouch, 0, 0, 40, at: 0.9) == PluckPinches.Told(why: .notArmedYet))
        #expect(moved(&fromTheTouch, 0, 0, 41, at: 1).actions == [.pullArmed, .breakFree])
    }

    /// With no delay, the pull arms as the item lifts, at the count's word.
    @Test func noDelayArmsAtOnce() {
        var pinches = PluckPinches(tuning: PluckTuning(pullArmDelay: 0))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.armPull(at: at(0.5)).actions == [.pullArmed])
    }

    // MARK: The pull

    /// A break-free distance of 4 cm takes 54 pt, here from the touch, the
    /// drag not having spoken as the pull armed.
    @Test func thePullsDistanceIsTheTunings() {
        let tuning = PluckTuning(breakFreeDistance: 0.04)
        #expect(tuning.breakFreeThreshold(pointsPerMeter: pointsPerMeter) == 54)
        var pinches = liftedAndArmed(tuning)
        #expect(moved(&pinches, 0, 0, 40, at: 0.8).actions == [])
        #expect(moved(&pinches, 0, 0, 54, at: 0.9).actions == [.breakFree])
    }

    /// The default takes a move across the container, as far as 2.5 cm;
    /// out of the plane, as first shipped, turns down one drifting far
    /// across, which toward the viewer takes.
    @Test func thePullRuleIsTheTunings() {
        var any = liftedAndArmed(PluckTuning())
        #expect(moved(&any, 0, 33.7, 0, at: 0.75).actions == [])
        #expect(moved(&any, 0, 33.8, 0, at: 0.8).actions == [.breakFree])
        var slanted = liftedAndArmed(.towardTheViewerFromTheTouch)
        #expect(moved(&slanted, 0, 30, 0, at: 0.8).actions == [])
        #expect(moved(&slanted, 0, 200, 40, at: 0.85).actions == [])
        var toward = PluckTuning.towardTheViewerFromTheTouch
        toward.pullDepthPerDrift = 0
        var towardPinches = liftedAndArmed(toward)
        #expect(moved(&towardPinches, 0, 200, 40, at: 0.8).actions == [.breakFree])
    }

    /// A drag whose depth the tuning reads as running away from the viewer
    /// pulls as its z falls.
    @Test func theDepthsSignIsTheTunings() {
        var flipped = PluckTuning.towardTheViewerFromTheTouch
        flipped.depthGrowsTowardViewer = false
        #expect(flipped.viewerTranslation(SIMD3(1, 2, -30)) == SIMD3(1, 2, 30))
        var pinches = liftedAndArmed(flipped)
        #expect(moved(&pinches, 0, 0, 40, at: 0.8).actions == [])
        #expect(moved(&pinches, 0, 0, -40, at: 0.9).actions == [.breakFree])
    }

    /// A drag whose depth the tuning scales up pulls sooner, its moves
    /// across as they were.
    @Test func theDepthsScaleIsTheTunings() {
        var scaled = PluckTuning.towardTheViewerFromTheTouch
        scaled.depthScale = 2
        #expect(scaled.viewerTranslation(SIMD3(10, 20, 14)) == SIMD3(10, 20, 28))
        var pinches = liftedAndArmed(scaled)
        let told = moved(&pinches, 0, 0, 14, at: 0.8)
        #expect(told.actions == [.breakFree])
        #expect(told.why == .brokeFree(PluckPullJudgement(depth: 28, drift: 0, threshold: 27, verdict: .pulls, origin: .touch)))
    }

    // MARK: The press's end

    /// Kept up past its press, as when the lift's stopping the container's
    /// scroll cancels the press, the item stays lifted, its pull arms, and a
    /// move breaks it free.
    @Test func aLiftKeptPastItsPressStillPulls() throws {
        let tuning = PluckTuning(pressEndSettlesLiftedItem: false)
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        let cancelled = pinches.pressEnded(at: at(0.51))
        #expect(cancelled == PluckPinches.Told(why: .liftOutlivesItsPress))
        #expect(pinches.press?.isLifted == true)
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        #expect(moved(&pinches, 0, 0, 34, at: 0.8).actions == [.breakFree])
        let told = pinches.dragEnded(at: at(1.2))
        #expect(told.actions == [.releaseSpawned, .settle])
        let account = try #require(told.ended)
        #expect(account.outcome == .pull)
        #expect(account.pressEndedAfter == .seconds(0.51))
    }

    /// As the pluck first shipped, the same press ending drops the item, and
    /// the drag that follows begins a pinch of its own, a scroll: the pull
    /// never comes.
    @Test func asFirstShippedAPressCancelledAtTheLiftDropsTheItem() throws {
        var pinches = PluckPinches(tuning: .firstShipped)
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
        var pinches = PluckPinches(tuning: PluckTuning(pressEndSettlesLiftedItem: true, releaseTapGrace: 0.3))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.pressEnded(at: at(0.9))
        #expect(!pinches.tapped(at: at(1.25)).isRelease)

        var quick = PluckPinches(tuning: PluckTuning(pressEndSettlesLiftedItem: true, releaseTapGrace: 0.3))
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
