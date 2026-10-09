import Testing
@testable import GestureCore

/// The pluck at its defaults, as Alex asked on October 9 after trying the
/// lab: the item lifts after a quarter second, half the hold it had; lifted,
/// it stays in its container, following the hand a little on its tether,
/// half the move at first and easing toward 20 pt; and only once the hand
/// has gone 2.5 cm any way from where it stood as the item lifted does the
/// item break free. Let go before that, it settles, with nothing spawned and
/// no tap. At the headset's 1,360 pt to the meter, 2.5 cm is 34 pt.
@Suite struct PluckStickyTests {
    let start = ContinuousClock.now
    let pointsPerMeter = 1360.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    func moved(_ pinches: inout PluckPinches, _ x: Double, _ y: Double, _ z: Double, at seconds: Double) -> PluckPinches.Told {
        pinches.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: at(seconds))
    }

    /// Pinches at `tuning`, pressed at 0, lifted at its hold, and armed two
    /// tenths later, the drag silent.
    func liftedAndArmed(_ tuning: PluckTuning = PluckTuning()) -> PluckPinches {
        var pinches = PluckPinches(tuning: tuning)
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(tuning.holdDuration))
        _ = pinches.armPull(at: at(tuning.holdDuration + tuning.pullArmDelay))
        return pinches
    }

    func isClose(_ a: SIMD3<Double>, _ b: SIMD3<Double>, within tolerance: Double = 1e-9) -> Bool {
        let d = a - b
        return (d * d).sum().squareRoot() <= tolerance
    }

    // MARK: The lift, at half the hold

    /// The hold is counted for a quarter second, half the one the pluck first
    /// shipped with, and the item lifts then; the arming counts from the
    /// lift, so it comes at 0.45 s rather than 0.7.
    @Test func theItemLiftsAtAQuarterSecond() throws {
        #expect(PluckTuning().holdDuration == PluckTuning.firstShipped.holdDuration / 2)
        var pinches = PluckPinches()
        #expect(pinches.pressBegan(at: at(0)).countdowns == [.stopArming, .startHold(.seconds(0.25))])
        let held = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        #expect(held == PluckPinches.Told(actions: [.lift], why: .heldStill, countdowns: [.startArming(.seconds(0.2))]))
        #expect(pinches.liftedAt == at(0.25))
        #expect(pinches.armPull(at: at(0.44)) == PluckPinches.Told(why: .armingNotDue))
        #expect(pinches.armPull(at: at(0.45)).actions == [.pullArmed])
        #expect(pinches.dragEnded(at: at(0.6)).actions == [.settle])
        let account = try #require(pinches.pressEnded(at: at(0.6)).ended)
        #expect(account.heldAfter == .seconds(0.25))
        #expect(account.armedAfter == .seconds(0.45))
    }

    /// A fresh pinch's settling, 15 pt in its first quarter second, still
    /// doesn't give the hold up.
    @Test func aFreshPinchsSettlingStillLifts() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        #expect(moved(&pinches, 4, 15, -2, at: 0.2).actions == [])
        #expect(pinches.holdFired(asTheContainerScrolled: false, at: at(0.25)).actions == [.lift])
        #expect(pinches.press?.liftPoint == SIMD3(4, 15, -2))
    }

    // MARK: Held: the item follows, with resistance

    /// Lifted, each move draws the item a little along with the hand, from
    /// where it lifted, half the move at first, less as it goes on, and says
    /// how far the hand has gone of the 34 pt it takes to break free; before
    /// the arming and after, and breaking nothing free short of 34 pt.
    @Test func aLiftedItemFollowsTheHandWithResistance() throws {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        #expect(pinches.stretch == nil)
        #expect(pinches.follow == .zero)

        let first = moved(&pinches, 0, 15, 0, at: 0.3)
        #expect(first == PluckPinches.Told(why: .notArmedYet))
        let held = try #require(pinches.stretch)
        #expect(held.reach == 15)
        #expect(abs(held.needs - 34) < 1e-9)
        // 7.5 · 20 / 27.5: a little over a third of the hand's 15 pt.
        #expect(isClose(held.follow, SIMD3(0, 150.0 / 27.5, 0)))
        #expect(pinches.follow == held.follow)

        let armed = moved(&pinches, 0, 30, 0, at: 0.5)
        #expect(armed.actions == [.pullArmed])
        guard case .notAPull(let judgement) = armed.why else {
            Issue.record("expected the item held, got \(armed.why)")
            return
        }
        #expect(judgement.verdict == .tooShort)
        #expect(judgement.description == "too short, 30.0 pt from the touch (0.0 deep, 30.0 across), needs 34.0 pt")
        // 15 · 20 / 35: the next 15 pt of the hand draw it 3 pt more.
        #expect(isClose(pinches.follow, SIMD3(0, 300.0 / 35, 0)))
        #expect(pinches.stretch?.reach == 30)
        #expect(pinches.press?.isLifted == true)
    }

    /// The follow is measured from where the pinch stood as its item lifted,
    /// as the break-free distance is, so a drift during the hold draws
    /// nothing: the hand back where it lifted draws the item where it stands
    /// lifted.
    @Test func theFollowIsMeasuredFromWhereItLifted() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 0, 20, 0, at: 0.2)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        _ = moved(&pinches, 0, 20.5, 0, at: 0.3)
        #expect(pinches.stretch?.reach == 0.5)
        _ = moved(&pinches, 0, 20, 0, at: 0.35)
        #expect(pinches.follow == .zero)
        _ = moved(&pinches, 10, 20, 0, at: 0.4)
        #expect(pinches.follow.y == 0)
        #expect(pinches.follow.x > 0 && pinches.follow.x < 5)
    }

    /// A hand that has pinched and holds still, settling and trembling a few
    /// points, never breaks the item free, however long it holds.
    @Test func aStillHandNeverBreaksFree() throws {
        var pinches = liftedAndArmed()
        var t = 0.5
        for (x, y, z) in [(3.0, 15.0, 0.0), (5, 17, 4.2), (4, 16, 0), (6, 18, 4.2), (5, 16, 8.4), (4, 17, 4.2)] {
            #expect(moved(&pinches, x, y, z, at: t).actions == [])
            t += 0.4
        }
        #expect(pinches.press?.hasPulled == false)
        #expect(pinches.dragEnded(at: at(t)).actions == [.settle])
        let account = try #require(pinches.pressEnded(at: at(t)).ended)
        #expect(account.outcome == .lift)
        #expect(account.farthestStretch < 21)
    }

    // MARK: Breaking free

    /// Armed, a move 34 pt from where the pinch stood as its item lifted
    /// breaks it free: it spawns, and the item springs back to where it
    /// stands lifted, its follow gone. 33.9 pt holds it.
    @Test func itBreaksFreeAt34PointsFromWhereItLifted() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = moved(&pinches, 0, 12, 0, at: 0.2)
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        _ = pinches.armPull(at: at(0.45))
        #expect(moved(&pinches, 0, 45.9, 0, at: 0.6).actions == [])
        #expect(pinches.follow.y > 9)
        let free = moved(&pinches, 0, 46, 0, at: 0.65)
        #expect(free.actions == [.breakFree])
        #expect(free.why == .brokeFree(PluckPullJudgement(depth: 0, drift: 34, threshold: 34, verdict: .pulls, origin: .lift)))
        #expect(pinches.stretch == nil)
        #expect(pinches.follow == .zero)
        #expect(pinches.press?.isPulling == true)
        #expect(pinches.press?.farthestStretch == 34)
    }

    /// Any way breaks it free: across, up, down, toward the viewer, or away.
    @Test func itBreaksFreeAnyWay() {
        for move in [SIMD3(34.0, 0, 0), SIMD3(-34, 0, 0), SIMD3(0, 34, 0), SIMD3(0, -34, 0), SIMD3(0, 0, 34), SIMD3(0, 0, -34), SIMD3(20, 20, 20)] {
            var pinches = PluckPinches()
            _ = pinches.pressBegan(at: at(0))
            _ = moved(&pinches, 0, 16, 0, at: 0.2)
            _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
            _ = pinches.armPull(at: at(0.45))
            let told = pinches.dragMoved(SIMD3(0, 16, 0) + move, pointsPerMeter: pointsPerMeter, at: at(0.6))
            #expect(told.actions == [.breakFree], "moved \(move)")
        }
    }

    /// A hand that went past the break-free distance before the arming
    /// breaks the item free at its first word after it: the item shows
    /// lifted, and held, for the arming's two tenths at the least.
    @Test func aHandPastTheDistanceBreaksFreeAtTheArming() {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        #expect(moved(&pinches, 0, 0, 40, at: 0.35).why == .notArmedYet)
        #expect(pinches.follow.z > 0)
        #expect(moved(&pinches, 0, 0, 44, at: 0.46).actions == [.pullArmed, .breakFree])
    }

    // MARK: Let go short of it

    /// Let go short of breaking free, the item settles back into its
    /// container: nothing spawns, and its release is no tap.
    @Test func letGoShortOfBreakingFreeItSettles() throws {
        var pinches = liftedAndArmed()
        _ = moved(&pinches, 0, 0, 30, at: 0.6)
        let told = pinches.dragEnded(at: at(0.8))
        #expect(told.actions == [.settle])
        #expect(pinches.follow == .zero)
        let account = try #require(pinches.pressEnded(at: at(0.8)).ended)
        #expect(account.outcome == .lift)
        #expect(account.pulledAfter == nil)
        #expect(account.farthestStretch == 30)
        #expect(abs(try #require(account.breakFreeAt) - 34) < 1e-9)
        #expect(pinches.tapped(at: at(0.81)).isRelease)
    }

    // MARK: The old behavior, through the tuning

    /// The pluck as Alex tried it on October 9 is still a tuning away: the
    /// hold half a second, the item following nothing, and 8.2 pt from where
    /// it lifted breaking it free.
    @Test func theOldBehaviorIsATuningAway() {
        var pinches = PluckPinches(tuning: .notSticky)
        #expect(pinches.pressBegan(at: at(0)).countdowns == [.stopArming, .startHold(.seconds(0.5))])
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.5))
        _ = pinches.armPull(at: at(0.7))
        #expect(moved(&pinches, 0, 5, 0, at: 0.75).actions == [])
        #expect(pinches.follow == .zero)
        #expect(pinches.stretch?.reach == 5)
        #expect(moved(&pinches, 0, 8.2, 0, at: 0.8).actions == [.breakFree])
    }

    /// A share of 0, or a cap of 0, follows nothing, whatever the distance.
    @Test func noShareOrNoCapFollowsNothing() {
        for tuning in [PluckTuning(followShare: 0), PluckTuning(followCap: 0)] {
            var pinches = liftedAndArmed(tuning)
            _ = moved(&pinches, 10, 10, 10, at: 0.6)
            #expect(pinches.follow == .zero)
            #expect(pinches.stretch != nil)
        }
    }

    /// Without the arming, as at 0, the distance alone keeps the item held.
    @Test func withNoArmingTheDistanceAloneHolds() {
        var pinches = PluckPinches(tuning: PluckTuning(pullArmDelay: 0))
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        #expect(moved(&pinches, 0, 0, 33, at: 0.26).actions == [.pullArmed])
        #expect(moved(&pinches, 0, 0, 34, at: 0.27).actions == [.breakFree])
    }
}

