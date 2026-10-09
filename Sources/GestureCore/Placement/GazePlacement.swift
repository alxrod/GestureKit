import simd

/// Where a panel stands as it opens: in front of the viewer's head,
/// slightly below where they look and angled up to them. Not where some
/// window happened to be, but `tuning.distance` out from the head,
/// `tuning.angleBelowTheGaze` below where it looks, straight down from the
/// gaze, and turned to face the head (`Facing`): tilted up to it as far as
/// the panel stands below its level, and never rolled. It's placed once, from
/// the head as it is then, and stays there as the head moves, until the
/// viewer carries it by its handle (`PanelHandle`, `HandCarry`) or it's
/// placed again.
///
/// In meters in the space, y up and −z straight ahead as the space opens,
/// with the head's transform as world tracking's device anchor gives it,
/// from the space's origin: its −z the way the face points, the gaze, and
/// its +y the way the top of the head points.
public enum GazePlacement {
    /// Where the panel stands, and the angles that put it there, for the log.
    public struct Placement: Equatable, Sendable {
        /// Where the panel's middle stands, and which way it faces: its
        /// front, +z, toward the head.
        public let pose: Pose
        /// How far the middle stands from the head, in meters.
        public let distance: Float
        /// Which way across the gaze points, in radians: 0 straight ahead,
        /// along −z, growing to the right, toward +x, as
        /// `ViewerCenteredFrame.azimuth` counts it.
        public let gazeAzimuth: Float
        /// How far up from level the gaze points, in radians, down for less
        /// than 0.
        public let gazeElevation: Float
        /// How far up from the head's level the middle stands, in radians,
        /// down for less than 0: the gaze's elevation less the angle below
        /// the gaze, held within the steepest.
        public let elevation: Float

        public init(pose: Pose, distance: Float, gazeAzimuth: Float, gazeElevation: Float, elevation: Float) {
            self.pose = pose
            self.distance = distance
            self.gazeAzimuth = gazeAzimuth
            self.gazeElevation = gazeElevation
            self.elevation = elevation
        }

        /// How far below the gaze the middle stands, in radians: the angle
        /// below the gaze, unless the steepest held it.
        public var belowTheGaze: Float { gazeElevation - elevation }

        /// How far the panel leans back from upright to face the head, in
        /// radians, up for more than 0: as far as it stands below its level.
        public var tilt: Float { -elevation }
    }

    /// Where the panel stands for a head with the transform `head`. Its
    /// gaze's way across is where it points laid level, or, within about 6°
    /// of straight down or up (`tuning.leastLevelGaze`), the way the top of
    /// the head points, ahead of the face looking down, and the other way
    /// looking up; so a head tipped to one side puts it where it would
    /// upright. Nil for a head that isn't a place, or doesn't point
    /// anywhere.
    public static func placement(forHead head: simd_float4x4, tuning: PlacementTuning = .standard) -> Placement? {
        let eye = SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
        let back = SIMD3(head.columns.2.x, head.columns.2.y, head.columns.2.z)
        let top = SIMD3(head.columns.1.x, head.columns.1.y, head.columns.1.z)
        guard isPlace(eye), isPlace(back), isPlace(top), simd_length(back) > 1e-6 else { return nil }
        let gaze = -simd_normalize(back)
        var across = SIMD3(gaze.x, 0, gaze.z)
        if simd_length(across) < tuning.leastLevelGaze {
            // The top of the head points ahead of the face looking down, and
            // behind it looking up.
            across = SIMD3(top.x, 0, top.z) * (gaze.y < 0 ? 1 : -1)
        }
        guard simd_length(across) > 1e-6 else { return nil }
        across = simd_normalize(across)
        let gazeElevation = asin(min(max(gaze.y, -1), 1))
        return place(from: eye, lookingAcross: across, gazeElevation: gazeElevation, tuning: tuning)
    }

    /// Where the panel stands for the head world tracking can't place
    /// (`UntrackedHead`).
    public static func forTheUntrackedHead(tuning: PlacementTuning = .standard) -> Placement {
        placement(forHead: UntrackedHead.transform, tuning: tuning)
            ?? place(from: SIMD3(0, 1.6, 0), lookingAcross: SIMD3(0, 0, -1), gazeElevation: 0, tuning: tuning)
    }

    /// Where the panel stands for a head at `eye`, its gaze pointing the
    /// level way `across`, of unit length, `gazeElevation` up from level.
    private static func place(from eye: SIMD3<Float>, lookingAcross across: SIMD3<Float>, gazeElevation: Float, tuning: PlacementTuning) -> Placement {
        let steepest = tuning.steepest
        let elevation = min(max(gazeElevation - tuning.angleBelowTheGaze, -steepest), steepest)
        let out = cos(elevation) * across + SIMD3(0, sin(elevation), 0)
        let middle = eye + tuning.distance * out
        return Placement(
            pose: Pose(position: middle, orientation: Facing.orientation(from: middle, toward: eye)),
            distance: tuning.distance,
            gazeAzimuth: atan2(across.x, -across.z),
            gazeElevation: gazeElevation,
            elevation: elevation
        )
    }

    /// Whether `vector` is a place: none of it infinite, or not a number.
    private static func isPlace(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
