import SwiftUI

/// GestureLab: a window listing a station for each of GestureKit's
/// gestures, and a mixed immersive space, opened at launch, where the
/// chosen station stands, so each gesture can be tried on the headset with
/// its trace and its tuning beside it.
@main
struct GestureLabApp: App {
    @State private var lab: LabModel

    init() {
        let stations = LabStations.all()
        // Every station's RealityKit components and systems, registered
        // before anything uses them, as an entity-targeted gesture's query
        // asks.
        for station in stations {
            type(of: station).registerComponents()
        }
        let lab = LabModel(stations: stations)
        _lab = State(initialValue: lab)
        #if DEBUG
        LabLoad.start(on: lab)
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "lab") {
            LabWindow(lab: lab)
        }
        .defaultSize(width: 1500, height: 950)

        // A station's own window, for a gesture that lives in a window: the
        // size of a library window, its trace beside it.
        WindowGroup(id: LabModel.stationWindowID, for: String.self) { $stationID in
            StationOwnWindow(lab: lab, stationID: stationID)
        }
        .defaultSize(width: 1200, height: 820)
        .windowResizability(.contentMinSize)

        ImmersiveSpace(id: LabModel.spaceID) {
            LabSpaceView(lab: lab)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
