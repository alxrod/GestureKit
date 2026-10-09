/// An item's pinches, one at a time, as its hold's press, its pull's drag,
/// and its tap tell them: each pinch told by `PluckPress`, from the first
/// word of either to the last; the countdowns the caller runs, the hold's
/// and the arming's; an account of each pinch as it ends, for a trace or a
/// log; and the item's tap taken as the release of a pinch that lifted its
/// item, which is no tap. The caller gives the time of each word, so its
/// tests step a clock of their own.
///
/// - **A pinch begins** with its hold's press, or its drag's first word,
///   should that come first, and the hold counts from then
///   (`Countdown.startHold`), unless that first word, past the hold's
///   stillness, makes it a scroll. A
///   press while the drag has the pinch under way is the press coming back
///   to the item, as the hand moved off it and back, or joining the pinch
///   the drag began, and no new pinch. A press while a pinch is under way
///   that the drag doesn't have ends that one, its end unseen, its item let
///   down, so a press whose end went unheard never keeps an item lifted,
///   nor its container's scroll off.
/// - **Its hold** comes as the caller's count says, and lifts the item if
///   the press or the drag still has the pinch and the container didn't
///   scroll during it; a pinch let go before then, or moved past the hold's
///   stillness first, lifts nothing.
/// - **Lifted, it's held**: its item follows the hand a little on its
///   tether, short of breaking free (`stretch`, `PluckTether`).
/// - **Its pull arms** once `pullArmDelay` has passed since its item
///   lifted, as the caller's count says (`armPull(at:)`), or the drag's
///   next word, should the count be late; then a move far enough breaks the
///   item free, and it spawns, the rest of the pinch carrying what spawned
///   (`PluckHandoff`).
/// - **It's over** once neither gesture has it and its item is down: as
///   the pull's drag ends after a scroll or a spawn, or as the hold's press
///   ends after it came, the item's lift or a hold after the container
///   scrolled. One let go before its hold, which no move told as a scroll,
///   waits for its tap, which comes as it's let go, unless it came already:
///   a pinch let go before its hold is the item's tap. One whose tap never
///   comes, as one cancelled, or let go past the item's reach, is told as
///   the next pinch begins, or its item goes, its end unseen.
/// - **Its release tap.** The item's tap fires as a pinch is let go, before
///   or after its gestures end. A pinch that lifted its item swallows it
///   (`PluckPress.swallowsReleaseTap`), while it's under way, or within
///   `releaseTapGrace` of its end, once; the next pinch's touch ends that
///   wait.
/// - **Its item going** mid-pinch takes its pull away and lets it down.
public struct PluckPinches: Sendable {
    /// What a pinch was, as it ended, for a trace or a log: whether a scroll
    /// begun on an item ever lifts it, and whether a hold, its lift, its
    /// pull's arming, and its settling came as they should.
    public struct Account: Equatable, Sendable {
        /// What a pinch became.
        public enum Outcome: String, Sendable, Codable {
            /// Let go before anything else: the item's tap.
            case tap
            /// Its container scrolled during it, or its drag moved past the
            /// hold's stillness before its hold: the container's scroll, or
            /// nothing.
            case scroll
            /// Its hold lifted the item, and it pulled nothing.
            case lift
            /// It pulled the item out.
            case pull
            /// None of those: cancelled, or its end went unseen.
            case nothing
        }

        /// How a pinch ended.
        public enum Ending: String, Sendable, Codable {
            /// Let go: its gestures ended, or its tap came.
            case letGo
            /// Its drag was cancelled.
            case cancelled
            /// Unseen: the next pinch began, its tap never having come.
            case unseen
            /// Its item went, as it left its container.
            case itemWent
        }

