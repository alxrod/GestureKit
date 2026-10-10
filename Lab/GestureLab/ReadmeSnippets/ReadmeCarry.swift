// The README's code for Carry, moving the entity itself, compiled with the
// lab so it can't rot. ReadmeSnippetsTests checks the README shows exactly
// the code below.

import GestureKit
import RealityKit
import SwiftUI

/// A box in the room, carried by the handle under it, 1:1 with the hand.
struct CarriedBoxView: View {
    var body: some View {
        RealityView { content in
            let box = ModelEntity(
                mesh: .generateBox(size: 0.2),
                materials: [SimpleMaterial(color: .orange, isMetallic: false)]
            )
            box.name = "box"
            box.position = [0, 1.3, -1]
            // A clear handle that takes the pinch and glows where it's
            // looked at; it carries the ancestor its component names.
            let handle = GrabHandle.make(carrying: "box", size: [0.16, 0.025])
            handle.position.y = -0.13
            box.addChild(handle)
            content.add(box)
        }
        .grabHandlesCarryEntities(tuning: CarryTuning(nearestToHead: 0.4)) { box in
            // Let go: it stands at box.position, in its parent's frame.
        }
    }
}
