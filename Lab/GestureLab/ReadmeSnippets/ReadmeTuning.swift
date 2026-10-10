// The README's code for tuning and tracing, compiled with the lab so it
// can't rot. ReadmeSnippetsTests checks the README shows exactly the code
// below.

import GestureKit
import RealityKit
import SwiftUI

/// The carry, tuned live as it's tried, each pinch traced.
@MainActor @Observable
final class CarryWorkbench {
    /// Saves the values that differ from the defaults in UserDefaults.
    let tuning = TuningStore<CarryTuning>(namespace: "MyApp.carry")
    /// Keeps the last 12 pinches; isRecording = false traces nothing.
    let trace = TraceRecorder()
}

/// A window: a slider for each number, Defaults, Copy tuning, and the trace.
struct CarryWorkbenchWindow: View {
    let bench: CarryWorkbench

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            TuningPanel(bench.tuning, title: "Carry")
                .frame(width: 480)
            TraceView(bench.trace)
        }
        .padding(24)
    }
}

/// The room: the adapter reads the tuning as each pinch touches.
struct CarryWorkbenchSpace: View {
    let bench: CarryWorkbench

    var body: some View {
        RealityView { _ in }
            .grabHandlesCarryEntities(tuning: bench.tuning.tuning, recorder: bench.trace)
    }
}

/// Numbers of your own, tuned in the same panel.
struct BadgeTuning: Tunable {
    var size = 0.2
    var spins = true

    static let defaults = BadgeTuning()

    static let parameters: [TuningParameter<BadgeTuning>] = [
        .number(\.size, key: "size", title: "Size", unit: "m", range: 0.05...0.6, step: 0.01),
        .toggle(\.spins, key: "spins", title: "Spins"),
    ]
}
