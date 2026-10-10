#if os(visionOS) && DEBUG
import GestureCore
import RealityKit
import SwiftUI

/// A hand's stand-in, in a debug build, for measuring and driving
/// GestureKit's adapters in the simulator, which can't pinch: while it
/// listens, each adapter on screen takes its steps as it takes its own
/// gesture's words, each move as a drag's change, each release as its end,
/// and each cancel as its gesture's reset with no end, so a load can drive a
/// stream of drag words through `.surfacePress`,
/// `.holdWatch`, or `.grabHandleCarry` as a hand would, and the cost of the
/// adapter's own work be read; and GestureKit's automation drives each
/// gesture through it (`GestureAutomation`).
///
/// It stands in for the gesture's words alone, not for the gesture: what the
/// gesture system does to tell them, and its state's reset as a pinch ends,
/// aren't measured. A step goes to the adapter as its view last made it,
/// its tuning and closures with it. It's in debug builds only, behind its
/// SPI:
///
///     @_spi(PinchStandIn) import GestureKit
///     PinchStandIn.shared.isListening = true   // as the app starts
///     PinchStandIn.shared.step(.surfacePress, .moved(points: SIMD3(120, 0, 0)))
///     PinchStandIn.shared.step(.surfacePress, .released)
///
/// A step goes to every adapter of its kind on screen, or, `named`, only to
/// those of that id (`surfacePress(automationID:…)`). A
/// pluckable item, by its title, and its container take words of their own
/// (`PluckStep`), each of the words their gestures and scroll view say, so a
/// load can say them in any order, or leave any out, as the pluck's replays
/// do (`PluckEndReplayTests`), and watch the real adapter's status and
/// alarm:
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
        /// Its pull's drag ended (`onEnded`), where it last moved to.
        case dragEnded
        /// Its pull's drag's gesture state went false, as it does as the
        /// drag ends or is cancelled.
        case dragStopped
        /// The item left its container.
        case itemWent
        /// The container's scroll view's phase changed.
        case scrollPhase(PluckScrollPhase)
        /// The container's scroll view moved its content to `offset`, in
        /// points, as its pan would: the content really moves, through
        /// SwiftUI's scroll position, so the container hears it as it hears
        /// a hand's scroll.
        case contentScrolled(to: SIMD2<Double>)
    }

    /// One word of a stand-in pinch.
    public enum Step {
        /// The pinch has moved `points` from where it touched, in the
        /// adapter's view's points, as a drag's translation: along, down, and
        /// toward the viewer. A grab handle's carry needs the handle pinched
        /// too, and the move in its carried thing's parent's frame, in
        /// meters. A surface's press takes where it touched, `touch`, in the
        /// view's points, or 100 pt along and 20 pt down.
        case moved(points: SIMD3<Double>, meters: SIMD3<Float> = .zero, handle: Entity? = nil, touch: SIMD2<Double>? = nil)
        /// The pinch was let go.
        case released
        /// The pinch's gesture was cancelled, its state reset with no end,
        /// as when the system takes the pinch away: each adapter ends the
        /// pinch as its gesture's cancel would.
        case cancelled
    }

    /// An adapter listening: its kind and what its view last made of it.
    @MainActor
    struct Ear {
        let adapter: Adapter
        let latest: PinchStandInLatest

        /// What it's driven by: an item's title, or the id its adapter was
        /// given; nil for none.
        var name: String? {
            if case .pluckItem(let title) = adapter { return title }
            return latest.name
        }

        /// Whether `asked` names it: its name, or an item's id as text.
        func answers(to asked: String) -> Bool {
            name == asked || latest.id == asked
        }
    }

    private var ears: [UUID: Ear] = [:]

    /// Told as an adapter starts or stops listening, so the automation can
    /// tell when an app has settled.
    var earsChanged: (() -> Void)?

    private init() {}

    /// Hands `step` to every adapter of the kind `adapter` listening, or only
    /// those `named` so, and says how many took it.
    @discardableResult
    public func step(_ adapter: Adapter, _ step: Step, named name: String? = nil) -> Int {
        let hearing = ears.values.filter { $0.adapter == adapter && (name == nil || $0.answers(to: name ?? "")) }
        for ear in hearing { ear.latest.step?(step) }
        return hearing.count
    }

    /// Hands the pluck's `step` to every adapter of the kind `adapter`
    /// listening, or only those `named` so, and says how many took it.
    @discardableResult
    public func step(_ adapter: Adapter, _ step: PluckStep, named name: String? = nil) -> Int {
        let hearing = ears.values.filter { $0.adapter == adapter && (name == nil || $0.answers(to: name ?? "")) }
        for ear in hearing { ear.latest.pluck?(step) }
        return hearing.count
    }

    /// The adapters listening now.
    var listening: [Ear] { Array(ears.values) }

    /// Starts handing `adapter`'s steps to what `latest` holds, until
    /// `stopListening`.
    func listen(as adapter: Adapter, _ latest: PinchStandInLatest) -> UUID {
        let id = UUID()
        ears[id] = Ear(adapter: adapter, latest: latest)
        earsChanged?()
        return id
    }

    func stopListening(_ id: UUID) {
        guard ears.removeValue(forKey: id) != nil else { return }
        earsChanged?()
    }
}

/// What an adapter's ear hands the stand-in's words to, as its view last
/// made them, kept in a reference so the view's every making sets it
/// without drawing again: its name, an item's id, its handlers, whether a
/// pinch is under way on it, what it goes by, and the trace it writes to,
/// for the automation.
@MainActor
final class PinchStandInLatest {
    var name: String?
    var id: String?
    var step: ((PinchStandIn.Step) -> Void)?
    var pluck: ((PinchStandIn.PluckStep) -> Void)?
    var isBusy: (() -> Bool)?
    var facts: (() -> AutomationJSON)?
    var recorder: TraceRecorder?
}

/// An adapter's ear for the stand-in: listens while the view is on screen,
/// if the stand-in listens, or GestureKit's automation is on, as it appears,
/// under the id its adapter was given, each word going to the view as it is
/// now, its environment and tuning with it, not as it appeared. It's how
/// every adapter registers itself with the automation, and goes as its view
/// does.
struct PinchStandInEar: ViewModifier {
    let adapter: PinchStandIn.Adapter
    /// What it's driven by; an item is driven by its title.
    var name: String?
    /// An item's id, as its app gave it, which drives it too.
    var id: String?
    var step: ((PinchStandIn.Step) -> Void)?
    var pluck: ((PinchStandIn.PluckStep) -> Void)?
    /// Whether a pinch is under way on it, or anything it began still runs.
    var isBusy: (() -> Bool)?
    /// What it goes by and what it holds now, for the automation's state.
    var facts: (() -> AutomationJSON)?
    /// The trace it writes to, whose interactions the automation's answers
    /// carry.
    var recorder: TraceRecorder?

    @State private var listening: UUID?
    @State private var latest = PinchStandInLatest()

    func body(content: Content) -> some View {
        let latest = latest
        latest.name = name
        latest.id = id
        latest.step = step
        latest.pluck = pluck
        latest.isBusy = isBusy
        latest.facts = facts
        latest.recorder = recorder
        return content
            .onAppear {
                guard listening == nil else { return }
                GestureAutomation.startIfAsked()
                guard PinchStandIn.shared.isListening || GestureAutomation.isOn else { return }
                listening = PinchStandIn.shared.listen(as: adapter, latest)
            }
            .onDisappear {
                guard let listening else { return }
                PinchStandIn.shared.stopListening(listening)
                self.listening = nil
            }
    }
}
#endif
