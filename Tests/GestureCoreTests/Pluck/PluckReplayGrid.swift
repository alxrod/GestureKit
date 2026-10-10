@testable import GestureCore

/// A pluckable grid as GestureKit's adapter wires GestureCore together, as
/// values, for replaying the words a pinch's gestures say in any order: a
/// container (`PluckContainer`) and its watch (`PluckHoldWatch`) as
/// `PluckContainerModel` keeps them, the watch told the container's hold
/// after each change and deciding what the scroll view is given, which the
/// replay keeps with its times (`given`), and each item's pinches
/// (`PluckPinches`) as its `PluckItemDriver` tells them, the counts each asks
/// for, and the watch's looks, run on the replay's clock, each action done
/// as the driver does it: a lift and a settle through the container; a pinch
/// that begins telling every other item kept up past its press, as the
/// model's `pinchBegan(by:)` does; the container's scroll phase told to each
/// pinch under way as the model's `scrollPhaseChanged(to:)` does; each
/// gesture word, and each change of a pinch, told to the watch; and a
/// pinch's end taking it off the container's pinches.
///
/// What the system does to the gestures, which words it says and in what
/// order, is the replay's to choose, which is the point: no word is
/// promised, so every order of the words that end a pinch, each said or
/// not, is replayed (`PluckEndReplayTests`).
struct PluckReplayGrid {
    let start = ContinuousClock.now
    let pointsPerMeter = 1360.0

    private(set) var now: ContinuousClock.Instant
    private(set) var container: PluckContainer<String>
    private(set) var watch = PluckHoldWatch<String>()
    /// The alarms the watch raised, as the model raises them, the safety
    /// net's among them.
    private(set) var alarms: [PluckHoldWatch<String>.Alarm] = []
    /// What the scroll view was given, held off or on, each time it changed,
    /// with when, as `pluckContainer` gives it the watch's hold.
    private(set) var given: [(at: ContinuousClock.Instant, heldOff: Bool)] = []
    /// Whether the scroll view is given held off now.
    var scrollViewHeldOff: Bool { given.last?.heldOff ?? false }
    /// Whether the safety net is letting a hold go, as the model's flag.
    private var isLettingGo = false
    /// Each item's pinches, as its driver keeps them; an item that went
    /// comes back with a driver of its own, as a view made again does.
    private(set) var pinches: [String: PluckPinches] = [:]
    /// The items with a pinch under way, as the model keeps their drivers.
    private(set) var pinched: Set<String> = []
    /// Each item's pinch as its driver last told the watch.
    private var reported: [String: PluckHoldWatch<String>.Pinch] = [:]
    /// When each item's hold and arming counts come up, as its driver runs
    /// them.
    private var holdDue: [String: ContinuousClock.Instant] = [:]
    private var armDue: [String: ContinuousClock.Instant] = [:]
    private var quietDue: [String: ContinuousClock.Instant] = [:]
    /// The container's scroll offset, as its scroll view last said.
    private(set) var scrollOffset = SIMD2<Double>(0, 0)
    /// What each word did, for a failure's message.
    private(set) var log: [String] = []
    let tuning: PluckTuning

    init(tuning: PluckTuning = PluckTuning()) {
        self.tuning = tuning
        now = start
        container = PluckContainer(tuning: tuning)
        watch.unheardLimit = tuning.unheardHoldReleaseTime
        watch.unheardScrollLimit = tuning.unheardScrollHoldReleaseTime
        watch.scrollComesBackMidPinch = tuning.scrollComesBackMidPinch
        watchChanged()
    }

    /// The time `seconds` into the replay.
    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// Whether any item's pinch holds its item lifted in the container.
    var anyPinchHoldsItsItem: Bool {
        pinches.values.contains { $0.press?.isHeld ?? false }
    }

    // MARK: The clock

    /// What comes up on the replay's clock: an item's count, or the watch's
    /// look, a twentieth of a second after its time, as the model looks.
    private enum Due {
        case hold(String)
        case arming(String)
        case quiet(String)
        case watch
    }

