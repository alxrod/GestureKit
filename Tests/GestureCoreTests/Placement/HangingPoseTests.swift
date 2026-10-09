import Testing
import simd
@testable import GestureCore

/// Places about the viewer: ahead, to either side, behind, above, and below.
private let hangingPoints: [SIMD3<Float>] = [
    SIMD3(0.2, 1.2, -1.2), SIMD3(1.1, 1.0, -0.3), SIMD3(-1.3, 1.6, 0.2),
    SIMD3(0.1, 0.9, 1.4), SIMD3(0.3, 2.6, -0.6), SIMD3(-0.2, 0.3, -0.5),
]

/// A thing hung from a point of it: the point lands exactly where it's
/// hung, and the thing faces the viewer from there, turning about it.
@Suite struct HangingPoseTests {
    /// A stand-in viewer's eyes, 1.5 m up at the space's origin.
    let eye = SIMD3<Float>(0, 1.5, 0)
    /// A point to hang from that's neither the thing's origin nor its
    /// middle: 0.31 m along it from its origin, and 8.85 cm below its
    /// middle line, as a handle centered beneath a row of items is.
    let pivot = SIMD3<Float>(0.31, -0.0885, 0)
    /// The thing's middle, on its middle line above the pivot.
    let middle = SIMD3<Float>(0.31, 0, 0)

    @Test(arguments: hangingPoints)
    func thePivotLandsExactlyOnThePoint(point: SIMD3<Float>) {
        let pose = Pose(hanging: pivot, at: point, facing: eye)
        #expect(simd_distance(pose.position + pose.orientation.act(pivot), point) < 1e-5)
    }

    /// It faces the viewer from the pivot, not from its origin or its
    /// middle: as anything at the point would, by yaw and pitch alone.
    @Test(arguments: hangingPoints)
    func itFacesTheViewerFromThePivot(point: SIMD3<Float>) {
        let pose = Pose(hanging: pivot, at: point, facing: eye)
        let facing = Facing.orientation(from: point, toward: eye)
        #expect(abs(simd_dot(pose.orientation.vector, facing.vector)) > 1 - 1e-6)
        #expect(simd_dot(pose.orientation.act(SIMD3(0, 0, 1)), simd_normalize(eye - point)) > 1 - 1e-5)
    }

    /// Its middle hangs 8.85 cm above the pivot in the thing's own plane:
    /// square to the line to the viewer, and up, since the thing never
    /// rolls.
    @Test(arguments: hangingPoints)
    func itsMiddleHangsAboveThePivotInItsPlane(point: SIMD3<Float>) {
        let pose = Pose(hanging: pivot, at: point, facing: eye)
        let above = pose.position + pose.orientation.act(middle) - point
        #expect(abs(simd_length(above) - 0.0885) < 1e-5)
        #expect(abs(simd_dot(above, simd_normalize(eye - point))) < 1e-5)
        #expect(above.y > 0)
    }

    /// A pivot at the thing's origin is a pose at the point, facing the
    /// viewer from it.
    @Test(arguments: hangingPoints)
    func aPivotAtTheOriginIsAPoseAtThePoint(point: SIMD3<Float>) {
        let pose = Pose(hanging: .zero, at: point, facing: eye)
        let plain = Pose(at: point, facing: eye)
        #expect(simd_distance(pose.position, plain.position) < 1e-6)
        #expect(abs(simd_dot(pose.orientation.vector, plain.orientation.vector)) > 1 - 1e-6)
    }

    /// Carried 1:1 with the hand by a sideways sweep, as PhotoFinder's drag
    /// carries it, the pivot goes exactly where the hand puts it, and the
    /// thing turns about it to face the head.
    @Test(arguments: [0.3, -0.6, 1.0])
    func aSweepCarriesThePivotWhereTheHandPutsIt(across: Double) {
        let start = SIMD3<Float>(0.2, 1.42, -1.1)
        let carried = start + SIMD3<Float>(Float(across), 0, 0)
        let pose = Pose(hanging: pivot, at: carried, facing: eye)
        #expect(simd_distance(pose.position + pose.orientation.act(pivot), carried) < 1e-5)
        #expect(simd_dot(pose.orientation.act(SIMD3(0, 0, 1)), simd_normalize(eye - carried)) > 1 - 1e-5)
    }
}
