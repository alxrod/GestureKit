/// One pinch on an item in a scrolling container, a grid's or a list's, from
/// its touch to its end, told as the container's scroll, a lift, or a pull
/// as it goes: scroll first, then a hold in place lifts the item a little,
/// it stays lifted, following the hand a little, and only once the hand has
/// gone far enough does it break free and spawn into the room. Two things
/// tell it, neither taking the pinch from the container's scroll: the hold,
/// which says when the pinch has been held `PluckTuning.holdDuration` (the
/// caller counts it, as `PluckPinches` says, and asks whether the container
/// scrolled meanwhile, `PluckScrolls`), and the pull's drag, which says
/// nothing until the pinch has moved `PluckTuning.dragStartDistance` from
/// where it touched, then says where it is at each move.
///
/// - **A pinch is a scroll unless it's a hold.** One whose container
///   scrolled during it, as its scroll view says, or whose scroll offset
///   moved from where it stood at the touch (`scrollOffsetMoved(_:)`,
///   `StayDown.containerScrolled`), is the container's scroll, and lifts and
///   pulls nothing for the rest of the pinch, however it moves after. So is
///   one the drag reports moving along the scroll past the hold's stillness
///   along it, 10 pt by default, or any way past its stillness, 40 pt, before
///   its hold (`StayDown.movedFirst`), so a slow scroll its scroll view
///   hasn't taken yet, or a quick pinch yanked toward the viewer, lifts
///   nothing. The drag's first word alone isn't such a move, as a hand that
///   has just pinched settles about 15 pt, the drag's start, mostly across.
/// - **A hold lifts.** Held `holdDuration`, a quarter second by default,
///   its container not having scrolled, the item lifts (`Action.lift`), and,
///   as the tuning says, its container's scroll stops under it until it
///   settles (`PluckContainer`), so the hand's move belongs to the item.
/// - **Lifted, it's held.** Each move of the hand draws the item a little
///   along with it, from where it stood as it lifted, on its tether
///   (`stretch`, `follow`, `PluckTether`), and says how far the hand has
///   gone toward breaking it free. A move mostly along the scroll, by
///   default, gives the pinch back to it: the item settles, and the pinch
///   is a scroll (`PluckTuning.givesLiftBackToScroll`,
///   `StayDown.givenBackToTheScroll`), so an item can't be pulled out
///   mostly along the scroll.
/// - **The pull arms** `pullArmDelay` after the lift (`armPull()`), the
///   least time the item shows lifted.
/// - **It breaks free** once armed, with the first move the pull rule
///   takes, by default 2.5 cm any other way from where the pinch stood as
///   its item lifted (`liftPoint`), so a hand that drifted during the hold
///   doesn't break it free the instant it arms, and one that came out as
///   the item lifted catches up as the pull arms; or, as the tuning says,
///   from where it stood as the pull armed (`armingPoint`), or from where it
///   touched (`PluckPullRule`, `PluckPullOrigin`). A move it turns down
///   breaks nothing free, and the item stays up, following. Breaking free,
///   the item spawns into the room where the drag is (`Action.breakFree`),
///   and the pluck's part is over: the rest of the pinch carries what
///   spawned, each move handed to a carry (`Action.carrySpawned`,
///   `PluckHandoff`). One pinch breaks free once.
/// - **The item settles** as the pinch is let go: as its drag ends, or is
///   cancelled, if the drag has spoken; else as the hold's press ends,
///   unless the tuning keeps it up then (`pressEndSettlesLiftedItem`). The
///   press may end while the drag goes on, as the hand moves off the item,
///   and the item stays up then. Let go short of breaking free, it settles
///   with nothing spawned.
/// - **The release tap**: a pinch that lifted its item lets the item's tap
///   fire as it's let go, which isn't a tap (`swallowsReleaseTap`). A pinch
///   let go before its hold is the item's tap.
///
/// Each word answers with what the item does, and leaves why in `why`, for
/// a trace. Distances are in the item's points, with +z toward the viewer.
public struct PluckPress: Equatable, Sendable {
    /// Why a pinch's item stays down, lifting and pulling nothing.
    public enum StayDown: String, Equatable, Sendable, Codable {
        /// The pull's drag said the pinch moved past the hold's stillness,
        /// any way or along the container's scroll, before its hold came: a
        /// yank, or a scroll the container's scroll view hasn't said it
        /// makes.
        case movedFirst
        /// Its container scrolled during the pinch, as its scroll view or
        /// its scroll offset said, as one that caught it coasting.
        case containerScrolled
        /// Its item was lifted, and its pinch, moving mostly along the
        /// container's scroll, was given back to the scroll, as the tuning
        /// says (`PluckTuning.givesLiftBackToScroll`).
        case givenBackToTheScroll
    }

