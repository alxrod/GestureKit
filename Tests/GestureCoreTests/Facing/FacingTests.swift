import Testing
import simd
@testable import GestureCore

/// PhotoFinder's facing, the reference `Facing` is held to:
/// `PictureManager.rotationToFaceDevice(newPos:curQuat:)`, ported verbatim,
/// its lines and comments as they are, but for `devPos`, which PhotoFinder
/// reads from its device manager (`deviceManager.getDeviceLocation()`), and
/// which this takes as an argument. PhotoFinder turns each picture with it
/// at every change of its drag, the drag chosen for carrying things by their
/// handles after four were tried on the headset. Where the device is
/// straight above or below the picture, its horizontal direction has no
/// length, and this has no number.
private func rotationToFaceDevice(newPos: SIMD3<Float>, curQuat: simd_quatf, devPos: SIMD3<Float>) -> simd_quatf {
    // Calculate direction vector from the entity to the device
    let direction = normalize(devPos - newPos)

    // Calculate horizontal component of the direction (for yaw)
    let horizontalDirection = normalize(SIMD3<Float>(direction.x, 0, direction.z))

    // Assuming the entity's forward vector is the negative Z-axis in its local space
    let globalForward = SIMD3<Float>(0, 0, 1)

    // Calculate yaw rotation (around Y-axis) to face the device horizontally
    let yawRotation = simd_quatf(from: globalForward, to: horizontalDirection)

    // Calculate pitch rotation (around the entity's local X-axis) to tilt up or down towards the device's elevation
    // First, transform global forward vector by yaw rotation to align it with horizontal direction
    let alignedForward = yawRotation.act(globalForward)

    // Then, calculate quaternion that rotates alignedForward to the actual direction vector
    let pitchRotation = simd_quatf(from: alignedForward, to: direction)

    // Combine yaw and pitch rotations
    // Note: This assumes yawRotation already aligns the entity's forward direction with the horizontal projection
    // of the direction vector. The pitchRotation then adjusts the tilt up or down.
    let combinedRotation = pitchRotation * yawRotation

    return combinedRotation
}

/// A stand-in viewer's eyes, 1.5 m up at the space's origin.
private let viewerStandIn = SIMD3<Float>(0, 1.5, 0)

/// Places of a viewer's head: the stand-in's, and tracked heads off the
/// space's origin, one leaning, one sitting low, one turned behind.
private let headsToFace: [SIMD3<Float>] = [
    viewerStandIn, SIMD3(0.42, 1.68, -0.3), SIMD3(-1.1, 1.12, 0.8), SIMD3(2.5, 1.55, 3.1),
]

@Suite struct FacingTests {
    let front = SIMD3<Float>(0, 0, 1)
    let right = SIMD3<Float>(1, 0, 0)
    let up = SIMD3<Float>(0, 1, 0)

    @Test func itsVerticalToleranceIsAMillimeter() {
        #expect(FacingTuning.standard.verticalTolerance == 0.001)
        #expect(FacingTuning() == .standard)
    }

    @Test func aThingStraightAheadOfTheViewerIsNotTurned() {
        let facing = Facing.orientation(from: SIMD3(0, 1.5, -1.5), toward: SIMD3(0, 1.5, 0))
        #expect(distance(facing.act(front), front) < 1e-5)
        #expect(distance(facing.act(up), up) < 1e-5)
    }

    @Test func aThingToTheViewersRightTurnsToFaceThem() {
        // The viewer is to the thing's left (−X), so its front turns there.
        let facing = Facing.orientation(from: SIMD3(2, 1.5, 0), toward: SIMD3(0, 1.5, 0))
        #expect(distance(facing.act(front), SIMD3(-1, 0, 0)) < 1e-5)
    }

    @Test(arguments: [
        SIMD3<Float>(0.3, 0.8, 1), SIMD3(-2, -0.5, -1), SIMD3(0, -1, -3), SIMD3(1, 3, 0.01), SIMD3(-0.2, 0, -5),
    ])
    func theFrontPointsAtTheTargetWithNoRoll(offset: SIMD3<Float>) {
        let position = SIMD3<Float>(0.4, 1.2, -1)
        let facing = Facing.orientation(from: position, toward: position + offset)
        #expect(distance(facing.act(front), normalize(offset)) < 1e-4)
        // No roll: the thing's sides stay level and its top stays up.
        #expect(abs(facing.act(right).y) < 1e-5)
        #expect(facing.act(up).y >= -1e-5)
    }