        public var outcome: Outcome
        public var ending: Ending
        /// From its first word to its last; nil when its end went unseen.
        public var lasted: Duration?
        /// When its hold came, from its first word; nil if it never did.
        public var heldAfter: Duration?
        /// When its pull armed, from its first word; nil if it never did.
        public var armedAfter: Duration?
        /// When its pull began, from its first word; nil if it never did.
        public var pulledAfter: Duration?
        /// When its hold's press last ended, the hold come or not; nil if it
        /// never pressed, or its press never ended.
        public var pressEndedAfter: Duration?
        /// When its lifted item settled, from its first word; nil if it
        /// never lifted, or settled only as the pinch ended unseen or its
        /// item went. A settle just after the lift, as the press ended, is
        /// the press cancelled as the lift took the container's scroll away.
        public var settledAfter: Duration?
        /// Why its item stayed down, lifting nothing.
        public var stayedDown: PluckPress.StayDown?
        /// When its drag first spoke, `dragStartDistance` from where it
        /// touched; nil if it never did.
        public var dragReportedAfter: Duration?
        /// Its drag's last translation, in the item's points: x across, y
        /// down, z toward the viewer; nil if it never spoke.
        public var moved: SIMD3<Double>?
        /// The farthest its drag said it went, in the item's points, in all
        /// three dimensions; 0 if it never spoke.
        public var farthest: Double
        /// The farthest its drag said it went before its hold came, or
        /// before it ended should its hold never come; 0 if its drag didn't
        /// speak by then.
        public var farthestBeforeHold: Double
        /// The farthest it stretched toward breaking its item free while
        /// the item was lifted, by the pull rule's measure, in the item's
        /// points; 0 if its drag never spoke with the item lifted.
        public var farthestStretch: Double
        /// How far it had to go to break its item free, in the item's
        /// points; nil if no move with the item lifted was judged.
        public var breakFreeAt: Double?
    }

    /// A count the caller runs on its own clock, for the hold and for the
    /// pull's arming, and tells back as `holdFired(asTheContainerScrolled:at:)`
    /// and `armPull(at:)` once it's up. A count started replaces one of its
    /// kind under way.
    public enum Countdown: Equatable, Sendable {
        /// Count the hold, this long from now, then tell `holdFired`.
        case startHold(Duration)
        /// Stop counting the hold: the pinch moved first, or ended.
        case stopHold
        /// Count to the pull's arming, this long from now, then tell
        /// `armPull`.
        case startArming(Duration)
        /// Stop counting to the arming: the pinch ended, or a new one began.
        case stopArming
    }

    /// What one word from a gesture did: what the item does, why, the
    /// counts to start or stop, and the account of the pinch it ended, if
    /// any.
    public struct Told: Equatable, Sendable {
        public var actions: [PluckPress.Action]
        /// Why the word did what it did, or nothing.
        public var why: PluckReason
        /// The counts the caller starts or stops, in order.
        public var countdowns: [Countdown]
        /// Whether the word began a pinch.
        public var beganAPinch: Bool
        /// The account of the pinch it ended, if any.
        public var ended: Account?

        public init(
            actions: [PluckPress.Action] = [],
            why: PluckReason = .noPinch,
            countdowns: [Countdown] = [],
            beganAPinch: Bool = false,
            ended: Account? = nil
        ) {
            self.actions = actions
            self.why = why
            self.countdowns = countdowns
            self.beganAPinch = beganAPinch
            self.ended = ended
        }
    }

    /// What the item's tap was.
    public struct Tap: Equatable, Sendable {
        /// Whether it's the release of a pinch that lifted its item, which
        /// does nothing.
        public var isRelease: Bool
        /// How long after its pinch's first word it came; nil before any.
        public var sinceTouch: Duration?
        /// What the item does: it settles, should a release find it lifted
        /// with both gestures let go, as when the tuning kept it up past
        /// its press.
        public var actions: [PluckPress.Action] = []
        /// The counts the caller stops, should it end a pinch.
        public var countdowns: [Countdown] = []
        /// The account of the pinch it ended: one that waited for its tap,
        /// or one its release let down.
        public var ended: Account?
    }

    /// The tuning each new pinch takes; one under way keeps its own.
    public var tuning: PluckTuning

