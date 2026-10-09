import Testing
import simd
@testable import GestureCore

/// One pinch on a grab handle, which carries the thing it's under as
/// PhotoFinder's drag carries a picture: it waits 8 pt, then grabs the thing
/// under its handle and carries its middle 1:1 with the hand, and its end,
/// released or cancelled, ends the carry once. At 1360 pt to the meter, 8 pt
/// is about 5.9 mm.
@Suite struct CarryPinchTests {
    /// A thing named `a`, its middle a little left of straight ahead, 1.2 m
    /// out, below the eyes.
    let grabbed = CarryPinch<String>.Grabbed(id: "a", middle: SIMD3(-0.2, 1.1, -1.2))

    @Test func itWaitsEightPointsAsTheCarryWasSettledOn() {
        #expect(CarryTuning.standard.startDistance == 8)
        #expect(CarryTuning() == .standard)
        #expect(CarryPinch<String>().tuning == .standard)
    }

    /// Under 8 pt it carries nothing, and grabs nothing: a pinch let go
    /// there was no drag, and its end ends nothing.
    @Test func underEightPointsItWaitsAndCarriesNothing() {
        var pinch = CarryPinch<String>()
        var asked = 0
        for distance in [0.0, 3, 7.99] {
            let actions = pinch.move(distance: distance, translation: SIMD3(Float(distance) / 1360, 0, 0)) {
                asked += 1
                return grabbed
            }
            #expect(actions == [])
        }
        #expect(asked == 0)
        #expect(pinch.stage == .waiting)
        #expect(pinch.end() == [])
    }

    /// At 8 pt it grabs the thing under its handle, begins its carry, and
    /// carries its middle at once as far as the hand has moved.
    @Test func atEightPointsItBeginsAndCarriesTheMiddleAsFarAsTheHand() {
        var pinch = CarryPinch<String>()
        let moved = SIMD3<Float>(0.0059, 0, 0)
        let actions = pinch.move(distance: 8, translation: moved) { grabbed }
        #expect(actions == [.beginCarry(id: "a"), .carry(id: "a", middle: grabbed.middle + moved, handMoved: moved)])
        #expect(pinch.stage == .moving(grabbed))
    }

    /// A pinch tuned to wait longer waits that long: tuned to 20 pt, it
    /// carries nothing at 19.9, and begins at 20.
    @Test func aPinchTunedToWaitLongerWaitsThatLong() {
        var pinch = CarryPinch<String>(tuning: CarryTuning(startDistance: 20))
        #expect(pinch.move(distance: 19.9, translation: SIMD3(0.0146, 0, 0)) { grabbed } == [])
        #expect(pinch.stage == .waiting)
        let moved = SIMD3<Float>(0.0147, 0, 0)
        #expect(pinch.move(distance: 20, translation: moved) { grabbed } == [
            .beginCarry(id: "a"), .carry(id: "a", middle: grabbed.middle + moved, handMoved: moved),
        ])
    }

    /// Each change carries the middle from where it was as the carry began,
    /// 1:1, so the hand back where it touched puts the thing back where it
    /// was; the thing is grabbed once, and where it is meanwhile doesn't
    /// count.
    @Test func itCarriesTheMiddleOneToOneFromWhereItWasAsTheCarryBegan() {
        var pinch = CarryPinch<String>()
        var asked = 0
        _ = pinch.move(distance: 9, translation: SIMD3(0, 0.0066, 0)) {
            asked += 1
            return grabbed
        }
        for moved in [SIMD3<Float>(0.3, 0.1, -0.2), SIMD3(-0.45, 0, 0.6), .zero] {
            let actions = pinch.move(distance: 400, translation: moved) {
                asked += 1
                return nil
            }
            #expect(actions == [.carry(id: "a", middle: grabbed.middle + moved, handMoved: moved)])
        }
        #expect(asked == 1)
        #expect(pinch.stage == .moving(grabbed))
    }

    /// A handle under nothing, as one whose thing went, ignores the rest of
    /// the pinch, and its end ends nothing.
    @Test func aHandleUnderNothingIgnoresThePinch() {
        var pinch = CarryPinch<String>()
        #expect(pinch.move(distance: 12, translation: SIMD3(0.009, 0, 0)) { nil } == [.ignore])
        #expect(pinch.stage == .ignored)
        #expect(pinch.move(distance: 200, translation: SIMD3(0.15, 0, 0)) { grabbed } == [])
        #expect(pinch.end() == [])
    }

    /// A carry the caller couldn't begin carries nothing for the rest of the
    /// pinch, and its end ends nothing.
    @Test func aCarryThatCouldntBeginIgnoresTheRestOfThePinch() {
        var pinch = CarryPinch<String>()
        _ = pinch.move(distance: 8, translation: SIMD3(0.0059, 0, 0)) { grabbed }
        pinch.refuse()
        #expect(pinch.stage == .ignored)
        #expect(pinch.move(distance: 100, translation: SIMD3(0.07, 0, 0)) { grabbed } == [])
        #expect(pinch.end() == [])
    }

    /// A refusal before the carry began, or after the pinch ended, changes
    /// nothing.
    @Test func aRefusalOutsideACarryChangesNothing() {
        var waiting = CarryPinch<String>()
        waiting.refuse()
        #expect(waiting.stage == .waiting)
        var over = CarryPinch<String>()
        _ = over.end()
        over.refuse()
        #expect(over.stage == .over)
    }

    /// Its end, released or cancelled, ends the carry once: whichever of the
    /// release and the gesture's reset comes first ends it, the other ends
    /// nothing, and nothing moves after it.
    @Test func itsEndEndsTheCarryOnce() {
        var pinch = CarryPinch<String>()
        _ = pinch.move(distance: 30, translation: SIMD3(0.022, 0, 0)) { grabbed }
        #expect(pinch.end() == [.endCarry(id: "a")])
        #expect(pinch.stage == .over)
        #expect(pinch.end() == [])
        #expect(pinch.move(distance: 40, translation: SIMD3(0.03, 0, 0)) { grabbed } == [])
    }

    /// A change that isn't a number moves nothing: waiting, it doesn't
    /// begin; moving, it carries nothing, and the carry goes on.
    @Test(arguments: [Float.nan, .infinity])
    func aChangeThatIsntANumberMovesNothing(value: Float) {
        var waiting = CarryPinch<String>()
        #expect(waiting.move(distance: Double(value), translation: .zero) { grabbed } == [])
        #expect(waiting.stage == .waiting)
        var waitingOnAPlace = CarryPinch<String>()
        #expect(waitingOnAPlace.move(distance: 30, translation: SIMD3(0, value, 0)) { grabbed } == [])
        #expect(waitingOnAPlace.stage == .waiting)
        var moving = CarryPinch<String>()
        _ = moving.move(distance: 8, translation: SIMD3(0.0059, 0, 0)) { grabbed }
        #expect(moving.move(distance: 20, translation: SIMD3(value, 0, 0)) { grabbed } == [])
        #expect(moving.stage == .moving(grabbed))
    }

    /// What's carried is named however the caller names it: here by a
    /// number.
    @Test func itCarriesWhateverTheCallerNames() {
        var pinch = CarryPinch<Int>()
        let middle = SIMD3<Float>(0, 1, -1), moved = SIMD3<Float>(0, 0, 0.01)
        let actions = pinch.move(distance: 10, translation: moved) {
            CarryPinch<Int>.Grabbed(id: 7, middle: middle)
        }
        #expect(actions == [.beginCarry(id: 7), .carry(id: 7, middle: middle + moved, handMoved: moved)])
        #expect(pinch.end() == [.endCarry(id: 7)])
    }
}
