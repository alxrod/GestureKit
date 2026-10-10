import Testing
@testable import GestureCore

/// The words that end a pinch on a pluckable item, as the rules take them
/// since Alex found the scroll stuck after a pluck on October 9: a lift
/// kept up past its press is let go after a quiet with nothing heard; the
/// tap is the pinch let go, whatever its gestures still say; a gesture gone
/// quiet, its end unheard, gives way to the next press or a pinch
/// elsewhere; and breaking free settles the item, so a carry never holds
/// the scroll.
@Suite struct PluckEndWordsTests {
    let start = ContinuousClock.now
    let pointsPerMeter = 1360.0

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// Pinches at the default tuning, pressed at 0, lifted at 0.25.
    func lifted() -> PluckPinches {
        var pinches = PluckPinches()
        _ = pinches.pressBegan(at: at(0))
        _ = pinches.holdFired(asTheContainerScrolled: false, at: at(0.25))
        return pinches
    }

    /// Lifted, armed, and broken free 40 pt across, the drag having spoken.
    func pulling() -> PluckPinches {
        var pinches = lifted()
        _ = pinches.armPull(at: at(0.45))
        _ = pinches.dragMoved(SIMD3(40, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.5))
        return pinches
    }

    // MARK: The quiet

    /// A lift kept up past its press, its drag silent, asks for the quiet;
    /// up early, or once the drag speaks, it does nothing; up with nothing
    /// heard, the pinch is let go, its item settling.
    @Test func aLiftKeptUpPastItsPressIsLetGoAfterTheQuiet() throws {
        var pinches = lifted()
        let pressUp = pinches.pressEnded(at: at(0.26))
        #expect(pressUp.countdowns == [.startQuiet(.seconds(0.5))])
        #expect(pinches.quietPassed(at: at(0.6)) == PluckPinches.Told(why: .toldAlready))
        let told = pinches.quietPassed(at: at(0.76))
        #expect(told.actions == [.settle])
        #expect(told.why == .nothingHeard(seconds: pluckEndWordsSeconds(at(0.76) - at(0.26))))
        #expect(told.countdowns == [.stopHold, .stopArming])
        let account = try #require(told.ended)
        #expect(account.outcome == .lift)
        #expect(account.ending == .quiet)
        #expect(pinches.press == nil)
        // Its tap, should it come late after all, is its release.
        #expect(pinches.tapped(at: at(0.9)).isRelease)

        var moved = lifted()
        _ = moved.pressEnded(at: at(0.26))
        _ = moved.dragMoved(SIMD3(16, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.5))
        #expect(moved.quietPassed(at: at(0.76)) == PluckPinches.Told(why: .toldAlready))
        #expect(moved.press?.isLifted == true)
    }

    /// The quiet's reason reads in plain words.
    @Test func theQuietsReasonSaysHowLong() {
        #expect(PluckReason.nothingHeard(seconds: 0.5).description == "kept up past its press, nothing heard for 0.50 s: taken as let go")
        #expect(PluckReason.dragWentQuiet(seconds: 1.234).description == "the drag said nothing for 1.23 s, its end unheard: a new pinch")
    }

    // MARK: The tap

    /// A tap while the carry of what broke free is under way, its drag's end
    /// not yet heard, lets the carry go where it stands, and the pinch is
    /// over; the drag's end and the press's after it find no pinch.
    @Test func aTapLetsACarryGo() throws {
        var pinches = pulling()
        let tap = pinches.tapped(at: at(1))
        #expect(tap.isRelease)
        #expect(tap.actions == [.releaseSpawned])
        #expect(try #require(tap.ended).outcome == .pull)
        #expect(pinches.dragEnded(at: at(1.01)) == PluckPinches.Told(why: .noPinch))
        #expect(pinches.pressEnded(at: at(1.02)) == PluckPinches.Told(why: .noPinch))
    }

    // MARK: Gestures gone quiet

    /// A press on the item while its drag says it has the pinch but has said
    /// nothing for the quiet, its end unheard, begins a pinch of its own: the
    /// one before is over, its end unseen, its carry let go where it stands.
    /// One that comes while the drag speaks is the press coming back.
    @Test func aPressAfterTheDragWentQuietIsANewPinch() throws {
        var stale = pulling()
        let told = stale.pressBegan(at: at(3))
        #expect(told.beganAPinch)
        #expect(told.actions == [.releaseSpawned])
        #expect(told.why == .dragWentQuiet(seconds: 2.5))
        #expect(try #require(told.ended).ending == .unseen)
        #expect(stale.isHolding)
        #expect(!stale.isDragging)

        var live = pulling()
        _ = live.pressEnded(at: at(0.6))
        #expect(live.pressBegan(at: at(0.8)) == PluckPinches.Told(why: .pressJoined))
    }

    /// A pinch elsewhere settles a lift whose gestures say they have it but
    /// have said nothing for the quiet, the lift counting as heard.
    @Test func aPinchElsewhereSettlesALiftGoneQuiet() throws {
        var pinches = lifted()
        _ = pinches.dragMoved(SIMD3(16, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.4))
        #expect(pinches.pinchBeganElsewhere(at: at(0.8)) == PluckPinches.Told(why: .toldAlready))
        let told = pinches.pinchBeganElsewhere(at: at(0.9))
        #expect(told.actions == [.settle])
        #expect(try #require(told.ended).ending == .unseen)
    }

    // MARK: The spawn

    /// Breaking free settles the item as what it pulls out spawns, so the
    /// container's scroll goes on while the pinch carries it; the carry's
    /// end lets it go, and the item, down already, doesn't settle again.
    @Test func breakingFreeSettlesTheItem() throws {
        var pinches = lifted()
        _ = pinches.armPull(at: at(0.45))
        let told = pinches.dragMoved(SIMD3(40, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.5))
        #expect(told.actions == [.breakFree, .settle])
        #expect(pinches.press?.isLifted == false)
        #expect(pinches.press?.isPulling == true)
        #expect(!pinches.isKeptUpPastItsPress)
        #expect(pinches.dragMoved(SIMD3(80, 0, 0), pointsPerMeter: pointsPerMeter, at: at(0.6)).actions == [.carrySpawned])
        _ = pinches.pressEnded(at: at(0.7))
        let end = pinches.dragEnded(at: at(1))
        #expect(end.actions == [.releaseSpawned])
        let account = try #require(end.ended)
        #expect(account.outcome == .pull)
        #expect(account.settledAfter == .seconds(0.5))
    }
}

/// `duration` in seconds, as a `Double`.
private func pluckEndWordsSeconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}
