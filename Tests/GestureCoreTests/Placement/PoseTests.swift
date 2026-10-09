import Testing
import simd
@testable import GestureCore

/// A pose, and a saved placement read back as one safely.
@Suite struct PoseTests {
    let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    @Test func aSavedPlacementBecomesAPose() throws {
        let half = sqrt(Float(0.5))
        let pose = try #require(Pose(savedPosition: [0.5, 1.5, -1.2], savedOrientation: [0, half, 0, half]))
        #expect(pose.position == SIMD3(0.5, 1.5, -1.2))
        #expect(abs(pose.orientation.angle - .pi / 2) < 1e-5)
    }

    @Test func theOrientationIsNormalized() throws {
        let pose = try #require(Pose(savedPosition: [0, 0, 0], savedOrientation: [0, 3, 0, 4]))
        #expect(abs(pose.orientation.length - 1) < 1e-6)
        #expect(abs(pose.orientation.imag.y - 0.6) < 1e-6)
        #expect(abs(pose.orientation.real - 0.8) < 1e-6)
    }

    @Test func aZeroOrientationIsTheIdentity() throws {
        let pose = try #require(Pose(savedPosition: [1, 2, 3], savedOrientation: [0, 0, 0, 0]))
        #expect(pose.orientation == identity)
    }

    @Test(arguments: [Float.nan, .infinity, -.infinity])
    func aNonFiniteOrientationIsTheIdentity(value: Float) throws {
        let pose = try #require(Pose(savedPosition: [1, 2, 3], savedOrientation: [0, value, 0, 1]))
        #expect(pose.orientation == identity)
    }

    @Test func aTinyOrientationIsStillNormalized() throws {
        let pose = try #require(Pose(savedPosition: [0, 0, 0], savedOrientation: [0, 0, 1e-30, 0]))
        #expect(abs(pose.orientation.imag.z - 1) < 1e-6)
    }

    /// An orientation that isn't four numbers, which a placement written by
    /// hand might have, is the identity.
    @Test(arguments: [[Float](), [0, 1, 0], [0, 0, 0, 1, 0]])
    func anOrientationOfTheWrongCountIsTheIdentity(orientation: [Float]) throws {
        let pose = try #require(Pose(savedPosition: [1, 2, 3], savedOrientation: orientation))
        #expect(pose.orientation == identity)
        #expect(pose.position == SIMD3(1, 2, 3))
    }

    @Test(arguments: [Float.nan, .infinity])
    func aNonFinitePositionIsNoPose(value: Float) {
        #expect(Pose(savedPosition: [0, value, 0], savedOrientation: [0, 0, 0, 1]) == nil)
    }

    /// A position that isn't three numbers is no pose.
    @Test(arguments: [[Float](), [0, 1], [0, 1, 2, 3]])
    func aPositionOfTheWrongCountIsNoPose(position: [Float]) {
        #expect(Pose(savedPosition: position, savedOrientation: [0, 0, 0, 1]) == nil)
    }

    @Test func aPoseRoundTripsThroughItsSavedPlacement() throws {
        let pose = Pose(
            position: SIMD3(-0.3, 1.4, -2),
            orientation: simd_quatf(angle: 0.7, axis: normalize(SIMD3<Float>(0.2, 1, 0.1)))
        )
        #expect(pose.savedPosition == [-0.3, 1.4, -2])
        #expect(pose.savedOrientation.count == 4)
        let back = try #require(Pose(savedPosition: pose.savedPosition, savedOrientation: pose.savedOrientation))
        #expect(distance(back.position, pose.position) < 1e-6)
        #expect(abs(dot(back.orientation.vector, pose.orientation.vector)) > 1 - 1e-6)
    }

    @Test func aPoseFacesTheTargetFromItsPosition() {
        let pose = Pose(at: SIMD3(1, 1.5, -1), facing: SIMD3(0, 1.5, 0))
        #expect(pose.position == SIMD3(1, 1.5, -1))
        #expect(distance(pose.orientation.act(SIMD3(0, 0, 1)), normalize(SIMD3(-1, 0, 1))) < 1e-5)
    }

    /// A pose made from an orientation of any length turns by it at unit
    /// length; one of none, or that isn't a number, doesn't turn.
    @Test func aPoseNormalizesTheOrientationItsGiven() {
        let turn = simd_quatf(angle: 0.4, axis: SIMD3(0, 1, 0))
        let scaled = Pose(position: .zero, orientation: simd_quatf(vector: turn.vector * 5))
        #expect(abs(scaled.orientation.length - 1) < 1e-6)
        #expect(abs(dot(scaled.orientation.vector, turn.vector)) > 1 - 1e-6)
        #expect(Pose(position: .zero, orientation: simd_quatf(vector: .zero)).orientation == identity)
        #expect(Pose(position: .zero, orientation: simd_quatf(vector: SIMD4(0, .nan, 0, 1))).orientation == identity)
    }
}
