#if os(visionOS)
import GestureCore
import Observation
import os
import SwiftUI

private let pluckContainerLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "PluckContainerModel")

/// A scrolling container whose items pluck, a grid or a list, as its scroll
/// view and its items tell it: which item is lifted, at most one, which its
/// items draw; whether its scroll is held off, as the tuning says, which its
/// scroll view is given (`scrollIsHeldOff`); its scroll view's phase and its
/// scroll offset, which it tells the pinch under way on each item, so a
/// scroll during a pinch, or its content moving at all, makes it a scroll
/// before its hold, and a scroll settles a lifted item, as the tuning says;
/// and the axes it scrolls along, which a hold watches moves along most
/// closely.
///
/// Its watch (`PluckHoldWatch`) decides what the scroll view is given: held
/// off from the lift until the pinch that lifted the item lets go, never
/// back on while that pinch is still down, unless the tuning says
/// (`PluckTuning.scrollComesBackMidPinch`). It shows, in a status line
/// (`status`), that value, the container's own hold and lifted item, the
/// watch's, what the scroll view has, as a debug build's probe reads it
/// (`pluckScrollViewProbe(_:)`), and its last phase. It raises alarms,
/// traced in red and logged: an item lifted with no pinch under way past
/// half a second; those views disagreeing; a pinch the rules told as a
/// scroll the scroll view never took. And its safety net lets a hold go,
/// traced as an alarm too, once nothing has been heard from the pinch that
/// backs it for `PluckTuning.unheardHoldRelease`, or for a pinch whose item
/// settled, `unheardScrollHoldRelease`, or at once should a lifted item have
/// no pinch under way.
///
/// Make one per scroll view, keep it with the view's state, and hand it to
/// `pluckContainer(_:tuning:trace:)` on the scroll view; each item inside
/// marked `pluckable(_:title:perform:)` finds it there.
@MainActor @Observable
public final class PluckContainerModel {
    /// The item lifted, by the id its `pluckable` was given; nil while none
    /// is.
    public private(set) var liftedItem: AnyHashable?

    /// Whether the container holds its scroll: an item is lifted, and the
    /// tuning stops the scroll under one. What its scroll view is given is
    /// `scrollIsHeldOff`, which lasts until the pinch that took it lets go.
    public private(set) var holdsItsScroll = false

    /// Whether its scroll view is held off: what `pluckContainer` gives it,
    /// as its watch says, from a lift until the pinch that lifted the item
    /// lets go, and never without a pinch backing it past its safety net.
    public private(set) var scrollIsHeldOff = false

    /// Its scroll view's phase, as last told.
    public private(set) var phase = PluckScrollPhase.idle

    /// What a status line shows of its hold, its scroll view, and the pinch
    /// under way, which changes only as an item lifts or settles, the scroll
    /// is held or let go, a gesture takes or lets go of a pinch, the scroll
    /// view says a phase or a probe reads it anew, or an alarm is raised,
    /// never at a drag's every word.
    public private(set) var status = PluckContainerStatus()

    /// Its scroll offset, as its scroll view last said, in points; nil
    /// until it says. Read at a pinch's touch and its hold, and told to the
    /// pinches under way as it changes, so it's observed by nothing, as it
    /// changes at every frame of a scroll.
    @ObservationIgnored private(set) var scrollOffset: SIMD2<Double>?

    /// The axes it scrolls along, as its modifier was last given them.
    @ObservationIgnored var scrollAxes: PluckScrollAxes = .vertical

    /// Reads what its scroll view has, as a debug build's probe sets it
    /// (`pluckScrollViewProbe(_:)`); nil without one.
    @ObservationIgnored var scrollViewReader: (@MainActor () -> PluckHoldWatch<AnyHashable>.ScrollViewReading?)?

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
    /// Whether the safety net is letting a hold go, so what that changes
    /// asks it nothing more.
    @ObservationIgnored private var isLettingGo = false
    /// When the scroll hold under way began, and the scroll view's last
    /// phase came, on the watch's clock and the wall's.
    @ObservationIgnored private var heldSinceInstant: ContinuousClock.Instant?
    @ObservationIgnored private var heldSinceDate: Date?
    @ObservationIgnored private var phaseInstant: ContinuousClock.Instant?
    @ObservationIgnored private var phaseDate: Date?
    #if DEBUG
    /// What GestureKit's automation drives its scroll view by, as its
    /// modifier was last given it.
    @ObservationIgnored var automationID = "grid"
    #endif

