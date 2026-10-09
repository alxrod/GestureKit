import Testing
import simd
@testable import GestureCore

/// Places a thing might stand about the viewer: straight ahead at three
/// heights, toward the end of a row ahead, to the viewer's left, behind
/// them, and twice as far out.
private let standingPlaces: [SIMD3<Float>] = [
    SIMD3(0, 1.0, -1.2), SIMD3(0, 0.72, -1.2), SIMD3(0, 0.44, -1.2),
    SIMD3(0.9, 1.0, -1.2), SIMD3(-0.8, 0.44, -1.2),
    SIMD3(-1.2, 0.72, 0.4), SIMD3(0.3, 1.0, 1.2), SIMD3(0, 1.0, -2.4),
]

/// A thing standing at its place, hung from its middle and facing the
/// viewer from there (`Pose(hanging:at:facing:)`): the point a carry by its
/// handle carries it by and turns it about, as PhotoFinder's drag turns a
/// picture (`CarryPinch`), so the carry starts with no turn. Faced from its
/// handle instead, 8.85 cm below its middle, the carry's first change turned
/// it 3 to 4° about its middle at these places.
@Suite struct CarryStartsStillTests {
    /// A stand-in viewer's eyes, 1.5 m up at the space's origin.
    let eye = SIMD3<Float>(0, 1.5, 0)
    /// The thing's middle in its own frame, 0.31 m along it from its
    /// origin, which the place stands.
    let middle = SIMD3<Float>(0.31, 0, 0)

    private func standing(at place: SIMD3<Float>) -> Pose {
        Pose(hanging: middle, at: place, facing: eye)
    }

    /// Its middle stands at its place.
    @Test(arguments: standingPlaces)
    func itsMiddleStandsAtItsPlace(place: SIMD3<Float>) {
        let pose = standing(at: place)
        #expect(simd_distance(pose.position + pose.orientation.act(middle), place) < 1e-5)
    }

    /// It faces the viewer from its middle, by yaw and pitch alone, as
    /// PhotoFinder's facing turns a picture from its own place.
    @Test(arguments: standingPlaces)
    func itFacesTheViewerFromItsMiddle(place: SIMD3<Float>) {
        let pose = standing(at: place)
        let facing = Facing.orientation(from: place, toward: eye)
        #expect(abs(simd_dot(pose.orientation.vector, facing.vector)) > 1 - 1e-6)
        #expect(angle(pose.orientation.act(SIMD3(0, 0, 1)), simd_normalize(eye - place)) < 0.01)
    }

    /// A pinch on its handle, which carries its middle from where it stands
    /// by the hand's translation, 1:1, and turns it about its middle to face
    /// the viewer from there, leaves it exactly where it was as the hand
    /// begins to move: no turn, and no move of its ends.
    @Test(arguments: standingPlaces)
    func aCarryByItsHandleStartsWithNoTurn(place: SIMD3<Float>) {
        let pose = standing(at: place)
        var pinch = CarryPinch<String>()
        let held = pose.position + pose.orientation.act(middle)
        let actions = pinch.move(distance: CarryTuning.standard.startDistance, translation: .zero) {
            CarryPinch<String>.Grabbed(id: "a", middle: held)
        }
        guard case .carry(_, let carried, _)? = actions.last else {
            Issue.record("the pinch carried nothing: \(actions)")
            return
        }
        let dragged = Pose(hanging: middle, at: carried, facing: eye)
        for axis in [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)] {
            #expect(angle(dragged.orientation.act(axis), pose.orientation.act(axis)) < 0.01)
        }
        for end in [SIMD3<Float>(-0.2, 0, 0), SIMD3(0.82, 0, 0)] {
            #expect(simd_distance(dragged.position + dragged.orientation.act(end), pose.position + pose.orientation.act(end)) < 1e-5)
        }
    }

    /// The angle between two directions, in degrees, exact for small ones.
    private func angle(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        atan2(simd_length(simd_cross(a, b)), simd_dot(a, b)) * 180 / .pi
    }
}
