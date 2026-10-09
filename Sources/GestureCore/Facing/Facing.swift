import simd

/// How a thing in the space turns to face the viewer, exactly as
/// PhotoFinder's facing turns a picture (`rotationToFaceDevice`), which its
/// tests hold it to: its front, +z, points at the viewer, turned by yaw and
/// pitch alone, never rolled, so its sides stay level and its top stays up.
/// Where PhotoFinder's has no number, with the viewer straight above or below
/// the thing, it says what to do instead.
public enum Facing {
    /// The orientation that turns a thing at `position` to face `target`:
    /// its front, +z, points at the target. It turns only by yaw (about +y)
    /// and pitch (about the thing's own +x), never by roll, so the thing's
    /// sides stay level and its top stays up.
    ///
    /// A target straight above or below pitches the thing without turning
    /// it. A target at the thing, or a non-finite one, leaves it unturned:
    /// the identity.
    public static func orientation(from position: SIMD3<Float>, toward target: SIMD3<Float>) -> simd_quatf {
        let offset = target - position
        let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        guard offset.x.isFinite, offset.y.isFinite, offset.z.isFinite, length(offset) > 0 else { return identity }
        let horizontal = (offset.x * offset.x + offset.z * offset.z).squareRoot()
        // atan2(0, 0) is 0, so a target straight up or down leaves the yaw at 0.
        let yaw = atan2(offset.x, offset.z)
        let pitch = atan2(offset.y, horizontal)
        // Pitch first, about +x (a negative angle lifts +z toward +y), then
        // yaw about +y.
        let turn = simd_quatf(angle: yaw, axis: SIMD3(0, 1, 0))
        let tilt = simd_quatf(angle: -pitch, axis: SIMD3(1, 0, 0))
        return simd_normalize(turn * tilt)
    }

    /// The orientation that turns a thing at `position` to face `target`, as
    /// `orientation(from:toward:)` does, but `current`, the way it faces
    /// now, where the target is within `tuning.verticalTolerance` of
    /// straight above or below it, or at it, or isn't a place: there, which
    /// way across it should turn has no meaning, and PhotoFinder's facing,
    /// which lays the line to the target level and normalizes it, has no
    /// number. So a thing carried over or under the viewer's head keeps the
    /// way it faced, rather than swinging round to face +z for a moment. A
    /// `current` with no length to turn by, or that isn't a number, is the
    /// identity.
    public static func orientation(
        from position: SIMD3<Float>,
        toward target: SIMD3<Float>,
        keeping current: simd_quatf,
        tuning: FacingTuning = .standard
    ) -> simd_quatf {
        let offset = target - position
        let level = (offset.x * offset.x + offset.z * offset.z).squareRoot()
        guard level.isFinite, offset.y.isFinite, level > tuning.verticalTolerance else {
            let v = current.vector
            let size = simd_length(v)
            guard size.isFinite, size > 0 else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
            return simd_quatf(vector: v / size)
        }
        return orientation(from: position, toward: target)
    }
}
