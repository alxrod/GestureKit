import Testing
@testable import GestureCore

/// A pinch on an item, told by its hold and its pull's drag, at the tuning
/// the pluck first shipped with: a move first is the container's scroll, which lifts and pulls
/// nothing for the rest of the pinch; held still, the item lifts; and only
/// once its pull has armed, `pullArmDelay` after the lift, does a move
/// toward the viewer pull it out. A lift's release is no tap, and the item
/// settles as the pinch is let go.
@Suite struct PluckPressTests {
    /// The points the tests measure to a meter, so the pull's 2 cm is 27 pt.
    static let pointsPerMeter = 1350.0

    func moved(_ press: inout PluckPress, _ x: Double, _ y: Double, _ z: Double) -> [PluckPress.Action] {
        press.dragMoved(SIMD3(x, y, z), pointsPerMeter: Self.pointsPerMeter)
    }

    /// A press lifted and armed, as a pinch held still half a second and
    /// two tenths more is.
    func armed() -> PluckPress {
        var press = PluckPress(tuning: .firstShipped)
        _ = press.holdFired(asTheContainerScrolled: false)
        _ = press.armPull()
        return press
    }

    @Test func thePullsDistanceIs27PointsAtTheTestsScale() {
        #expect(PluckTuning.firstShipped.breakFreeThreshold(pointsPerMeter: Self.pointsPerMeter) == 27)
    }

