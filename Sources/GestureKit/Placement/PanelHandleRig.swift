#if os(visionOS)
import GestureCore
import RealityKit
import SwiftUI

/// The handle under a panel that stands in the space with no window bar of
/// its own, as an attachment does: a node just under the panel's bottom
/// edge, however tall the panel lays out, where the handle's pill stands
/// (`PanelHandle`, `PanelHandlePill`), and a grab handle in front of the
/// pill taking its looks and pinches (`GrabHandle`), so a drag of it carries
/// the panel by its middle (`GrabHandleCarry`, `CarriedEntity`).
///
/// It hangs on the panel's entity, whose origin is the panel's middle, so
/// it moves, turns, and hides with the panel, and is drawn at the panel's
/// scale. Its sizes are in points, as the panel's attachment is drawn,
/// `metersPerPoint` to the meter in the panel's own frame: 1/1360 for a
/// panel whose attachment hangs at the panel's scale, as visionOS draws an
/// attachment 1360 pt to the meter.
@MainActor
public final class PanelHandleRig {
    /// How many meters a point is in an attachment drawn at its entity's
    /// scale: visionOS draws 1360 pt to the meter.
    public static let attachmentMetersPerPoint: Float = 1.0 / 1360

    /// The node under the panel's middle where the pill stands: hang the
    /// pill's attachment on it (`hang(pill:)`).
    public let node: Entity

    /// The grab handle in front of the pill.
    public let handle: ModelEntity

    /// The numbers its pill and reach go by.
    public private(set) var tuning: PlacementTuning

    /// How many meters a point of the panel is, in the panel's own frame.
    public let metersPerPoint: Float

    /// How tall the panel lays out, in points, as it last said.
    public private(set) var panelHeight: Double

    /// A handle under `panel`, carrying what `carriedID` names, marked with
    /// a `GrabHandleComponent`, for a panel `panelHeight` points tall until
    /// it says otherwise (`panelResized(toHeight:)`).
    public convenience init(
        under panel: Entity,
        carrying carriedID: String,
        tuning: PlacementTuning = .standard,
        panelHeight: Double = 0,
        metersPerPoint: Float = PanelHandleRig.attachmentMetersPerPoint
    ) {
        self.init(under: panel, marking: GrabHandleComponent(carriedID: carriedID), tuning: tuning, panelHeight: panelHeight, metersPerPoint: metersPerPoint)
    }

    /// A handle under `panel` marked by `marker`, which the drag that takes
    /// its pinches queries for.
    public init(
        under panel: Entity,
        marking marker: some Component,
        tuning: PlacementTuning = .standard,
        panelHeight: Double = 0,
        metersPerPoint: Float = PanelHandleRig.attachmentMetersPerPoint
    ) {
        self.tuning = tuning
        self.metersPerPoint = metersPerPoint
        self.panelHeight = panelHeight
        node = Entity()
        node.name = panel.name.isEmpty ? "panel-handle" : "\(panel.name)-handle"
        panel.addChild(node)
        handle = GrabHandle.make(named: "handle of \(panel.name.isEmpty ? "a panel" : panel.name)", size: SIMD2(1, 1), marking: marker)
        node.addChild(handle)
        shape()
    }

    /// Hangs `attachment`, the pill's, on the node: its middle on the node's
    /// origin, facing as the panel faces, behind the grab handle.
    public func hang(pill attachment: Entity) {
        if attachment.parent !== node {
            node.addChild(attachment)
        }
        attachment.transform = .identity
    }

    /// The panel laid out `height` points tall: the pill stands just under
    /// its bottom edge.
    public func panelResized(toHeight height: Double) {
        guard height != panelHeight else { return }
        panelHeight = height
        shape()
    }

    /// The handle's numbers changed, as a lab's tuning does live: the pill's
    /// place and the handle's size and reach follow.
    public func retune(_ tuning: PlacementTuning) {
        guard tuning != self.tuning else { return }
        self.tuning = tuning
        shape()
    }

    /// Stands the node under the panel's bottom edge, and sizes the grab
    /// handle to the pill and its reach.
    private func shape() {
        let below = Float(PanelHandle.middle(belowPanelOfHeight: panelHeight, tuning: tuning)) * metersPerPoint
        node.position = SIMD3(0, below, 0)
        let size = SIMD2<Float>(tuning.handleSize) * metersPerPoint
        let reach = SIMD2<Float>(PanelHandle.reach(tuning: tuning)) * metersPerPoint
        let offset = SIMD2(0, Float(PanelHandle.reachOffset(tuning: tuning)) * metersPerPoint)
        let wasEnabled = handle.isEnabled
        GrabHandle.reshape(handle, size: size, reach: reach, reachOffset: offset)
        handle.isEnabled = wasEnabled && handle.isEnabled
    }
}

/// The pill a panel's handle draws, as visionOS's window bar is: a glass
/// capsule, `PlacementTuning.handleSize`, which only draws, the grab handle
/// in front of it taking its looks and pinches (`PanelHandleRig`). VoiceOver
/// reads it as `label`, and its default action, given, does what
/// `onActivate` says, as bringing the panel back below the gaze.
public struct PanelHandlePill: View {
    private let tuning: PlacementTuning
    private let label: String
    private let hint: String?
    private let onActivate: (@MainActor () -> Void)?

    public init(
        tuning: PlacementTuning = .standard,
        label: String = "Move",
        hint: String? = "Drag to move it.",
        onActivate: (@MainActor () -> Void)? = nil
    ) {
        self.tuning = tuning
        self.label = label
        self.hint = hint
        self.onActivate = onActivate
    }

    public var body: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: tuning.handleWidth, height: tuning.handleHeight)
            .glassBackgroundEffect(in: Capsule())
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAction {
                onActivate?()
            }
    }
}
#endif
