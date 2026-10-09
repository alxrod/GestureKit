import GestureKit
import os
import SwiftUI

private let logger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "LabWindow")

/// The lab's window: the stations, each with its summary, and, for the one
/// chosen, its window content, its tuning, and its trace. It opens the
/// immersive space as it first appears, and offers to open it again should
/// it close; then the chosen station's own window, if it has one, which it
/// closes as another station is chosen, opening that one's.
struct LabWindow: View {
    let lab: LabModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<String?>(
                get: { lab.chosenID },
                set: { if let id = $0 { lab.chosenID = id } }
            )) {
                ForEach(lab.stations.indices, id: \.self) { index in
                    let station = lab.stations[index]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.title)
                            .font(.system(size: 22, weight: .semibold))
                        Text(station.summary)
                            .font(.system(size: 17))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .tag(station.id)
                }
            }
            .navigationTitle("GestureLab")
        } detail: {
            StationDetail(station: lab.chosen, openOwnWindow: { openOwnWindow(of: lab.chosenID) })
                .id(lab.chosenID)
                .toolbar {
                    if !lab.isSpaceOpen {
                        ToolbarItem {
                            Button("Open the space", systemImage: "cube.transparent") {
                                Task { await openSpace() }
                            }
                        }
                    }
                }
        }
        .task {
            // The space first, so the station's window is made with the
            // space open, and its geometry gives the space's coordinates.
            await openSpace()
            openOwnWindow(of: lab.chosenID)
        }
        .onChange(of: lab.chosenID) { old, new in
            if lab.station(withID: old)?.ownWindowTitle != nil {
                dismissWindow(id: LabModel.stationWindowID, value: old)
            }
            openOwnWindow(of: new)
        }
    }

    /// Opens the own window of the station `id`, if it has one, or brings it
    /// forward.
    private func openOwnWindow(of id: String) {
        guard let title = lab.station(withID: id)?.ownWindowTitle else { return }
        logger.info("Opening the window of its own, \(title, privacy: .public), of the station \(id, privacy: .public)")
        openWindow(id: LabModel.stationWindowID, value: id)
    }

    private func openSpace() async {
        guard !lab.isSpaceOpen else { return }
        switch await openImmersiveSpace(id: LabModel.spaceID) {
        case .opened:
            logger.info("Opened the lab's space")
        case .userCancelled:
            logger.info("The lab's space didn't open: the person declined")
        case .error:
            logger.error("The lab's space didn't open")
        @unknown default:
            logger.error("The lab's space didn't open, for a reason this build doesn't know")
        }
    }
}

/// The chosen station: its title and summary, a button that opens its own
/// window if it has one, its window content and its tuning in a column, and
/// its trace beside them, filling the rest.
private struct StationDetail: View {
    let station: any LabStation
    let openOwnWindow: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(station.title)
                        .font(.system(size: 34, weight: .bold))
                    Text(station.summary)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    if let ownWindowTitle = station.ownWindowTitle {
                        Button("Open the \(ownWindowTitle)", systemImage: "macwindow", action: openOwnWindow)
                    }
                    station.windowView
                    station.tuningView
                        .background(.regularMaterial, in: .rect(cornerRadius: 24))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 540)
            TraceView(station.trace)
        }
        .padding(24)
    }
}

/// A station's own window: its content, edge to edge, and its trace in an
/// ornament beside it, so the trace reads while the window is pinched. A
/// station that has none, as one a later build dropped whose window the
/// system restored, says so.
struct StationOwnWindow: View {
    let lab: LabModel
    let stationID: String?

    var body: some View {
        if let id = stationID, let station = lab.station(withID: id), station.ownWindowTitle != nil {
            station.ownWindowView
                .ornament(attachmentAnchor: .scene(.trailing), contentAlignment: .leading) {
                    TraceView(station.trace)
                        .frame(width: 560, height: 820)
                        .padding(.leading, 24)
                }
        } else {
            Text("This window belongs to no station. Close it, and choose a station in the lab's window.")
                .font(.system(size: 22))
                .padding(40)
        }
    }
}
