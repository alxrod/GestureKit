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
        _lab = State(initialValue: LabModel(stations: stations))
    }

    var body: some Scene {
        WindowGroup(id: "lab") {
            LabWindow(lab: lab)
        }
        .defaultSize(width: 1500, height: 950)

        ImmersiveSpace(id: LabModel.spaceID) {
            LabSpaceView(lab: lab)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
