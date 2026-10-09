import Foundation
import Testing
import simd
@testable import GestureCore

/// Where a carried point stands about the viewer's head as the carry
/// begins, and the hand's translation since, taken apart in that frame, for
/// the carry's logs.
@Suite struct ViewerCenteredFrameTests {
    /// The head, a little off the origin, as a tracked head is.
    let head = SIMD3<Float>(0.1, 1.55, 0.2)
    /// A point ahead of it, to its right and below its eyes: about 1.21 m
    /// away, 21° right, and 17° down.
    let start = SIMD3<Float>(0.5, 1.2, -0.9)

    private func frame() throws -> ViewerCenteredFrame {
        try #require(ViewerCenteredFrame(from: start, around: head))
    }

    /// `direction` scaled by `meters`, as a hand's translation in the space.
    private func hand(_ direction: SIMD3<Double>, _ meters: Double) -> SIMD3<Float> {
        SIMD3<Float>(direction * meters)
    }

    /// Its center is the head as the carry began, and it says how far away
    /// the point was, which way across, straight ahead being 0 and the
    /// right positive, and how far up.
    @Test func itSaysHowFarWhichWayAndHowHighThePointWas() throws {
        let frame = try frame()
        let offset = SIMD3<Double>(start - head)
        #expect(simd_distance(SIMD3<Float>(frame.head), head) < 1e-6)
        #expect(abs(frame.radius - simd_length(offset)) < 1e-6)
        #expect(abs(frame.azimuth - atan2(offset.x, -offset.z)) < 1e-6)
        #expect(abs(frame.elevation - asin(offset.y / simd_length(offset))) < 1e-6)
        #expect(frame.azimuth > 0.3 && frame.azimuth < 0.4)
        #expect(frame.elevation < -0.25 && frame.elevation > -0.35)
        let right = try #require(ViewerCenteredFrame(from: SIMD3(1, 1.5, 0), around: SIMD3(0, 1.5, 0)))
        #expect(abs(right.azimuth - .pi / 2) < 1e-12)
        #expect(right.elevation == 0)
    }

    /// Its three directions, out from the head through the point, across
    /// to the right along the level circle, and up along the sphere, are
    /// each a unit long and square to each other.
    @Test func itsDirectionsAreOutAcrossAndUpSquareToEachOther() throws {
        let frame = try frame()
        for direction in [frame.radial, frame.across, frame.upward] {
            #expect(abs(simd_length(direction) - 1) < 1e-12)
        }
        #expect(abs(simd_dot(frame.radial, frame.across)) < 1e-12)
        #expect(abs(simd_dot(frame.radial, frame.upward)) < 1e-12)
        #expect(abs(simd_dot(frame.across, frame.upward)) < 1e-12)
        #expect(simd_distance(frame.radial, simd_normalize(SIMD3<Double>(start - head))) < 1e-6)
        // Across is level, toward the right; up has the world's up in it.
        #expect(frame.across.y == 0)
        #expect(frame.across.x > 0)
        #expect(frame.upward.y > 0)
    }

    /// A hand's translation is told apart into those three parts, in
    /// meters, as the logs give it.
    @Test func itsPartsAreHowFarTheHandMovedOutAcrossAndUp() throws {
        let frame = try frame()
        let parts = frame.parts(of: hand(frame.radial, -0.12) + hand(frame.across, 0.34) + hand(frame.upward, 0.05))
        #expect(abs(parts.outward + 0.12) < 1e-6)
        #expect(abs(parts.across - 0.34) < 1e-6)
        #expect(abs(parts.up - 0.05) < 1e-6)
    }

    /// A point at the head itself has no bearing: straight ahead, level, no
    /// way off.
    @Test func aPointAtTheHeadIsStraightAhead() throws {
        let frame = try #require(ViewerCenteredFrame(from: head, around: head))
        #expect(frame.radius == 0)
        #expect(frame.azimuth == 0)
        #expect(frame.elevation == 0)
        let above = try #require(ViewerCenteredFrame(from: head + SIMD3(0, 1, 0), around: head))
        #expect(above.azimuth == 0)
        #expect(abs(above.elevation - .pi / 2) < 1e-12)
    }

    /// Neither the point nor the head can be a place that isn't one: there's
    /// no frame then.
    @Test(arguments: [Float.nan, .infinity, -.infinity])
    func aPlaceThatIsNotOneMakesNoFrame(value: Float) {
        #expect(ViewerCenteredFrame(from: SIMD3(value, 1, -1), around: head) == nil)
        #expect(ViewerCenteredFrame(from: start, around: SIMD3(0, value, 0)) == nil)
    }

    /// A hand's translation that isn't one has no parts.
    @Test(arguments: [Float.nan, .infinity])
    func aTranslationThatIsNotOneHasNoParts(value: Float) throws {
        let parts = try frame().parts(of: SIMD3(value, 0, 0))
        #expect(parts.outward == 0 && parts.across == 0 && parts.up == 0)
    }
}
