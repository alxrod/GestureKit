#if os(visionOS)
import GestureCore
import RealityKit
import UIKit

/// Marks a grab handle (`GrabHandle`), naming the thing it carries: the
/// component a carry's drag (`GrabHandleCarry`) can take its pinches by.
/// An app with several kinds of handle, each carried its own way, marks each
/// kind with a component of its own instead, and gives each its own drag.
public struct GrabHandleComponent: Component {
    /// What the handle carries, as the app names it.
    public var carriedID: String

    public init(carriedID: String) {
        self.carriedID = carriedID
    }
}

/// A grab handle: a RealityKit entity that takes the looks and pinches of a
/// grabber an app draws, a pill under a panel, a capsule under a row of
/// items, or a whole surface, so an entity-targeted drag on it carries the
/// thing it's under as PhotoFinder's drag carries a picture
/// (`GrabHandleCarry`). Four drags were tried side by side on the headset,
/// and this, an entity-targeted drag on an entity, was the only one that
/// followed the hand; a SwiftUI drag on an attachment in an immersive space
/// didn't.
///
/// It draws nothing at rest and hides nothing behind it: a plane in the
/// grabber's shape, clear, writing no depth, whose highlight hover effect
/// glows over the grabber where it's looked at. A RealityKit hover effect
/// can't join a SwiftUI hover group, so the glow is the handle's own. It
/// takes looks and pinches over its reach, a box that may be bigger than
/// the shape and stand off its middle, and stands `lift` in front of where
/// it's hung, toward the viewer, so nothing of the grabber's attachment
/// comes between it and the hand.
@MainActor
public enum GrabHandle {
    /// How far in front of where it's hung a handle stands, toward the
    /// viewer, in meters: 4 mm, in front of the grabber's attachment.
    public static let lift: Float = 0.004

    /// How deep a handle takes looks and pinches, in meters, about where it
    /// stands.
    public static let reachDepth: Float = 0.006

    /// Registers the component that marks GestureKit's grab handles, which
    /// an entity-targeted drag's query asks for before anything uses it.
    public static func registerComponents() {
        GrabHandleComponent.registerComponent()
    }

    /// A new handle carrying the thing `carriedID` names, marked with a
    /// `GrabHandleComponent`, as `make(named:size:reach:reachOffset:cornerRadius:marking:)`
    /// makes one.
    public static func make(
        carrying carriedID: String,
        size: SIMD2<Float>,
        reach: SIMD2<Float>? = nil,
        reachOffset: SIMD2<Float> = .zero
    ) -> ModelEntity {
        make(named: "grab-handle", size: size, reach: reach, reachOffset: reachOffset, marking: GrabHandleComponent(carriedID: carriedID))
    }

    /// A new handle named `name` and marked by `marker`, which the drag that
    /// takes its pinches queries for: its glow `size` wide and tall, in
    /// meters, rounded at its ends unless `cornerRadius` says otherwise,
    /// taking looks and pinches over `reach`, or its size, with the reach's
    /// middle `reachOffset` from the glow's; standing `lift` in front of
    /// its parent's origin.
    public static func make(
        named name: String,
        size: SIMD2<Float>,
        reach: SIMD2<Float>? = nil,
        reachOffset: SIMD2<Float> = .zero,
        cornerRadius: Float? = nil,
        marking marker: some Component
    ) -> ModelEntity {
        let handle = ModelEntity()
        handle.name = name
        handle.components.set(marker)
        handle.components.set(InputTargetComponent())
        handle.components.set(HoverEffectComponent(.highlight(.init(color: .white, strength: 1, opacityFunction: .full))))
        handle.position = SIMD3(0, 0, lift)
        reshape(handle, size: size, reach: reach, reachOffset: reachOffset, cornerRadius: cornerRadius)
        return handle
    }

    /// Shapes `handle` afresh, as a grabber's size changes, or a handle
    /// covering part of a surface covers another part: its glow `size`, its
    /// reach `reach`, or its size, `reachOffset` from the glow's middle, and
    /// turns it on. A size with no area turns it off, hidden and taking no
    /// looks or pinches, until it's shaped with one.
    public static func reshape(
        _ handle: ModelEntity,
        size: SIMD2<Float>,
        reach: SIMD2<Float>? = nil,
        reachOffset: SIMD2<Float> = .zero,
        cornerRadius: Float? = nil
    ) {
        guard size.x > 0, size.y > 0, size.x.isFinite, size.y.isFinite else {
            handle.isEnabled = false
            return
        }
        let reach = reach ?? size
        let corner = min(cornerRadius ?? size.y / 2, size.x / 2, size.y / 2)
        // Clear, and writing no depth, so it hides nothing: the hover
        // effect's glow draws in full however clear the material is.
        var material = UnlitMaterial(color: .white)
        material.blending = .transparent(opacity: .init(floatLiteral: 0))
        material.writesDepth = false
        handle.model = ModelComponent(mesh: .generatePlane(width: size.x, height: size.y, cornerRadius: corner), materials: [material])
        let box = ShapeResource.generateBox(width: max(reach.x, 0.001), height: max(reach.y, 0.001), depth: reachDepth)
            .offsetBy(translation: SIMD3(reachOffset.x, reachOffset.y, 0))
        handle.components.set(CollisionComponent(shapes: [box]))
        handle.isEnabled = true
    }
}
#endif
