#if os(visionOS) && DEBUG
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

    private init() {}

    /// Hands `step` to every adapter of the kind `adapter` listening, and
    /// says how many took it.
    @discardableResult
    public func step(_ adapter: Adapter, _ step: Step) -> Int {
        let handlers = listeners[adapter] ?? [:]
        for handler in handlers.values { handler(step) }
        return handlers.count
    }

    /// Starts handing `adapter`'s steps to `handler`, until `stopListening`.
    func listen(as adapter: Adapter, _ handler: @escaping (Step) -> Void) -> UUID {
        let id = UUID()
        listeners[adapter, default: [:]][id] = handler
        return id
    }

    func stopListening(_ id: UUID) {
        for adapter in listeners.keys { listeners[adapter]?[id] = nil }
    }
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