    @Test func aPinchHeldStillLifts() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(!press.isLifted)
        #expect(press.holdFired(asTheContainerScrolled: false) == [.lift])
        #expect(press.why == .heldStill)
        #expect(press.isHeld)
        #expect(press.isLifted)
        #expect(!press.isArmed)
        #expect(!press.isPulling)
    }

    /// The container scrolled during the pinch, as one caught coasting: it's
    /// a scroll, and the item stays down.
    @Test func aHoldAfterTheContainerScrolledLiftsNothing() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(press.holdFired(asTheContainerScrolled: true) == [.stayDown(.containerScrolled)])
        #expect(press.why == .containerScrolled)
        #expect(!press.isLifted)
        #expect(press.stayedDown == .containerScrolled)
    }

    /// A pinch that moves before its hold is the container's scroll: it
    /// says so as the drag first speaks, and neither lifts nor pulls for the
    /// rest of the pinch, however it moves.
    @Test func aMoveBeforeTheHoldIsAScrollForTheRestOfThePinch() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(moved(&press, 0, 40, 5) == [.stayDown(.movedFirst)])
        let distance: Double = (1600 + 25 as Double).squareRoot()
        #expect(press.why == .movedFirst(distance: distance, stillness: 15))
        #expect(press.stayedDown == .movedFirst)
        #expect(press.holdFired(asTheContainerScrolled: false) == [])
        #expect(press.why == .toldAlready)
        #expect(!press.isLifted)
        #expect(press.armPull() == [])
        #expect(moved(&press, 0, 0, 120) == [])
        #expect(press.why == .scrolling(.movedFirst))
        #expect(!press.isPulling)
        #expect(press.dragEnded() == [])
        #expect(!press.hasPulled)
    }

    /// A quick pinch yanked toward the viewer, with no hold, is no pull, and
    /// no lift.
    @Test func aYankTowardTheViewerBeforeTheHoldPullsNothing() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(moved(&press, 0, 0, 15) == [.stayDown(.movedFirst)])
        #expect(moved(&press, 3, 4, 60) == [])
        #expect(moved(&press, 0, 0, 200) == [])
        #expect(!press.isLifted)
        #expect(press.dragEnded() == [])
        #expect(!press.hasPulled)
        #expect(!press.swallowsReleaseTap)
    }

    /// Between the lift and its pull's arming, a move neither pulls nor
    /// settles the item; once armed, the next move pulls, judged from where
    /// the pinch touched, so a hand already on its way out catches up.
    @Test func aLiftedPinchPullsNothingUntilItsPullArms() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(press.holdFired(asTheContainerScrolled: false) == [.lift])
        #expect(moved(&press, 0, 0, 40) == [])
        #expect(press.why == .notArmedYet)
        #expect(moved(&press, 5, 0, 60) == [])
        #expect(press.isLifted)
        #expect(!press.isPulling)
        #expect(press.armPull() == [.pullArmed])
        #expect(press.why == .armed)
        #expect(press.isArmed)
        #expect(moved(&press, 5, 0, 61) == [.breakFree])
        #expect(press.isPulling)
        #expect(press.why == .brokeFree(PluckPullJudgement(depth: 61, drift: 5, threshold: 27, verdict: .pulls, origin: .touch)))
    }

    /// The pull arms once, and only on a lifted item.
    @Test func thePullArmsOnceAndOnlyOnALiftedItem() {
        var unheld = PluckPress(tuning: .firstShipped)
        #expect(unheld.armPull() == [])
        #expect(unheld.why == .notLifted)
        #expect(!unheld.isArmed)

        var press = PluckPress(tuning: .firstShipped)
        _ = press.holdFired(asTheContainerScrolled: false)
        #expect(press.armPull() == [.pullArmed])
        #expect(press.armPull() == [])
        #expect(press.why == .armingNotDue)

        var settled = PluckPress(tuning: .firstShipped)
        _ = settled.holdFired(asTheContainerScrolled: false)
        _ = settled.pressEnded()
        #expect(settled.armPull() == [])
        #expect(settled.why == .notLifted)
    }

    /// Once armed, a pull comes 2 cm toward the viewer, drifting across the
    /// container at most twice as far as it comes; a move short of that, or
    /// into the container, pulls nothing.
    @Test func anArmedPullComesTowardTheViewerOneDeepForTwoAcross() {
        for (x, y, z) in [(0.0, 0.0, 27.0), (40, 0, 27), (0, 54, 27), (36, 48, 30)] {
            var press = armed()
            #expect(moved(&press, x, y, z) == [.breakFree], "moved (\(x), \(y), \(z))")
        }
        for (x, y, z) in [(54.1, 0.0, 27.0), (36, 48, 29.9), (0, 0, 26.9), (0, 0, -40), (120, 0, 5), (0, -260, 30)] {
            var press = armed()
            #expect(moved(&press, x, y, z) == [], "moved (\(x), \(y), \(z))")
            #expect(press.isLifted)
        }
    }

    /// The reason a move turned down gives is the pull rule's judgement.
    @Test func aMoveTurnedDownSaysWhy() {
        var slanted = armed()
        _ = moved(&slanted, 120, 0, 30)
        #expect(slanted.why == .notAPull(PluckPullJudgement(depth: 30, drift: 120, threshold: 27, verdict: .tooSlanted, origin: .touch)))
        var shallow = armed()
        _ = moved(&shallow, 0, 0, 12)
        #expect(shallow.why == .notAPull(PluckPullJudgement(depth: 12, drift: 0, threshold: 27, verdict: .tooShallow, origin: .touch)))
    }

    /// A lifted pinch moved across the container, up, or into it pulls
    /// nothing, and its item stays up, its container's scroll off, until
    /// it's let go or the move comes round toward the viewer.
    @Test func aLiftedPinchMovedAcrossUpOrInStaysUpAndPullsNothing() {
        var press = armed()
        #expect(moved(&press, 120, 0, 5) == [])
        #expect(moved(&press, 0, -260, 30) == [])
        #expect(moved(&press, 5, 0, -90) == [])
        #expect(press.isLifted)
        #expect(!press.isPulling)
        #expect(moved(&press, 120, 0, 61) == [.breakFree])
    }

    @Test func aPullMovesWithItsDrag() {
        var press = armed()
        _ = moved(&press, 0, 0, 30)
        #expect(moved(&press, 10, -40, 90) == [.carrySpawned])
        #expect(press.why == .handedToTheCarry)
        #expect(moved(&press, 200, -400, 300) == [.carrySpawned])
    }

    /// A lifted pinch let go without moving, its drag never having spoken,
    /// settles as its press ends.
    @Test func aLiftedPinchLetGoWithoutAPullSettles() {
        var press = PluckPress(tuning: .firstShipped)
        _ = press.holdFired(asTheContainerScrolled: false)
        #expect(press.pressEnded() == [.settle])
        #expect(press.why == .pressEnded)
        #expect(!press.isLifted)
        #expect(!press.hasPulled)
    }

    /// The drag's end is the pinch let go: a pull lands, and the item
    /// settles, whether or not the hold's press has ended yet; the press's
    /// end after it does nothing more.
    @Test func theDragsEndIsThePinchLetGo() {
        var pulled = armed()
        _ = moved(&pulled, 0, 0, 40)
        #expect(pulled.dragEnded() == [.releaseSpawned, .settle])
        #expect(pulled.why == .dragEnded)
        #expect(!pulled.isLifted)
        #expect(pulled.pressEnded() == [])

        var across = armed()
        _ = moved(&across, 40, 0, 5)
        #expect(across.dragEnded() == [.settle])
        #expect(!across.isLifted)
    }

    /// The hold's press ends while the drag still has the pinch, as when the
    /// hand moves off the item: the item stays up, and its drag's end
    /// settles it.
    @Test func thePressEndingMidDragLeavesTheItemUpUntilTheDragEnds() {
        var press = armed()
        _ = moved(&press, 20, 0, 5)
        #expect(press.pressEnded() == [])
        #expect(press.why == .dragHasThePinch)
        #expect(press.isLifted)
        #expect(moved(&press, 20, 0, 50) == [.breakFree])
        #expect(press.dragEnded() == [.releaseSpawned, .settle])
        #expect(!press.isLifted)
    }

    /// A cancelled drag takes its pull away, and the item settles at once,
    /// so the container scrolls again, whatever the hold's press says.
    @Test func aCancelledDragTakesItsPullAwayAndSettles() {
        var pulled = armed()
        _ = moved(&pulled, 0, 0, 40)
        #expect(pulled.dragCancelled() == [.cancelSpawn, .settle])
        #expect(pulled.why == .dragCancelled)
        #expect(!pulled.isLifted)

        var lifted = armed()
        _ = moved(&lifted, 10, 0, 12)
        #expect(lifted.dragCancelled() == [.settle])
        #expect(!lifted.isLifted)
        #expect(lifted.pressEnded() == [])
    }

    @Test func aDragThatNeverPulledEndsWithNothing() {
        var press = PluckPress(tuning: .firstShipped)
        _ = moved(&press, 0, 60, 0)
        #expect(press.dragEnded() == [])
        var cancelled = PluckPress(tuning: .firstShipped)
        _ = moved(&cancelled, 0, 60, 0)
        #expect(cancelled.dragCancelled() == [])
    }

    /// A lift let go, pulled or not, is no tap; a pinch let go before its
    /// hold, one that moved first, and one whose container scrolled are what
    /// they were.
    @Test func aLiftSwallowsTheReleaseTap() {
        var held = PluckPress(tuning: .firstShipped)
        _ = held.holdFired(asTheContainerScrolled: false)
        #expect(held.swallowsReleaseTap)
        _ = held.pressEnded()
        #expect(held.swallowsReleaseTap)
        #expect(held.liftedByHold)
        #expect(!held.hasPulled)

        var pulled = armed()
        _ = moved(&pulled, 0, 0, 40)
        _ = pulled.dragEnded()
        #expect(pulled.swallowsReleaseTap)
        #expect(pulled.hasPulled)

        #expect(!PluckPress(tuning: .firstShipped).swallowsReleaseTap)

        var scrolled = PluckPress(tuning: .firstShipped)
        _ = moved(&scrolled, 0, 60, 0)
        #expect(!scrolled.swallowsReleaseTap)

        var scrolling = PluckPress(tuning: .firstShipped)
        _ = scrolling.holdFired(asTheContainerScrolled: true)
        #expect(!scrolling.swallowsReleaseTap)
    }

    /// A pinch whose container scrolled lifts nothing, and its moves after
    /// are a scroll's: they pull nothing.
    @Test func afterAHoldAsTheContainerScrolledNothingPulls() {
        var press = PluckPress(tuning: .firstShipped)
        _ = press.holdFired(asTheContainerScrolled: true)
        #expect(press.armPull() == [])
        #expect(moved(&press, 0, 0, 60) == [])
        #expect(press.why == .scrolling(.containerScrolled))
        #expect(!press.isLifted)
        #expect(press.hasMoved)
    }

    /// The hold firing again, as a press coming back to the item mid-drag
    /// might make it, changes nothing.
    @Test func aHoldLiftsOnce() {
        var press = PluckPress(tuning: .firstShipped)
        _ = press.holdFired(asTheContainerScrolled: false)
        #expect(press.holdFired(asTheContainerScrolled: false) == [])
        #expect(press.why == .toldAlready)
        _ = press.pressEnded()
        #expect(press.holdFired(asTheContainerScrolled: false) == [])
        #expect(!press.isLifted)
    }

    /// One pinch pulls once.
    @Test func aPressPullsOnce() {
        var press = armed()
        _ = moved(&press, 0, 0, 40)
        _ = press.dragEnded()
        #expect(moved(&press, 0, 0, 80) == [])
        #expect(press.why == .pulledAlready)
        #expect(!press.isPulling)
    }

    /// A move that isn't a number is no move: it neither keeps the hold
    /// from lifting nor pulls.
    @Test func aMoveThatIsntANumberMovesNothing() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(moved(&press, .nan, 0, 40) == [])
        #expect(press.why == .notANumber)
        #expect(moved(&press, 0, .infinity, 40) == [])
        #expect(press.holdFired(asTheContainerScrolled: false) == [.lift])
        _ = press.armPull()
        #expect(moved(&press, 0, 0, .nan) == [])
        #expect(!press.isPulling)
    }

    /// Letting go of a hold that never fired, or of a pinch that pulled
    /// nothing, does nothing.
    @Test func lettingGoOfNothingDoesNothing() {
        var press = PluckPress(tuning: .firstShipped)
        #expect(press.pressEnded() == [])
        #expect(press.dragEnded() == [])
        #expect(press.dragCancelled() == [])
    }
}