    /// What the item does as the pinch is told.
    public enum Action: Equatable, Sendable {
        /// The item lifts, its pinch held.
        case lift
        /// Its pull arms: the next move the pull rule takes breaks it free.
        case pullArmed
        /// The item broke free: the caller spawns what it pulls out in the
        /// room where the drag is, and the pluck's part ends. The rest of the
        /// pinch carries what spawned (`carrySpawned`, `PluckHandoff`).
        case breakFree
        /// The pinch moved after the spawn: the carry of what spawned takes
        /// the move, 1:1 with the hand (`PluckHandoff`).
        case carrySpawned
        /// The pinch let go of what spawned, which stays where its carry
        /// last put it.
        case releaseSpawned
        /// The pull's drag was cancelled after the spawn: what spawned is
        /// taken away.
        case cancelSpawn
        /// The item settles back into its container.
        case settle
        /// The item stays down for the rest of the pinch: nothing to do,
        /// but worth saying.
        case stayDown(StayDown)
    }

    /// The tuning this pinch is judged by, the one it began with.
    public let tuning: PluckTuning
    /// The axes its container scrolls along, as the container said as it
    /// began.
    public let scrollAxes: PluckScrollAxes

    /// Whether its hold has lifted its item, which hasn't settled yet.
    public private(set) var isHeld = false
    /// Whether its pull has armed.
    public private(set) var isArmed = false
    /// Whether its pull is under way: its item broke free, and the pinch
    /// carries what spawned.
    public private(set) var isPulling = false
    /// Whether its item broke free.
    public private(set) var hasPulled = false
    /// Whether the pull's drag has said it moved past the hold's stillness,
    /// at any time; at a stillness no greater than the drag's start, whether
    /// it has spoken at all.
    public private(set) var hasMoved = false
    /// Where the pull's drag last said the pinch is, from where it touched,
    /// in the item's points; nil until it speaks.
    public private(set) var dragTranslation: SIMD3<Double>?
    /// Where the pinch stood as its item lifted, from where it touched, in
    /// the item's points, as the drag last said then. Nil until the item
    /// lifts, and after, should the drag not have spoken by then: the pinch
    /// stood within the drag's start of the touch, and a pull measured from
    /// the lift is measured from the touch.
    public private(set) var liftPoint: SIMD3<Double>?
    /// Where the pinch stood as its pull armed, as `liftPoint` is where it
    /// stood as its item lifted: nil until the pull arms, or with the drag
    /// silent by then.
    public private(set) var armingPoint: SIMD3<Double>?
    /// Whether the pull's drag has the pinch: it has spoken, and not yet
    /// ended or been cancelled.
    public private(set) var isDragging = false
    /// Whether its hold lifted its item.
    public private(set) var liftedByHold = false
    /// How far it has stretched toward breaking its item free, and where the
    /// item is drawn for it, as its last move with the item lifted was
    /// judged; nil until the drag speaks with the item lifted, and once the
    /// item breaks free or settles.
    public private(set) var stretch: PluckStretch?
    /// The farthest it stretched toward breaking its item free while the
    /// item was lifted, by the pull rule's measure, in the item's points: 0
    /// if the drag never spoke with it lifted.
    public private(set) var farthestStretch = 0.0
    /// How far it had to go to break its item free, in the item's points, as
    /// its moves with the item lifted were judged; nil if none was.
    public private(set) var breakFreeAt: Double?
    /// Why its item stays down; nil unless it does.
    public private(set) var stayedDown: StayDown?
    /// Why its last word did what it did, for a trace.
    public private(set) var why: PluckReason = .began

    /// Whether its item's tap firing as it's let go is its release, which
    /// is no tap: a pinch that lifted its item, pulled or not.
    public var swallowsReleaseTap: Bool {
        liftedByHold || hasPulled
    }