/// The tether a lifted item follows its pinch on: a share of the hand's
/// move at first, easing toward a cap, as a scroll view's content follows a
/// pinch past its end.
@Suite struct PluckTetherTests {
    let tether = PluckTuning().tether

    @Test func itFollowsHalfAtFirstAndEasesTowardItsCap() {
        #expect(tether.followDistance(forMove: 0) == 0)
        // Half the move at first: 0.001 pt draws 0.0005.
        #expect(abs(tether.followDistance(forMove: 0.001) - 0.0005) < 1e-7)
        #expect(abs(tether.followDistance(forMove: 5) - 2.5 * 20 / 22.5) < 1e-12)
        #expect(abs(tether.followDistance(forMove: 15) - 7.5 * 20 / 27.5) < 1e-12)
        #expect(abs(tether.followDistance(forMove: 34) - 17 * 20 / 37) < 1e-12)
        #expect(tether.followDistance(forMove: 1_000_000) < 20)
        #expect(tether.followDistance(forMove: 1_000_000) > 19.99)
    }

    /// The farther the hand goes, the less each point of it draws the item:
    /// by 34 pt, where it breaks free, a seventh of what it drew at first.
    @Test func eachPointDrawsLessThanTheOneBefore() {
        var last = 0.0
        var lastStep = Double.infinity
        for points in stride(from: 1.0, through: 60, by: 1) {
            let drawn = tether.followDistance(forMove: points)
            let step = drawn - last
            #expect(step > 0)
            #expect(step < lastStep)
            last = drawn
            lastStep = step
        }
        let slopeAtBreakFree = (tether.followDistance(forMove: 34.001) - tether.followDistance(forMove: 33.999)) / 0.002
        #expect(abs(slopeAtBreakFree - 0.5 / (1.85 * 1.85)) < 1e-6)
    }

