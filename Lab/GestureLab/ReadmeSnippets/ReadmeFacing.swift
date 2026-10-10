// The README's code for Facing, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import RealityKit
import SwiftUI

/// Two signs: one turned to face the viewer once, as it's placed, and one
/// turned every frame as the viewer walks around it.
struct FacingSignsView: View {
    var body: some View {
        RealityView { content in
            let head = HeadTracker.shared.viewerPosition() ?? UntrackedHead.eye

            let placed = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.25), materials: [SimpleMaterial()])
            placed.position = [-0.6, 1.4, -1.2]
            placed.orientation = Facing.orientation(from: placed.position, toward: head)
            content.add(placed)

            let following = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.25), materials: [SimpleMaterial()])
            following.position = [0.6, 1.4, -1.2]
            following.components.set(FacesTheViewerComponent())
            content.add(following)
        }
    }
}
