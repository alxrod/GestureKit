// The README's code for Automation, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import SwiftUI

/// A surface the automation drives as "strip" rather than by its trace's
/// title, and, in a debug build, the app's own state in every answer.
struct AutomationNamedStrip: View {
    let clipCount: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .frame(width: 600, height: 120)
            .surfacePress(traceTitle: "Pinch on the strip", automationID: "strip") { _ in }
            #if DEBUG
            .onAppear {
                GestureAutomation.shared.register(state: "editor") { ["clips": .number(Double(clipCount))] }
            }
            #endif
    }
}