    /// The pinch under way; nil between pinches.
    public private(set) var press: PluckPress?
    /// Whether the pull's drag has the pinch: it has spoken, and not yet
    /// ended or been cancelled.
    public private(set) var isDragging = false
    /// Whether the hold's press has the pinch, from its press until the
    /// press ends.
    public private(set) var isHolding = false

    /// When the pinch under way began, its touch, from which the hold counts
    /// and the container's scrolls are asked about; nil between pinches.
    public var touchedAt: ContinuousClock.Instant? {
        began
    }

    private var began: ContinuousClock.Instant?
    private var lastBegan: ContinuousClock.Instant?
    private var heldAt: ContinuousClock.Instant?
    /// When the item of the pinch under way lifted, from which its pull
    /// arms; nil until it lifts.
    public private(set) var liftedAt: ContinuousClock.Instant?
    private var armedAt: ContinuousClock.Instant?
    private var pulledAt: ContinuousClock.Instant?
    private var pressEndedAt: ContinuousClock.Instant?
    private var settledAt: ContinuousClock.Instant?
    private var dragReportedAt: ContinuousClock.Instant?
    private var moved: SIMD3<Double>?
    private var farthest = 0.0
    /// The farthest the drag of the pinch under way has said it went from
    /// where it touched, in the item's points, before its hold came, or so
    /// far should its hold not have come: 0 if the drag hasn't spoken by
    /// then. What a trace says of how still a hold was.
    public private(set) var farthestBeforeHold = 0.0
    /// Whether the item's tap came while the pinch was under way.
    private var tapCame = false
    /// Until when the item's tap is still the release of the pinch that
    /// last ended; nil when none is expected.
    private var releaseTapExpectedUntil: ContinuousClock.Instant?

    public init(tuning: PluckTuning = PluckTuning()) {
        self.tuning = tuning
    }

    /// The hold's press began: a new pinch begins, the one under way told
    /// first, its end unseen, its item let down, and the hold counts; or,
    /// while the drag has the pinch under way, the press joined it, and the
    /// pinch goes on.
    public mutating func pressBegan(at now: ContinuousClock.Instant) -> Told {
        if press != nil, isDragging {
            isHolding = true
            return Told(why: .pressJoined)
        }
        var told = Told(why: .began, beganAPinch: true)
        if let press {
            if press.isLifted {
                told.actions.append(.settle)
            }
            told.ended = end(.unseen, at: now)
        }
        begin(at: now)
        isHolding = true
        told.countdowns = [.stopArming, .startHold(tuning.holdTime)]
        return told
    }

    /// The hold's count is up, the pinch held `holdDuration`, its container
    /// having scrolled during it, `containerScrolled`, or not: the item
    /// lifts, unless the pinch is told already, or neither gesture has it.
    public mutating func holdFired(asTheContainerScrolled containerScrolled: Bool, at now: ContinuousClock.Instant) -> Told {
        guard press != nil else { return Told(why: .noPinch) }
        guard isHolding || isDragging else { return Told(why: .letGoBeforeTheHold) }
        heldAt = heldAt ?? now
        let (actions, why) = tell { $0.holdFired(asTheContainerScrolled: containerScrolled) }
        var countdowns: [Countdown] = []
        if actions.contains(.lift), let tuning = press?.tuning {
            liftedAt = now
            countdowns = [.startArming(tuning.pullArmTime)]
        }
        return Told(actions: actions, why: why, countdowns: countdowns)
    }

    /// The caller's count to the arming is up, `pullArmDelay` after the
    /// item lifted: its pull arms, unless it has, or it's early.
    public mutating func armPull(at now: ContinuousClock.Instant) -> Told {
        guard press != nil else { return Told(why: .noPinch) }
        let (actions, why) = armIfDue(at: now)
        return Told(actions: actions, why: why)
    }

