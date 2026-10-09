import simd

/// Where a thing stands in the space and which way it's turned: its
/// position and orientation relative to the space's origin, in meters, with
/// its front +z.
public struct Pose: Equatable, Sendable {
    /// Meters from the space's origin.
    public var position: SIMD3<Float>
    /// Of unit length, as every initializer leaves it.
    public var orientation: simd_quatf

    /// A pose at `position`, turned by `orientation` brought to unit length,
    /// or the identity should it have no length to scale, or not be a number.
    public init(position: SIMD3<Float>, orientation: simd_quatf) {
        self.position = position
        self.orientation = Self.normalized(orientation)
    }

    /// A pose standing at `position`, turned to face `target` (`Facing`).
    public init(at position: SIMD3<Float>, facing target: SIMD3<Float>) {
        self.init(position: position, orientation: Facing.orientation(from: position, toward: target))
    }

    /// The pose a saved placement describes, read safely: `savedPosition`,
    /// x, y, and z in meters, and `savedOrientation`, a quaternion as x, y,
    /// z, and w. Nil if the position isn't three finite numbers. The
    /// orientation is normalized, since nothing checks a saved one's length;
    /// one of zero or non-finite length, or that isn't four numbers, is the
    /// identity.
    public init?(savedPosition: [Float], savedOrientation: [Float]) {
        let p = savedPosition, q = savedOrientation
        guard p.count == 3, p.allSatisfy(\.isFinite) else { return nil }
        let orientation = q.count == 4 ? simd_quatf(ix: q[0], iy: q[1], iz: q[2], r: q[3]) : Self.identity
        self.init(position: SIMD3(p[0], p[1], p[2]), orientation: orientation)
    }

    /// The position as a placement saves it: x, y, and z in meters.
    public var savedPosition: [Float] {
        [position.x, position.y, position.z]
    }

    /// The orientation as a placement saves it: x, y, z, and w.
    public var savedOrientation: [Float] {
        let v = orientation.vector
        return [v.x, v.y, v.z, v.w]
    }

    private static let identity = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)

    /// `q` at unit length, or the identity if it has none to scale.
    private static func normalized(_ q: simd_quatf) -> simd_quatf {
        let v = SIMD4<Double>(q.vector)
        guard v.x.isFinite, v.y.isFinite, v.z.isFinite, v.w.isFinite else { return identity }
        // In Double, so a tiny but nonzero quaternion still scales to unit
        // length rather than underflowing.
        let size = (v * v).sum().squareRoot()
        guard size.isFinite, size > 0 else { return identity }
        return simd_quatf(vector: SIMD4<Float>(v / size))
    }
}

extension Pose {
    /// The pose of a thing that hangs from `pivot`, a point of it in its own
    /// frame, at `point` in the space, facing `target` from there: turned as
    /// something at `point` turns to face the target
    /// (`Facing.orientation(from:toward:)`), and placed at `point` less
    /// `pivot` turned, so the pivot lands exactly on `point`, and the thing
    /// turns about it.
    ///
    /// A carry hangs a thing from its middle, where the hand carries it,
    /// 1:1 (`CarryPinch`); so a thing standing still, hung from its middle at
    /// its place, starts a carry with no turn.
    public init(hanging pivot: SIMD3<Float>, at point: SIMD3<Float>, facing target: SIMD3<Float>) {
        let orientation = Facing.orientation(from: point, toward: target)
        self.init(position: point - orientation.act(pivot), orientation: orientation)
    }
}