    /// Whether its item is lifted: held, or pulling.
    public var isLifted: Bool {
        isHeld || isPulling
    }

    /// Where its item is drawn from where it stands lifted, in its points,
    /// following the hand on its tether while it's held short of breaking
    /// free (`stretch`); none otherwise, so it springs back to its place as
    /// it breaks free or settles.
    public var follow: SIMD3<Double> {
        stretch?.follow ?? .zero
    }

    public init(tuning: PluckTuning = PluckTuning(), scrollAxes: PluckScrollAxes = .vertical) {
        self.tuning = tuning
        self.scrollAxes = scrollAxes
    }

    /// The hold came, the pinch held `holdDuration`: the item lifts, unless
    /// its container scrolled during the pinch, `containerScrolled`, a
    /// scroll. A pinch that moved first, or whose item lifted already, is
    /// told already, and changes nothing.
    public mutating func holdFired(asTheContainerScrolled containerScrolled: Bool) -> [Action] {
        guard !liftedByHold, stayedDown == nil else {
            why = .toldAlready
            return []
        }
        guard !containerScrolled else {
            stayedDown = .containerScrolled
            why = .containerScrolled
            return [.stayDown(.containerScrolled)]
        }
        isHeld = true
        liftedByHold = true
        liftPoint = dragTranslation
        why = .heldStill
        return [.lift]
    }

    /// `pullArmDelay` has passed since the lift: the pull arms, on an item
    /// still lifted, once.
    public mutating func armPull() -> [Action] {
        guard isHeld else {
            why = .notLifted
            return []
        }
        guard !isArmed, !hasPulled else {
            why = .armingNotDue
            return []
        }
        isArmed = true
        armingPoint = dragTranslation
        why = .armed
        return [.pullArmed]
    }

    /// The pull's drag moved, `translation` from where the pinch touched, in
    /// the item's points, where the caller measures `pointsPerMeter` to a
    /// meter of the hand's move: before the hold, past the stillness, the
    /// pinch is a scroll for good; lifted, the item follows on its tether,
    /// and once the pull has armed, it breaks free as the pull rule takes
    /// the move, from where the pinch stood as its item lifted, or as its
    /// pull armed, or from the touch, as tuned; broken free, each move is
    /// handed to the carry of what spawned. A move that isn't a number moves
    /// nothing.
    public mutating func dragMoved(_ translation: SIMD3<Double>, pointsPerMeter: Double) -> [Action] {
        isDragging = true
        guard translation.x.isFinite, translation.y.isFinite, translation.z.isFinite else {
            why = .notANumber
            return []
        }
        dragTranslation = translation
        let distance = (translation * translation).sum().squareRoot()
        let breaksStillness = tuning.breaksStillness(distance)
        if breaksStillness {
            hasMoved = true
        }
        if isPulling {
            why = .handedToTheCarry
            return [.carrySpawned]
        }
        if !liftedByHold, stayedDown == nil {
            let along = scrollAxes.distance(along: translation)
            if breaksStillness {
                why = .movedFirst(distance: distance, stillness: tuning.holdStillness)
            } else if tuning.breaksStillnessAlongScroll(along) {
                hasMoved = true
                why = .movedAlongTheScroll(distance: along, stillness: tuning.holdStillnessAlongScroll)
            } else {
                why = .withinStillness(distance: distance, stillness: tuning.holdStillness)
                return []
            }
            // Moved before its hold: the container's scroll, for the rest
            // of the pinch.
            stayedDown = .movedFirst
            return [.stayDown(.movedFirst)]
        }
        if let stayedDown {
            why = .scrolling(stayedDown)
            return []
        }
        guard !hasPulled else {
            why = .pulledAlready
            return []
        }
        guard isHeld else {
            why = .notLifted
            return []
        }
        let moveSinceTheLift = translation - (liftPoint ?? .zero)
        if tuning.givesBackToScroll(moveSinceTheLift, along: scrollAxes) {
            // Mostly along the scroll: the pinch is the container's scroll
            // after all.
            stayedDown = .givenBackToTheScroll
            why = .givenBackToTheScroll(along: scrollAxes.distance(along: moveSinceTheLift), across: scrollAxes.distance(across: moveSinceTheLift))
            return letDown()
        }
        let judgement = tuning.judgePull(translation, liftPoint: liftPoint, armingPoint: armingPoint, pointsPerMeter: pointsPerMeter)
        breakFreeAt = judgement.threshold
        guard isArmed, judgement.isPull else {
            // Held: the item follows a little, and the pinch has gone this
            // far toward breaking it free.
            let reach = tuning.pullRule.reach(of: judgement)
            stretch = PluckStretch(reach: reach, needs: judgement.threshold, follow: tuning.tether.follow(forMove: moveSinceTheLift))
            farthestStretch = max(farthestStretch, reach)
            why = isArmed ? .notAPull(judgement) : .notArmedYet
            return []
        }
        farthestStretch = max(farthestStretch, tuning.pullRule.reach(of: judgement))
        stretch = nil
        isPulling = true
        hasPulled = true
        why = .brokeFree(judgement)
        return [.breakFree]
    }