    /// Moves the clock to `seconds`, running what comes up on the way, in
    /// order, as the driver's and the model's tasks would.
    mutating func advance(to seconds: Double) {
        let target = at(seconds)
        var looks = 0
        while true {
            looks += 1
            precondition(looks < 10_000, "the replay's clock made no progress: holds \(holdDue), arms \(armDue), quiets \(quietDue), the watch at \(String(describing: watch.nextCheck.map { $0 - start })), its verdict \(watch.verdict(at: now)), its disagreement \(watch.disagreement ?? "none"), its ruling \(watch.scrollRulingTitle ?? "none"), lifted \(watch.heldTitle ?? "none"), scroll for \(watch.scrollHeldTitle ?? "none"):\n" + log.suffix(20).joined(separator: "\n"))
            var dues: [(ContinuousClock.Instant, Due)] = holdDue.map { ($0.value, .hold($0.key)) }
                + armDue.map { ($0.value, .arming($0.key)) }
                + quietDue.map { ($0.value, .quiet($0.key)) }
            if let look = watch.nextCheck { dues.append((look + .milliseconds(50), .watch)) }
            guard let (when, due) = dues.filter({ $0.0 <= target }).min(by: { $0.0 < $1.0 }) else { break }
            now = max(now, when)
            switch due {
            case .hold(let item):
                holdDue[item] = nil
                holdCountIsUp(item)
            case .arming(let item):
                armDue[item] = nil
                apply(tell(item) { $0.armPull(at: $1) }, to: item, word: "arming")
            case .quiet(let item):
                quietDue[item] = nil
                let told = tell(item) { $0.quietPassed(at: $1) }
                if !told.actions.isEmpty || told.ended != nil { apply(told, to: item, word: "quiet") }
            case .watch:
                lookAtTheHold()
            }
        }
        now = max(now, target)
    }

    // MARK: The item's words, as its driver hears them

    mutating func press(_ item: String, down: Bool) {
        watch.heard(down ? "press down" : "press up", from: item, title: item, at: now)
        let told = tell(item) { down ? $0.pressBegan(at: $1) : $0.pressEnded(at: $1) }
        apply(told, to: item, word: down ? "press down" : "press up")
    }

    mutating func tap(_ item: String) {
        watch.heard("tap", from: item, title: item, at: now)
        let tap = tell(item) { $0.tapped(at: $1) }
        log.append("\(item) tap: \(tap.isRelease ? "release" : "tap"), \(tap.actions)")
        run(tap.countdowns, for: item)
        reportPinchGoingOn(item)
        for action in tap.actions { perform(action, for: item) }
        if tap.ended != nil { pinched.remove(item) }
        reportPinch(of: item)
    }

    mutating func drag(_ item: String, _ x: Double, _ y: Double, _ z: Double) {
        watch.heard(pinches[item]?.isDragging == true ? nil : "drag spoke", from: item, title: item, at: now)
        let pointsPerMeter = pointsPerMeter
        let told = tell(item) { $0.dragMoved(SIMD3(x, y, z), pointsPerMeter: pointsPerMeter, at: $1) }
        apply(told, to: item, word: "drag")
    }

    /// The drag's `onEnded`.
    mutating func dragEnded(_ item: String) {
        watch.heard("drag end", from: item, title: item, at: now)
        let told = tell(item) { $0.dragEnded(at: $1) }
        apply(told, to: item, word: "drag end")
    }

    /// The drag's gesture state going false, as it ends or is cancelled: a
    /// cancel, should the drag still have the pinch.
    mutating func dragStopped(_ item: String) {
        guard pinches[item]?.isDragging == true else { return }
        watch.heard("drag cancelled", from: item, title: item, at: now)
        let told = tell(item) { $0.dragCancelled(at: $1) }
        apply(told, to: item, word: "drag cancelled")
    }

    /// The item left the container: its counts stop, its pinch is told, and
    /// should it come back, it comes with a driver of its own.
    mutating func itemWent(_ item: String) {
        holdDue[item] = nil
        armDue[item] = nil
        quietDue[item] = nil
        watch.heard("item went", from: item, title: item, at: now)
        let told = tell(item) { $0.itemWent(at: $1) }
        apply(told, to: item, word: "item went")
        pinches[item] = nil
        reported[item] = nil
    }

