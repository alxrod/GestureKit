/// A pluckable container's watch over its hold: the item lifted, and with it
/// the scroll held off (`PluckContainer`), and whether a pinch backs it; what
/// a status line shows of it; and an alarm when the hold outlives every
/// pinch.
///
/// A lifted item holds its container's scroll off until its pinch says it's
/// let go. Should the words that say so never come, the hold outlives the
/// pinch, and the next pinch, meeting the scroll off as it touches, can't
/// scroll, as Alex found on October 9: "If you pluck one item, then try
/// scrolling again sometimes you can get stuck unable to scroll." The watch
/// is told what the container and its items' pinches do, with the time, and
/// says:
///
/// - **Whether a pinch is under way**: an item's pinch has a gesture that
///   says it has the pinch, its press down or its drag speaking and not yet
///   ended or cancelled (`Pinch.isClaimed`). A pinch whose press has ended
///   and whose drag is silent is under way only as far as its rules know,
///   as one kept up past its press is: no gesture says it's still pinched.
/// - **An alarm** once an item has stayed lifted with no pinch under way for
///   more than half a second (`alarmAfter`), once a hold: a hand let go whose
///   words never came, or one held still whose press went as its item
///   lifted, which nothing it's told can tell apart. Or once nothing has been
///   heard from the held item's pinch for a second (`unheardAlarmAfter`),
///   whatever its gestures last said: a hand held still, or a gesture whose
///   end went unheard and so still says it has the pinch.
///
/// It keeps the last ten things it was told, for an alarm's lines, and is
/// cheap to tell a drag's every word (`heard(_:from:title:at:)` with no
/// word), which only notes the time.
public struct PluckHoldWatch<Item: Hashable> {
    /// One item's pinch, as its rules last said: what it's on, whether its
    /// press is down, whether its drag has it, and whether it holds its item
    /// lifted.
    public struct Pinch: Equatable, Sendable {
        public var title: String
        public var pressIsDown: Bool
        public var dragHasIt: Bool
        public var holdsItsItem: Bool

        public init(title: String, pressIsDown: Bool, dragHasIt: Bool, holdsItsItem: Bool) {
            self.title = title
            self.pressIsDown = pressIsDown
            self.dragHasIt = dragHasIt
            self.holdsItsItem = holdsItsItem
        }

        /// Whether a gesture says it has the pinch: its press is down, or its
        /// drag has it.
        public var isClaimed: Bool { pressIsDown || dragHasIt }

        /// The pinch in a few words: "item 7: press down, drag silent, its
        /// item lifted".
        public var description: String {
            let press = pressIsDown ? "press down" : "press up"
            let drag = dragHasIt ? "drag has it" : "drag silent or ended"
            let item = holdsItsItem ? (isClaimed ? "its item lifted" : "its item kept up past its press") : "its item down"
            return "\(title): \(press), \(drag), \(item)"
        }
    }

    /// One thing the watch was told: when, and what, in words.
    public struct Event: Equatable, Sendable {
        public var at: ContinuousClock.Instant
        public var what: String
    }

    /// What the watch found wrong.
    public struct Alarm: Equatable, Sendable {
        /// Which wrong it found.
        public enum Kind: String, Equatable, Sendable {
            /// An item stayed lifted, its container's scroll held, with no
            /// pinch under way, past `alarmAfter`.
            case heldWithNoPinchUnderWay
            /// An item stayed lifted with nothing heard from its pinch for
            /// `unheardAlarmAfter`, whatever its gestures last said.
            case heldWithNothingHeard
        }

        public var kind: Kind
        /// The item held lifted.
        public var title: String
        /// How long it had been held.
        public var heldFor: Duration
        /// How long no pinch had been under way; zero while one was.
        public var unclaimedFor: Duration
        /// How long since a gesture last spoke on its pinch, its lift
        /// included.
        public var unheardFor: Duration
        /// The pinch on the held item, as its rules last said; nil if none
        /// was under way.
        public var pinch: Pinch?

        /// The alarm in a line: "Scroll held by item 7 for 0.62 s with no
        /// pinch under way for 0.55 s; its pinch: item 7: press up, …".
        public var line: String {
            let pinchText = pinch.map { "its pinch: \($0.description)" } ?? "no pinch on it under way"
            switch kind {
            case .heldWithNoPinchUnderWay:
                return "Scroll held by \(title) for \(pluckWatchSeconds(heldFor)) s with no pinch under way for \(pluckWatchSeconds(unclaimedFor)) s; \(pinchText)"
            case .heldWithNothingHeard:
                return "Scroll held by \(title) for \(pluckWatchSeconds(heldFor)) s with nothing heard from its pinch for \(pluckWatchSeconds(unheardFor)) s; \(pinchText)"
            }
        }
    }

