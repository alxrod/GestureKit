import Testing
import simd
@testable import GestureCore

/// A head's transform as world tracking's device anchor gives it: at
/// `position`, its −z, the way the face points, turned `azimuth` across from
/// straight ahead, to the right for more than 0, as `ViewerCenteredFrame`
/// counts it, then pitched `elevation` up, and rolled `roll` about the way it
/// points, its top tipping to the right for more than 0.
private func head(at position: SIMD3<Float>, azimuth: Float = 0, elevation: Float = 0, roll: Float = 0) -> simd_float4x4 {
    let turn = simd_quatf(angle: -azimuth, axis: SIMD3(0, 1, 0))
    let pitch = simd_quatf(angle: elevation, axis: SIMD3(1, 0, 0))
    let tip = simd_quatf(angle: -roll, axis: SIMD3(0, 0, 1))
    var transform = simd_float4x4(turn * pitch * tip)
    transform.columns.3 = SIMD4(position, 1)
    return transform
}

private func degrees(_ value: Float) -> Float {
    value * .pi / 180
}

/// The way a head with `transform` looks: its −z.
private func gaze(of transform: simd_float4x4) -> SIMD3<Float> {
    simd_normalize(-SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
}

private func position(of transform: simd_float4x4) -> SIMD3<Float> {
    SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
}

/// Heads a panel is placed for: standing and sitting, off the space's
/// origin, turned every way across, and looking a little up or down, as a
/// viewer does as a panel opens.
private let heads: [simd_float4x4] = [
    head(at: SIMD3(0, 1.6, 0)),
    head(at: SIMD3(0.42, 1.68, -0.3), azimuth: degrees(35)),
    head(at: SIMD3(-1.1, 1.12, 0.8), azimuth: degrees(-120), elevation: degrees(-15)),
    head(at: SIMD3(2.5, 1.55, 3.1), azimuth: degrees(180), elevation: degrees(12)),
    head(at: SIMD3(0.2, 1.4, 0.1), azimuth: degrees(80), elevation: degrees(-30)),
    head(at: SIMD3(-0.3, 1.7, -0.6), azimuth: degrees(-10), elevation: degrees(25)),
]

/// Where a panel stands as it opens: slightly below the viewer's gaze,
/// angled up to them.
@Suite struct GazePlacementTests {
    /// The panel's front, which faces the viewer, its right, and its top, in
    /// its own frame.
    let front = SIMD3<Float>(0, 0, 1)
    let right = SIMD3<Float>(1, 0, 0)
    let up = SIMD3<Float>(0, 1, 0)

    /// 0.7 m out, within reach, 20° below the gaze, no steeper than 60°,
    /// and drawn at 0.7, so it looks as big as an attachment does a meter
    /// out, 1360 pt to the meter, rather than an 860 pt panel's 48° across
    /// at full size.
    @Test func itStandsWithinReachTwentyDegreesBelowTheGaze() {
        let tuning = PlacementTuning.standard
        #expect(tuning == PlacementTuning())
        #expect(tuning.distance == 0.7)
        #expect(abs(tuning.angleBelowTheGaze - degrees(20)) < 1e-6)
        #expect(abs(tuning.steepest - degrees(60)) < 1e-6)
        #expect(tuning.leastLevelGaze == 0.1)
        #expect(abs(tuning.scale / tuning.distance - 1) < 1e-6)
        #expect(tuning.scale == 0.7)
    }

    /// A head looking straight ahead, level: the panel's middle 0.7 m out
    /// along a line 20° below the gaze, facing the head, tilted 20° up to
    /// it, and not rolled.
    @Test func aLevelGazePutsItAheadAndBelowTiltedUp() throws {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let placement = try #require(GazePlacement.placement(forHead: head(at: eye)))
        let below = degrees(20)
        let expected = eye + 0.7 * SIMD3(0, -sin(below), -cos(below))
        #expect(simd_distance(placement.pose.position, expected) < 1e-5)
        #expect(simd_distance(placement.pose.orientation.act(front), SIMD3(0, sin(below), cos(below))) < 1e-5)
        #expect(simd_distance(placement.pose.orientation.act(right), right) < 1e-5)
        #expect(abs(placement.distance - 0.7) < 1e-6)
        #expect(abs(placement.gazeAzimuth) < 1e-6)
        #expect(abs(placement.gazeElevation) < 1e-6)
        #expect(abs(placement.elevation + below) < 1e-6)
        #expect(abs(placement.belowTheGaze - below) < 1e-6)
        #expect(abs(placement.tilt - below) < 1e-6)
    }

    /// Wherever the head is and however it's turned, the middle stands
    /// 0.7 m from it, 20° below where it looks, straight down from the gaze
    /// rather than off to a side, and the panel faces it.
    @Test(arguments: heads)
    func itStandsItsDistanceOutAndTwentyDegreesBelowTheGaze(head: simd_float4x4) throws {
        let placement = try #require(GazePlacement.placement(forHead: head))
        let eye = position(of: head)
        let looking = gaze(of: head)
        let offset = placement.pose.position - eye
        #expect(abs(simd_length(offset) - 0.7) < 1e-5)
        // 20° from the gaze, and below it.
        let apart = acos(min(max(simd_dot(simd_normalize(offset), looking), -1), 1))
        #expect(abs(apart - degrees(20)) < 1e-4)
        #expect(offset.y < 0.7 * looking.y)
        // In the upright plane through the gaze: the same way across.
        let across = simd_normalize(SIMD3(looking.x, 0, looking.z))
        let offsetAcross = simd_normalize(SIMD3(offset.x, 0, offset.z))
        #expect(simd_distance(across, offsetAcross) < 1e-4)
        // Facing the head.
        #expect(simd_distance(placement.pose.orientation.act(front), simd_normalize(-offset)) < 1e-4)
    }

    /// The panel tilts up as far as it stands below the head's level, and
    /// never rolls: its sides stay level and its top up.
    @Test(arguments: heads)
    func itTiltsUpToTheHeadWithNoRoll(head: simd_float4x4) throws {
        let placement = try #require(GazePlacement.placement(forHead: head))
        let orientation = placement.pose.orientation
        #expect(abs(orientation.act(right).y) < 1e-5)
        #expect(orientation.act(up).y > 0)
        #expect(abs(asin(orientation.act(front).y) - placement.tilt) < 1e-4)
        #expect(abs(placement.tilt + placement.elevation) < 1e-6)
        #expect(abs(orientation.length - 1) < 1e-5)
    }

    /// The angles the log gives: which way across the gaze points, as
    /// `ViewerCenteredFrame` counts it, how far up, and how far up the
    /// middle stands, all from the head's level.
    @Test(arguments: [(Float(35), Float(10)), (-120, -15), (180, 0), (80, -30), (-10, 25)])
    func itSaysWhichWayTheGazePointedAndWhereItStands(azimuth: Float, elevation: Float) throws {
        let placement = try #require(GazePlacement.placement(forHead: head(at: SIMD3(0.3, 1.5, -0.2), azimuth: degrees(azimuth), elevation: degrees(elevation))))
        // 180° and −180° are one way.
        let across = remainder(placement.gazeAzimuth - degrees(azimuth), 2 * .pi)
        #expect(abs(across) < 1e-4)
        #expect(abs(placement.gazeElevation - degrees(elevation)) < 1e-4)
        #expect(abs(placement.elevation - degrees(elevation - 20)) < 1e-4)
        #expect(abs(placement.belowTheGaze - degrees(20)) < 1e-4)
    }

    /// A head turned to the right looks along +x: the panel stands that
    /// way, and faces back along −x, tilted up.
    @Test func aHeadTurnedToTheRightHasItToTheRight() throws {
        let eye = SIMD3<Float>(0.5, 1.5, -0.5)
        let placement = try #require(GazePlacement.placement(forHead: head(at: eye, azimuth: degrees(90))))
        let below = degrees(20)
        #expect(simd_distance(placement.pose.position, eye + 0.7 * SIMD3(cos(below), -sin(below), 0)) < 1e-5)
        #expect(simd_distance(placement.pose.orientation.act(front), SIMD3(-cos(below), sin(below), 0)) < 1e-5)
        #expect(abs(placement.gazeAzimuth - degrees(90)) < 1e-5)
    }

    /// A head tipped to one side puts it where it would upright: the gaze
    /// points the same way, and the panel stays level.
    @Test(arguments: [Float(-25), -8, 8, 25])
    func tippingTheHeadToASideChangesNothing(roll: Float) throws {
        let eye = SIMD3<Float>(-0.2, 1.62, 0.3)
        let upright = try #require(GazePlacement.placement(forHead: head(at: eye, azimuth: degrees(40), elevation: degrees(-12))))
        let tipped = try #require(GazePlacement.placement(forHead: head(at: eye, azimuth: degrees(40), elevation: degrees(-12), roll: degrees(roll))))
        #expect(simd_distance(tipped.pose.position, upright.pose.position) < 1e-5)
        for axis in [front, right, up] {
            #expect(simd_distance(tipped.pose.orientation.act(axis), upright.pose.orientation.act(axis)) < 1e-5)
        }
    }

    /// A gaze far down puts it no steeper than 60° below the head's level,
    /// rather than under the chin; a gaze far up, no steeper than 60° above.
    /// Within that, it stands 20° below the gaze.
    @Test(arguments: [(Float(-35), Float(-55)), (-40, -60), (-55, -60), (-80, -60), (75, 55), (85, 60), (89, 60)])
    func itStandsNoSteeperThanSixtyDegrees(gazeElevation: Float, standing: Float) throws {
        let eye = SIMD3<Float>(0, 1.6, 0)
        let placement = try #require(GazePlacement.placement(forHead: head(at: eye, azimuth: degrees(30), elevation: degrees(gazeElevation))))
        #expect(abs(placement.elevation - degrees(standing)) < 1e-4)
        #expect(abs(placement.tilt + degrees(standing)) < 1e-4)
        #expect(abs(simd_distance(placement.pose.position, eye) - 0.7) < 1e-5)
        // Still the way the gaze points across.
        #expect(abs(placement.gazeAzimuth - degrees(30)) < 1e-3)
    }

    /// A gaze straight down or up points nowhere across: the panel stands
    /// the way the face is turned, ahead of where the top of the head
    /// points looking down, and behind where it points looking up, 60° from
    /// the head's level.
    @Test(arguments: [(Float(-90), Float(-60)), (90, 60)])
    func aGazeStraightDownOrUpTakesItsWayAcrossFromTheFace(gazeElevation: Float, standing: Float) throws {
        let eye = SIMD3<Float>(0.4, 1.5, -0.2)
        let placement = try #require(GazePlacement.placement(forHead: head(at: eye, azimuth: degrees(-50), elevation: degrees(gazeElevation))))
        #expect(abs(placement.gazeAzimuth - degrees(-50)) < 1e-3)
        #expect(abs(placement.elevation - degrees(standing)) < 1e-4)
        let offset = placement.pose.position - eye
        let expected = 0.7 * SIMD3(cos(degrees(standing)) * sin(degrees(-50)), sin(degrees(standing)), -cos(degrees(standing)) * cos(degrees(-50)))
        #expect(simd_distance(offset, expected) < 1e-4)
    }

    /// A head that isn't a place, or doesn't point anywhere, has nowhere to
    /// put it.
    @Test func aHeadThatIsntAPlaceHasNoPlacement() {
        var nowhere = head(at: SIMD3(0, 1.6, 0))
        nowhere.columns.3 = SIMD4(.nan, 1.6, 0, 1)
        #expect(GazePlacement.placement(forHead: nowhere) == nil)
        var pointless = head(at: SIMD3(0, 1.6, 0))
        pointless.columns.2 = SIMD4(0, 0, 0, 0)
        #expect(GazePlacement.placement(forHead: pointless) == nil)
        var infinite = head(at: SIMD3(0, 1.6, 0))
        infinite.columns.2 = SIMD4(0, .infinity, 1, 0)
        #expect(GazePlacement.placement(forHead: infinite) == nil)
    }

    /// Where world tracking can't say where the head is, as in the
    /// simulator, the head is taken to stand as the simulator's camera does,
    /// 1.6 m up at the space's origin, looking straight ahead, down −z: the
    /// panel 20° below the middle of its view.
    @Test func theUntrackedHeadStandsAsTheSimulatorsCameraDoes() throws {
        let untracked = UntrackedHead.transform
        #expect(simd_distance(position(of: untracked), SIMD3(0, 1.6, 0)) < 1e-6)
        #expect(simd_distance(gaze(of: untracked), SIMD3(0, 0, -1)) < 1e-6)
        #expect(UntrackedHead.eye == SIMD3(0, 1.6, 0))
        let expected = try #require(GazePlacement.placement(forHead: untracked))
        #expect(GazePlacement.forTheUntrackedHead() == expected)
        #expect(abs(GazePlacement.forTheUntrackedHead().elevation + degrees(20)) < 1e-6)
    }

    /// Tuned otherwise, it stands as tuned: a meter out, 30° below the gaze,
    /// no steeper than 45°, and drawn at 1, as an attachment is a meter out.
    @Test func tunedOtherwiseItStandsAsTuned() throws {
        let tuning = PlacementTuning(distance: 1, belowTheGazeDegrees: 30, steepestDegrees: 45)
        #expect(tuning.scale == 1)
        let eye = SIMD3<Float>(0, 1.6, 0)
        let level = try #require(GazePlacement.placement(forHead: head(at: eye), tuning: tuning))
        let below = degrees(30)
        #expect(simd_distance(level.pose.position, eye + SIMD3(0, -sin(below), -cos(below))) < 1e-5)
        #expect(abs(level.distance - 1) < 1e-6)
        #expect(abs(level.belowTheGaze - below) < 1e-6)
        let lookingDown = try #require(GazePlacement.placement(forHead: head(at: eye, elevation: degrees(-30)), tuning: tuning))
        #expect(abs(lookingDown.elevation + degrees(45)) < 1e-5)
        #expect(abs(GazePlacement.forTheUntrackedHead(tuning: tuning).elevation + below) < 1e-6)
        let smaller = PlacementTuning(distance: 0.5, looksAsBigAsAt: 2)
        #expect(smaller.scale == 0.25)
    }
}
