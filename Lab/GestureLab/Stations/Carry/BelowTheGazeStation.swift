import GestureKit
import RealityKit
import SwiftUI

/// The station for placing a panel below the gaze: as the space opens, and
/// at each press of Place below my gaze, a panel stands in front of the
/// head, slightly below where it looks, tilted up to it, drawn so it looks
/// as big as it would a meter out, and stays there as the head moves,
/// until it's carried by the pill under it. A change to where the placement
/// stands it, as a slider moves, stands it again; a change to the pill moves
/// and sizes the pill at once.
@MainActor @Observable
final class BelowTheGazeStation: LabStation {
    let id = "below-the-gaze"
    let title = "Below the gaze"
    let summary = "A panel placed below your gaze, tilted up to you, carried by the handle under it, and placed again by a button."
    let placement = TuningStore<PlacementTuning>(namespace: "GestureLab.below-the-gaze.placement")
    let carry = TuningStore<CarryTuning>(namespace: "GestureLab.below-the-gaze.carry")
    let trace = TraceRecorder(logsSummariesPublicly: true)

    /// Where the panel was last placed, and the angles that put it there.
    private(set) var placed: GazePlacement.Placement?

    /// Where the panel last stood as it was let go, about the head.
    private(set) var lastStood: String?

    /// The panel's name, which its handle carries it by.
    static let panelName = "gaze-panel"
    static let pillID = "gaze-panel-pill"

    @ObservationIgnored private var panel: Entity?
    @ObservationIgnored private var handle: PanelHandleRig?
    @ObservationIgnored private var height: Double = 0
    /// The tuning the panel was last placed with, so a change to where the
    /// placement stands it places it again, and a change to its pill alone
    /// doesn't.
    @ObservationIgnored private var placedWith: PlacementTuning?
    @ObservationIgnored private var placing: Task<Void, Never>?

    static func registerComponents() {
        GrabHandle.registerComponents()
    }

    var windowContent: some View { BelowTheGazeWindow(station: self) }
    var spaceContent: some View { BelowTheGazeSpace(station: self) }
    var tuningContent: some View {
        VStack(spacing: 0) {
            TuningPanel(placement, title: "Placement")
            TuningPanel(carry, title: "Carry")
        }
    }

    /// Makes the panel under `root`, with its attachment and its pill's from
    /// `attachments`, hidden until it's placed below the gaze.
    func makePanel(under root: Entity, attachments: RealityViewAttachments) {
        let entity = Entity()
        entity.name = Self.panelName
        entity.isEnabled = false
        root.addChild(entity)
        if let view = attachments.entity(for: Self.panelName) {
            entity.addChild(view)
        }
        let handle = PanelHandleRig(under: entity, carrying: Self.panelName, tuning: placement.tuning, panelHeight: height)
        if let pill = attachments.entity(for: Self.pillID) {
            handle.hang(pill: pill)
        }
        panel = entity
        self.handle = handle
        placedWith = nil
    }

    /// Places the panel below the gaze, waiting for world tracking to say
    /// where the head is should it be starting, traced unless `quietly`.
    func placeBelowTheGaze(because reason: String, quietly: Bool = false) {
        guard let panel else { return }
        let tuning = placement.tuning
        placing?.cancel()
        placing = Task {
            let stood = await GazePanel.standBelowTheGaze(
                panel, tuning: tuning, recorder: quietly ? nil : trace, because: reason
            )
            guard let stood else { return }
            panel.isEnabled = true
            placed = stood
            placedWith = tuning
            lastStood = nil
        }
    }

    /// The placement's tuning as it stands now: the pill follows at once,
    /// and a change to where the placement stands the panel places it again,
    /// untraced, as a slider moves.
    func applyPlacement(_ tuning: PlacementTuning) {
        handle?.retune(tuning)
        guard let placedWith, let panel, panel.isEnabled else { return }
        var pillAside = tuning
        pillAside.handleWidth = placedWith.handleWidth
        pillAside.handleHeight = placedWith.handleHeight
        pillAside.handleGap = placedWith.handleGap
        pillAside.handleReachBeyondEnds = placedWith.handleReachBeyondEnds
        pillAside.handleReachHeight = placedWith.handleReachHeight
        if pillAside != placedWith {
            placeBelowTheGaze(because: "its placement's tuning changed", quietly: true)
        }
    }

    /// The panel laid out `height` points tall.
    func panelResized(toHeight height: Double) {
        self.height = height
        handle?.panelResized(toHeight: height)
    }

    /// The panel was let go.
    func panelLetGo(_ entity: Entity) {
        lastStood = CarriedEntity.describe(entity, aboutHeadAt: HeadTracker.shared.viewerPosition())
    }

    /// Where the panel was placed, in a line.
    var placedText: String {
        guard let placed else { return "Not placed yet" }
        return String(
            format: "%.2f m out · %.1f° below your gaze · tilted up %.1f°",
            placed.distance, placed.belowTheGaze * 180 / .pi, placed.tilt * 180 / .pi
        )
    }
}

/// The below-the-gaze station's part of the window: how to try it, where
/// the panel was placed and where it stood, and the button that places it.
private struct BelowTheGazeWindow: View {
    let station: BelowTheGazeStation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Look somewhere and press Place below my gaze: the panel stands in front of you, a little below where you look, tilted up to you, and stays there as you look around. Look far down or up and it stands no steeper than the tuning's steepest. Carry it by the pill under it, then place it again. Moving Distance, Below the gaze, or Steepest places it again as you slide; the handle's numbers move and size the pill at once.")
                .font(.system(size: 20))
            Text(station.placedText)
                .font(.system(size: 18, weight: .medium).monospacedDigit())
            if let lastStood = station.lastStood {
                Text("Let go at \(lastStood)")
                    .font(.system(size: 18, weight: .medium).monospacedDigit())
            }
            Button("Place below my gaze", systemImage: "arrow.down.to.line") {
                station.placeBelowTheGaze(because: "the window's button was pressed")
            }
        }
    }
}

/// The below-the-gaze station's part of the space: the panel, its pill, and
/// its grab handle.
private struct BelowTheGazeSpace: View {
    let station: BelowTheGazeStation

    var body: some View {
        let tuning = station.placement.tuning
        let placedText = station.placedText
        RealityView { content, attachments in
            let root = Entity()
            root.name = "below-the-gaze"
            content.add(root)
            station.makePanel(under: root, attachments: attachments)
        } update: { _, _ in
            station.applyPlacement(tuning)
        } attachments: {
            Attachment(id: BelowTheGazeStation.panelName) {
                CarryLabPanel(
                    title: "Below the gaze",
                    detail: placedText,
                    resized: { height in station.panelResized(toHeight: height) }
                ) {
                    Button("Place below my gaze", systemImage: "arrow.down.to.line") {
                        station.placeBelowTheGaze(because: "the panel's button was pressed")
                    }
                    .font(.system(size: 20))
                }
            }
            Attachment(id: BelowTheGazeStation.pillID) {
                PanelHandlePill(tuning: tuning, label: "Move the panel", hint: "Drag to move it. Activate to bring it back below your gaze.") {
                    station.placeBelowTheGaze(because: "VoiceOver activated its handle")
                }
            }
        }
        .grabHandlesCarryEntities(
            tuning: station.carry.tuning,
            recorder: station.trace,
            onEnd: { entity in station.panelLetGo(entity) }
        )
        .task {
            await HeadTracker.shared.start()
            station.placeBelowTheGaze(because: "the station's space opened")
        }
    }
}
