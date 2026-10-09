#if os(visionOS)
import Foundation
import GestureCore
import RealityKit
import simd

/// An entity carried by a grab handle, stood where the hand puts it, for an
/// app that lets the carry move the entity itself, as GestureLab does,
/// rather than route each step through its own state: its middle, its
/// origin, where the hand carries it, 1:1, never nearer the viewer's head
/// than `CarryTuning.nearestToHead`, turned to face the head, never rolled,
/// keeping the way it faced with the head straight above or below it
/// (`HandCarry.pose(carriedTo:clearOf:from:keeping:tuning:facing:)`). Its
/// scale stays as it was.
@MainActor
public enum CarriedEntity {
    /// Where `entity` stands now: its middle, its origin, in its parent's
    /// frame, the frame a carry of it is measured in, named `id`, for a
    /// carry to begin from.
    public static func grabbed<ID: Equatable & Sendable>(_ entity: Entity, as id: ID) -> CarryPinch<ID>.Grabbed {
        CarryPinch<ID>.Grabbed(id: id, middle: entity.position)
    }

    /// The entity a GestureKit grab handle carries: the handle's nearest
    /// ancestor named as its `GrabHandleComponent` says; nil for a handle
    /// with no such component, or none of that name above it.
    public static func carried(byHandle handle: Entity) -> Entity? {
        guard let name = handle.components[GrabHandleComponent.self]?.carriedID else { return nil }
        var ancestor = handle.parent
        while let candidate = ancestor {
            if candidate.name == name { return candidate }
            ancestor = candidate.parent
        }
        return nil
    }

    /// Stands `entity` carried by its middle to `middle`, in its parent's
    /// frame, facing the viewer's head at `head`, in the scene's frame, and
    /// gives the pose it stands at, in its parent's frame. With no head, as
    /// while world tracking has lost it for a moment, its middle goes where
    /// the hand puts it and it keeps the way it faced. A parent turned from
    /// the scene's own up turns "level" with it.
    @discardableResult
    public static func stand(
        _ entity: Entity,
        carriedTo middle: SIMD3<Float>,
        facingHeadAt head: SIMD3<Float>?,
        tuning: CarryTuning = .standard,
        facing: FacingTuning = .standard
    ) -> Pose {
        guard let head else {
            let pose = Pose(position: middle, orientation: entity.orientation)
            entity.position = pose.position
            return pose
        }
        let headInParent = entity.parent?.convert(position: head, from: nil) ?? head
        let pose = HandCarry.pose(
            carriedTo: middle, clearOf: headInParent, from: entity.position, keeping: entity.orientation,
            tuning: tuning, facing: facing
        )
        entity.position = pose.position
        entity.orientation = pose.orientation
        return pose
    }

    /// Where `entity` stands about the viewer's head at `head`, in the
    /// scene's frame, for a trace or a log: "(0.12, 1.20, -0.85) m, 0.62 m
    /// from the head, 18.0° below its level".
    public static func describe(_ entity: Entity, aboutHeadAt head: SIMD3<Float>?) -> String {
        let middle = entity.position(relativeTo: nil)
        var text = carryPlaceText(middle)
        guard let head else { return text }
        let out = middle - head
        let distance = simd_length(out)
        let below = distance > 0 ? asin(min(max(-out.y / distance, -1), 1)) * 180 / .pi : 0
        text += String(format: ", %.2f m from the head, %.1f° %@ its level", distance, abs(below), below >= 0 ? "below" : "above")
        return text
    }
}

/// A point as a trace or a log gives it, in meters: "(0.12, 1.20, -0.85) m".
func carryPlaceText(_ point: SIMD3<Float>) -> String {
    String(format: "(%.2f, %.2f, %.2f) m", point.x, point.y, point.z)
}
#endif