    // MARK: The container's words, as its model hears them

    mutating func scrollPhase(_ phase: PluckScrollPhase) {
        let wasScrolling = container.phase.isScrolling
        let change = container.scrollPhaseChanged(to: phase, at: now)
        watch.scrollViewSaid(phase, at: now)
        if change.settled != nil { watch.settled(because: "the container's scroll", at: now) }
        mirror()
        log.append("scroll phase \(phase.rawValue): holds \(container.holdsItsScroll)")
        let began = phase.isScrolling && !wasScrolling
        for item in pinched.sorted() {
            if began {
                let told = tell(item) { $0.containerScrolled(at: $1) }
                apply(told, to: item, word: "container scrolled")
            }
            if change.settled == item { containerSettled(item) }
        }
    }

    mutating func scrollOffsetChanged(to offset: SIMD2<Double>) {
        guard offset != scrollOffset else { return }
        scrollOffset = offset
        for item in pinched.sorted() {
            offsetChanged(for: item)
        }
    }

    // MARK: The model's watch

    /// After the watch was told something: lets a hold go at once should the
    /// safety net say so, and gives the scroll view the watch's hold, as the
    /// model's `watchChanged` and `pluckContainer` do.
    private mutating func watchChanged() {
        if !isLettingGo, case .letGo(let alarm) = watch.verdict(at: now) { letGo(alarm) }
        let heldOff = watch.holdsTheScroll
        if given.last?.heldOff != heldOff {
            given.append((now, heldOff))
            log.append("the scroll view given \(heldOff ? "held off" : "on")")
            watch.scrollGiven(heldOff: heldOff, at: now)
        }
    }

    /// Tells the watch the container's hold, as the model's `mirror` does.
    private mutating func mirror() {
        watch.container(holds: container.holdsItsScroll, lifted: container.liftedItem, at: now)
        watchChanged()
    }

    /// Does what the watch says now, as the model's look does.
    private mutating func lookAtTheHold() {
        switch watch.verdict(at: now) {
        case .alarm(let alarm): raise(alarm)
        case .letGo(let alarm): letGo(alarm)
        case .fine: break
        }
        watchChanged()
    }

    private mutating func raise(_ alarm: PluckHoldWatch<String>.Alarm) {
        alarms.append(alarm)
        log.append("alarm: \(alarm.line)")
        watch.raised(alarm, at: now)
    }

    /// The safety net, as the model's `letGo` does it.
    private mutating func letGo(_ alarm: PluckHoldWatch<String>.Alarm) {
        isLettingGo = true
        defer { isLettingGo = false }
        raise(alarm)
        watch.releaseTheScroll(because: "the safety net", at: now)
        let lifted = container.liftedItem
        if lifted != nil { _ = container.settleLiftedItem() }
        // The container's state first, so the watch's settle takes no hold
        // for an item the container no longer has.
        watch.container(holds: container.holdsItsScroll, lifted: container.liftedItem, at: now)
        watch.settled(because: "the safety net", at: now)
        mirror()
        if let lifted { containerSettled(lifted) }
    }

    /// The container settled `item`: its driver, should it have a pinch
    /// under way, tells its pinch, as `containerSettledIt(because:)` does.
    private mutating func containerSettled(_ item: String) {
        guard pinched.contains(item) else { return }
        let told = tell(item) { $0.containerSettledIt(at: $1) }
        if told.why == .settledByTheContainer { apply(told, to: item, word: "settled by the container") }
    }

    // MARK: The driver's wiring

    private func fresh() -> PluckPinches {
        PluckPinches(tuning: tuning)
    }

    /// Tells `item`'s pinches a word at the replay's time, giving back what
    /// it said.
    private mutating func tell<Said>(_ item: String, _ word: (inout PluckPinches, ContinuousClock.Instant) -> Said) -> Said {
        var itemPinches = pinches[item] ?? fresh()
        let said = word(&itemPinches, now)
        pinches[item] = itemPinches
        return said
    }

