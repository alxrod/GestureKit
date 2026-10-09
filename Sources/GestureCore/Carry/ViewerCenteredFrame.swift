import Foundation
import simd

/// Where a point a hand carries stands about the viewer's head as the carry
/// begins, and the hand's translation since, taken apart in that frame, for
/// a carry's logs and traces: how far out from the head the point was, r0,
/// which way across, α0, and how far up, β0; and how far the hand then
/// moved out from the head, across, and up, so a sweep that brought the
/// point nearer, or took it farther, shows by its part out from the head.
/// A carry by a grab handle carries its thing's middle so, 1:1 with the
/// hand, in a straight line (`CarryPinch`, `HandCarry`). In meters in the
/// space, with y up and −z straight ahead.
///
/// With H the head as the carry began, and C0 the carried point then:
/// - o0 = C0 − H, r0 = |o0|, α0 = atan2(o0.x, −o0.z), β0 = asin(o0.y / r0);
/// - out from the head, û = (cos β0 sin α0, sin β0, −cos β0 cos α0);
/// - across, to the viewer's right as they faced the point, level,
///   êα = (cos α0, 0, sin α0);
/// - up along the sphere about the head, êβ = (−sin β0 sin α0, cos β0,
///   sin β0 cos α0).
///
/// A carry that swept its thing around the head along that sphere, a meter
/// across turning it a meter's worth of arc, was tried and given up for the
/// straight carry; this is what's left of it: its frame, which tells how a
/// hand moved about the head.
public struct ViewerCenteredFrame: Equatable, Sendable {
    /// A hand's translation taken apart in the frame, in meters.
    public struct Parts: Equatable, Sendable {
        /// Along `radial`: out from the head through the carried point, for
        /// more than 0; toward the head for less.
        public var outward: Double
        /// Along `across`: to the viewer's right, as they faced it, for
        /// more than 0.
        public var across: Double
        /// Along `upward`: up, along the sphere, for more than 0.
        public var up: Double

        public init(outward: Double, across: Double, up: Double) {
            self.outward = outward
            self.across = across
            self.up = up
        }
    }

    /// Where the head was as the carry began.
    public let head: SIMD3<Double>
    /// How far the carried point was from the head as the carry began, r0.
    public let radius: Double
    /// Which way across the carried point was from the head as the carry
    /// began, α0, in radians: 0 straight ahead, along −z, growing to the
    /// right, to π/2 along +x, and to ±π straight behind.
    public let azimuth: Double
    /// How far up from the head's level the carried point was as the carry
    /// began, β0, in radians, down for less than 0.
    public let elevation: Double

    /// The frame of a carry of a point at `point`, about the head at `head`,
    /// both in meters in the space, as it begins. A point at the head has
    /// no bearing: it's taken as straight ahead. Nil if either isn't a
    /// place.
    public init?(from point: SIMD3<Float>, around head: SIMD3<Float>) {
        let head = SIMD3<Double>(head)
        let offset = SIMD3<Double>(point) - head
        guard Self.isPlace(head), Self.isPlace(offset) else { return nil }
        let distance = simd_length(offset)
        self.head = head
        radius = distance
        guard distance > 1e-6 else {
            azimuth = 0
            elevation = 0
            return
        }
        // Straight ahead, 0, for a point straight up or down, which has no
        // way across, and whose −0 ahead atan2 would read as straight behind.
        azimuth = offset.x * offset.x + offset.z * offset.z > 1e-12 ? atan2(offset.x, -offset.z) : 0
        elevation = asin(min(max(offset.y / distance, -1), 1))
    }

    /// The direction out from the head through the carried point as the
    /// carry began, û: a unit vector.
    public var radial: SIMD3<Double> {
        SIMD3(cos(elevation) * sin(azimuth), sin(elevation), -cos(elevation) * cos(azimuth))
    }

    /// The direction across, êα: level, to the viewer's right as they faced
    /// the carried point as the carry began. A unit vector.
    public var across: SIMD3<Double> {
        SIMD3(cos(azimuth), 0, sin(azimuth))
    }

    /// The direction up along the sphere about the head, êβ, at the carried
    /// point as the carry began: square to `radial` and `across`. A unit
    /// vector.
    public var upward: SIMD3<Double> {
        SIMD3(-sin(elevation) * sin(azimuth), cos(elevation), sin(elevation) * cos(azimuth))
    }

    /// `translation`, a hand's since the carry began, in meters in the
    /// space, taken apart along `radial`, `across`, and `upward`. A
    /// translation that isn't one has no parts: all 0.
    public func parts(of translation: SIMD3<Float>) -> Parts {
        let hand = SIMD3<Double>(translation)
        guard Self.isPlace(hand) else { return Parts(outward: 0, across: 0, up: 0) }
        return Parts(outward: simd_dot(hand, radial), across: simd_dot(hand, across), up: simd_dot(hand, upward))
    }

    /// Whether `vector` is a place: none of it infinite, or not a number.
    private static func isPlace(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