    /// The hold's press ended: let go, or cancelled, as when the container's
    /// scroll takes the pinch, the hold come or not.
    public mutating func pressEnded(at now: ContinuousClock.Instant) -> Told {
        guard press != nil else { return Told(why: .noPinch) }
        isHolding = false
        pressEndedAt = now
        var (actions, why) = tell { $0.pressEnded() }
        if why == .liftOutlivesItsPress, tapCame {
            // Its tap came already, so the pinch was let go.
            (actions, why) = tell { $0.releaseTapped() }
        }
        noteSettling(actions, at: now)
        let ended = endIfOver(.letGo, at: now)
        return Told(actions: actions, why: why, countdowns: ended == nil ? [] : Self.stopBoth, ended: ended)
    }

    /// The pull's drag spoke: `translation` from where the pinch touched, in
    /// the item's points, where the caller measures `pointsPerMeter`.
    public mutating func dragMoved(_ translation: SIMD3<Double>, pointsPerMeter: Double, at now: ContinuousClock.Instant) -> Told {
        let beganAPinch = press == nil
        begin(at: now)
        isDragging = true
        if translation.x.isFinite, translation.y.isFinite, translation.z.isFinite {
            dragReportedAt = dragReportedAt ?? now
            moved = translation
            let distance = (translation * translation).sum().squareRoot()
            farthest = max(farthest, distance)
            if heldAt == nil {
                farthestBeforeHold = max(farthestBeforeHold, distance)
            }
        }
        let (armed, _) = armIfDue(at: now)
        let (actions, why) = tell { $0.dragMoved(translation, pointsPerMeter: pointsPerMeter) }
        if actions.contains(.breakFree) {
            pulledAt = now
        }
        var countdowns: [Countdown] = []
        if beganAPinch {
            countdowns.append(.stopArming)
        }
        if actions.contains(.stayDown(.movedFirst)) {
            countdowns.append(.stopHold)
        } else if beganAPinch, press?.stayedDown == nil {
            countdowns.append(.startHold(tuning.holdTime))
        }
        return Told(actions: armed + actions, why: why, countdowns: countdowns, beganAPinch: beganAPinch)
    }

    /// The pull's drag was let go.
    public mutating func dragEnded(at now: ContinuousClock.Instant) -> Told {
        guard press != nil else { return Told(why: .noPinch) }
        isDragging = false
        let (actions, why) = tell { $0.dragEnded() }
        noteSettling(actions, at: now)
        let ended = endIfOver(.letGo, at: now)
        return Told(actions: actions, why: why, countdowns: ended == nil ? [] : Self.stopBoth, ended: ended)
    }

    /// The pull's drag was cancelled.
    public mutating func dragCancelled(at now: ContinuousClock.Instant) -> Told {
        guard press != nil else { return Told(why: .noPinch) }
        isDragging = false
        let (actions, why) = tell { $0.dragCancelled() }
        noteSettling(actions, at: now)
        let ended = endIfOver(.cancelled, at: now)
        return Told(actions: actions, why: why, countdowns: ended == nil ? [] : Self.stopBoth, ended: ended)
    }

    /// The item's tap fired: the release of a pinch that lifted its item,
    /// while it's under way or within `releaseTapGrace` of its end, once,
    /// which does nothing but let down an item both gestures have let go;
    /// otherwise a tap, which ends a pinch waiting for it.
    public mutating func tapped(at now: ContinuousClock.Instant) -> Tap {
        let sinceTouch = (began ?? lastBegan).map { now - $0 }
        if let press {
            tapCame = true
            var actions: [PluckPress.Action] = []
            if press.swallowsReleaseTap, press.isLifted, !isHolding, !isDragging {
                (actions, _) = tell { $0.releaseTapped() }
                noteSettling(actions, at: now)
            }
            let ended = isOver ? end(.letGo, at: now) : nil
            return Tap(
                isRelease: press.swallowsReleaseTap,
                sinceTouch: sinceTouch,
                actions: actions,
                countdowns: ended == nil ? [] : Self.stopBoth,
                ended: ended
            )
        }
        if let until = releaseTapExpectedUntil {
            releaseTapExpectedUntil = nil
            if now < until {
                return Tap(isRelease: true, sinceTouch: sinceTouch)
            }
        }
        return Tap(isRelease: false, sinceTouch: sinceTouch)
    }

