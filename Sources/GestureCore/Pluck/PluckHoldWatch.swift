/// A pluckable container's watch over its hold: the item lifted; the scroll
/// held off under it, as the watch applies it to the scroll view; whether a
/// pinch backs either; what a status line shows of them; alarms when they
/// outlive every pinch, disagree, or the scroll view doesn't take a scroll;
/// and the safety net that lets a hold go.
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
/// - **Whether the scroll is held off** (`holdsTheScroll`), the value the
///   caller gives its scroll view (`.scrollDisabled`): from the moment the
///   container holds it under a lifted item until the pinch that took it
///   lets go, its drag no longer saying it has it, even should the item
///   settle first, as it does breaking free or given back to the scroll,
///   both the drag's doing, whose end or reset comes as the pinch is let go. Turned back on while that pinch was still down, as it was at a
///   spawn from October 9, the grid's scroll view took no pinch after: Alex's
///   clip of October 10 showed every later scroll told as one by the rules,
///   the status line saying the scroll was on, and the scroll view neither
///   moving nor saying a phase. The tuning can bring it back as the item
///   settles, mid-pinch, to try that again (`scrollComesBackMidPinch`).
/// - **An alarm** once an item has stayed lifted with no pinch under way for
///   more than half a second (`alarmAfter`), once a hold: a hand let go whose
///   words never came, or one held still whose press went as its item
///   lifted, which nothing it's told can tell apart. The pluck's own rules
///   let such a lift go at that moment (`PluckTuning.quietRelease`), so the
///   alarm says they didn't.
/// - **An alarm when its views disagree** for a quarter second
///   (`disagreementAfter`): the item the container has lifted against the
///   one the watch was told lifted; the container's hold against the
///   watch's; the value the scroll view was given against the watch's hold;
///   and what the scroll view has, as a probe reads it, its scrolling and
///   its pan, against what it was given.
/// - **An alarm when the scroll view never took a scroll**: the rules told a
///   pinch as the container's scroll, and in the next 0.3 s (`scrollTakeUp`)
///   the scroll view said no phase of scrolling, nor did its pan begin.
/// - **The safety net**: the container never holds its scroll without a
///   pinch. A lift is let go at once should its item have no pinch under way
///   at all, and once nothing has been heard from its pinch for
///   `unheardLimit`, a second by default (`PluckTuning.unheardHoldRelease`),
///   whatever its gestures last said; and the scroll hold kept for a pinch
///   after its item settled once nothing has been heard from it for
///   `unheardScrollLimit`, three seconds by default. Each is an alarm too, so
///   a recurrence shows.
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

    /// What a scroll view has, as a probe of the platform's scroll view reads
    /// it: whether it scrolls, whether its pan is on, the pan's state, and
    /// whether it's tracking a touch, dragging, or coasting.
    public struct ScrollViewReading: Equatable, Sendable {
        public var scrollEnabled: Bool
        public var panEnabled: Bool
        public var panState: String
        public var tracking: Bool
        public var dragging: Bool
        public var decelerating: Bool

        public init(scrollEnabled: Bool, panEnabled: Bool, panState: String, tracking: Bool, dragging: Bool, decelerating: Bool) {
            self.scrollEnabled = scrollEnabled
            self.panEnabled = panEnabled
            self.panState = panState
            self.tracking = tracking
            self.dragging = dragging
            self.decelerating = decelerating
        }

        /// Whether it can take a pinch to scroll: its scrolling and its pan
        /// on.
        public var takesScrolls: Bool { scrollEnabled && panEnabled }

        /// The reading in a few words: "scrolling on, pan on, pan possible".
        public var description: String {
            var parts = [scrollEnabled ? "scrolling on" : "scrolling off", panEnabled ? "pan on" : "pan off", "pan \(panState)"]
            if tracking { parts.append("tracking") }
            if dragging { parts.append("dragging") }
            if decelerating { parts.append("coasting") }
            return parts.joined(separator: ", ")
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
            /// The safety net let go of an item that stayed lifted with
            /// nothing heard from its pinch for `unheardLimit`, whatever its
            /// gestures last said.
            case letGoWithNothingHeard
            /// The safety net let go of an item that stayed lifted with no
            /// pinch under way on it at all.
            case letGoWithNoPinchOnIt
            /// The safety net let the scroll go, held for a pinch whose item
            /// had settled, with nothing heard from it for
            /// `unheardScrollLimit`.
            case scrollLetGoWithNothingHeard
            /// What the container, the watch, the value the scroll view was
            /// given, or the scroll view itself say of the hold disagreed for
            /// `disagreementAfter`.
            case viewsDisagree
            /// The rules told a pinch as the container's scroll, and the
            /// scroll view said no phase of scrolling, nor did its pan begin,
            /// within `scrollTakeUp`.
            case scrollViewNeverTookIt

            /// Whether the safety net let the hold go.
            public var letsGo: Bool {
                switch self {
                case .letGoWithNothingHeard, .letGoWithNoPinchOnIt, .scrollLetGoWithNothingHeard: true
                case .heldWithNoPinchUnderWay, .viewsDisagree, .scrollViewNeverTookIt: false
                }
            }
        }

        public var kind: Kind
        /// The item it's about: the one held lifted, the scroll held for, or
        /// the one whose pinch was told as a scroll.
        public var title: String
        /// How long the hold had lasted, or since the pinch was told as a
        /// scroll; zero with neither.
        public var heldFor: Duration
        /// How long no pinch had been under way; zero while one was.
        public var unclaimedFor: Duration
        /// How long since a gesture last spoke on the hold's pinch, its lift
        /// included; zero with no hold.
        public var unheardFor: Duration
        /// The pinch on the item, as its rules last said; nil if none was
        /// under way.
        public var pinch: Pinch?
        /// What disagreed, or the state, in words.
        public var detail: String?

        public init(
            kind: Kind,
            title: String,
            heldFor: Duration,
            unclaimedFor: Duration,
            unheardFor: Duration,
            pinch: Pinch?,
            detail: String? = nil
        ) {
            self.kind = kind
            self.title = title
            self.heldFor = heldFor
            self.unclaimedFor = unclaimedFor
            self.unheardFor = unheardFor
            self.pinch = pinch
            self.detail = detail
        }

        /// The alarm in a line: "Scroll held by item 7 for 0.62 s with no
        /// pinch under way for 0.55 s; its pinch: item 7: press up, …".
        public var line: String {
            let pinchText = pinch.map { "its pinch: \($0.description)" } ?? "no pinch on it under way"
            switch kind {
            case .heldWithNoPinchUnderWay:
                return "Scroll held by \(title) for \(pluckWatchSeconds(heldFor)) s with no pinch under way for \(pluckWatchSeconds(unclaimedFor)) s; \(pinchText)"
            case .letGoWithNothingHeard:
                return "Scroll held by \(title) for \(pluckWatchSeconds(heldFor)) s with nothing heard from its pinch for \(pluckWatchSeconds(unheardFor)) s, let go by the safety net; \(pinchText)"
            case .letGoWithNoPinchOnIt:
                return "Scroll held by \(title) for \(pluckWatchSeconds(heldFor)) s with no pinch on it, let go by the safety net"
            case .scrollLetGoWithNothingHeard:
                return "Scroll held for the pinch on \(title), its item down, for \(pluckWatchSeconds(heldFor)) s with nothing heard from it for \(pluckWatchSeconds(unheardFor)) s, let go by the safety net; \(pinchText)"
            case .viewsDisagree:
                return "The hold's views disagree: \(detail ?? "")"
            case .scrollViewNeverTookIt:
                return "The scroll view never took the scroll of the pinch on \(title): no phase of scrolling, nor its pan begun, \(pluckWatchSeconds(heldFor)) s after the rules told it as one; \(detail ?? "")"
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
        /// Let a hold go, the safety net: raise the alarm as for `alarm`;
        /// let the scroll go (`releaseTheScroll(because:at:)`); settle the
        /// held item, if one is, through the container, tell the watch so
        /// (`settled(because:at:)`), and tell the item's pinch its container
        /// settled it.
        case letGo(Alarm)
    }

    /// How long an item may stay lifted with no pinch under way before the
    /// watch raises its alarm: half a second, as long as a hand takes to let
    /// go and pinch again to scroll.
    public static var alarmAfter: Duration { .milliseconds(500) }

    /// How long its views may disagree before it raises the alarm: a quarter
    /// second, past a frame or two for the value given to reach the scroll
    /// view.
    public static var disagreementAfter: Duration { .milliseconds(250) }

    /// How long after the rules tell a pinch as the container's scroll the
    /// scroll view has to say it scrolls: 0.3 s. A flick the scroll view took
    /// on the headset was coasting before its pinch's 0.11 s were out.
    public static var scrollTakeUp: Duration { .milliseconds(300) }

    /// How many of the things it was told it keeps.
    public static var eventsKept: Int { 10 }

    /// How long a hold may last with nothing heard from its pinch before the
    /// safety net lets it go, whatever its gestures last said: a second
    /// unless the caller sets it from its tuning
    /// (`PluckTuning.unheardHoldRelease`).
    public var unheardLimit: Duration = .seconds(1)

    /// How long the scroll may stay held for a pinch whose item settled, as
    /// a carry's, with nothing heard from it, before the safety net lets it
    /// go: three seconds unless the caller sets it from its tuning
    /// (`PluckTuning.unheardScrollHoldRelease`). Longer than a lift's, as
    /// letting it go while that pinch is still down is what to avoid.
    public var unheardScrollLimit: Duration = .seconds(3)

    /// Whether the scroll comes back as its item settles, mid-pinch, rather
    /// than once the pinch that took it lets go: off unless the caller sets
    /// it from its tuning (`PluckTuning.scrollComesBackMidPinch`).
    public var scrollComesBackMidPinch = false

    // MARK: The lift

    /// The item held lifted, as the watch was told, and its title; nil while
    /// none is.
    public private(set) var heldItem: Item?
    public private(set) var heldTitle: String?
    /// When it lifted; nil while none is.
    public private(set) var heldSince: ContinuousClock.Instant?

    // MARK: The scroll hold

    /// The item whose pinch took the scroll hold, which keeps it until that
    /// pinch lets go, and its title; nil while the scroll is on.
    public private(set) var scrollHeldFor: Item?
    public private(set) var scrollHeldTitle: String?
    /// When the hold was taken.
    public private(set) var scrollHeldSince: ContinuousClock.Instant?

    /// Whether the scroll is held off: what the caller gives its scroll view.
    public var holdsTheScroll: Bool { scrollHeldFor != nil }

    // MARK: What the others say

    /// Whether the container says it holds its scroll, and the item it has
    /// lifted, as last told.
    public private(set) var containerHolds = false
    public private(set) var containerLifted: Item?
    /// What the scroll view was given: whether it's held off; nil until told.
    public private(set) var scrollGiven: Bool?
    /// What the scroll view has, as a probe last read it; nil without one.
    public private(set) var scrollView: ScrollViewReading?
    /// The scroll view's last phase, and when it said it.
    public private(set) var lastPhase: PluckScrollPhase?
    public private(set) var lastPhaseAt: ContinuousClock.Instant?
    /// When the scroll view last scrolled: a phase of scrolling, or its pan
    /// beginning.
    public private(set) var lastScrolledAt: ContinuousClock.Instant?

    // MARK: Its own

    /// When a gesture last spoke on the pinch of the held item, or of the one
    /// the scroll is held for, its lift included.
    public private(set) var lastHeard: ContinuousClock.Instant?
    /// The pinches under way, by item, as their rules last said.
    public private(set) var pinches: [Item: Pinch] = [:]
    /// Since when an item has been held with no pinch under way; nil while
    /// one is, or none is held.
    public private(set) var unclaimedSince: ContinuousClock.Instant?
    /// What its views disagree on, and since when; nil while they agree.
    public private(set) var disagreement: String?
    public private(set) var disagreementSince: ContinuousClock.Instant?
    /// The item whose pinch the rules last told as a scroll, and when, while
    /// the scroll view hasn't said it took it.
    public private(set) var scrollRulingTitle: String?
    public private(set) var scrollRulingAt: ContinuousClock.Instant?
    /// How many alarms it has raised.
    public private(set) var alarms = 0
    /// The last alarm it raised, in a line.
    public private(set) var lastAlarm: String?
    /// The last things it was told, oldest first.
    public private(set) var events: [Event] = []
    /// Whether it has raised its alarm for the hold under way.
    private var alarmedThisHold = false
    /// Whether it has raised its alarm for the disagreement under way.
    private var alarmedThisDisagreement = false

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

    /// `item`, titled `title`, lifted at `now`; one lifted in another's place
    /// begins a hold of its own.
    public mutating func lifted(_ item: Item, title: String, at now: ContinuousClock.Instant) {
        heldItem = item
        heldTitle = title
        heldSince = now
        lastHeard = now
        alarmedThisHold = false
        note("\(title) lifted", at: now)
        update(at: now)
    }

    /// The held item settled at `now`, for the reason given. The scroll
    /// stays held should the pinch that took it still have it.
    public mutating func settled(because reason: String, at now: ContinuousClock.Instant) {
        guard let title = heldTitle else { return }
        note("\(title) settled: \(reason)", at: now)
        heldItem = nil
        heldTitle = nil
        heldSince = nil
        alarmedThisHold = false
        update(at: now)
    }

    /// The container says it holds its scroll, `holds`, or not, with `lifted`
    /// up, at `now`.
    public mutating func container(holds: Bool, lifted: Item?, at now: ContinuousClock.Instant) {
        guard holds != containerHolds || lifted != containerLifted else { return }
        containerHolds = holds
        containerLifted = lifted
        update(at: now)
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
        update(at: now)
    }

    /// A gesture on `item`, titled `title`, spoke at `now`: `word`, kept as
    /// one of the last things told, or, for a drag's every move, nil, which
    /// only notes the time.
    public mutating func heard(_ word: String?, from item: Item, title: String, at now: ContinuousClock.Instant) {
        if item == heldItem || item == scrollHeldFor { lastHeard = now }
        if let word { note("\(title): \(word)", at: now) }
    }

    /// The rules told the pinch on the item titled `title` as the container's
    /// scroll, at `now`: should the scroll view say no phase of scrolling, nor
    /// its pan begin, within `scrollTakeUp`, the alarm says it never took it.
    /// One told while the scroll view scrolls already, or while another
    /// awaits, changes nothing.
    public mutating func ruledAScroll(on title: String, at now: ContinuousClock.Instant) {
        if let lastScrolledAt, now - lastScrolledAt < Self.scrollTakeUp { return }
        guard scrollRulingAt == nil else { return }
        scrollRulingTitle = title
        scrollRulingAt = now
        note("\(title): told as a scroll", at: now)
    }

    /// The scroll view said `phase`, at `now`.
    public mutating func scrollViewSaid(_ phase: PluckScrollPhase, at now: ContinuousClock.Instant) {
        lastPhase = phase
        lastPhaseAt = now
        if phase.isScrolling { scrolled(at: now) }
        note("scroll \(phase.rawValue)", at: now)
    }

    /// The scroll view was given `heldOff`, as the caller handed it, at
    /// `now`.
    public mutating func scrollGiven(heldOff: Bool, at now: ContinuousClock.Instant) {
        guard scrollGiven != heldOff else { return }
        scrollGiven = heldOff
        note("the scroll view given \(heldOff ? "held off" : "on")", at: now)
        updateDisagreement(at: now)
    }

    /// A probe read the scroll view as `reading`, at `now`; its pan began,
    /// `panBegan`, should it have.
    public mutating func scrollViewRead(_ reading: ScrollViewReading, panBegan: Bool = false, at now: ContinuousClock.Instant) {
        if panBegan { scrolled(at: now) }
        guard scrollView != reading else { return }
        scrollView = reading
        note("the scroll view: \(reading.description)", at: now)
        updateDisagreement(at: now)
    }

    /// The safety net let the scroll go, at `now`: it's on, whatever any
    /// pinch says.
    public mutating func releaseTheScroll(because reason: String, at now: ContinuousClock.Instant) {
        guard scrollHeldFor != nil else { return }
        releaseScroll(because: reason, at: now)
        updateDisagreement(at: now)
    }

    /// Something else happened at `now`, kept as one of the last things told.
    public mutating func note(_ what: String, at now: ContinuousClock.Instant) {
        events.append(Event(at: now, what: what))
        if events.count > Self.eventsKept { events.removeFirst(events.count - Self.eventsKept) }
    }

    // MARK: What it says

    /// What the caller does at `now`: let a hold go, should the held item
    /// have no pinch under way, or nothing have been heard from its pinch for
    /// `unheardLimit`, or the scroll be held for a pinch whose item settled
    /// and nothing have been heard from it for as long; else raise an alarm:
    /// an item lifted with no pinch under way for more than `alarmAfter`,
    /// once a hold; views disagreeing for `disagreementAfter`; or a pinch
    /// told as a scroll the scroll view hasn't taken in `scrollTakeUp`;
    /// nothing otherwise.
    public func verdict(at now: ContinuousClock.Instant) -> Verdict {
        if let heldItem, let heldSince, let title = heldTitle {
            let unheardFor = now - (lastHeard ?? heldSince)
            let alarm = { (kind: Alarm.Kind) in
                Alarm(
                    kind: kind,
                    title: title,
                    heldFor: now - heldSince,
                    unclaimedFor: self.unclaimedSince.map { now - $0 } ?? .zero,
                    unheardFor: unheardFor,
                    pinch: self.pinches[heldItem]
                )
            }
            if pinches[heldItem] == nil {
                return .letGo(alarm(.letGoWithNoPinchOnIt))
            }
            if unheardFor >= unheardLimit {
                return .letGo(alarm(.letGoWithNothingHeard))
            }
        } else if let scrollHeldFor, let scrollHeldSince {
            let unheardFor = now - (lastHeard ?? scrollHeldSince)
            if unheardFor >= unheardScrollLimit {
                return .letGo(Alarm(
                    kind: .scrollLetGoWithNothingHeard,
                    title: scrollHeldTitle ?? "an item",
                    heldFor: now - scrollHeldSince,
                    unclaimedFor: .zero,
                    unheardFor: unheardFor,
                    pinch: pinches[scrollHeldFor]
                ))
            }
        }
        if !alarmedThisHold, let heldItem, let heldSince, let title = heldTitle,
           let unclaimedSince, now - unclaimedSince > Self.alarmAfter {
            return .alarm(Alarm(
                kind: .heldWithNoPinchUnderWay,
                title: title,
                heldFor: now - heldSince,
                unclaimedFor: now - unclaimedSince,
                unheardFor: now - (lastHeard ?? heldSince),
                pinch: pinches[heldItem]
            ))
        }
        if !alarmedThisDisagreement, let disagreement, let disagreementSince, now - disagreementSince >= Self.disagreementAfter {
            return .alarm(Alarm(
                kind: .viewsDisagree,
                title: heldTitle ?? scrollHeldTitle ?? "no item",
                heldFor: .zero,
                unclaimedFor: .zero,
                unheardFor: .zero,
                pinch: nil,
                detail: disagreement
            ))
        }
        if let scrollRulingAt, let scrollRulingTitle, now - scrollRulingAt >= Self.scrollTakeUp {
            return .alarm(Alarm(
                kind: .scrollViewNeverTookIt,
                title: scrollRulingTitle,
                heldFor: now - scrollRulingAt,
                unclaimedFor: .zero,
                unheardFor: .zero,
                pinch: nil,
                detail: stateLine(at: now)
            ))
        }
        return .fine
    }

    /// When the caller asks again (`verdict(at:)`) for something it might
    /// say: the soonest of the safety net's time and each alarm's, while one
    /// may come; nil while none can. Each word heard puts the net's time off,
    /// so a caller that looks then and finds nothing due looks again at this.
    public var nextCheck: ContinuousClock.Instant? {
        var times: [ContinuousClock.Instant] = []
        if let heldSince {
            times.append((lastHeard ?? heldSince) + unheardLimit)
            if !alarmedThisHold, let unclaimedSince { times.append(unclaimedSince + Self.alarmAfter) }
        } else if let scrollHeldSince {
            times.append((lastHeard ?? scrollHeldSince) + unheardScrollLimit)
        }
        if !alarmedThisDisagreement, let disagreementSince { times.append(disagreementSince + Self.disagreementAfter) }
        if let scrollRulingAt { times.append(scrollRulingAt + Self.scrollTakeUp) }
        return times.min()
    }

    /// The alarm raised at `now`: it's counted, and the same alarm isn't
    /// raised again for what it's about.
    public mutating func raised(_ alarm: Alarm, at now: ContinuousClock.Instant) {
        alarms += 1
        lastAlarm = alarm.line
        switch alarm.kind {
        case .heldWithNoPinchUnderWay, .letGoWithNothingHeard, .letGoWithNoPinchOnIt, .scrollLetGoWithNothingHeard:
            alarmedThisHold = true
        case .viewsDisagree:
            alarmedThisDisagreement = true
        case .scrollViewNeverTookIt:
            scrollRulingTitle = nil
            scrollRulingAt = nil
        }
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

    /// The state in a line, for an alarm: the scroll hold and what each view
    /// says of it, the scroll view's last phase, and the pinch under way.
    public func stateLine(at now: ContinuousClock.Instant) -> String {
        var parts: [String] = []
        if let scrollHeldTitle, let scrollHeldSince {
            parts.append("scroll held off for \(scrollHeldTitle) for \(pluckWatchSeconds(now - scrollHeldSince)) s")
        } else {
            parts.append("scroll on")
        }
        parts.append("given \(scrollGiven.map { $0 ? "held off" : "on" } ?? "nothing yet")")
        parts.append("container \(containerHolds ? "holds" : "doesn't hold"), \(containerLifted == nil ? "nothing lifted" : "an item lifted")")
        if let heldTitle, let heldSince {
            parts.append("\(heldTitle) lifted for \(pluckWatchSeconds(now - heldSince)) s")
        } else {
            parts.append("nothing lifted")
        }
        if let lastHeard, holdsTheScroll || heldItem != nil {
            parts.append("its pinch last heard \(pluckWatchSeconds(now - lastHeard)) s ago")
        }
        if let scrollView { parts.append("scroll view \(scrollView.description)") }
        if let lastPhase, let lastPhaseAt {
            parts.append("last phase \(lastPhase.rawValue) \(pluckWatchSeconds(now - lastPhaseAt)) s ago")
        } else {
            parts.append("no phase yet")
        }
        parts.append(shownPinch.map { "pinch on \($0.description)" } ?? "no pinch")
        return parts.joined(separator: "; ")
    }

    // MARK: Keeping it

    /// Takes the scroll hold as the container takes its own, and lets it go
    /// once the container no longer holds and the pinch that took it lets go,
    /// or at once, should the tuning bring the scroll back mid-pinch; then
    /// notes what's under way.
    private mutating func update(at now: ContinuousClock.Instant) {
        if containerHolds {
            if let item = heldItem ?? containerLifted, item != scrollHeldFor {
                scrollHeldFor = item
                scrollHeldTitle = item == heldItem ? heldTitle : nil
                scrollHeldSince = now
                if lastHeard == nil { lastHeard = now }
                note("the scroll held off for \(scrollHeldTitle ?? "an item")", at: now)
            } else if scrollHeldTitle == nil, scrollHeldFor == heldItem {
                scrollHeldTitle = heldTitle
            }
        } else if let item = scrollHeldFor {
            // Down while its drag has it: what settles an item mid-pinch, a
            // break-free or a give-back, is the drag's, whose end or reset
            // comes as the pinch is let go. A press alone may end at the lift,
            // or its end go unheard, so it keeps no scroll held.
            let stillDown = !scrollComesBackMidPinch && (pinches[item]?.dragHasIt ?? false)
            if !stillDown {
                releaseScroll(because: pinches[item] == nil ? "its pinch is over" : "its pinch let go", at: now)
            }
        }
        if heldItem == nil, scrollHeldFor == nil { lastHeard = nil }
        if heldItem != nil, !isPinchUnderWay {
            unclaimedSince = unclaimedSince ?? now
        } else {
            unclaimedSince = nil
        }
        updateDisagreement(at: now)
    }

    private mutating func releaseScroll(because reason: String, at now: ContinuousClock.Instant) {
        note("the scroll on again: \(reason)", at: now)
        scrollHeldFor = nil
        scrollHeldTitle = nil
        scrollHeldSince = nil
        if heldItem == nil { lastHeard = nil }
    }

    /// The scroll view scrolled at `now`: a pinch told as a scroll was taken.
    private mutating func scrolled(at now: ContinuousClock.Instant) {
        lastScrolledAt = now
        scrollRulingTitle = nil
        scrollRulingAt = nil
    }

    /// Notes what its views disagree on, and since when.
    private mutating func updateDisagreement(at now: ContinuousClock.Instant) {
        var found: [String] = []
        if heldItem != containerLifted {
            found.append(heldItem == nil
                ? "the container has an item lifted, the watch none"
                : "the container has \(containerLifted == nil ? "nothing" : "another item") lifted, the watch \(heldTitle ?? "an item")")
        }
        if containerHolds, !holdsTheScroll {
            found.append("the container holds its scroll, the watch doesn't")
        }
        if let scrollGiven, scrollGiven != holdsTheScroll {
            found.append("the scroll view was given \(scrollGiven ? "held off" : "on"), the watch has it \(holdsTheScroll ? "held off" : "on")")
        }
        if let scrollGiven, let scrollView, scrollView.takesScrolls == scrollGiven {
            found.append("the scroll view was given \(scrollGiven ? "held off" : "on"), and has \(scrollView.description)")
        }
        guard !found.isEmpty else {
            disagreement = nil
            disagreementSince = nil
            alarmedThisDisagreement = false
            return
        }
        if disagreement == nil { disagreementSince = now }
        disagreement = found.joined(separator: "; ")
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
