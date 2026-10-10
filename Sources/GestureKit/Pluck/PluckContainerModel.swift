#if os(visionOS)
import GestureCore
import Observation
import os
import SwiftUI

private let pluckContainerLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "PluckContainerModel")

/// A scrolling container whose items pluck, a grid or a list, as its scroll
/// view and its items tell it: which item is lifted, at most one, which its
/// items draw; whether its scroll is held off under it, as the tuning says;
/// its scroll view's phase and its scroll offset, which it tells the pinch
/// under way on each item, so a scroll during a pinch, or its content
/// moving at all, makes it a scroll before its hold, and a scroll settles a
/// lifted item, as the tuning says; and the axes it scrolls along, which a
/// hold watches moves along most closely.
///
/// Make one per scroll view, keep it with the view's state, and hand it to
/// `pluckContainer(_:tuning:trace:)` on the scroll view; each item inside
/// marked `pluckable(_:title:perform:)` finds it there.
@MainActor @Observable
public final class PluckContainerModel {
    /// The item lifted, by the id its `pluckable` was given; nil while none
    /// is.
    public private(set) var liftedItem: AnyHashable?

    /// Whether its scroll is held off: an item is lifted, and the tuning
    /// stops the scroll under one.
    public private(set) var holdsItsScroll = false

    /// Its scroll view's phase, as last told.
    public private(set) var phase = PluckScrollPhase.idle

    /// Its scroll offset, as its scroll view last said, in points; nil
    /// until it says. Read at a pinch's touch and its hold, and told to the
    /// pinches under way as it changes, so it's observed by nothing, as it
    /// changes at every frame of a scroll.
    @ObservationIgnored private(set) var scrollOffset: SIMD2<Double>?

    /// The axes it scrolls along, as its modifier was last given them.
    @ObservationIgnored var scrollAxes: PluckScrollAxes = .vertical

    @ObservationIgnored private var container = PluckContainer<AnyHashable>()
    @ObservationIgnored var recorder: TraceRecorder?
    /// The interaction a scroll of the container is traced as, from its
    /// first scrolling phase to its rest.
    @ObservationIgnored private var scrollTrace: InteractionTrace?
    /// The items with a pinch under way, which hear the container's scroll.
    @ObservationIgnored private var pinchedItems: [ObjectIdentifier: PluckItemDriver] = [:]

    public init() {}

    /// The tuning it goes by, as its modifier was last given it.
    var tuning: PluckTuning {
        get { container.tuning }
        set {
            container.tuning = newValue
            mirror()
        }
    }

    /// Whether `item` is the one lifted.
    public func isLifted(_ item: some Hashable) -> Bool {
        liftedItem == AnyHashable(item)
    }

    /// Whichever item is lifted settles, as an app does as the container's
    /// contents change under it; its pinch goes on, and its item reports
    /// settling.
    public func settleLiftedItem() {
        let lifted = liftedItem
        _ = container.settleLiftedItem()
        mirror()
        if let lifted {
            driver(of: lifted)?.containerSettledIt(because: "the app settled it")
        }
    }

    /// Whether the container scrolled at any time since `touch`, a pinch's.
    func scrolled(since touch: ContinuousClock.Instant) -> Bool {
        container.scrolled(since: touch)
    }

    /// `item` lifted, by `driver`'s pinch: it takes the place of another
    /// lifted, which reports settling.
    func lift(_ item: AnyHashable, by driver: PluckItemDriver) -> PluckContainer<AnyHashable>.Change {
        let change = container.lift(item, at: .now)
        mirror()
        if let displaced = change.settled, displaced != item {
            self.driver(of: displaced)?.containerSettledIt(because: "another item lifted")
        }
        return change
    }

    /// `item` settled, as its pinch says.
    func settle(_ item: AnyHashable) -> PluckContainer<AnyHashable>.Change {
        let change = container.settle(item)
        mirror()
        return change
    }

    /// `driver`'s item began a pinch: one kept up past its press elsewhere
    /// is over, its end unseen, and settles.
    func pinchBegan(by driver: PluckItemDriver) {
        for other in pinchedItems.values where other !== driver && other.isKeptUpPastItsPress {
            other.pinchBeganElsewhere()
        }
        pinchedItems[ObjectIdentifier(driver)] = driver
    }

    /// `driver`'s item's pinch is over.
    func pinchEnded(by driver: PluckItemDriver) {
        pinchedItems[ObjectIdentifier(driver)] = nil
    }

    /// Its scroll view's phase changed to `phase`: its scroll begins or
    /// stops, which settles a lifted item as the tuning says, and each pinch
    /// under way hears of it.
    func scrollPhaseChanged(to phase: PluckScrollPhase) {
        let wasScrolling = self.phase.isScrolling
        self.phase = phase
        let change = container.scrollPhaseChanged(to: phase, at: .now)
        mirror()
        traceScroll(phase, settled: change.settled)
        let began = phase.isScrolling && !wasScrolling
        for driver in Array(pinchedItems.values) {
            driver.containerPhaseChanged(to: phase, scrollBegan: began, settledIt: change.settled != nil && change.settled == driver.itemID)
        }
    }

    /// Its scroll view's content offset changed to `offset`: each pinch
    /// under way hears of it, and gives its hold up should the content have
    /// moved since its touch.
    func scrollOffsetChanged(to offset: CGPoint) {
        let offset = SIMD2(Double(offset.x), Double(offset.y))
        guard offset != scrollOffset else { return }
        scrollOffset = offset
        for driver in Array(pinchedItems.values) {
            driver.containerOffsetChanged(to: offset)
        }
    }

