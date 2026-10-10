#if os(visionOS) && DEBUG
import GestureCore
import SwiftUI

/// A pluckable container's ear for the hand's stand-in, in a debug build,
/// on its scroll view: the scroll view's phases, as its pan would say them,
/// told to the container as SwiftUI's own; and its content moved to an
/// offset through SwiftUI's scroll position, so the scroll view really
/// scrolls, its lazy grid makes the items that come into view, and
/// `onScrollGeometryChange` tells the container each step, as it does a
/// hand's scroll. Only the pan is stood in for.
///
/// It holds the scroll view's position only while the stand-in listens, so
/// an app's own scroll position is untouched otherwise.
struct PluckContainerStandIn: ViewModifier {
    let model: PluckContainerModel
    let automationID: String
    let recorder: TraceRecorder?

    @State private var position = ScrollPosition(edge: .top)
    @State private var geometry = PluckContainerStandInGeometry()

    func body(content: Content) -> some View {
        model.automationID = automationID
        GestureAutomation.startIfAsked()
        let geometry = geometry
        let model = model
        return Group {
            if PinchStandIn.shared.isListening || GestureAutomation.isOn {
                content
                    .scrollPosition($position)
                    .onScrollGeometryChange(for: PluckContainerStandInGeometry.Reading.self) { scroll in
                        PluckContainerStandInGeometry.Reading(
                            offset: scroll.contentOffset,
                            contentSize: scroll.contentSize,
                            containerSize: scroll.containerSize,
                            insets: scroll.contentInsets
                        )
                    } action: { _, reading in
                        geometry.reading = reading
                    }
                    .modifier(PinchStandInEar(
                        adapter: .pluckContainer,
                        name: automationID,
                        pluck: { step in
                            switch step {
                            case .scrollPhase(let phase): model.scrollPhaseChanged(to: phase)
                            case .contentScrolled(let offset): position.scrollTo(point: CGPoint(x: offset.x, y: offset.y))
                            default: break
                            }
                        },
                        isBusy: { model.liftedItem != nil || model.scrollIsHeldOff || model.phase.isScrolling },
                        facts: { facts(geometry.reading) },
                        recorder: recorder
                    ))
            } else {
                content
            }
        }
    }

    /// What the container and its scroll view say of themselves now.
    private func facts(_ reading: PluckContainerStandInGeometry.Reading?) -> AutomationJSON {
        let status = model.status
        var facts: [String: AutomationJSON] = [
            "phase": .string(model.phase.rawValue),
            "lifted": status.lifted.map { .string($0) } ?? .null,
            "scrollIsHeldOff": .bool(model.scrollIsHeldOff),
            "holdsItsScroll": .bool(model.holdsItsScroll),
            "alarms": .number(Double(status.alarms)),
            "lastAlarm": status.lastAlarm.map { .string($0) } ?? .null,
            "pinch": status.pinch.map { .string($0) } ?? .null,
            "disagreement": status.disagreement.map { .string($0) } ?? .null,
            "scrollView": status.scrollView.map { .string($0) } ?? .null,
        ]
        if let reading {
            let lowest = -Double(reading.insets.top)
            let highest = max(lowest, Double(reading.contentSize.height - reading.containerSize.height + reading.insets.bottom))
            facts["offset"] = [.number(Double(reading.offset.x), decimals: 1), .number(Double(reading.offset.y), decimals: 1)]
            facts["minOffset"] = .number(lowest, decimals: 1)
            facts["maxOffset"] = .number(highest, decimals: 1)
            facts["viewport"] = [.number(Double(reading.containerSize.width), decimals: 1), .number(Double(reading.containerSize.height), decimals: 1)]
        }
        return .object(facts)
    }
}

/// Where a pluckable container's scroll view last said it was, kept in a
/// reference, so a scroll's every frame draws nothing.
@MainActor
final class PluckContainerStandInGeometry {
    struct Reading: Equatable {
        var offset: CGPoint
        var contentSize: CGSize
        var containerSize: CGSize
        var insets: EdgeInsets
    }

    var reading: Reading?
}
#endif
