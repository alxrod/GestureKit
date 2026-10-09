import Testing
import simd
@testable import GestureCore

/// Where a thing carried by its grab handle stands: exactly where the hand
/// puts its middle, 1:1, but never nearer the viewer's head than 0.3 m,
/// pushed out along the line from the head through it.
@Suite struct HandCarryTests {
    /// A stand-in viewer's eyes, 1.5 m up at the space's origin.
    let viewer = SIMD3<Float>(0, 1.5, 0)
    /// Where the middle stood before, ahead and a little to the right.
    let before = SIMD3<Float>(0.6, 1.5, -0.8)

    /// As near as a carry around the head, tried before, let a thing come.
    @Test func itNeverComesNearerTheHeadThanThirtyCentimeters() {
        #expect(CarryTuning.standard.nearestToHead == 0.3)
    }

    /// From 0.3 m out, the middle is exactly where the hand puts it, ahead,
    /// beside, behind, above, and below the head alike.
    @Test(arguments: [
        SIMD3<Float>(0, 1.5, -0.3), SIMD3(0.2, 1.2, -1.1), SIMD3(-2, 0.4, 1), SIMD3(0, 2.6, 0), SIMD3(0.05, 1.5, 0.35), SIMD3(0.1, 0.2, -0.1),
    ])
    func fromThreeTenthsOfAMeterOutItsWhereTheHandPutsIt(point: SIMD3<Float>) {
        #expect(HandCarry.middle(carriedTo: point, clearOf: viewer, from: before) == point)
    }

    /// Nearer, it's pushed out along the line from the head through it, to
    /// 0.3 m.
    @Test(arguments: [
        SIMD3<Float>(0, 1.5, -0.12), SIMD3(0.1, 1.45, -0.05), SIMD3(0, 1.3, 0), SIMD3(-0.15, 1.6, 0.2), SIMD3(0, 1.5001, 0),
    ])
    func nearerItsPushedOutAlongTheLineFromTheHead(point: SIMD3<Float>) {
        let kept = HandCarry.middle(carriedTo: point, clearOf: viewer, from: before)
        #expect(abs(simd_distance(kept, viewer) - 0.3) < 1e-5)
        #expect(simd_distance(simd_normalize(kept - viewer), simd_normalize(point - viewer)) < 1e-4)
    }

    /// A thing 0.6 m ahead, pulled straight in toward the face, follows the
    /// hand 1:1 until it's 0.3 m out, and stays there however much farther
    /// the hand comes.
    @Test func aThingPulledTowardTheFaceStopsShortOfIt() {
        let start = SIMD3<Float>(0, 1.5, -0.6)
        for step in 0...11 {
            let pulled = Float(step) * 0.05
            let point = start + SIMD3(0, 0, pulled)
            let kept = HandCarry.middle(carriedTo: point, clearOf: viewer, from: start)
            let expected = pulled <= 0.3 ? point : SIMD3<Float>(0, 1.5, -0.3)
            #expect(simd_distance(kept, expected) < 1e-5, "pulled \(pulled) m in")
        }
    }

    /// Tuned to keep it half a meter off the head, it stops there instead.
    @Test func tunedFartherOffItStopsFartherOut() {
        let tuning = CarryTuning(nearestToHead: 0.5)
        let kept = HandCarry.middle(carriedTo: SIMD3(0, 1.5, -0.4), clearOf: viewer, from: before, tuning: tuning)
        #expect(simd_distance(kept, SIMD3(0, 1.5, -0.5)) < 1e-5)
        let farther = SIMD3<Float>(0, 1.5, -0.6)
        #expect(HandCarry.middle(carriedTo: farther, clearOf: viewer, from: before, tuning: tuning) == farther)
    }

    /// At the head itself, which is on no line from it, it goes out through
    /// where it stood before, or straight ahead should that be at the head
    /// too.
    @Test func atTheHeadItGoesOutThroughWhereItStood() {
        let kept = HandCarry.middle(carriedTo: viewer, clearOf: viewer, from: before)
        #expect(simd_distance(kept, viewer + 0.3 * simd_normalize(before - viewer)) < 1e-5)
        let ahead = HandCarry.middle(carriedTo: viewer, clearOf: viewer, from: viewer)
        #expect(simd_distance(ahead, viewer + SIMD3(0, 0, -0.3)) < 1e-5)
    }

    /// A point or a head that isn't a place leaves the middle where it
    /// stood.
    @Test(arguments: [Float.nan, .infinity])
    func aPlaceThatIsntOneLeavesTheMiddleWhereItStood(value: Float) {
        #expect(HandCarry.middle(carriedTo: SIMD3(value, 1.5, -1), clearOf: viewer, from: before) == before)
        #expect(HandCarry.middle(carriedTo: SIMD3(0, 1.5, -1), clearOf: SIMD3(0, value, 0), from: before) == before)
    }
}
