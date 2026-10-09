import Testing
@testable import GestureCore

/// The pluck at its defaults, as the lab's traces on the headset asked for:
/// the hold given up only by a real scroll of the container, or a move of
/// 40 pt, never by the drag's first word; and, once the item is lifted and
/// its pull armed, a move of 6 mm any way from where the pinch stood as it
/// armed pulls it out. The replays at the end are the trace's own pinches,
/// at the headset's 1,360 pt to the meter, where 6 mm is 8.16 pt.
@Suite struct PluckDefaultsTests {
    let start = ContinuousClock.now
    /// The points the headset measured to a meter at the grid window's own
    /// size: its trace said 2 cm needs 27.2 pt.
    let pointsPerMeter = 1360.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func moved(_ pinches: inout PluckPinches, _ x: Double, _ y: Double, _ z: Double, at seconds: Double) -> PluckPinches.Told {
        pinches.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: at(seconds))
    }

    @Test func thePullIsAbout8PointsOnTheHeadset() {
        let threshold = PluckTuning().pullThreshold(pointsPerMeter: pointsPerMeter)
        #expect(abs(threshold - 8.16) < 1e-9)
    }

    // MARK: The hold

    /// A hand that has just pinched settles about 15 pt, which the drag
    /// reports as its first word: the hold goes on, and lifts.
    @Test func aDriftOf15PointsBeforeTheHoldDoesntStopTheLift() throws {
        var pinches = PluckPinches()
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
        var pinches = PluckPinches()
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
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = container.scrollPhaseChanged(to: .idle, at: at(0.05))
        let held = pinches.holdFired(asTheContainerScrolled: container.scrolled(since: at(0)), at: at(0.5))
        #expect(held.actions == [.stayDown(.containerScrolled)])
    }

    /// The scroll view tracking a pinch that hasn't moved it isn't a scroll:
    /// the hold lifts.
    @Test func trackingAPinchIsNoScroll() {
        var container = PluckContainer<Int>()
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = container.scrollPhaseChanged(to: .tracking, at: at(0.05))
        #expect(!container.scrolled(since: at(0)))
        #expect(pinches.holdFired(asTheContainerScrolled: container.scrolled(since: at(0)), at: at(0.5)).actions == [.lift])
    }

    /// A move of 40 pt before the hold, as a yank toward the viewer, is
    /// still a scroll, and pulls nothing however far it goes.
    @Test func aMoveOf40PointsBeforeTheHoldIsAScroll() {
        var pinches = PluckPinches()
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
    /// stood as the pull armed, pulls the item out; 5 pt doesn't.
    @Test func anArmedLiftedItemPullsOnASmallSidewaysMove() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 0, 16, 0, at: 0.3)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        #expect(pinches.press?.armedAt == SIMD3(0, 16, 0))
        let short = moved(&pinches, 5, 16, 0, at: 0.75)
        #expect(short.actions == [])
        #expect(short.why == .notAPull(PluckPullJudgement(depth: 0, drift: 5, threshold: 8.16, verdict: .tooShort, origin: .arming)))
        let pull = moved(&pinches, 8.2, 16, 0, at: 0.8)
        #expect(pull.actions == [.beginPull])
        #expect(moved(&pinches, 60, 40, 0, at: 1).actions == [.movePull])
        #expect(pinches.dragEnded(at: at(1.2)).actions == [.endPull, .settle])
    }

    /// Any way: up, down, toward the viewer, or away, 8.2 pt from where it
    /// armed pulls.
    @Test func everyWayPulls() {
        for move in [SIMD3(0.0, -8.2, 0), SIMD3(0, 8.2, 0), SIMD3(-8.2, 0, 0), SIMD3(0, 0, 8.2), SIMD3(0, 0, -8.2), SIMD3(5, 5, 5)] {
            var pinches = PluckPinches()
            _ = pinches.pressBegan(at: at(0))
            _ = moved(&pinches, 0, 20, 0, at: 0.3)
            _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
            _ = pinches.armPull(at: at(0.7))
            let told = pinches.dragMoved(SIMD3(0, 20, 0) + move, pointsPerMeter: pointsPerMeter, at: at(0.8))
            #expect(told.actions == [.beginPull], "moved \(move)")
        }
    }

    /// A hand that drifted 30 pt during the hold doesn't pull the instant
    /// its pull arms: measured from where it stood then, its next word is a
    /// point away. Measured from the touch, as first shipped, the same word
    /// pulls at once.
    @Test func aHandThatDriftedDuringTheHoldDoesntPullTheInstantItArms() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 0, 30, 0, at: 0.45)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, 0, 31, 0, at: 0.72).actions == [])
        #expect(moved(&pinches, 0, 38.2, 0, at: 0.8).actions == [.beginPull])

        var fromTheTouch = PluckPinches(tuning: PluckTuning(measuresPullFromArming: false))
        _ = fromTheTouch.pressBegan(at: at(0))
        _ = moved(&fromTheTouch, 0, 30, 0, at: 0.45)
        _ = fromTheTouch.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = fromTheTouch.armPull(at: at(0.7))
        #expect(moved(&fromTheTouch, 0, 31, 0, at: 0.72).actions == [.beginPull])
    }

    /// The drag reports depth in steps of about 4.2 pt: one step from where
    /// the pinch armed doesn't pull, two do.
    @Test func oneDepthStepDoesntPullAndTwoDo() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 7.5, -2.1, 13.3, at: 0.4)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, 7.5, -2.1, 17.5, at: 0.75).actions == [])
        #expect(moved(&pinches, 7.5, -2.1, 21.7, at: 0.8).actions == [.beginPull])
    }

    /// With the drag silent as the pull arms, the pinch stood within its
    /// 15 pt start of the touch, so its first word, the first sign of a
    /// move, pulls.
    @Test func theDragsFirstWordAfterASilentArmingPulls() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.armPull(at: at(0.7)).actions == [.pullArmed])
        #expect(pinches.press?.armedAt == nil)
        let first = moved(&pinches, 0, 15, 0, at: 0.9)
        #expect(first.actions == [.beginPull])
        #expect(first.why == .pulled(PluckPullJudgement(depth: 0, drift: 15, threshold: 8.16, verdict: .pulls, origin: .touch)))
    }

    /// The rest stays: the lift outlives a press its scroll's stopping
    /// cancels, and still pulls; its release tap is no tap.
    @Test func theLiftOutlivesItsPressAndItsReleaseIsNoTap() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        #expect(pinches.pressEnded(at: at(0.51)) == PluckPinches.Told(why: .liftOutlivesItsPress))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, -12, 9, 2, at: 0.8).actions == [.beginPull])
        let told = pinches.dragEnded(at: at(1.1))
        #expect(told.actions == [.endPull, .settle])
        #expect(try #require(told.ended).outcome == .pull)
        #expect(pinches.tapped(at: at(1.12)).isRelease)
    }

    // MARK: The headset's trace

    /// Item 6: lifted at 0.56 s and armed at 0.76 s, the drag silent, then
    /// moved across more than toward the viewer. Pulled only after 3.64 s
    /// as first shipped, every word "too shallow"; now its first word pulls.
    @Test func itemSixPullsAtItsFirstWord() {
        var defaults = PluckPinches()
        _ = defaults.pressBegan(at: at(0))
        _ = defaults.holdFired(asTheContainerScrolled: false, at: at(0.56))
        _ = defaults.armPull(at: at(0.76))
        let first = moved(&defaults, -14.3, -2.1, 4.2, at: 0.8)
        #expect(first.actions == [.beginPull])

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

        var defaults = PluckPinches()
        _ = defaults.pressBegan(at: at(0))
        let first = moved(&defaults, 12.5, 8.2, -2.5, at: 0.25)
        #expect(first.actions == [])
        #expect(first.why.name == "withinStillness")
        #expect(defaults.holdFired(asTheContainerScrolled: false, at: at(0.5)).actions == [.lift])
    }

    /// Item 3: lifted at 0.59 s, its drag's first word at 0.73 s, armed at
    /// 0.79 s, its next word at 0.81 s, then let go at 0.87 s. Its hand came
    /// out mostly before the arming, so measured from the arming, its word
    /// at 0.81 s is 5.5 pt along, short of the pull; the words between that
    /// and its end, which the trace didn't show, decide it, 8.2 pt along.
    @Test func itemThreeIsMeasuredFromItsArming() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.59))
        #expect(moved(&pinches, 7.5, -2.1, 13.3, at: 0.73).why == .notArmedYet)
        _ = pinches.armPull(at: at(0.79))
        #expect(pinches.press?.armedAt == SIMD3(7.5, -2.1, 13.3))
        let next = moved(&pinches, 8.6, -0.9, 18.6, at: 0.81)
        #expect(next.actions == [])
        guard case .notAPull(let judgement) = next.why else {
            Issue.record("expected no pull, got \(next.why)")
            return
        }
        #expect(judgement.verdict == .tooShort)
        #expect(judgement.origin == .arming)
        #expect(abs(judgement.distance - 5.54) < 0.01)
        #expect(moved(&pinches, 9.5, -0.5, 21.2, at: 0.84).actions == [.beginPull])
    }
}
