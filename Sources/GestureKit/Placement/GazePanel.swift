#if os(visionOS)
import Foundation
import GestureCore
import os
import RealityKit

private let gazePanelLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "GazePanel")

/// A panel stood below the viewer's gaze: in front of the head,
/// `PlacementTuning.distance` out, slightly below where it looks, straight
/// down from the gaze, tilted up to face the head and never rolled, drawn
/// at `PlacementTuning.scale` so it looks as big as it would a meter out
/// (`GazePlacement`). It's stood once, from the head as it is then, and
/// stays there as the head moves, until it's carried by its handle
/// (`PanelHandleRig`, `GrabHandleCarry`) or stood again.
///
/// The panel is any entity: its origin is its middle, its front +z, and an
/// attachment hung on it at its origin draws at its scale.
@MainActor
public enum GazePanel {
    /// How long `standBelowTheGaze(_:tracker:tuning:scales:recorder:quietly:waitingAtMost:because:)`
    /// waits for world tracking to say where the head is, as while a space
    /// that's just opened starts tracking, before it stands the panel for
    /// the untracked head.
    public static let headPatience: Duration = .seconds(1.5)

    /// Stands `panel` below the gaze of the head with the transform `head`,
    /// in the scene's frame, or of the untracked head (`UntrackedHead`) for
    /// nil, and gives where it stood it and why. With `scales`, it draws the
    /// panel at `tuning.scale`; otherwise its scale stays as it was. A
    /// recorder, given and recording, traces the placement, its summary the
    /// console's line; otherwise it's logged at info level. `quietly`, it's
    /// traced not at all and logged only at debug level, as for a panel
    /// stood again at each step of a slider.
    @discardableResult
    public static func stand(
        _ panel: Entity,
        forHead head: simd_float4x4?,
        tuning: PlacementTuning = .standard,
        scales: Bool = true,
        recorder: TraceRecorder? = nil,
        quietly: Bool = false,
        because reason: String = "it was asked to"
    ) -> GazePlacement.Placement {
        let tracked = head.flatMap { GazePlacement.placement(forHead: $0, tuning: tuning) }
        let placement = tracked ?? GazePlacement.forTheUntrackedHead(tuning: tuning)
        panel.setPosition(placement.pose.position, relativeTo: nil)
        panel.setOrientation(placement.pose.orientation, relativeTo: nil)
        if scales {
            panel.setScale(SIMD3(repeating: tuning.scale), relativeTo: nil)
        }
        let drawnAt = scales ? tuning.scale : panel.scale(relativeTo: nil).x
        /// Where it stood, in words, made only for a line that's kept.
        func stood() -> String {
            let whose = tracked == nil ? "the untracked head, 1.6 m up at the origin looking down -z" : "the head"
            return String(
                format: "%.2f m from %@, %.1f° below its gaze, which points %.1f° across and %.1f° up; tilted up %.1f° to face it, its middle at (%.2f, %.2f, %.2f) m, drawn at %.2f",
                placement.distance, whose, degrees(placement.belowTheGaze), degrees(placement.gazeAzimuth),
                degrees(placement.gazeElevation), degrees(placement.tilt),
                placement.pose.position.x, placement.pose.position.y, placement.pose.position.z,
                drawnAt
            )
        }
        if quietly {
            gazePanelLogger.debug("A panel stands \(stood(), privacy: .public), as \(reason)")
        } else if let trace = recorder?.begin("Placement", title: "Below the gaze") {
            trace.event("asked", reason)
            trace.event("head", tracked == nil
                ? "untracked: the stand-in, 1.6 m up at the origin"
                : String(format: "gaze %.1f° across, %.1f° up", degrees(placement.gazeAzimuth), degrees(placement.gazeElevation)))
            trace.event("stood", stood())
            trace.finish(String(format: "%.2f m out, %.1f° below the gaze", placement.distance, degrees(placement.belowTheGaze)))
        } else {
            gazePanelLogger.info("A panel stands \(stood(), privacy: .public), as \(reason)")
        }
        return placement
    }

    /// Stands `panel` below the gaze as the head is once world tracking says
    /// where it is, waiting up to `patience` for it, as while a space that's
    /// just opened starts tracking, and for the untracked head should it not
    /// say by then, as in the simulator; as `stand(_:forHead:tuning:scales:recorder:quietly:because:)`
    /// stands it, `quietly` or not. Stands nothing should the task be
    /// cancelled meanwhile.
    @discardableResult
    public static func standBelowTheGaze(
        _ panel: Entity,
        tracker: HeadTracker = .shared,
        tuning: PlacementTuning = .standard,
        scales: Bool = true,
        recorder: TraceRecorder? = nil,
        quietly: Bool = false,
        waitingAtMost patience: Duration = headPatience,
        because reason: String = "it was asked to"
    ) async -> GazePlacement.Placement? {
        let head = await tracker.headTransform(waitingAtMost: patience)
        guard !Task.isCancelled else { return nil }
        return stand(panel, forHead: head, tuning: tuning, scales: scales, recorder: recorder, quietly: quietly, because: reason)
    }

    private static func degrees(_ radians: Float) -> Float {
        radians * 180 / .pi
    }
}
#endif