    private mutating func offsetChanged(for item: String) {
        let offset = scrollOffset
        let told = tell(item) { $0.scrollOffset(offset, at: $1) }
        guard !told.actions.isEmpty else { return }
        apply(told, to: item, word: "scroll offset")
    }

    private mutating func holdCountIsUp(_ item: String) {
        offsetChanged(for: item)
        let touched = pinches[item]?.touchedAt ?? now
        let scrolled = container.scrolled(since: touched)
        let told = tell(item) { $0.holdFired(asTheContainerScrolled: scrolled, at: $1) }
        apply(told, to: item, word: "hold")
    }

    /// Does what one word told, as `PluckItemDriver.apply` does.
    private mutating func apply(_ told: PluckPinches.Told, to item: String, word: String) {
        log.append("\(item) \(word): \(told.why.name) \(told.actions)\(told.ended.map { ", ended \($0.outcome.rawValue) \($0.ending.rawValue)" } ?? "")")
        if told.beganAPinch {
            if told.ended != nil {
                for action in told.actions { perform(action, for: item) }
                pinched.remove(item)
            }
            for other in pinched.sorted() where other != item {
                let elsewhere = tell(other) { $0.pinchBeganElsewhere(at: $1) }
                if !elsewhere.actions.isEmpty || elsewhere.ended != nil {
                    apply(elsewhere, to: other, word: "pinch elsewhere")
                }
            }
            pinched.insert(item)
            run(told.countdowns, for: item)
            if told.ended == nil {
                reportPinchGoingOn(item)
                for action in told.actions { perform(action, for: item) }
            }
            offsetChanged(for: item)
            reportPinch(of: item)
            return
        }
        run(told.countdowns, for: item)
        reportPinchGoingOn(item)
        for action in told.actions { perform(action, for: item) }
        if told.ended != nil {
            pinched.remove(item)
            quietDue[item] = nil
        }
        reportPinch(of: item)
    }

    /// The rules told `item`'s pinch as a scroll, as the driver tells the
    /// model.
    private mutating func ruledAScroll(_ item: String) {
        watch.ruledAScroll(on: item, at: now)
        watchChanged()
    }

    /// Tells the watch what `item`'s pinch is now before its word's actions,
    /// should it go on, as the driver's `reportPinchGoingOn` does.
    private mutating func reportPinchGoingOn(_ item: String) {
        guard pinches[item]?.press != nil else { return }
        reportPinch(of: item)
    }

    /// Tells the watch what `item`'s pinch is now, should that have changed,
    /// as the driver does.
    private mutating func reportPinch(of item: String) {
        let itemPinches = pinches[item]
        let pinch = itemPinches?.press.map { press in
            PluckHoldWatch<String>.Pinch(
                title: item,
                pressIsDown: itemPinches?.isHolding ?? false,
                dragHasIt: itemPinches?.isDragging ?? false,
                holdsItsItem: press.isLifted
            )
        }
        guard pinch != reported[item] else { return }
        reported[item] = pinch
        watch.pinch(item, is: pinch, at: now)
        watchChanged()
    }

    private mutating func run(_ countdowns: [PluckPinches.Countdown], for item: String) {
        for countdown in countdowns {
            switch countdown {
            case .startHold(let duration): holdDue[item] = now + duration
            case .stopHold: holdDue[item] = nil
            case .startArming(let duration): armDue[item] = now + duration
            case .stopArming: armDue[item] = nil
            case .startQuiet(let duration): quietDue[item] = now + duration
            }
        }
    }

    private mutating func perform(_ action: PluckPress.Action, for item: String) {
        switch action {
        case .lift:
            let change = container.lift(item, at: now)
            if change.settled != item { watch.lifted(item, title: item, at: now) }
            mirror()
            if let displaced = change.settled, displaced != item { containerSettled(displaced) }
        case .settle:
            if container.settle(item).settled != nil { watch.settled(because: "its pinch", at: now) }
            mirror()
            if case .givenBackToTheScroll = pinches[item]?.press?.why { ruledAScroll(item) }
        case .stayDown:
            ruledAScroll(item)
        default:
            break
        }
    }
}
