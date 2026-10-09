import Testing
import simd
@testable import GestureCore

/// A head's transform at `position`, its −z the gaze, turned `azimuth`
/// across, to the right for more than 0, and pitched `elevation` up.
private func head(at position: SIMD3<Float>, azimuth: Float = 0, elevation: Float = 0) -> simd_float4x4 {
    let turn = simd_quatf(angle: -azimuth, axis: SIMD3(0, 1, 0))
    let pitch = simd_quatf(angle: elevation, axis: SIMD3(1, 0, 0))
    var transform = simd_float4x4(turn * pitch)
    transform.columns.3 = SIMD4(position, 1)
    return transform
}

private func degrees(_ value: Float) -> Float {
    value * .pi / 180
}

/// The way a thing's front points with `orientation`: its +z.
private func front(of orientation: simd_quatf) -> SIMD3<Float> {
    orientation.act(SIMD3(0, 0, 1))
}

/// A thing carried by its middle, as a panel is by the handle under it
/// (`PanelHandle`): where it stands, and which way it faces, as the hand
/// carries it (`HandCarry.pose(carriedTo:clearOf:from:keeping:tuning:facing:)`).
@Suite struct CarriedPoseTests {
    /// The way it faced before, straight ahead.
    let ahead = simd_quatf(angle: 0, axis: SIMD3(0, 1, 0))
    /// Where its middle stood before: below the gaze, ahead.
    let before = SIMD3<Float>(0, 1.36, -0.66)

    /// Carried, its middle goes where the hand puts it, 1:1, from 0.3 m from
    /// the head out, as `HandCarry.middle` puts it.
    @Test(arguments: [
        SIMD3<Float>(0.2, 1.46, -0.66), SIMD3(-0.5, 1.1, -0.4), SIMD3(0.9, 1.7, 0.2), SIMD3(0, 1.3, -0.31),
    ])
    func itGoesWhereTheHandPutsIt(point: SIMD3<Float>) {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let pose = HandCarry.pose(carriedTo: point, clearOf: eye, from: before, keeping: ahead)
        #expect(pose.position == point)
    }

    /// Nearer the head than 0.3 m, it stops 0.3 m out along the line from
    /// the head through where the hand put it.
    @Test(arguments: [SIMD3<Float>(0, 1.5, -0.15), SIMD3(0.1, 1.62, -0.1), SIMD3(-0.05, 1.45, 0.05)])
    func itNeverComesNearerTheHeadThanThirtyCentimeters(point: SIMD3<Float>) {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let pose = HandCarry.pose(carriedTo: point, clearOf: eye, from: before, keeping: ahead)
        #expect(abs(simd_distance(pose.position, eye) - 0.3) < 1e-5)
        #expect(simd_distance(simd_normalize(pose.position - eye), simd_normalize(point - eye)) < 1e-4)
    }

    /// Wherever it's carried, it turns to face the head, never rolled, so
    /// it tilts up as far as it stands below the head's level, and down as
    /// far as it stands above it.
    @Test(arguments: [
        SIMD3<Float>(0.2, 1.46, -0.66), SIMD3(-0.5, 1.1, -0.4), SIMD3(0.9, 1.7, 0.2), SIMD3(0.4, 0.9, 0.5), SIMD3(0, 2.1, -0.6),
    ])
    func itFacesTheHeadTiltedAsItStandsBelowOrAboveIt(point: SIMD3<Float>) {
        let eye = SIMD3<Float>(0.1, 1.55, -0.1)
        let pose = HandCarry.pose(carriedTo: point, clearOf: eye, from: before, keeping: ahead)
        let toHead = simd_normalize(eye - pose.position)
        #expect(simd_distance(front(of: pose.orientation), toHead) < 1e-4)
        #expect(abs(pose.orientation.act(SIMD3(1, 0, 0)).y) < 1e-5)
        #expect(pose.orientation.act(SIMD3(0, 1, 0)).y > 0)
        // Tilted up as far as the head stands above it.
        #expect(abs(asin(front(of: pose.orientation).y) - asin(toHead.y)) < 1e-4)
    }

    /// A panel placed below the gaze and carried to where it was placed
    /// stands exactly as the placement stood it: the carry tilts it as the
    /// placement does.
    @Test(arguments: [
        head(at: SIMD3(0, 1.6, 0)),
        head(at: SIMD3(0.42, 1.68, -0.3), azimuth: degrees(35)),
        head(at: SIMD3(-1.1, 1.12, 0.8), azimuth: degrees(-120), elevation: degrees(-15)),
        head(at: SIMD3(0.2, 1.4, 0.1), azimuth: degrees(80), elevation: degrees(-30)),
    ])
    func carriedWhereItWasPlacedItStandsAsPlaced(head: simd_float4x4) throws {
        let placement = try #require(GazePlacement.placement(forHead: head))
        let eye = SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let pose = HandCarry.pose(
            carriedTo: placement.pose.position, clearOf: eye, from: placement.pose.position, keeping: placement.pose.orientation
        )
        #expect(simd_distance(pose.position, placement.pose.position) < 1e-6)
        for axis in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
            #expect(simd_distance(pose.orientation.act(axis), placement.pose.orientation.act(axis)) < 1e-5)
        }
    }

    /// With the head straight above or below where it's carried, which way
    /// across it should turn has no meaning: it keeps the way it faced.
    @Test func withTheHeadStraightAboveItKeepsTheWayItFaced() {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let faced = simd_quatf(angle: 0.6, axis: SIMD3(0, 1, 0))
        let pose = HandCarry.pose(carriedTo: SIMD3(0, 1.1, 0), clearOf: eye, from: before, keeping: faced)
        #expect(pose.position == SIMD3(0, 1.1, 0))
        #expect(simd_distance(front(of: pose.orientation), front(of: faced)) < 1e-5)
    }

    /// A hand's place that isn't one leaves it where it stood, facing the
    /// head from there.
    @Test(arguments: [Float.nan, .infinity])
    func aPlaceThatIsntOneLeavesItWhereItStood(value: Float) {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let pose = HandCarry.pose(carriedTo: SIMD3(value, 1.4, -0.6), clearOf: eye, from: before, keeping: ahead)
        #expect(pose.position == before)
        #expect(simd_distance(front(of: pose.orientation), simd_normalize(eye - before)) < 1e-4)
    }

    /// It goes by the carry's tuning and the facing's: kept half a meter off
    /// the head, it stops there, and with a centimeter's vertical tolerance
    /// it keeps the way it faced with the head 5 mm across from straight
    /// above.
    @Test func itGoesByItsTunings() {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let kept = HandCarry.pose(
            carriedTo: SIMD3(0, 1.6, -0.4), clearOf: eye, from: before, keeping: ahead, tuning: CarryTuning(nearestToHead: 0.5)
        )
        #expect(simd_distance(kept.position, SIMD3(0, 1.6, -0.5)) < 1e-5)
        let faced = simd_quatf(angle: 0.6, axis: SIMD3(0, 1, 0))
        let under = HandCarry.pose(
            carriedTo: SIMD3(0.005, 1.1, 0), clearOf: eye, from: before, keeping: faced, facing: FacingTuning(verticalTolerance: 0.01)
        )
        #expect(simd_distance(front(of: under.orientation), front(of: faced)) < 1e-5)
    }
}
