#if os(visionOS)
import GestureCore
import RealityKit
import simd

/// Keeps an entity turned to face the viewer, frame by frame, as the viewer
/// moves (`FacesTheViewerSystem`): its front, +z, toward the head, by yaw
/// and pitch alone, never rolled, exactly as `Facing` turns a thing, and the
/// way it faced kept while the head is straight above or below it.
public struct FacesTheViewerComponent: Component {
    /// The numbers its facing goes by.
    public var tuning: FacingTuning

    /// The point it turns about, in its own frame: its origin, standing on
    /// it, or another point it hangs from, as a row hangs from its middle,
    /// which stays where it is as the entity turns.
    public var pivot: SIMD3<Float>

    public init(tuning: FacingTuning = .standard, pivot: SIMD3<Float> = .zero) {
        self.tuning = tuning
        self.pivot = pivot
    }
}

/// Turns every entity wearing a `FacesTheViewerComponent` to face the
/// viewer's head each frame, about its pivot, in the scene's frame, which in
/// an immersive space is world tracking's.
///
/// It asks `headTracker` where the head is (`HeadTracker.viewerPosition()`):
/// where world tracking has lost the head for a moment, it leaves every
/// entity as it faced.
@MainActor
public struct FacesTheViewerSystem: System {
    /// The tracker it asks where the head is: the shared one unless the app
    /// says otherwise.
    public static var headTracker: HeadTracker = .shared

    private static let query = EntityQuery(where: .has(FacesTheViewerComponent.self))

    /// Registers the component and the system, as an app does once, before
    /// anything uses them.
    public static func registerComponentsAndSystem() {
        FacesTheViewerComponent.registerComponent()
        registerSystem()
    }

    public init(scene: Scene) {}

    public func update(context: SceneUpdateContext) {
        // The head is asked for once a frame, and only with something to
        // turn.
        var viewer: SIMD3<Float>??
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard let facing = entity.components[FacesTheViewerComponent.self] else { continue }
            if viewer == nil { viewer = .some(Self.headTracker.viewerPosition()) }
            guard let head = viewer ?? nil else { return }
            Self.turn(entity, toFace: head, as: facing)
        }
    }

    /// Turns `entity` about its pivot to face `viewer`, in the scene's frame,
    /// keeping the way it faced where the viewer is straight above or below
    /// the pivot.
    public static func turn(_ entity: Entity, toFace viewer: SIMD3<Float>, as facing: FacesTheViewerComponent) {
        let pivot = entity.convert(position: facing.pivot, to: nil)
        let current = entity.orientation(relativeTo: nil)
        let orientation = Facing.orientation(from: pivot, toward: viewer, keeping: current, tuning: facing.tuning)
        guard abs(simd_dot(orientation.vector, current.vector)) < 1 - 1e-7 else { return }
        entity.setOrientation(orientation, relativeTo: nil)
        if facing.pivot != .zero {
            // The pivot stays where it was.
            let moved = entity.convert(position: facing.pivot, to: nil)
            entity.setPosition(entity.position(relativeTo: nil) + pivot - moved, relativeTo: nil)
        }
    }
}
#endif