    /// What the caller does now, as the watch sees it.
    public enum Verdict: Equatable, Sendable {
        /// Nothing.
        case fine
        /// Raise the alarm: trace it and log it (`alarmLines(for:at:)`), then
        /// tell the watch it's raised (`raised(_:at:)`).
        case alarm(Alarm)
    }

    /// How long an item may stay lifted with no pinch under way before the
    /// watch raises its alarm: half a second, as long as a hand takes to let
    /// go and pinch again to scroll.
    public static var alarmAfter: Duration { .milliseconds(500) }

    /// How many of the things it was told it keeps.
    public static var eventsKept: Int { 10 }

    /// How long an item may stay lifted with nothing heard from its pinch
    /// before the watch raises its alarm, whatever its gestures last said: a
    /// second, twice as long as a hand pulling an item out goes without a
    /// word.
    public var unheardAlarmAfter: Duration = .seconds(1)

    /// The item held lifted, and its title; nil while none is.
    public private(set) var heldItem: Item?
    public private(set) var heldTitle: String?
    /// When it lifted; nil while none is.
    public private(set) var heldSince: ContinuousClock.Instant?
    /// When a gesture last spoke on the held item's pinch, its lift included.
    public private(set) var lastHeard: ContinuousClock.Instant?
    /// The pinches under way, by item, as their rules last said.
    public private(set) var pinches: [Item: Pinch] = [:]
    /// Since when an item has been held with no pinch under way; nil while
    /// one is, or none is held.
    public private(set) var unclaimedSince: ContinuousClock.Instant?
    /// How many alarms it has raised.
    public private(set) var alarms = 0
    /// The last alarm it raised, in a line.
    public private(set) var lastAlarm: String?
    /// The last things it was told, oldest first.
    public private(set) var events: [Event] = []
    /// Whether it has raised its alarm for the hold under way.
    private var alarmedThisHold = false

    public init() {}

    /// Whether a pinch is under way: a gesture says it has one.
    public var isPinchUnderWay: Bool {
        pinches.values.contains(where: \.isClaimed)
    }

    /// The pinch that says it's under way, or else any the rules keep, for a
    /// status line.
    public var shownPinch: Pinch? {
        pinches.values.first(where: \.isClaimed) ?? pinches.values.first
    }

    // MARK: What it's told

    /// `item`, titled `title`, lifted at `now`, holding its container's
    /// scroll as the container's tuning says; one lifted in another's place
    /// begins a hold of its own.
    public mutating func lifted(_ item: Item, title: String, at now: ContinuousClock.Instant) {
        heldItem = item
        heldTitle = title
        heldSince = now
        lastHeard = now
        alarmedThisHold = false
        note("\(title) lifted, the scroll held", at: now)
        updateUnclaimed(at: now)
    }

    /// The held item settled at `now`, for the reason given.
    public mutating func settled(because reason: String, at now: ContinuousClock.Instant) {
        guard let title = heldTitle else { return }
        note("\(title) settled, the scroll on: \(reason)", at: now)
        heldItem = nil
        heldTitle = nil
        heldSince = nil
        lastHeard = nil
        alarmedThisHold = false
        updateUnclaimed(at: now)
    }

    /// `item`'s pinch is `pinch` now, as its rules say, or over, nil.
    public mutating func pinch(_ item: Item, is pinch: Pinch?, at now: ContinuousClock.Instant) {
        guard pinches[item] != pinch else { return }
        if let pinch {
            if pinches[item] == nil { note("pinch on \(pinch.title) began", at: now) }
            pinches[item] = pinch
        } else if let ended = pinches.removeValue(forKey: item) {
            note("pinch on \(ended.title) over", at: now)
        }
        updateUnclaimed(at: now)
    }

    /// A gesture on `item`, titled `title`, spoke at `now`: `word`, kept as
    /// one of the last things told, or, for a drag's every move, nil, which
    /// only notes the time.
    public mutating func heard(_ word: String?, from item: Item, title: String, at now: ContinuousClock.Instant) {
        if item == heldItem { lastHeard = now }
        if let word { note("\(title): \(word)", at: now) }
    }