    public init() {}

    /// The tuning it goes by, as its modifier was last given it.
    var tuning: PluckTuning {
        get { container.tuning }
        set {
            container.tuning = newValue
            watch.unheardLimit = newValue.unheardHoldReleaseTime
            watch.unheardScrollLimit = newValue.unheardScrollHoldReleaseTime
            watch.scrollComesBackMidPinch = newValue.scrollComesBackMidPinch
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
        if lifted != nil { watch.settled(because: "the app settled it", at: .now) }
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
    func lift(_ item: AnyHashable, title: String, by driver: PluckItemDriver) -> PluckContainer<AnyHashable>.Change {
        let change = container.lift(item, at: .now)
        if change.settled != item {
            watch.lifted(item, title: title, at: .now)
        }
        mirror()
        if let displaced = change.settled, displaced != item {
            self.driver(of: displaced)?.containerSettledIt(because: "another item lifted")
        }
        return change
    }

    /// `item` settled, as its pinch says, `because` of what.
    func settle(_ item: AnyHashable, because reason: String) -> PluckContainer<AnyHashable>.Change {
        let change = container.settle(item)
        if change.settled != nil {
            watch.settled(because: reason, at: .now)
        }
        mirror()
        return change
    }

    /// A gesture on `driver`'s item spoke: `word`, kept for the watch's
    /// alarm, or, for a drag's every move, nil, which only notes the time.
    func heard(_ word: String?, from driver: PluckItemDriver) {
        guard let item = driver.itemID else { return }
        watch.heard(word, from: item, title: driver.title, at: .now)
    }

    /// `driver`'s item's pinch is `pinch` now, as its rules say, or over,
    /// nil: the scroll hold it took may go, and the scroll view is read.
    func pinchChanged(of driver: PluckItemDriver, to pinch: PluckHoldWatch<AnyHashable>.Pinch?) {
        guard let item = driver.itemID else { return }
        watch.pinch(item, is: pinch, at: .now)
        readScrollView()
        watchChanged()
    }

    /// The rules told `driver`'s pinch as the container's scroll: should the
    /// scroll view not take it, the watch says so.
    func ruledAScroll(by driver: PluckItemDriver) {
        watch.ruledAScroll(on: driver.title, at: .now)
        watchChanged()
    }

    /// What `pluckContainer` gave its scroll view, `heldOff`, as it gave it.
    func scrollGiven(heldOff: Bool) {
        watch.scrollGiven(heldOff: heldOff, at: .now)
        watchChanged()
        // What the scroll view has, once the value has reached it.
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.readScrollView()
            self?.watchChanged()
        }
    }

    /// A debug build's probe saw the scroll view's pan change its state, as
    /// to began, `panBegan`, or otherwise.
    func scrollViewPanChanged(panBegan: Bool) {
        guard let reading = scrollViewReader?() else { return }
        watch.scrollViewRead(reading, panBegan: panBegan, at: .now)
        watchChanged()
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
        let now = ContinuousClock.now
        let change = container.scrollPhaseChanged(to: phase, at: now)
        watch.scrollViewSaid(phase, at: now)
        if change.settled != nil {
            watch.settled(because: "the container's scroll", at: now)
        }
        mirror()
        readScrollView()
        traceScroll(phase, settled: change.settled)
        let began = phase.isScrolling && !wasScrolling
        for driver in Array(pinchedItems.values) {
            driver.containerPhaseChanged(to: phase, scrollBegan: began, settledIt: change.settled != nil && change.settled == driver.itemID)
        }
        watchChanged()
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

    /// After the watch was told something: lets a hold go at once should the
    /// safety net say so, gives the scroll view what the watch holds, shows
    /// its status, and looks again when it next may say something.
    private func watchChanged() {
        let now = ContinuousClock.now
        if !isLettingGo, case .letGo(let alarm) = watch.verdict(at: now) {
            letGo(alarm, at: now)
        }
        if scrollIsHeldOff != watch.holdsTheScroll {
            scrollIsHeldOff = watch.holdsTheScroll
            pluckContainerLogger.info("The container's scroll view is \(self.scrollIsHeldOff ? "held off" : "on again", privacy: .public)")
            #if DEBUG
            GestureAutomation.shared.heard("grid", on: automationID, scrollIsHeldOff ? "scroll held off" : "scroll on again")
            #endif
        }
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
    /// the state and the last ten things it was told, and logged; or lets
    /// a hold go, the safety net, traced so too.
    private func lookAtTheHold() {
        watchCheck = nil
        readScrollView()
        let now = ContinuousClock.now
        switch watch.verdict(at: now) {
        case .alarm(let alarm): raise(alarm, at: now)
        case .letGo(let alarm): letGo(alarm, at: now)
        case .fine: break
        }
        watchChanged()
    }

    /// The safety net: the scroll comes back on; the lifted item, should one
    /// be, settles, its pinch hearing its container settled it; and the
    /// alarm says so.
    private func letGo(_ alarm: PluckHoldWatch<AnyHashable>.Alarm, at now: ContinuousClock.Instant) {
        isLettingGo = true
        defer { isLettingGo = false }
        raise(alarm, at: now)
        watch.releaseTheScroll(because: "the safety net", at: now)
        let lifted = liftedItem
        if lifted != nil { _ = container.settleLiftedItem() }
        // The container's state first, so the watch's settle takes no hold
        // for an item the container no longer has; and the watch's lift goes
        // whatever the container had, so the net never finds the same hold
        // due again.
        watch.container(holds: container.holdsItsScroll, lifted: container.liftedItem, at: now)
        watch.settled(because: "the safety net", at: now)
        mirror()
        if let lifted {
            driver(of: lifted)?.containerSettledIt(because: "the safety net: \(alarm.line)")
        }
    }

    private func raise(_ alarm: PluckHoldWatch<AnyHashable>.Alarm, at now: ContinuousClock.Instant) {
        let lines = [("alarm", alarm.line)] + watch.alarmLines(for: alarm, at: now)
        #if DEBUG
        GestureAutomation.shared.heard("grid", on: automationID, "alarm", .string(alarm.line))
        #endif
        watch.raised(alarm, at: now)
        let title = switch alarm.kind {
        case .heldWithNoPinchUnderWay: "Scroll held by \(alarm.title), no pinch under way"
        case .letGoWithNothingHeard: "Scroll held by \(alarm.title), nothing heard from its pinch: let go"
        case .letGoWithNoPinchOnIt: "Scroll held by \(alarm.title), no pinch on it: let go"
        case .scrollLetGoWithNothingHeard: "Scroll held for the pinch on \(alarm.title), nothing heard: let go"
        case .viewsDisagree: "The hold's views disagree"
        case .scrollViewNeverTookIt: "The scroll view never took the pinch on \(alarm.title)"
        }
        let outcome = alarm.kind.letsGo ? "let go by the net" : "stuck"
        let traced = recorder?.alarm("Pluck", title: title, lines: lines, outcome: outcome) ?? false
        if !traced {
            let events = lines.dropFirst().map { "\($0.0) \($0.1)" }.joined(separator: "; ")
            pluckContainerLogger.info("Alarm: \(alarm.line, privacy: .public); \(events, privacy: .public)")
        }
    }

    /// Reads what the scroll view has, should a probe be there.
    private func readScrollView() {
        guard let reading = scrollViewReader?() else { return }
        watch.scrollViewRead(reading, at: .now)
    }

    /// Shows the watch's status, should it have changed, the scroll hold's
    /// start and the last phase's by the wall clock taken as each came.
    private func showStatus() {
        if watch.scrollHeldSince != heldSinceInstant {
            heldSinceInstant = watch.scrollHeldSince
            heldSinceDate = watch.scrollHeldSince == nil ? nil : .now
        }
        if watch.lastPhaseAt != phaseInstant {
            phaseInstant = watch.lastPhaseAt
            phaseDate = watch.lastPhaseAt == nil ? nil : .now
        }
        let shown = PluckContainerStatus(watch: watch, heldSince: heldSinceDate, lastPhaseDate: phaseDate)
        if status != shown { status = shown }
    }

    /// The driver of `item`'s pinch under way, if it has one.
    private func driver(of item: AnyHashable) -> PluckItemDriver? {
        pinchedItems.values.first { $0.itemID == item }
    }

    /// Mirrors the container's lifted item and hold, observed, and tells the
    /// watch, which lets the scroll go once nothing backs it.
    private func mirror() {
        if liftedItem != container.liftedItem { liftedItem = container.liftedItem }
        if holdsItsScroll != container.holdsItsScroll {
            holdsItsScroll = container.holdsItsScroll
            pluckContainerLogger.info("The container \(self.holdsItsScroll ? "holds its scroll under a lifted item" : "holds its scroll no more", privacy: .public)")
        }
        watch.container(holds: container.holdsItsScroll, lifted: container.liftedItem, at: .now)
        watchChanged()
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

/// What a pluckable container's status line shows, each view of its hold
/// side by side: the scroll held off as its scroll view is given it, and for
/// which item's pinch, since when; the value `.scrollDisabled` got; the
/// container's own hold and lifted item; the watch's lifted item; what the
/// scroll view has, as a debug build's probe reads it; the scroll view's
/// last phase and when; the pinch under way, or the one its rules still
/// keep; what they disagree on; and its alarms.
public struct PluckContainerStatus: Equatable, Sendable {
    /// The item whose pinch the scroll is held off for, by its title; nil
    /// while the scroll is on.
    public var heldBy: String?
    /// When the scroll was held off, by the wall clock.
    public var heldSince: Date?
    /// What the scroll view was given: held off, or on; nil until given.
    public var scrollGiven: Bool?
    /// Whether the container holds its scroll, and whether it has an item
    /// lifted.
    public var containerHolds = false
    public var containerLifted = false
    /// The item the watch was told is lifted, by its title.
    public var lifted: String?
    /// What the scroll view has, as a probe reads it, in a few words.
    public var scrollView: String?
    /// The scroll view's last phase, and when it came by the wall clock.
    public var lastPhase: String?
    public var lastPhaseDate: Date?
    /// The pinch under way, or else one its rules keep, in a few words:
    /// "item 7: press up, drag silent or ended, its item kept up past its
    /// press"; nil while there's none.
    public var pinch: String?
    /// Whether a gesture says a pinch is under way.
    public var pinchIsUnderWay = false
    /// What its views disagree on, in words; nil while they agree.
    public var disagreement: String?
    /// How many alarms it has raised.
    public var alarms = 0
    /// The last alarm it raised, in a line.
    public var lastAlarm: String?

    public init() {}

    init(watch: PluckHoldWatch<AnyHashable>, heldSince: Date?, lastPhaseDate: Date?) {
        heldBy = watch.holdsTheScroll ? (watch.scrollHeldTitle ?? "an item") : nil
        self.heldSince = watch.holdsTheScroll ? heldSince : nil
        scrollGiven = watch.scrollGiven
        containerHolds = watch.containerHolds
        containerLifted = watch.containerLifted != nil
        lifted = watch.heldTitle
        scrollView = watch.scrollView?.description
        lastPhase = watch.lastPhase?.rawValue
        self.lastPhaseDate = lastPhaseDate
        pinch = watch.shownPinch?.description
        pinchIsUnderWay = watch.isPinchUnderWay
        disagreement = watch.disagreement
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
    /// each scroll of its own. In a debug build, GestureKit's automation
    /// drives it as `automationID`, "grid" unless given.
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
        scrollAxes: Axis.Set = .vertical,
        automationID: String? = nil
    ) -> some View {
        modifier(PluckContainerModifier(
            model: model, tuning: tuning, recorder: trace, scrollAxes: PluckScrollAxes(scrollAxes),
            automationID: automationID ?? "grid"
        ))
    }
}

/// Holds the scroll view off as the container's watch says
/// (`PluckContainerModel.scrollIsHeldOff`), and tells the model the value it
/// gave, read exactly where it's given, for its status line and its alarm.
private struct PluckScrollHold: ViewModifier {
    let model: PluckContainerModel

    func body(content: Content) -> some View {
        let heldOff = model.scrollIsHeldOff
        content
            .scrollDisabled(heldOff)
            .onChange(of: heldOff, initial: true) { _, heldOff in
                model.scrollGiven(heldOff: heldOff)
            }
    }
}

/// The container's side of a pluck, on its scroll view.
private struct PluckContainerModifier: ViewModifier {
    let model: PluckContainerModel
    let tuning: PluckTuning
    let recorder: TraceRecorder?
    let scrollAxes: PluckScrollAxes
    let automationID: String

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
            // A lifted item's pinch moves the item, not the scroll, held off
            // until that pinch lets go, as the container's watch says; what
            // it's given is told back, read where it's given.
            .modifier(PluckScrollHold(model: model))
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
            // The hand's stand-in's words for the scroll view: its phase,
            // and its content moved.
            .modifier(PluckContainerStandIn(model: model, automationID: automationID, recorder: recorder))
            #endif
            .environment(\.pluckContainerContext, PluckContainerContext(model: model, tuning: tuning, recorder: recorder, scrollAxes: scrollAxes))
    }
}
#endif