    @Test func aTargetStraightAboveTiltsTheFrontUpWithoutTurning() {
        let facing = Facing.orientation(from: SIMD3(1, 1, 1), toward: SIMD3(1, 3, 1))
        #expect(distance(facing.act(front), up) < 1e-5)
        #expect(distance(facing.act(right), right) < 1e-5)
    }

    @Test func aTargetAtTheThingLeavesItUnturned() {
        let facing = Facing.orientation(from: SIMD3(1, 1, 1), toward: SIMD3(1, 1, 1))
        #expect(facing == simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    }

    @Test(arguments: [Float.nan, .infinity])
    func aNonFiniteTargetLeavesTheThingUnturned(value: Float) {
        let facing = Facing.orientation(from: SIMD3(0, 1, 0), toward: SIMD3(value, 1, -1))
        #expect(facing == simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    }

    @Test func theOrientationHasUnitLength() {
        let facing = Facing.orientation(from: SIMD3(0.2, 1, -0.7), toward: SIMD3(-1, 1.6, 0.3))
        #expect(abs(facing.length - 1) < 1e-5)
    }

    /// The facing is PhotoFinder's: wherever a thing stands about the
    /// viewer's head, all the way round, from 80° below the head to 80°
    /// above, near and far, both turn its every axis to the same place, so
    /// the two quaternions are one rotation, up to sign. They differ only
    /// where PhotoFinder's has no number, the head straight above or below,
    /// which `aTargetStraightAboveTiltsTheFrontUpWithoutTurning` covers.
    @Test(arguments: headsToFace)
    func itTurnsEveryThingExactlyAsPhotoFindersFacingDoes(head: SIMD3<Float>) {
        var compared = 0
        var differing: [String] = []
        for azimuthStep in 0..<36 {
            for elevationStep in -8...8 {
                for distance: Float in [0.3, 0.75, 1.2, 2.4, 5] {
                    let azimuth = Float(azimuthStep) * 10 * .pi / 180
                    let elevation = Float(elevationStep) * 10 * .pi / 180
                    let offset = distance * SIMD3(cos(elevation) * sin(azimuth), sin(elevation), -cos(elevation) * cos(azimuth))
                    let position = head + offset
                    let photoFinders = rotationToFaceDevice(newPos: position, curQuat: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), devPos: head)
                    let facing = Facing.orientation(from: position, toward: head)
                    compared += 1
                    let axesAgree = [front, right, up].allSatisfy { simd_distance(photoFinders.act($0), facing.act($0)) < 1e-4 }
                    if !axesAgree || abs(simd_dot(photoFinders.vector, facing.vector)) < 1 - 1e-5 {
                        differing.append("\(azimuthStep * 10)° across, \(elevationStep * 10)° up, \(distance) m")
                    }
                }
            }
        }
        #expect(compared == 36 * 17 * 5)
        #expect(differing.isEmpty, "Facing turns otherwise than PhotoFinder at \(differing.count) places, first \(differing.prefix(5))")
    }

    /// A carried thing keeps the way it faces while the head is within a
    /// millimeter across of straight above or below its middle, or at it,
    /// where which way across it should turn has no meaning, and
    /// PhotoFinder's facing has no number: it doesn't swing round to face +z
    /// as it passes over or under the head.
    @Test(arguments: [SIMD3<Float>(0, 1, 0), SIMD3(0, -0.8, 0), SIMD3(0.0006, 0.9, -0.0007), SIMD3(0, 0, 0)])
    func itKeepsTheWayItFacesWithTheTargetStraightAboveOrBelow(offset: SIMD3<Float>) {
        let current = simd_quatf(angle: 2.1, axis: SIMD3(0, 1, 0))
        let position = SIMD3<Float>(0.4, 1.2, -1)
        let kept = Facing.orientation(from: position, toward: position + offset, keeping: current)
        #expect(abs(simd_dot(kept.vector, current.vector)) > 1 - 1e-6)
    }

    /// Anywhere else, a millimeter and more across from straight above or
    /// below, it faces the target as ever.
    @Test(arguments: [SIMD3<Float>(0.3, 0.8, 1), SIMD3(-2, -0.5, -1), SIMD3(0.002, 1, 0), SIMD3(0, -0.4, -0.0015)])
    func elsewhereItFacesTheTargetAsEver(offset: SIMD3<Float>) {
        let current = simd_quatf(angle: 2.1, axis: SIMD3(0, 1, 0))
        let position = SIMD3<Float>(0.4, 1.2, -1)
        let kept = Facing.orientation(from: position, toward: position + offset, keeping: current)
        let facing = Facing.orientation(from: position, toward: position + offset)
        #expect(abs(simd_dot(kept.vector, facing.vector)) > 1 - 1e-6)
    }

    /// A wider vertical tolerance keeps the way it faces farther across from
    /// straight above or below: within a centimeter, a target 5 mm across
    /// keeps it, and one 2 cm across is faced.
    @Test func aWiderToleranceKeepsTheWayItFacesFartherAcross() {
        let current = simd_quatf(angle: 2.1, axis: SIMD3(0, 1, 0))
        let position = SIMD3<Float>(0.4, 1.2, -1)
        let tuning = FacingTuning(verticalTolerance: 0.01)
        let near = Facing.orientation(from: position, toward: position + SIMD3(0.005, 1, 0), keeping: current, tuning: tuning)
        #expect(abs(simd_dot(near.vector, current.vector)) > 1 - 1e-6)
        let far = Facing.orientation(from: position, toward: position + SIMD3(0.02, 1, 0), keeping: current, tuning: tuning)
        let facing = Facing.orientation(from: position, toward: position + SIMD3(0.02, 1, 0))
        #expect(abs(simd_dot(far.vector, facing.vector)) > 1 - 1e-6)
    }

    /// A target that isn't a place keeps the way it faces too; and a way it
    /// faced with no length, or that isn't a number, is no way to keep: it's
    /// the identity.
    @Test func itKeepsTheWayItFacesForATargetThatIsntAPlaceAndTheIdentityForNoWay() {
        let current = simd_quatf(angle: -0.7, axis: SIMD3(0, 1, 0))
        let position = SIMD3<Float>(0.4, 1.2, -1)
        let unplaced = Facing.orientation(from: position, toward: SIMD3(.nan, 1.5, 0), keeping: current)
        #expect(abs(simd_dot(unplaced.vector, current.vector)) > 1 - 1e-6)
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        #expect(Facing.orientation(from: position, toward: position + SIMD3(0, 1, 0), keeping: simd_quatf(vector: .zero)) == identity)
        #expect(Facing.orientation(from: position, toward: position, keeping: simd_quatf(vector: SIMD4(.nan, 0, 0, 1))) == identity)
        let scaled = Facing.orientation(from: position, toward: position, keeping: simd_quatf(vector: current.vector * 3))
        #expect(abs(scaled.length - 1) < 1e-6)
        #expect(abs(simd_dot(scaled.vector, current.vector)) > 1 - 1e-6)
    }

    /// Straight ahead of the head, straight behind it, and square to either
    /// side, at its level, the cases where PhotoFinder's yaw turns from
    /// +z to its own opposite or a right angle: the same turn again.
    @Test(arguments: [SIMD3<Float>(0, 0, -1.2), SIMD3(0, 0, 1.2), SIMD3(1.2, 0, 0), SIMD3(-1.2, 0, 0)])
    func itTurnsAsPhotoFindersFacingDoesLevelWithTheHead(offset: SIMD3<Float>) {
        let head = viewerStandIn
        let photoFinders = rotationToFaceDevice(newPos: head + offset, curQuat: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), devPos: head)
        let facing = Facing.orientation(from: head + offset, toward: head)
        for axis in [front, right, up] {
            #expect(simd_distance(photoFinders.act(axis), facing.act(axis)) < 1e-4)
        }
    }
}
