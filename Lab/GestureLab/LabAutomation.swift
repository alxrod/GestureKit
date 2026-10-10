#if DEBUG
import GestureKit

/// What GestureLab adds to GestureKit's automation, as any app may: a
/// command to choose a station, as its window's list does; the lab's state,
/// which every answer carries; and the press's coast, which `wait` waits
/// for. Everything a station's gestures drive registers itself, as in any
/// app on GestureKit.
enum LabAutomation {
    @MainActor static func register(_ lab: LabModel) {
        let automation = GestureAutomation.shared
        automation.register(command: "station", takes: ["target", "id"], help: "Chooses the lab's station id (trace-check, carry-and-face, below-the-gaze, press, or pluck), as its window's list does, and waits for it to settle. Outcome: chosen.") { arguments in
            let id = try arguments.string("id") ?? arguments.requiredString("target", example: "pluck")
            guard lab.station(withID: id) != nil else {
                throw AutomationError("No station “\(id)”; the lab has \(lab.stations.map(\.id).joined(separator: ", ")).")
            }
            lab.chosenID = id
            try? await Task.sleep(for: .milliseconds(300))
            await automation.settle(atMost: 10)
            return GestureAutomationAnswer("chosen", ["station": .string(id)])
        }
        automation.register(state: "lab") { state(of: lab) }
        for station in lab.stations {
            if let press = station as? PressStation {
                automation.register(busy: "the press's coast") { press.coastRun != nil }
            }
        }
    }

    /// The lab's state: the chosen station, whether the space is open, and
    /// what the chosen station shows.
    @MainActor private static func state(of lab: LabModel) -> AutomationJSON {
        var state: [String: AutomationJSON] = [
            "station": .string(lab.chosenID),
            "spaceOpen": .bool(lab.isSpaceOpen),
            "tracing": .bool(lab.tracesAnything),
        ]
        switch lab.chosen {
        case let press as PressStation:
            state["press"] = [
                "playhead": .number(press.playhead, decimals: 4),
                "length": .number(press.length, decimals: 4),
                "center": .vector(press.center),
                "markers": .number(Double(press.markers.count)),
                "coasting": .bool(press.coastRun != nil),
                "lastEvent": .string(press.lastEvent),
            ]
        case let pluck as PluckStation:
            state["pluck"] = [
                "cards": .number(Double(pluck.cardCount)),
                "lastTapped": pluck.lastTapped.map { .number(Double($0)) } ?? .null,
                "taps": .number(Double(pluck.taps)),
            ]
        case let carry as CarryAndFaceStation:
            state["carryAndFace"] = ["lastStood": carry.lastStood.map { .string($0) } ?? .null]
        case let gaze as BelowTheGazeStation:
            state["belowTheGaze"] = [
                "placed": .string(gaze.placedText),
                "lastStood": gaze.lastStood.map { .string($0) } ?? .null,
            ]
        case let check as TraceCheckStation:
            state["traceCheck"] = ["taps": .number(Double(check.taps))]
        default:
            break
        }
        return .object(state)
    }
}
#endif
