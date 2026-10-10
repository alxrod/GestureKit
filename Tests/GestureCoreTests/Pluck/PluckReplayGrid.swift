@testable import GestureCore

/// A pluckable grid as GestureKit's adapter wires GestureCore together, as
/// values, for replaying the words a pinch's gestures say in any order: a
/// container (`PluckContainer`) and its watch (`PluckHoldWatch`) as
/// `PluckContainerModel` keeps them, and each item's pinches
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
    /// The alarms the watch raised, as the model raises them.
    private(set) var alarms: [PluckHoldWatch<String>.Alarm] = []
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
    /// The container's scroll offset, as its scroll view last said.
    private(set) var scrollOffset = SIMD2<Double>(0, 0)
    /// What each word did, for a failure's message.
    private(set) var log: [String] = []
    let tuning: PluckTuning

    init(tuning: PluckTuning = PluckTuning()) {
        self.tuning = tuning
        now = start
        container = PluckContainer(tuning: tuning)
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
        case watch
    }

    /// Moves the clock to `seconds`, running what comes up on the way, in
    /// order, as the driver's and the model's tasks would.
    mutating func advance(to seconds: Double) {
        let target = at(seconds)
        while true {
            var dues: [(ContinuousClock.Instant, Due)] = holdDue.map { ($0.value, .hold($0.key)) } + armDue.map { ($0.value, .arming($0.key)) }
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
        watch.note("scroll \(phase.rawValue)", at: now)
        if change.settled != nil { watch.settled(because: "the container's scroll", at: now) }
        log.append("scroll phase \(phase.rawValue): holds \(container.holdsItsScroll)")
        let began = phase.isScrolling && !wasScrolling
        guard began else { return }
        for item in pinched.sorted() {
            let told = tell(item) { $0.containerScrolled(at: $1) }
            apply(told, to: item, word: "container scrolled")
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

    /// Does what the watch says now, as the model's look does.
    private mutating func lookAtTheHold() {
        guard case .alarm(let alarm) = watch.verdict(at: now) else { return }
        alarms.append(alarm)
        log.append("alarm: \(alarm.line)")
        watch.raised(alarm, at: now)
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
            for other in pinched.sorted() where other != item && (pinches[other]?.isKeptUpPastItsPress ?? false) {
                let elsewhere = tell(other) { $0.pinchBeganElsewhere(at: $1) }
                apply(elsewhere, to: other, word: "pinch elsewhere")
            }
            pinched.insert(item)
            run(told.countdowns, for: item)
            if told.ended == nil {
                for action in told.actions { perform(action, for: item) }
            }
            offsetChanged(for: item)
            reportPinch(of: item)
            return
        }
        run(told.countdowns, for: item)
        for action in told.actions { perform(action, for: item) }
        if told.ended != nil { pinched.remove(item) }
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
    }

    private mutating func run(_ countdowns: [PluckPinches.Countdown], for item: String) {
        for countdown in countdowns {
            switch countdown {
            case .startHold(let duration): holdDue[item] = now + duration
            case .stopHold: holdDue[item] = nil
            case .startArming(let duration): armDue[item] = now + duration
            case .stopArming: armDue[item] = nil
            }
        }
    }

    private mutating func perform(_ action: PluckPress.Action, for item: String) {
        switch action {
        case .lift:
            let change = container.lift(item, at: now)
            if change.settled != item { watch.lifted(item, title: item, at: now) }
        case .settle:
            if container.settle(item).settled != nil { watch.settled(because: "its pinch", at: now) }
        default:
            break
        }
    }
}
