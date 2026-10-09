import GestureKit
import os
import SwiftUI

private let logger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "LabWindow")

/// The lab's window: the stations, each with its summary, and, for the one
/// chosen, its window content, its tuning, and its trace. It opens the
/// immersive space as it first appears, and offers to open it again should
/// it close.
struct LabWindow: View {
    let lab: LabModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

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
            StationDetail(station: lab.chosen)
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
        .task { await openSpace() }
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

/// The chosen station: its title and summary, its window content and its
/// tuning in a column, and its trace beside them, filling the rest.
private struct StationDetail: View {
    let station: any LabStation

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(station.title)
                        .font(.system(size: 34, weight: .bold))
                    Text(station.summary)
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
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
