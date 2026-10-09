import simd

/// The head things are placed for and face where world tracking can't say
/// where it is, as in the visionOS simulator, whose device anchor stays on
/// the floor: 1.6 m up at the space's origin, looking straight ahead, down
/// −z, as the simulator's camera stands, so a panel placed below its gaze
/// stands below the middle of the simulator's view. On the headset, as an
/// immersive space opens around the viewer, its origin at their feet and −z
/// the way they face, that's about where their eyes are.
public enum UntrackedHead {
    /// Its transform from the space's origin, as world tracking's device
    /// anchor gives a head's: at its place, its −z the gaze, its +y the top
    /// of the head.
    public static let transform = simd_float4x4(
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(0, 1.6, 0, 1)
    )

    /// Where its eyes are, its transform's place, which a carried thing
    /// faces where world tracking can't say where the head is.
    public static var eye: SIMD3<Float> {
        SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }
}