    /// The container began to scroll during the pinch, as its scroll view
    /// says, at `now`: before the hold, the pinch is a scroll, and its hold
    /// stops counting; lifted, its item settles, as the tuning says. One
    /// neither gesture has any more, as the scroll view took it, is over.
    public mutating func containerScrolled(at now: ContinuousClock.Instant) -> Told {
        guard press != nil else { return Told(why: .noPinch) }
        let (actions, why) = tell { $0.containerScrolled() }
        noteSettling(actions, at: now)
        var countdowns: [Countdown] = actions.contains(.stayDown(.containerScrolled)) ? [.stopHold] : []
        let ended = endIfOver(.cancelled, at: now)
        if ended != nil {
            countdowns = Self.stopBoth
        }
        return Told(actions: actions, why: why, countdowns: countdowns, ended: ended)
    }

    /// A pinch began on another item of the container, at `now`: should
    /// neither gesture have this one, its item kept up past its press, it's
    /// over, its end unseen, and its item settles, so a press cancelled as
    /// the lift stopped the scroll never keeps the item up, and the scroll
    /// off, past the next pinch anywhere.
    public mutating func pinchBeganElsewhere(at now: ContinuousClock.Instant) -> Told {
        guard let press else { return Told(why: .noPinch) }
        guard press.isLifted, !isHolding, !isDragging else { return Told(why: .toldAlready) }
        let (actions, why) = tell { $0.pinchBeganElsewhere() }
        noteSettling(actions, at: now)
        let ended = end(.unseen, at: now)
        return Told(actions: actions, why: why, countdowns: Self.stopBoth, ended: ended)
    }

    /// How far the pinch under way has stretched toward breaking its item
    /// free, and where the item is drawn for it, while the item is held
    /// lifted short of breaking free; nil otherwise
    /// (`PluckPress.stretch`).
    public var stretch: PluckStretch? {
        press?.stretch
    }

    /// Where the item of the pinch under way is drawn from where it stands
    /// lifted, in its points, following the hand on its tether; none
    /// unless it's held lifted short of breaking free.
    public var follow: SIMD3<Double> {
        press?.follow ?? .zero
    }

    /// Whether the pinch under way has its item kept up past its press:
    /// lifted, with neither its press nor its drag having it.
    public var isKeptUpPastItsPress: Bool {
        guard let press else { return false }
        return press.isLifted && !isHolding && !isDragging
    }

    /// The item went mid-pinch: its pull is taken away and the item let
    /// down, and no tap is expected after.
    public mutating func itemWent(at now: ContinuousClock.Instant) -> Told {
        releaseTapExpectedUntil = nil
        guard let press else { return Told(why: .noPinch) }
        var actions: [PluckPress.Action] = []
        if press.isPulling {
            actions.append(.cancelSpawn)
        }
        if press.isLifted {
            actions.append(.settle)
        }
        let account = account(.itemWent, at: now)
        forget()
        return Told(actions: actions, why: .itemWent, countdowns: Self.stopBoth, ended: account)
    }

    /// Both counts stopped, as a pinch ends.
    private static let stopBoth: [Countdown] = [.stopHold, .stopArming]

    /// Begins a pinch, unless one is under way.
    private mutating func begin(at now: ContinuousClock.Instant) {
        guard press == nil else { return }
        press = PluckPress(tuning: tuning)
        began = now
        lastBegan = now
        heldAt = nil
        liftedAt = nil
        armedAt = nil
        pulledAt = nil
        pressEndedAt = nil
        settledAt = nil
        dragReportedAt = nil
        moved = nil
        farthest = 0
        farthestBeforeHold = 0
        tapCame = false
        // A new pinch's touch comes after the last one's release.
        releaseTapExpectedUntil = nil
    }

