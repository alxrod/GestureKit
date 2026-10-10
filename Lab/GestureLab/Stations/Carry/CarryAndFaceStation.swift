import GestureKit
import RealityKit
import SwiftUI

/// The station for carrying and facing: three panels in the space, each
/// carried by the pill under it, 1:1 with the hand, never nearer the head
/// than the carry's tuning lets it come, turning to face the head as it
/// goes; and, with Face me on, turning to face it as the head moves too.
/// Each pinch on a handle is traced from its touch to where the panel
/// stood, and the carry's and facing's tunings take effect as their sliders
/// move.
@MainActor @Observable
final class CarryAndFaceStation: LabStation {
    let id = "carry-and-face"
    let title = "Carry and face"
    let summary = "Three panels, each carried by the handle under it, 1:1 with your hand, turning to face you."
    let carry = TuningStore<CarryTuning>(namespace: "GestureLab.carry-and-face.carry")
    let facing = TuningStore<FacingTuning>(namespace: "GestureLab.carry-and-face.facing")
    let trace = TraceRecorder(logsSummariesPublicly: true)

    /// Whether the panels turn to face the head as it moves, not only as
    /// they're carried.
    var facesYouAsYouMove = true

    /// Where the last panel let go stood, about the head.
    private(set) var lastStood: String?

    /// The panels, by name, as the space last made them.
    @ObservationIgnored private var panels: [String: Entity] = [:]

    /// Each panel's handle, by the panel's name.
    @ObservationIgnored fileprivate var handles: [String: PanelHandleRig] = [:]

    /// How tall each panel lays out, in points, by its name, which may be
    /// said before its handle is made.
    @ObservationIgnored private var heights: [String: Double] = [:]

    /// The panels: each one's name, title, and where it stands from
    /// `LabSpace.front` as the space opens.
    static let layout: [(name: String, title: String, offset: SIMD3<Float>)] = [
        ("panel-a", "Panel A", SIMD3(-0.5, 0, 0.15)),
        ("panel-b", "Panel B", SIMD3(0, 0.05, 0)),
        ("panel-c", "Panel C", SIMD3(0.5, 0, 0.15)),
    ]

    static func registerComponents() {
        GrabHandle.registerComponents()
        FacesTheViewerSystem.registerComponentsAndSystem()
    }

    var windowContent: some View { CarryAndFaceWindow(station: self) }
    var spaceContent: some View { CarryAndFaceSpace(station: self) }
    var tuningContent: some View {
        VStack(spacing: 0) {
            TuningPanel(carry, title: "Carry")
            TuningPanel(facing, title: "Facing")
        }
    }

    /// Makes the panels under `root`, each with its attachment and its
    /// pill's from `attachments`, standing where `layout` says, facing the
    /// head.
    func makePanels(under root: Entity, attachments: RealityViewAttachments) {
        panels = [:]
        handles = [:]
        for panel in Self.layout {
            let entity = Entity()
            entity.name = panel.name
            root.addChild(entity)
            if let view = attachments.entity(for: panel.name) {
                entity.addChild(view)
            }
            let handle = PanelHandleRig(under: entity, carrying: panel.name, panelHeight: heights[panel.name] ?? 0)
            if let pill = attachments.entity(for: Self.pillID(of: panel.name)) {
                handle.hang(pill: pill)
            }
            panels[panel.name] = entity
            handles[panel.name] = handle
        }
        putBack()
    }

    /// Puts every panel back where it stood as the space opened, facing the
    /// head.
    func putBack() {
        let viewer = HeadTracker.shared.viewerPosition() ?? UntrackedHead.eye
        for panel in Self.layout {
            guard let entity = panels[panel.name] else { continue }
            let place = LabSpace.front + panel.offset
            entity.position = place
            entity.orientation = Facing.orientation(from: place, toward: viewer)
        }
        lastStood = nil
    }

    /// Turns facing as the head moves on or off, at `tuning`.
    func applyFacing(_ tuning: FacingTuning, always: Bool) {
        for entity in panels.values {
            if always {
                entity.components.set(FacesTheViewerComponent(tuning: tuning))
            } else {
                entity.components.remove(FacesTheViewerComponent.self)
            }
        }
    }

    /// The panel named `name` laid out `height` points tall.
    func panelResized(_ name: String, toHeight height: Double) {
        heights[name] = height
        handles[name]?.panelResized(toHeight: height)
    }

    /// The panel `entity` was let go.
    func panelLetGo(_ entity: Entity) {
        let title = Self.layout.first { $0.name == entity.name }?.title ?? entity.name
        lastStood = "\(title): \(CarriedEntity.describe(entity, aboutHeadAt: HeadTracker.shared.viewerPosition()))"
    }

    static func pillID(of name: String) -> String { "\(name)-pill" }
}

#if DEBUG
extension CarryAndFaceStation {
    /// The grab handle of the middle panel, which the lab load's stand-in
    /// pinch carries (`LabLoad`).
    func loadHandle() -> Entity? {
        handles["panel-b"]?.handle
    }
}
#endif

/// The carry and face station's part of the window: how to try it, where
/// the last panel stood, and its switches.
private struct CarryAndFaceWindow: View {
    @Bindable var station: CarryAndFaceStation

    var body: some View {
        let carry = station.carry.tuning
        VStack(alignment: .leading, spacing: 14) {
            Text("Pinch the pill under a panel and carry it: it follows your hand 1:1 once your pinch has moved \(carry.startDistance.formatted()) pt, turns to face you as it goes, and stops \(Double(carry.nearestToHead).formatted()) m from your head however close you pull it. Carry one over or under your head and it keeps the way it faced. Each pinch shows in the trace, with how far your hand and the panel went and where it stood.")
                .font(.system(size: 20))
            if let lastStood = station.lastStood {
                Text(lastStood)
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
            }
            Toggle("Face me as I move", isOn: $station.facesYouAsYouMove)
                .font(.system(size: 20))
            Button("Put them back", systemImage: "arrow.uturn.backward") {
                station.putBack()
            }
        }
    }
}

/// The carry and face station's part of the space: the three panels, each
/// with its pill and grab handle.
private struct CarryAndFaceSpace: View {
    let station: CarryAndFaceStation

    var body: some View {
        let facing = station.facing.tuning
        let always = station.facesYouAsYouMove
        RealityView { content, attachments in
            let root = Entity()
            root.name = "carry-and-face"
            content.add(root)
            station.makePanels(under: root, attachments: attachments)
            station.applyFacing(facing, always: always)
        } update: { _, _ in
            station.applyFacing(facing, always: always)
        } attachments: {
            ForEach(CarryAndFaceStation.layout, id: \.name) { panel in
                Attachment(id: panel.name) {
                    CarryLabPanel(
                        title: panel.title,
                        detail: "Carry me by the pill under me."
                    ) { height in
                        station.panelResized(panel.name, toHeight: height)
                    }
                }
                Attachment(id: CarryAndFaceStation.pillID(of: panel.name)) {
                    PanelHandlePill(label: "Move \(panel.title)")
                }
            }
        }
        .grabHandlesCarryEntities(
            tuning: station.carry.tuning,
            facing: facing,
            recorder: station.trace,
            onEnd: { entity in station.panelLetGo(entity) }
        )
        .task {
            await HeadTracker.shared.start()
        }
    }
}
