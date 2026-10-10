// The README's code for Placement, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import RealityKit
import SwiftUI

/// Controls that open below the viewer's gaze, tilted up to them, and stay
/// put until carried by the pill under them.
struct GazeControlsView: View {
    @State private var panel = Entity()

    var body: some View {
        RealityView { content, attachments in
            panel.name = "controls"
            content.add(panel)
            if let controls = attachments.entity(for: "controls") {
                panel.addChild(controls)
            }
            // The pill under a panel 200 pt tall, and the grab handle on it.
            let rig = PanelHandleRig(under: panel, carrying: "controls", panelHeight: 200)
            if let pill = attachments.entity(for: "pill") {
                rig.hang(pill: pill)
            }
        } attachments: {
            Attachment(id: "controls") {
                HStack(spacing: 24) {
                    Button("Back", systemImage: "backward.fill") {}
                    Button("Play", systemImage: "play.fill") {}
                    Button("Next", systemImage: "forward.fill") {}
                }
                .labelStyle(.iconOnly)
                .frame(width: 480, height: 200)
                .glassBackgroundEffect()
            }
            Attachment(id: "pill") {
                PanelHandlePill(label: "Move the controls")
            }
        }
        .grabHandlesCarryEntities()
        .task {
            await HeadTracker.shared.start()
            await GazePanel.standBelowTheGaze(panel)
        }
    }
}
