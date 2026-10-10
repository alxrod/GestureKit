#if os(visionOS) && DEBUG
import GestureCore
import RealityKit
import SwiftUI

/// A hand's stand-in, in a debug build, for measuring GestureKit's adapters
/// in the simulator, which can't pinch: while it listens, each adapter on
/// screen takes its steps as it takes its own gesture's words, each move as
/// a drag's change and each release as its end, so a load can drive a
/// stream of drag words through `.surfacePress`, `.holdWatch`, or
/// `.grabHandleCarry` as a hand would, and the cost of the adapter's own
/// work be read.
///
/// It stands in for the gesture's words alone, not for the gesture: what the
/// gesture system does to tell them, and its state's reset as a pinch ends,
/// aren't measured, and a step goes to whatever its adapter was handed as
/// it appeared. It's in debug builds only, behind its SPI:
///
///     @_spi(PinchStandIn) import GestureKit
///     PinchStandIn.shared.isListening = true   // as the app starts
///     PinchStandIn.shared.step(.surfacePress, .moved(points: SIMD3(120, 0, 0)))
///     PinchStandIn.shared.step(.surfacePress, .released)
///
/// A pluckable item, by its title, and its container take words of their
/// own (`PluckStep`), each of the words their gestures and scroll view say,
/// so a load can say them in any order, or leave any out, as the pluck's
/// replays do (`PluckEndReplayTests`), and watch the real adapter's status
/// and alarm:
///
///     PinchStandIn.shared.step(.pluckItem("item 7"), .pressDown)
///     PinchStandIn.shared.step(.pluckItem("item 7"), .pressUp)
@_spi(PinchStandIn) @MainActor
public final class PinchStandIn {
    /// The one stand-in every adapter listens to.
    public static let shared = PinchStandIn()

    /// Whether adapters listen: set before any appears, as the app starts.
    /// An adapter that appeared while it didn't never listens.
    public var isListening = false

    /// Which adapter a step goes to.
    public enum Adapter: Hashable, Sendable {
        case surfacePress
        case holdWatch
        case grabHandleCarry
        /// The pluckable item titled so (`pluckable(_:title:perform:)`).
        case pluckItem(String)
        /// Every pluckable container (`pluckContainer(_:tuning:trace:scrollAxes:)`).
        case pluckContainer
    }

    /// One word a pluckable item's gestures, or its container's scroll view,
    /// say.
    public enum PluckStep: Sendable {
        /// The item's button pressed, as a pinch touches it.
        case pressDown
        /// Its press ended, let go or cancelled.
        case pressUp
        /// Its button's tap.
        case tapped
        /// Its pull's drag moved, `points` from where the pinch touched, in
        /// the item's points: across, down, and toward the viewer.
        case dragMoved(points: SIMD3<Double>)
        /// Its pull's drag ended (`onEnded`).
        case dragEnded
        /// Its pull's drag's gesture state went false, as it does as the
        /// drag ends or is cancelled.
        case dragStopped
        /// The item left its container.
        case itemWent
        /// The container's scroll view's phase changed.
        case scrollPhase(PluckScrollPhase)
    }

    /// One word of a stand-in pinch.
    public enum Step {
        /// The pinch has moved `points` from where it touched, in the
        /// adapter's view's points, as a drag's translation: along, down, and
        /// toward the viewer. A grab handle's carry needs the handle pinched
        /// too, and the move in its carried thing's parent's frame, in
        /// meters.
        case moved(points: SIMD3<Double>, meters: SIMD3<Float> = .zero, handle: Entity? = nil)
        /// The pinch was let go.
        case released
    }

    private var listeners: [Adapter: [UUID: (Step) -> Void]] = [:]
    private var pluckListeners: [Adapter: [UUID: (PluckStep) -> Void]] = [:]

    private init() {}

    /// Hands `step` to every adapter of the kind `adapter` listening, and
    /// says how many took it.
    @discardableResult
    public func step(_ adapter: Adapter, _ step: Step) -> Int {
        let handlers = listeners[adapter] ?? [:]
        for handler in handlers.values { handler(step) }
        return handlers.count
    }

    /// Hands the pluck's `step` to every adapter of the kind `adapter`
    /// listening, and says how many took it.
    @discardableResult
    public func step(_ adapter: Adapter, _ step: PluckStep) -> Int {
        let handlers = pluckListeners[adapter] ?? [:]
        for handler in handlers.values { handler(step) }
        return handlers.count
    }

    /// Starts handing `adapter`'s steps to `handler`, until `stopListening`.
    func listen(as adapter: Adapter, _ handler: @escaping (Step) -> Void) -> UUID {
        let id = UUID()
        listeners[adapter, default: [:]][id] = handler
        return id
    }

    /// Starts handing `adapter`'s pluck steps to `handler`, until
    /// `stopListening`.
    func listen(as adapter: Adapter, toPluck handler: @escaping (PluckStep) -> Void) -> UUID {
        let id = UUID()
        pluckListeners[adapter, default: [:]][id] = handler
        return id
    }

    func stopListening(_ id: UUID) {
        for adapter in listeners.keys { listeners[adapter]?[id] = nil }
        for adapter in pluckListeners.keys { pluckListeners[adapter]?[id] = nil }
    }
}

/// A pluck adapter's ear for the stand-in, as `PinchStandInListener` is the
/// others': listens while the view is on screen, if the stand-in listens as
/// it appears.
struct PluckStandInListener: ViewModifier {
    let adapter: PinchStandIn.Adapter
    let handler: (PinchStandIn.PluckStep) -> Void
    @State private var listening: UUID?
    /// The handler as the view last made it, so a step goes to the view as
    /// it is now, its environment and tuning with it, not as it appeared.
    @State private var latest = PluckStandInHandler()

    func body(content: Content) -> some View {
        let latest = latest
        latest.handler = handler
        return content
            .onAppear {
                guard PinchStandIn.shared.isListening, listening == nil else { return }
                listening = PinchStandIn.shared.listen(as: adapter, toPluck: { latest.handler?($0) })
            }
            .onDisappear {
                guard let listening else { return }
                PinchStandIn.shared.stopListening(listening)
                self.listening = nil
            }
    }
}

/// The latest handler of a pluck adapter's ear, kept in a reference so the
/// view's every making sets it without drawing again.
@MainActor
final class PluckStandInHandler {
    var handler: ((PinchStandIn.PluckStep) -> Void)?
}

/// An adapter's ear for the stand-in: listens while the view is on screen,
/// if the stand-in listens as it appears.
struct PinchStandInListener: ViewModifier {
    let adapter: PinchStandIn.Adapter
    let handler: (PinchStandIn.Step) -> Void
    @State private var listening: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard PinchStandIn.shared.isListening, listening == nil else { return }
                listening = PinchStandIn.shared.listen(as: adapter, handler)
            }
            .onDisappear {
                guard let listening else { return }
                PinchStandIn.shared.stopListening(listening)
                self.listening = nil
            }
    }
}

#endif
