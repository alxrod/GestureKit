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
/// It watches its hold (`PluckHoldWatch`): what a status line shows of it
/// (`status`), and an alarm, traced in red and logged, once an item has
/// stayed lifted with no pinch under way for more than half a second.
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

    /// What a status line shows of its hold and the pinch under way, which
    /// changes only as an item lifts or settles, a gesture takes or lets go
    /// of a pinch, or the alarm is raised, never at a drag's every word.
    public private(set) var status = PluckContainerStatus()

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
    /// The watch over its hold, told what its items' pinches do.
    @ObservationIgnored private var watch = PluckHoldWatch<AnyHashable>()
    /// The watch's next look, while one is due.
    @ObservationIgnored private var watchCheck: Task<Void, Never>?
    /// When the hold under way began, on the watch's clock and the wall's.
    @ObservationIgnored private var heldSinceInstant: ContinuousClock.Instant?
    @ObservationIgnored private var heldSinceDate: Date?

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
            watched { $0.settled(because: "the app settled it", at: .now) }
            driver(of: lifted)?.containerSettledIt(because: "the app settled it")
        }
    }

    /// Whether the container scrolled at any time since `touch`, a pinch's.
    func scrolled(since touch: ContinuousClock.Instant) -> Bool {
        container.scrolled(since: touch)
    }

    /// `item` lifted, by `driver`'s pinch: it takes the place of another
    /// lifted, which reports settling.
    func lift(_ item: AnyHashable, title: String, by driver: PluckItemDriver) -> PluckContainer<AnyHashable>.Change {
        let change = container.lift(item, at: .now)
        mirror()
        if change.settled != item {
            watched { $0.lifted(item, title: title, at: .now) }
        }
        if let displaced = change.settled, displaced != item {
            self.driver(of: displaced)?.containerSettledIt(because: "another item lifted")
        }
        return change
    }

    /// `item` settled, as its pinch says, `because` of what.
    func settle(_ item: AnyHashable, because reason: String) -> PluckContainer<AnyHashable>.Change {
        let change = container.settle(item)
        mirror()
        if change.settled != nil {
            watched { $0.settled(because: reason, at: .now) }
        }
        return change
    }

    /// A gesture on `driver`'s item spoke: `word`, kept for the watch's
    /// alarm, or, for a drag's every move, nil, which only notes the time.
    func heard(_ word: String?, from driver: PluckItemDriver) {
        guard let item = driver.itemID else { return }
        watch.heard(word, from: item, title: driver.title, at: .now)
    }

    /// `driver`'s item's pinch is `pinch` now, as its rules say, or over,
    /// nil.
    func pinchChanged(of driver: PluckItemDriver, to pinch: PluckHoldWatch<AnyHashable>.Pinch?) {
        guard let item = driver.itemID else { return }
        watched { $0.pinch(item, is: pinch, at: .now) }
    }

    /// `driver`'s item began a pinch: each other item's pinch hears of it,
    /// and one kept up past its press, or gone quiet, its ends unheard, is
    /// over, its end unseen, and settles.
    func pinchBegan(by driver: PluckItemDriver) {
        for other in Array(pinchedItems.values) where other !== driver {
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
        watch.note("scroll \(phase.rawValue)", at: .now)
        if change.settled != nil {
            watched { $0.settled(because: "the container's scroll", at: .now) }
        }
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

    // MARK: The watch

    /// Tells the watch something that may change what it says, then shows
    /// its status and looks again when it next may say something.
    private func watched(_ change: (inout PluckHoldWatch<AnyHashable>) -> Void) {
        change(&watch)
        showStatus()
        scheduleWatchCheck()
    }

    /// Looks again a twentieth of a second after the watch's next time, so a
    /// count due at the same moment, as an item's own, runs first.
    private func scheduleWatchCheck() {
        watchCheck?.cancel()
        watchCheck = nil
        guard let next = watch.nextCheck else { return }
        watchCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(until: next + .milliseconds(50), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.lookAtTheHold()
        }
    }

    /// Does what the watch says now: raises its alarm, traced in red with
    /// the state and the last ten things it was told, and logged.
    private func lookAtTheHold() {
        watchCheck = nil
        let now = ContinuousClock.now
        if case .alarm(let alarm) = watch.verdict(at: now) {
            raise(alarm, at: now)
        }
        showStatus()
        scheduleWatchCheck()
    }

    private func raise(_ alarm: PluckHoldWatch<AnyHashable>.Alarm, at now: ContinuousClock.Instant) {
        let lines = [("alarm", alarm.line)] + watch.alarmLines(for: alarm, at: now)
        watch.raised(alarm, at: now)
        let why = switch alarm.kind {
        case .heldWithNoPinchUnderWay: "no pinch under way"
        case .heldWithNothingHeard: "nothing heard from its pinch"
        }
        let traced = recorder?.alarm("Pluck", title: "Scroll held by \(alarm.title), \(why)", lines: lines, outcome: "stuck") ?? false
        if !traced {
            let events = lines.dropFirst().map { "\($0.0) \($0.1)" }.joined(separator: "; ")
            pluckContainerLogger.info("Alarm: \(alarm.line, privacy: .public); \(events, privacy: .public)")
        }
    }

    /// Shows the watch's status, should it have changed, the hold's start by
    /// the wall clock taken as it began.
    private func showStatus() {
        if watch.heldSince != heldSinceInstant {
            heldSinceInstant = watch.heldSince
            heldSinceDate = watch.heldSince == nil ? nil : .now
        }
        let shown = PluckContainerStatus(watch: watch, heldSince: heldSinceDate)
        if status != shown { status = shown }
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

/// What a pluckable container's status line shows: the item holding its
/// scroll, if one is, and since when; the pinch under way, or the one its
/// rules still keep; and its alarms.
public struct PluckContainerStatus: Equatable, Sendable {
    /// The item lifted, holding the scroll, by its title; nil while none is.
    public var heldBy: String?
    /// When it lifted, by the wall clock.
    public var heldSince: Date?
    /// The pinch under way, or else one its rules keep, in a few words:
    /// "item 7: press up, drag silent or ended, its item kept up past its
    /// press"; nil while there's none.
    public var pinch: String?
    /// Whether a gesture says a pinch is under way.
    public var pinchIsUnderWay = false
    /// How many alarms it has raised.
    public var alarms = 0
    /// The last alarm it raised, in a line.
    public var lastAlarm: String?

    public init() {}

    init(watch: PluckHoldWatch<AnyHashable>, heldSince: Date?) {
        heldBy = watch.heldTitle
        self.heldSince = watch.heldTitle == nil ? nil : heldSince
        pinch = watch.shownPinch?.description
        pinchIsUnderWay = watch.isPinchUnderWay
        alarms = watch.alarms
        lastAlarm = watch.lastAlarm
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
            #if DEBUG
            // The hand's stand-in's word for the scroll view's phase.
            .modifier(PluckStandInListener(adapter: .pluckContainer) { step in
                if case .scrollPhase(let phase) = step { model.scrollPhaseChanged(to: phase) }
            })
            #endif
            .environment(\.pluckContainerContext, PluckContainerContext(model: model, tuning: tuning, recorder: recorder, scrollAxes: scrollAxes))
    }
}
#endif