    /// Its scroll view left the screen: it no longer scrolls.
    func disappeared() {
        _ = container.disappeared(at: .now)
        phase = .idle
        mirror()
        scrollTrace?.finish("the container went")
        scrollTrace = nil
    }

    /// The driver of `item`'s pinch under way, if it has one.
    private func driver(of item: AnyHashable) -> PluckItemDriver? {
        pinchedItems.values.first { $0.itemID == item }
    }

    /// Mirrors the container's lifted item and scroll hold, observed.
    private func mirror() {
        if liftedItem != container.liftedItem { liftedItem = container.liftedItem }
        if holdsItsScroll != container.holdsItsScroll {
            holdsItsScroll = container.holdsItsScroll
            pluckContainerLogger.info("The container's scroll is \(self.holdsItsScroll ? "held off under a lifted item" : "on again", privacy: .public)")
        }
    }

    /// Traces a scroll of the container, from its first scrolling phase to
    /// its rest, apart from any pinch's: a scroll that coasts on after its
    /// pinch is over still shows.
    private func traceScroll(_ phase: PluckScrollPhase, settled: AnyHashable?) {
        if phase.isScrolling, scrollTrace == nil {
            scrollTrace = recorder?.begin("Pluck", title: "Scroll of the container")
        }
        scrollTrace?.event("phase", phase.rawValue)
        if let settled {
            scrollTrace?.event("settled", "\(settled.base)")
        }
        if phase == .idle {
            scrollTrace?.finish("scroll")
            scrollTrace = nil
        }
    }
}

/// What a container marked `pluckContainer` hands its items through the
/// environment: its model, its tuning, its trace, and the axes it scrolls
/// along.
struct PluckContainerContext: Sendable {
    let model: PluckContainerModel
    let tuning: PluckTuning
    let recorder: TraceRecorder?
    let scrollAxes: PluckScrollAxes
}

extension EnvironmentValues {
    /// The pluckable container around a view, if there is one.
    @Entry var pluckContainerContext: PluckContainerContext? = nil
}

extension PluckScrollAxes {
    /// SwiftUI's axes as the pluck's.
    init(_ axes: Axis.Set) {
        var plain: PluckScrollAxes = []
        if axes.contains(.horizontal) { plain.insert(.horizontal) }
        if axes.contains(.vertical) { plain.insert(.vertical) }
        self = plain
    }
}

extension PluckScrollPhase {
    /// SwiftUI's scroll phase as a plain value.
    init(_ phase: ScrollPhase) {
        switch phase {
        case .idle: self = .idle
        case .tracking: self = .tracking
        case .interacting: self = .interacting
        case .decelerating: self = .decelerating
        case .animating: self = .animating
        }
    }
}

extension View {
    /// Makes this scroll view a container whose items pluck: each item inside
    /// marked `pluckable(_:title:perform:)` lifts, pulls out, and settles
    /// through `model`, by `tuning`, writing each pinch to `trace`, if it's
    /// given one. A pinch is the scroll's unless it's a hold: the container
    /// watches the scroll view's phase and its content offset, which a hold
    /// asks about and the pinches under way hear, and tells each pinch the
    /// axes it scrolls along, `scrollAxes`, the scroll view's own, vertical
    /// by default, along which a hold allows only a small move. It holds the
    /// scroll off while an item is lifted, if the tuning stops it, and traces
    /// each scroll of its own.
    ///
    ///     ScrollView {
    ///         LazyVGrid(columns: columns) {
    ///             ForEach(items) { item in
    ///                 ItemView(item)
    ///                     .aspectRatio(1, contentMode: .fit)
    ///                     .pluckable(item.id, title: item.name) { event in … }
    ///             }
    ///         }
    ///     }
    ///     .pluckContainer(container, tuning: tuning, trace: recorder)
    public func pluckContainer(
        _ model: PluckContainerModel,
        tuning: PluckTuning = .defaults,
        trace: TraceRecorder? = nil,
        scrollAxes: Axis.Set = .vertical
    ) -> some View {
        modifier(PluckContainerModifier(model: model, tuning: tuning, recorder: trace, scrollAxes: PluckScrollAxes(scrollAxes)))
    }
}

/// The container's side of a pluck, on its scroll view.
private struct PluckContainerModifier: ViewModifier {
    let model: PluckContainerModel
    let tuning: PluckTuning
    let recorder: TraceRecorder?
    let scrollAxes: PluckScrollAxes

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                model.scrollPhaseChanged(to: PluckScrollPhase(phase))
            }
            // The content's every move, which a hold gives itself up to
            // whatever phase the scroll view says it's in.
            .onScrollGeometryChange(for: CGPoint.self) { geometry in
                geometry.contentOffset
            } action: { _, offset in
                model.scrollOffsetChanged(to: offset)
            }
            // A lifted item's pinch moves the item, not the scroll, until it
            // settles, if the tuning stops the scroll.
            .scrollDisabled(model.holdsItsScroll)
            .onChange(of: tuning, initial: true) { _, tuning in
                model.tuning = tuning
            }
            .onAppear {
                model.recorder = recorder
                model.scrollAxes = scrollAxes
            }
            .onDisappear {
                model.disappeared()
            }
            .environment(\.pluckContainerContext, PluckContainerContext(model: model, tuning: tuning, recorder: recorder, scrollAxes: scrollAxes))
    }
}
#endif
