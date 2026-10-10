// The README's code for setting up, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import RealityKit
import SwiftUI

struct RoomApp: App {
    init() {
        // Before anything uses them: an entity-targeted drag finds its
        // handles by their component, which RealityKit wants registered.
        GrabHandle.registerComponents()
        FacesTheViewerSystem.registerComponentsAndSystem()
    }

    var body: some SwiftUI.Scene {
        ImmersiveSpace(id: "room") {
            RealityView { _ in }
                // Where the head is, for Carry, Facing, and Placement.
                .task { await HeadTracker.shared.start() }
                .onDisappear { HeadTracker.shared.stop() }
        }
    }
}
