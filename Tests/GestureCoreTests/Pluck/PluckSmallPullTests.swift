import Testing
@testable import GestureCore

/// The pluck as Alex tried it in the lab on October 9 (`PluckTuning.notSticky`),
/// still three values away from today's defaults: the hold given up only by
/// a real scroll of the container, or a move of 40 pt, never by the drag's
/// first word, as at the defaults; and, once the item is lifted and its pull
/// armed, a move of 6 mm any way from where the pinch stood as it lifted
/// pulls it out, the item following nothing. The replays at the end are the
/// trace's own pinches, at the headset's 1,360 pt to the meter, where 6 mm
/// is 8.16 pt.
@Suite struct PluckSmallPullTests {
    let start = ContinuousClock.now
    /// The points the headset measured to a meter at the grid window's own
    /// size: its trace said 2 cm needs 27.2 pt.
    let pointsPerMeter = 1360.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// The not-sticky tuning, its pull measured from elsewhere.
    func notSticky(measuresPullFromLift: Bool, measuresPullFromArming: Bool = false) -> PluckTuning {
        var tuning = PluckTuning.notSticky
        tuning.measuresPullFromLift = measuresPullFromLift
        tuning.measuresPullFromArming = measuresPullFromArming
        return tuning
    }

    func moved(_ pinches: inout PluckPinches, _ x: Double, _ y: Double, _ z: Double, at seconds: Double) -> PluckPinches.Told {
        pinches.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: at(seconds))
    }

    @Test func thePullIsAbout8PointsOnTheHeadset() {
        let threshold = PluckTuning.notSticky.breakFreeThreshold(pointsPerMeter: pointsPerMeter)
        #expect(abs(threshold - 8.16) < 1e-9)
    }

    // MARK: The hold

    /// A hand that has just pinched settles about 15 pt, which the drag
    /// reports as its first word: the hold goes on, and lifts.
    @Test func aDriftOf15PointsBeforeTheHoldDoesntStopTheLift() throws {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        let drift = moved(&pinches, 3, 15, 0, at: 0.2)
        #expect(drift.actions == [])
        #expect(drift.countdowns == [])
        #expect(pinches.press?.stayedDown == nil)
        #expect(moved(&pinches, 6, 24, -4, at: 0.35).actions == [])
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
        #expect(pinches.farthestBeforeHold > 24)
        #expect(pinches.dragEnded(at: at(0.9)).actions == [.settle])
        let account = try #require(pinches.pressEnded(at: at(0.9)).ended)
        #expect(account.outcome == .lift)
    }

    /// The container's scroll view moving with the pinch gives the hold up:
    /// the pinch is a scroll for the rest of it, lifting and pulling
    /// nothing, should the hold's count come anyway.
    @Test func aRealScrollStopsTheLift() throws {
        var container = PluckContainer<Int>()
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = container.scrollPhaseChanged(to: .tracking, at: at(0.05))
        #expect(moved(&pinches, 0, 15.5, 0, at: 0.15).actions == [])
        _ = container.scrollPhaseChanged(to: .interacting, at: at(0.2))
        let scrolled = pinches.containerScrolled(at: at(0.2))
        #expect(scrolled == PluckPinches.Told(actions: [.stayDown(.containerScrolled)], why: .containerScrolled, countdowns: [.stopHold]))
        let touch = try #require(pinches.touchedAt)
        #expect(container.scrolled(since: touch))
        #expect(pinches.holdFired(asTheContainerScrolled: container.scrolled(since: touch), at: at(0.5)).actions == [])
        #expect(pinches.armPull(at: at(0.7)).actions == [])
        #expect(moved(&pinches, 0, 0, 80, at: 0.9).actions == [])
        #expect(pinches.press?.isLifted == false)
    }

    /// A pinch that caught its container coasting, its scroll over before
    /// the hold, lifts nothing: the hold asks whether it scrolled since the
    /// touch.
    @Test func aPinchThatCaughtACoastLiftsNothing() {
        var container = PluckContainer<Int>()
        _ = container.scrollPhaseChanged(to: .interacting, at: at(-0.6))
        _ = container.scrollPhaseChanged(to: .decelerating, at: at(-0.3))
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = container.scrollPhaseChanged(to: .idle, at: at(0.05))
        let held = pinches.holdFired(asTheContainerScrolled: container.scrolled(since: at(0)), at: at(0.5))
        #expect(held.actions == [.stayDown(.containerScrolled)])
    }

    /// The scroll view tracking a pinch that hasn't moved it isn't a scroll:
    /// the hold lifts.
    @Test func trackingAPinchIsNoScroll() {
        var container = PluckContainer<Int>()
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = container.scrollPhaseChanged(to: .tracking, at: at(0.05))
        #expect(!container.scrolled(since: at(0)))
        #expect(pinches.holdFired(asTheContainerScrolled: container.scrolled(since: at(0)), at: at(0.5)).actions == [.lift])
    }

    /// A move of 40 pt before the hold, as a yank toward the viewer, is
    /// still a scroll, and pulls nothing however far it goes.
    @Test func aMoveOf40PointsBeforeTheHoldIsAScroll() {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        #expect(moved(&pinches, 10, 8, 25, at: 0.15).actions == [])
        let yank = moved(&pinches, 10, 8, 38, at: 0.25)
        #expect(yank.actions == [.stayDown(.movedFirst)])
        #expect(yank.countdowns == [.stopHold])
        #expect(yank.why == .movedFirst(distance: (100 + 64 + 1444 as Double).squareRoot(), stillness: 40))
        #expect(moved(&pinches, 10, 8, 120, at: 0.6).actions == [])
        #expect(pinches.press?.isLifted == false)
    }

    // MARK: The pull

    /// Lifted and armed, a small move sideways, 8.2 pt from where the pinch
    /// stood as the item lifted, pulls the item out; 5 pt doesn't.
    @Test func anArmedLiftedItemPullsOnASmallSidewaysMove() {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 0, 16, 0, at: 0.3)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.press?.liftPoint == SIMD3(0, 16, 0))
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        let short = moved(&pinches, 5, 16, 0, at: 0.75)
        #expect(short.actions == [])
        #expect(short.why == .notAPull(PluckPullJudgement(depth: 0, drift: 5, threshold: 8.16, verdict: .tooShort, origin: .lift)))
        let pull = moved(&pinches, 8.2, 16, 0, at: 0.8)
        #expect(pull.actions == [.breakFree])
        #expect(moved(&pinches, 60, 40, 0, at: 1).actions == [.carrySpawned])
        #expect(pinches.dragEnded(at: at(1.2)).actions == [.releaseSpawned, .settle])
    }

    /// Any way: up, down, toward the viewer, or away, 8.2 pt from where it
    /// lifted pulls.
    @Test func everyWayPulls() {
        for move in [SIMD3(0.0, -8.2, 0), SIMD3(0, 8.2, 0), SIMD3(-8.2, 0, 0), SIMD3(0, 0, 8.2), SIMD3(0, 0, -8.2), SIMD3(5, 5, 5)] {
            var pinches = PluckPinches(tuning: .notSticky)
            _ = pinches.pressBegan(at: at(0))
            _ = moved(&pinches, 0, 20, 0, at: 0.3)
            _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
            _ = pinches.armPull(at: at(0.7))
            let told = pinches.dragMoved(SIMD3(0, 20, 0) + move, pointsPerMeter: pointsPerMeter, at: at(0.8))
            #expect(told.actions == [.breakFree], "moved \(move)")
        }
    }

    /// A hand that drifted 30 pt during the hold doesn't pull the instant
    /// its pull arms: measured from where it stood as the item lifted, its
    /// next word is a point away. Measured from the touch, as first shipped,
    /// the same word pulls at once.
    @Test func aHandThatDriftedDuringTheHoldDoesntPullTheInstantItArms() {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 0, 30, 0, at: 0.45)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, 0, 31, 0, at: 0.72).actions == [])
        #expect(moved(&pinches, 0, 38.2, 0, at: 0.8).actions == [.breakFree])

        var fromTheTouch = PluckPinches(tuning: notSticky(measuresPullFromLift: false))
        _ = fromTheTouch.pressBegan(at: at(0))
        _ = moved(&fromTheTouch, 0, 30, 0, at: 0.45)
        _ = fromTheTouch.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = fromTheTouch.armPull(at: at(0.7))
        #expect(moved(&fromTheTouch, 0, 31, 0, at: 0.72).actions == [.breakFree])
    }

    /// The drag reports depth in steps of about 4.2 pt: one step from where
    /// the pinch lifted doesn't pull, two do.
    @Test func oneDepthStepDoesntPullAndTwoDo() {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 7.5, -2.1, 13.3, at: 0.4)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, 7.5, -2.1, 17.5, at: 0.75).actions == [])
        #expect(moved(&pinches, 7.5, -2.1, 21.7, at: 0.8).actions == [.breakFree])
    }

    /// With the drag silent as the item lifts, the pinch stood within its
    /// 15 pt start of the touch, so its first word after the arming, the
    /// first sign of a move, pulls, measured from the touch.
    @Test func theDragsFirstWordAfterASilentLiftPulls() {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        #expect(pinches.press?.liftPoint == nil)
        let first = moved(&pinches, 0, 15, 0, at: 0.9)
        #expect(first.actions == [.breakFree])
        #expect(first.why == .brokeFree(PluckPullJudgement(depth: 0, drift: 15, threshold: 8.16, verdict: .pulls, origin: .touch)))
    }

    /// The rest stays: the lift outlives a press its scroll's stopping
    /// cancels, and still pulls; its release tap is no tap.
    @Test func theLiftOutlivesItsPressAndItsReleaseIsNoTap() throws {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.pressEnded(at: at(0.51)) == PluckPinches.Told(why: .liftOutlivesItsPress))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, -12, 9, 2, at: 0.8).actions == [.breakFree])
        let told = pinches.dragEnded(at: at(1.1))
        #expect(told.actions == [.releaseSpawned, .settle])
        #expect(try #require(told.ended).outcome == .pull)
        #expect(pinches.tapped(at: at(1.12)).isRelease)
    }

    // MARK: The headset's trace

    /// Item 6: lifted at 0.56 s and armed at 0.76 s, the drag silent, then
    /// moved across more than toward the viewer. Pulled only after 3.64 s
    /// as first shipped, every word "too shallow"; now its first word pulls.
    @Test func itemSixPullsAtItsFirstWord() {
        var defaults = PluckPinches(tuning: .notSticky)
        _ = defaults.pressBegan(at: at(0))
        _ = defaults.holdFired(asTheContainerScrolled: false, at: at(0.56))
        _ = defaults.armPull(at: at(0.76))
        let first = moved(&defaults, -14.3, -2.1, 4.2, at: 0.8)
        #expect(first.actions == [.breakFree])

        var asFirstShipped = PluckPinches(tuning: .towardTheViewerFromTheTouch)
        _ = asFirstShipped.pressBegan(at: at(0))
        _ = asFirstShipped.holdFired(asTheContainerScrolled: false, at: at(0.56))
        _ = asFirstShipped.armPull(at: at(0.76))
        for (x, y, z, t) in [(-14.3, -2.1, 4.2, 0.8), (-15.8, -2.6, 4.2, 0.9), (-18.0, -5.7, 8.4, 1.0)] {
            let told = moved(&asFirstShipped, x, y, z, at: t)
            #expect(told.actions == [])
            guard case .notAPull(let judgement) = told.why else {
                Issue.record("expected no pull, got \(told.why)")
                continue
            }
            #expect(judgement.verdict == .tooShallow)
            #expect(judgement.description.hasSuffix("needs 27.2 pt"))
        }
    }

    /// Item 2: its drag's first word, 15.1 pt from the touch at 0.25 s,
    /// made it a scroll for good, though the grid never scrolled; now the
    /// hold goes on, and lifts.
    @Test func itemTwosSettlingIsNoScroll() {
        var asFirstShipped = PluckPinches(tuning: .firstShipped)
        _ = asFirstShipped.pressBegan(at: at(0))
        #expect(moved(&asFirstShipped, 12.5, 8.2, -2.5, at: 0.25).actions == [.stayDown(.movedFirst)])

        var defaults = PluckPinches(tuning: .notSticky)
        _ = defaults.pressBegan(at: at(0))
        let first = moved(&defaults, 12.5, 8.2, -2.5, at: 0.25)
        #expect(first.actions == [])
        #expect(first.why.name == "withinStillness")
        #expect(defaults.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
    }

    /// Item 3: lifted at 0.59 s, its drag silent, its first word at 0.73 s,
    /// 13.3 pt toward the viewer, armed at 0.79 s, its next word at 0.81 s,
    /// then let go at 0.87 s. Its hand came out as the item lifted, before
    /// the arming. Measured from the lift, as by default, that move counts,
    /// and its word at 0.81 s pulls; measured from the arming, the same word
    /// is 5.5 pt along, short of the pull.
    @Test func itemThreePullsAt081Seconds() throws {
        var pinches = PluckPinches(tuning: .notSticky)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.59))
        #expect(pinches.press?.liftPoint == nil)
        #expect(moved(&pinches, 7.5, -2.1, 13.3, at: 0.73).why == .notArmedYet)
        _ = pinches.armPull(at: at(0.79))
        let pull = moved(&pinches, 8.6, -0.9, 18.6, at: 0.81)
        #expect(pull.actions == [.breakFree])
        guard case .brokeFree(let pulled) = pull.why else {
            Issue.record("expected a pull, got \(pull.why)")
            return
        }
        #expect(pulled.origin == .touch)
        #expect(abs(pulled.distance - 20.5) < 0.05)
        let account = try #require(pinches.dragEnded(at: at(0.87)).ended ?? pinches.pressEnded(at: at(0.87)).ended)
        #expect(account.outcome == .pull)
        #expect(account.pulledAfter == .seconds(0.81))

        var fromTheArming = PluckPinches(tuning: notSticky(measuresPullFromLift: false, measuresPullFromArming: true))
        _ = fromTheArming.pressBegan(at: at(0))
        _ = fromTheArming.holdFired(asTheContainerScrolled: false, at: at(0.59))
        _ = moved(&fromTheArming, 7.5, -2.1, 13.3, at: 0.73)
        _ = fromTheArming.armPull(at: at(0.79))
        #expect(fromTheArming.press?.armingPoint == SIMD3(7.5, -2.1, 13.3))
        let short = moved(&fromTheArming, 8.6, -0.9, 18.6, at: 0.81)
        #expect(short.actions == [])
        guard case .notAPull(let judgement) = short.why else {
            Issue.record("expected no pull, got \(short.why)")
            return
        }
        #expect(judgement.verdict == .tooShort)
        #expect(judgement.origin == .arming)
        #expect(abs(judgement.distance - 5.54) < 0.01)
    }

    /// A hand's move between the lift and the arming counts from the lift,
    /// and is lost from the arming.
    @Test func aMoveBetweenTheLiftAndTheArmingCountsFromTheLift() {
        func pinch(_ tuning: PluckTuning) -> PluckPinches.Told {
            var pinches = PluckPinches(tuning: tuning)
            _ = pinches.pressBegan(at: at(0))
            _ = pinches.dragMoved(SIMD3(0, 20, 0), pointsPerMeter: pointsPerMeter, at: at(0.3))
            _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
            _ = pinches.dragMoved(SIMD3(0, 26, 0), pointsPerMeter: pointsPerMeter, at: at(0.6))
            _ = pinches.armPull(at: at(0.7))
            return pinches.dragMoved(SIMD3(0, 28.2, 0), pointsPerMeter: pointsPerMeter, at: at(0.72))
        }
        #expect(pinch(.notSticky).actions == [.breakFree])
        #expect(pinch(notSticky(measuresPullFromLift: false, measuresPullFromArming: true)).actions == [])
    }
}