    /// The item follows along the hand's move, any way.
    @Test func itFollowsAlongTheMove() {
        let move = SIMD3<Double>(3, -4, 12)
        let follow = tether.follow(forMove: move)
        let drawn = (follow * follow).sum().squareRoot()
        #expect(abs(drawn - tether.followDistance(forMove: 13)) < 1e-12)
        let along = follow / drawn
        let unit = move / 13
        #expect(abs((along * unit).sum() - 1) < 1e-12)
        #expect(tether.follow(forMove: .zero) == .zero)
    }

    /// A move that isn't a number, or a tether that follows nothing, draws
    /// nothing.
    @Test func nothingFollowsWhatIsntANumber() {
        #expect(tether.follow(forMove: SIMD3(.nan, 0, 0)) == .zero)
        #expect(tether.followDistance(forMove: .infinity) == 0)
        #expect(!PluckTether(share: 0, cap: 20).follows)
        #expect(!PluckTether(share: 0.5, cap: 0).follows)
        #expect(!PluckTether(share: .nan, cap: 20).follows)
        #expect(PluckTether(share: 0.5, cap: 0).follow(forMove: SIMD3(10, 0, 0)) == .zero)
    }

    /// A share of 1 and a cap far off follow the hand almost 1:1, near it.
    @Test func aWholeShareWithAFarCapAlmostKeepsUp() {
        let loose = PluckTether(share: 1, cap: 1_000_000)
        #expect(abs(loose.followDistance(forMove: 30) - 30) < 0.001)
    }

    /// How far a move went by the rule's own measure: any way for the
    /// default, toward the viewer for the rules that ask for depth.
    @Test func theRulesReachIsItsOwnMeasure() {
        let judgement = PluckPullJudgement(depth: 4, drift: 3, threshold: 34, verdict: .tooShort, origin: .lift)
        #expect(PluckPullRule.anyDirection.reach(of: judgement) == 5)
        #expect(PluckPullRule.towardTheViewer.reach(of: judgement) == 4)
        #expect(PluckPullRule.outOfThePlane(depthPerDrift: 0.5).reach(of: judgement) == 4)
        let away = PluckPullJudgement(depth: -4, drift: 3, threshold: 34, verdict: .tooShallow, origin: .lift)
        #expect(PluckPullRule.towardTheViewer.reach(of: away) == 0)
    }
}
