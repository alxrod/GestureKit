import simd

/// Where a thing carried by a grab handle stands as the hand carries it, as
/// PhotoFinder's drag carries a picture: its middle where it was as the
/// carry began plus the hand's translation since, converted into the space
/// it stands in, 1:1 (`CarryPinch`), turned about its middle to face the
/// viewer's head where it is now (`Facing`).
///
/// One guard keeps it off the face: its middle never comes nearer the
/// viewer's head than `CarryTuning.nearestToHead`, 0.3 m. A middle carried
/// nearer is pushed out along the line from the head through it, so a thing
/// pulled in toward the eyes stops short of them, rather than coming up
/// against them, or passing through the head and spinning round to face it
/// from behind. From there out, it's exactly where the hand puts it.
public enum HandCarry {
    /// Where a carried thing's middle stands, carried to `point`, with the
    /// viewer's head at `viewer`, both in meters in the space:
    /// `point`, if it's `tuning.nearestToHead` from the head or farther;
    /// else that far out from the head along the line through it, or, for a
    /// point at the head, which is on no line from it, along the line
    /// through `away`, where the middle stood before, or straight ahead,
    /// along −z, should that be at the head too. A point or a head that
    /// isn't a place leaves the middle at `away`.
    public static func middle(
        carriedTo point: SIMD3<Float>,
        clearOf viewer: SIMD3<Float>,
        from away: SIMD3<Float>,
        tuning: CarryTuning = .standard
    ) -> SIMD3<Float> {
        let nearest = tuning.nearestToHead
        let offset = point - viewer
        guard isPlace(point), isPlace(viewer), isPlace(offset) else { return away }
        let distance = simd_length(offset)
        guard distance < nearest else { return point }
        // A point at the head is on no line from it: out through where the
        // middle stood, or straight ahead.
        var direction = offset
        if distance < 1e-6 {
            let before = away - viewer
            direction = isPlace(before) && simd_length(before) >= 1e-6 ? before : SIMD3(0, 0, -1)
        }
        return viewer + nearest * simd_normalize(direction)
    }

    /// Where a thing carried by its middle stands, the hand having put its
    /// middle at `point`, with the viewer's head at `head`: its middle where
    /// `middle(carriedTo:clearOf:from:tuning:)` puts it, `point`, but no
    /// nearer the head than `tuning.nearestToHead`, or `before`, where it
    /// stood, should `point` not be a place; turned to face the head from
    /// there, never rolled, so tilted up as far as it stands below the
    /// head's level; but keeping `current`, the way it faced, with the head
    /// within `facing.verticalTolerance` of straight above or below it
    /// (`Facing.orientation(from:toward:keeping:tuning:)`).
    ///
    /// The pose is the thing's own, its origin at its middle: a panel
    /// carried by a handle beneath it stands so.
    public static func pose(
        carriedTo point: SIMD3<Float>,
        clearOf head: SIMD3<Float>,
        from before: SIMD3<Float>,
        keeping current: simd_quatf,
        tuning: CarryTuning = .standard,
        facing: FacingTuning = .standard
    ) -> Pose {
        let middle = Self.middle(carriedTo: point, clearOf: head, from: before, tuning: tuning)
        return Pose(position: middle, orientation: Facing.orientation(from: middle, toward: head, keeping: current, tuning: facing))
    }

    /// Whether `vector` is a place: none of it infinite, or not a number.
    private static func isPlace(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
