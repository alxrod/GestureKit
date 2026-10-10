#if os(visionOS) && DEBUG
import GestureCore
import Foundation

/// What each adapter reports to the automation while a command runs, as
/// events an answer carries: the adapter's own words for what happened,
/// worked out only while a command listens.
extension GestureAutomation {
    /// A pluckable item's event, as its app hears it (`PluckEvent`).
    func heardPluck(_ event: PluckEvent, on title: String) {
        guard isListeningToAdapters else { return }
        switch event {
        case .tapped: heard("pluck", on: title, "tapped")
        case .lifted: heard("pluck", on: title, "lifted")
        case .settled: heard("pluck", on: title, "settled")
        case .spawned(let at): heard("pluck", on: title, "spawned", ["at": .vector(at)])
        case .carried(let middle, let handMoved):
            heard("pluck", on: title, "carried", ["middle": .vector(middle), "handMoved": .vector(handMoved)])
        case .released(let at): heard("pluck", on: title, "released", ["at": .vector(at)])
        case .spawnCancelled: heard("pluck", on: title, "spawn cancelled")
        }
    }

    /// What a pinch on a surface was told to do (`SurfacePress.Action`).
    func heardSurfacePress(_ action: SurfacePress.Action, on name: String?) {
        guard isListeningToAdapters else { return }
        let target = name ?? "unnamed"
        switch action {
        case .tap(let along): heard("press", on: target, "tap", ["along": .number(along, decimals: 4)])
        case .beginDragAlong(let from, let to): heard("press", on: target, "beginDragAlong", ["from": .number(from, decimals: 4), "to": .number(to, decimals: 4)])
        case .moveDragAlong(let to): heard("press", on: target, "moveDragAlong", ["to": .number(to, decimals: 4)])
        case .endDragAlong: heard("press", on: target, "endDragAlong")
        case .ignoreDragAcross: heard("press", on: target, "ignoreDragAcross")
        case .giveUpHold: heard("press", on: target, "giveUpHold")
        case .pickUp: heard("press", on: target, "pickUp")
        case .putDown: heard("press", on: target, "putDown")
        case .fireHold: heard("press", on: target, "fireHold")
        case .endHold: heard("press", on: target, "endHold")
        case .beginScroll(let handMoved): heard("press", on: target, "beginScroll", ["handMoved": .vector(handMoved)])
        case .moveScroll(let handMoved): heard("press", on: target, "moveScroll", ["handMoved": .vector(handMoved)])
        case .endScroll(let coasting): heard("press", on: target, "endScroll", ["coasting": .bool(coasting)])
        case .endCatch: heard("press", on: target, "endCatch")
        case .beginCarry(_, let handMoved): heard("press", on: target, "beginCarry", ["handMoved": .vector(handMoved)])
        case .moveCarry(let handMoved): heard("press", on: target, "moveCarry", ["handMoved": .vector(handMoved)])
        case .endCarry: heard("press", on: target, "endCarry")
        case .cancelCarry: heard("press", on: target, "cancelCarry")
        }
    }
}
#endif