    /// Something else happened at `now`, as the container's scroll changing
    /// phase, kept as one of the last things told.
    public mutating func note(_ what: String, at now: ContinuousClock.Instant) {
        events.append(Event(at: now, what: what))
        if events.count > Self.eventsKept { events.removeFirst(events.count - Self.eventsKept) }
    }

    // MARK: What it says

    /// What the caller does at `now`: raise the alarm once an item has stayed
    /// lifted with no pinch under way for more than `alarmAfter`, once a
    /// hold; nothing otherwise.
    public func verdict(at now: ContinuousClock.Instant) -> Verdict {
        guard let heldSince, let title = heldTitle, let heldItem, !alarmedThisHold else { return .fine }
        let unheardFor = now - (lastHeard ?? heldSince)
        let kind: Alarm.Kind
        if let unclaimedSince, now - unclaimedSince > Self.alarmAfter {
            kind = .heldWithNoPinchUnderWay
        } else if unheardFor >= unheardAlarmAfter {
            kind = .heldWithNothingHeard
        } else {
            return .fine
        }
        return .alarm(Alarm(
            kind: kind,
            title: title,
            heldFor: now - heldSince,
            unclaimedFor: unclaimedSince.map { now - $0 } ?? .zero,
            unheardFor: unheardFor,
            pinch: pinches[heldItem]
        ))
    }

    /// When the caller asks again (`verdict(at:)`) for something it might
    /// say: the soonest alarm's time, while one may come; nil while nothing
    /// can. Each word heard puts the second alarm's time off, so a caller
    /// that looks then and finds nothing due looks again at this.
    public var nextCheck: ContinuousClock.Instant? {
        guard let heldSince, !alarmedThisHold else { return nil }
        let unheard = (lastHeard ?? heldSince) + unheardAlarmAfter
        guard let unclaimedSince else { return unheard }
        return min(unclaimedSince + Self.alarmAfter, unheard)
    }

    /// The alarm raised at `now`: it's counted, and none is raised again for
    /// this hold.
    public mutating func raised(_ alarm: Alarm, at now: ContinuousClock.Instant) {
        alarms += 1
        alarmedThisHold = true
        lastAlarm = alarm.line
        note("alarm: \(alarm.kind.rawValue)", at: now)
    }

    /// An alarm's lines for a trace, at `now`: the state, then the last ten
    /// things told, oldest first, each with how long before `now` it came.
    public func alarmLines(for alarm: Alarm, at now: ContinuousClock.Instant) -> [(name: String, detail: String)] {
        var lines: [(name: String, detail: String)] = [("state", stateLine(at: now))]
        for (index, event) in events.enumerated() {
            lines.append(("event \(index + 1)", "-\(pluckWatchSeconds(now - event.at)) s: \(event.what)"))
        }
        return lines
    }

    /// The state in a line, for a status line or an alarm: what's held and
    /// for how long, and the pinch under way.
    public func stateLine(at now: ContinuousClock.Instant) -> String {
        var parts: [String] = []
        if let heldTitle, let heldSince {
            parts.append("scroll held by \(heldTitle) for \(pluckWatchSeconds(now - heldSince)) s")
            if let lastHeard { parts.append("its pinch last heard \(pluckWatchSeconds(now - lastHeard)) s ago") }
        } else {
            parts.append("scroll on")
        }
        if let pinch = shownPinch {
            parts.append("pinch on \(pinch.description)")
        } else {
            parts.append("no pinch")
        }
        return parts.joined(separator: "; ")
    }

    /// Notes since when an item has been held with no pinch under way.
    private mutating func updateUnclaimed(at now: ContinuousClock.Instant) {
        if heldItem != nil, !isPinchUnderWay {
            unclaimedSince = unclaimedSince ?? now
        } else {
            unclaimedSince = nil
        }
    }
}

extension PluckHoldWatch: Sendable where Item: Sendable {}

/// A duration in seconds, to two decimals, without Foundation's formatting:
/// "0.62".
private func pluckWatchSeconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    let hundredths = Int(((Double(seconds) + Double(attoseconds) / 1e18) * 100).rounded())
    let sign = hundredths < 0 ? "-" : ""
    let whole = abs(hundredths) / 100
    let fraction = abs(hundredths) % 100
    return "\(sign)\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
}