    /// Arms the pull under way, if its item lifted `pullArmDelay` ago,
    /// within half a millisecond, a timer's rounding.
    private mutating func armIfDue(at now: ContinuousClock.Instant) -> ([PluckPress.Action], PluckReason) {
        guard let press else { return ([], .noPinch) }
        guard let liftedAt, now - liftedAt >= press.tuning.pullArmTime - Self.timerRounding else {
            return ([], press.isLifted ? .armingNotDue : .notLifted)
        }
        let (actions, why) = tell { $0.armPull() }
        if !actions.isEmpty {
            armedAt = now
        }
        return (actions, why)
    }

    /// How early a count may come and still count as due, whatever its
    /// rounding.
    private static let timerRounding: Duration = .microseconds(500)

    /// Tells the pinch under way, giving back what it does and why.
    private mutating func tell(_ event: (inout PluckPress) -> [PluckPress.Action]) -> ([PluckPress.Action], PluckReason) {
        guard var told = press else { return ([], .noPinch) }
        let actions = event(&told)
        press = told
        return (actions, told.why)
    }

    /// Notes when the item settled, should `actions` settle it.
    private mutating func noteSettling(_ actions: [PluckPress.Action], at now: ContinuousClock.Instant) {
        if actions.contains(.settle) {
            settledAt = settledAt ?? now
        }
    }

    /// Whether neither gesture has the pinch, and its item is down.
    private var isOver: Bool {
        guard let press else { return false }
        return !isDragging && !isHolding && !press.isLifted
    }

    /// Whether the pinch waits only for its tap: it's over, but nothing
    /// told what it was.
    private var awaitsItsTap: Bool {
        guard let press, isOver else { return false }
        return !press.hasMoved && !press.liftedByHold && !press.hasPulled && press.stayedDown == nil && !tapCame
    }

    /// Ends the pinch if it's over and told, its `ending` the word that
    /// ended it; one that waits for its tap goes on.
    private mutating func endIfOver(_ ending: Account.Ending, at now: ContinuousClock.Instant) -> Account? {
        guard isOver else { return nil }
        guard !awaitsItsTap || ending == .cancelled else { return nil }
        return end(ending, at: now)
    }

    /// Ends the pinch under way: its account, and, should it have lifted
    /// its item with no tap yet, the wait for its release.
    private mutating func end(_ ending: Account.Ending, at now: ContinuousClock.Instant) -> Account {
        let account = account(ending, at: now)
        if let press, press.swallowsReleaseTap, !tapCame {
            releaseTapExpectedUntil = now + press.tuning.releaseTapTime
        }
        forget()
        return account
    }

    private mutating func forget() {
        press = nil
        began = nil
        isDragging = false
        isHolding = false
    }

    /// The pinch under way's account, as `ending` ends it now.
    private func account(_ ending: Account.Ending, at now: ContinuousClock.Instant) -> Account {
        let press = self.press ?? PluckPress(tuning: tuning)
        let outcome: Account.Outcome = if press.hasPulled {
            .pull
        } else if press.liftedByHold {
            .lift
        } else if press.hasMoved || press.stayedDown == .containerScrolled {
            .scroll
        } else if ending == .letGo {
            .tap
        } else {
            .nothing
        }
        let began = self.began ?? now
        return Account(
            outcome: outcome,
            ending: ending,
            lasted: ending == .unseen ? nil : now - began,
            heldAfter: heldAt.map { $0 - began },
            armedAfter: armedAt.map { $0 - began },
            pulledAfter: pulledAt.map { $0 - began },
            pressEndedAfter: pressEndedAt.map { $0 - began },
            settledAfter: settledAt.map { $0 - began },
            stayedDown: press.stayedDown,
            dragReportedAfter: dragReportedAt.map { $0 - began },
            moved: moved,
            farthest: farthest,
            farthestBeforeHold: farthestBeforeHold,
            farthestStretch: press.farthestStretch,
            breakFreeAt: press.breakFreeAt
        )
    }
}