    /// The container's scroll offset is `distance` points from where it
    /// stood at the pinch's touch: before the hold, past the tuning's
    /// stillness for it, the pinch is the container's scroll for good, and
    /// its item stays down, whatever phase the scroll view says it's in. A
    /// pinch told already, or past its hold, changes nothing.
    public mutating func scrollOffsetMoved(_ distance: Double) -> [Action] {
        guard !liftedByHold, stayedDown == nil, tuning.scrollOffsetGivesUpHold(distance) else {
            why = .scrollOffsetWithin(distance: distance, stillness: tuning.scrollOffsetStillness)
            return []
        }
        stayedDown = .containerScrolled
        why = .scrollOffsetMoved(distance: distance, stillness: tuning.scrollOffsetStillness)
        return [.stayDown(.containerScrolled)]
    }

    /// The pull's drag was let go, the pinch with it: what spawned is let
    /// go, and the item settles.
    public mutating func dragEnded() -> [Action] {
        isDragging = false
        var actions: [Action] = []
        if isPulling {
            isPulling = false
            actions.append(.releaseSpawned)
        }
        why = .dragEnded
        return actions + letDown()
    }

    /// The pull's drag was cancelled: what spawned is taken away, and the
    /// item settles at once, so its container scrolls again, whatever the
    /// hold's press says.
    public mutating func dragCancelled() -> [Action] {
        isDragging = false
        var actions: [Action] = []
        if isPulling {
            isPulling = false
            actions.append(.cancelSpawn)
        }
        why = .dragCancelled
        return actions + letDown()
    }

    /// The hold's press ended, let go or cancelled: a lifted item settles,
    /// unless the drag still has the pinch, as when the hand moves off the
    /// item, whose end settles it, or the tuning keeps it up.
    public mutating func pressEnded() -> [Action] {
        guard !isDragging else {
            why = .dragHasThePinch
            return []
        }
        if isHeld, !tuning.pressEndSettlesLiftedItem {
            why = .liftOutlivesItsPress
            return []
        }
        why = .pressEnded
        return letDown()
    }

    /// The item's tap came as the pinch was let go, its press and its drag
    /// having let go of it, before its press's end or after: a lifted item
    /// settles, as one whose press's end the tuning kept up.
    public mutating func releaseTapped() -> [Action] {
        why = .releasedByItsTap
        return letDown()
    }

    /// The container began to scroll during the pinch: before the hold, the
    /// pinch is a scroll for good, and its item stays down; lifted, the item
    /// settles, unless its pull is under way, or the tuning keeps it up.
    public mutating func containerScrolled() -> [Action] {
        if stayedDown != nil || (liftedByHold && !isHeld) {
            why = .toldAlready
            return []
        }
        guard liftedByHold else {
            stayedDown = .containerScrolled
            why = .containerScrolled
            return [.stayDown(.containerScrolled)]
        }
        guard !isPulling, tuning.scrollSettlesLiftedItem else {
            why = .scrollLeftTheItemUp
            return []
        }
        why = .containerScrolled
        return letDown()
    }

    /// A pinch began elsewhere in the container while neither gesture has
    /// this one: an item kept up past its press settles, its pinch's end
    /// gone unseen.
    public mutating func pinchBeganElsewhere() -> [Action] {
        why = .pinchElsewhere
        return letDown()
    }

    /// The item settles, if it's lifted.
    private mutating func letDown() -> [Action] {
        guard isHeld else { return [] }
        isHeld = false
        stretch = nil
        return [.settle]
    }
}
