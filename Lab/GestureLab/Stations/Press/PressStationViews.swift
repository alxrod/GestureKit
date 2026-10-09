import GestureKit
import RealityKit
import SwiftUI

/// The press station's part of the window: how to try it, its choices, and
/// what last happened.
struct PressStationWindow: View {
    @Bindable var station: PressStation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("""
                Tap the long surface to drop a marker. Drag along it to move the yellow playhead, and flick it to coast; \
                pinch it while it coasts to catch it. Drag across it and nothing happens. Hold still half a second to pick \
                it up, which pops it toward you, then move 2 cm to carry it. Hold a full second and "Held" flashes. Two \
                hands stretch it. Drag the tab at its right end to resize it, or hold the tab still to see its hold \
                watched beside its drag.
                """)
                .font(.system(size: 19))
            Toggle("A drag along scrolls, and a flick coasts", isOn: $station.dragAlongScrolls)
            Toggle("Refuse every pickup", isOn: $station.refusesPickUps)
            Toggle("Refuse every carry", isOn: $station.refusesCarries)
            HStack {
                Text(station.lastEvent)
                    .font(.system(size: 24, weight: .semibold))
                Spacer()
                Button("Reset the surface") { station.resetSurface() }
            }
        }
        .font(.system(size: 19))
    }
}

/// The press station's part of the space: the surface, its tab beside its
/// right end, and what last happened above it.
struct PressStationSpace: View {
    let station: PressStation

    var body: some View {
        let center = station.center
        let length = station.length
        RealityView { content, attachments in
            for id in PressStationAttachment.allCases {
                guard let entity = attachments.entity(for: id) else { continue }
                entity.position = id.position(center: center, length: length)
                content.add(entity)
            }
        } update: { _, attachments in
            for id in PressStationAttachment.allCases {
                attachments.entity(for: id)?.position = id.position(center: center, length: length)
            }
        } attachments: {
            Attachment(id: PressStationAttachment.surface) { PressSurfaceView(station: station) }
            Attachment(id: PressStationAttachment.tab) { PressTabView(station: station) }
            Attachment(id: PressStationAttachment.caption) {
                Text(station.lastEvent)
                    .font(.system(size: 30, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassBackgroundEffect()
            }
        }
    }
}

/// The press station's attachments, and where each stands about the
/// surface's middle.
private enum PressStationAttachment: String, CaseIterable, Hashable {
    case surface
    case tab
    case caption

    func position(center: SIMD3<Float>, length: Double) -> SIMD3<Float> {
        switch self {
        case .surface: center
        case .tab: center + SIMD3(Float(length / 2) + 0.045, 0, 0)
        case .caption: center + SIMD3(0, 0.14, 0)
        }
    }
}

/// The surface: a long dark bar with a tick every 10 cm, the taps' markers,
/// and the playhead, which a coast moves frame by frame; and over it what
/// flashes. Every pinch on it is one press.
private struct PressSurfaceView: View {
    let station: PressStation
    @Environment(\.physicalMetrics) private var physicalMetrics

    var body: some View {
        let width = points(station.length)
        let height = points(0.1)
        let corner = points(0.012)
        TimelineView(.animation(paused: station.coastRun == nil)) { _ in
            let playhead = station.playheadShown(at: station.now())
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner)
                    .fill(Color(white: station.isPinched ? 0.3 : 0.2))
                ForEach(0...Int(station.length * 10), id: \.self) { tick in
                    Rectangle()
                        .fill(.white.opacity(tick % 5 == 0 ? 0.5 : 0.22))
                        .frame(width: 2, height: tick % 5 == 0 ? height * 0.5 : height * 0.25)
                        .offset(x: points(Double(tick) / 10) - 1)
                }
                ForEach(Array(station.markers.enumerated()), id: \.offset) { _, marker in
                    Circle()
                        .fill(.cyan)
                        .frame(width: 18, height: 18)
                        .offset(x: points(marker) - 9, y: -height * 0.32)
                }
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 5, height: height)
                    .offset(x: points(playhead) - 2.5)
            }
            .frame(width: width, height: height)
        }
        .overlay {
            if let flash = station.flash {
                Text(flash.text)
                    .font(.system(size: 44, weight: .bold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.65), in: .capsule)
                    .id(flash.serial)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(.hoverEffect, .rect(cornerRadius: corner))
        .hoverEffect(.highlight)
        .surfacePress(
            tuning: station.pressTuning,
            recorder: station.trace,
            traceTitle: "Pinch on the surface",
            canHold: true,
            canPickUp: true,
            dragAlongScrolls: station.dragAlongScrolls,
            catchCoast: { station.catchCoast() },
            pickUpRefusal: { station.pickUpRefusal() },
            onPinchUnderWay: { station.pinchUnderWay($0) },
            onMagnify: { station.magnify($0) },
            perform: { station.perform($0) }
        )
    }

    private func points(_ meters: Double) -> CGFloat {
        physicalMetrics.convert(meters, from: .meters)
    }
}

/// The tab beside the surface's right end: its own drag resizes the
/// surface, and its tap flashes, while its hold is watched beside them;
/// once it holds, its drag and tap do nothing for the rest of the pinch.
private struct PressTabView: View {
    let station: PressStation
    @Environment(\.physicalMetrics) private var physicalMetrics
    @State private var held = false
    @GestureState private var dragging = false

    var body: some View {
        Capsule()
            .fill(held ? Color.orange : Color.yellow)
            .frame(width: points(0.035), height: points(0.1))
            .contentShape(.hoverEffect, .capsule)
            .hoverEffect(.highlight)
            .gesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .immersiveSpace)
                    .updating($dragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        guard !held else { return }
                        station.tabDragChanged(byMeters: Double(physicalMetrics.convert(CGFloat(value.translation3D.x), to: .meters)))
                    }
                    .exclusively(before: TapGesture().onEnded {
                        guard !held else { return }
                        station.tabTapped()
                    })
            )
            .onChange(of: dragging) { _, isDragging in
                if !isDragging { station.tabDragEnded() }
            }
            .holdWatch(
                isHeld: $held,
                dragHasBegun: dragging,
                tuning: station.holdWatch.tuning,
                recorder: station.trace,
                traceTitle: "Pinch on the tab"
            ) {
                station.tabHeld()
            }
    }

    private func points(_ meters: Double) -> CGFloat {
        physicalMetrics.convert(meters, from: .meters)
    }
}
