/// One pinch on an item in a scrolling container, a grid's or a list's, from
/// its touch to its end, told as the container's scroll, a lift, or a pull
/// as it goes: scroll first, then a hold in place lifts the item a little,
/// and only a little later may it be pulled out into the room. Two things
/// tell it, neither taking the pinch from the container's scroll: the hold,
/// which says when the pinch has been held `PluckTuning.holdDuration` (the
/// caller counts it, as `PluckPinches` says, and asks whether the container
/// scrolled meanwhile, `PluckScrolls`), and the pull's drag, which says
/// nothing until the pinch has moved `PluckTuning.dragStartDistance` from
/// where it touched, then says where it is at each move.
///
/// - **A scroll first is a scroll.** A pinch whose container scrolled
///   during it, as its scroll view says (`StayDown.containerScrolled`), is
///   the container's scroll, and lifts and pulls nothing for the rest of
///   the pinch, however it moves after. So is one the drag reports moving
///   past the hold's stillness before its hold, 40 pt by default
///   (`StayDown.movedFirst`), so a quick pinch yanked toward the viewer
///   pulls nothing. The drag's first word alone isn't such a move, as a
///   hand that has just pinched settles about 15 pt, the drag's start.
/// - **A hold lifts.** Held `holdDuration`, its container not having
///   scrolled, the item lifts (`Action.lift`), and, as the tuning says, its
///   container's scroll stops under it until it settles
///   (`PluckContainer`), so the hand's move belongs to the item.
/// - **Then the pull arms**, `pullArmDelay` after the lift (`armPull()`).
///   Between the lift and then, a move neither pulls nor scrolls.
/// - **An armed pull** comes out with the first move the pull rule takes,
///   by default 6 mm any way from where the pinch stood as the pull armed
///   (`armedAt`), so a hand that drifted during the hold doesn't pull the
///   instant it arms; or, as the tuning says, from where it touched, so a
///   hand already on its way out catches up as the pull arms
///   (`PluckPullRule`, `PluckPullOrigin`). A move it turns down pulls
///   nothing, and the item stays up. A pull moves with its drag; one pinch
///   pulls once.
/// - **The item settles** as the pinch is let go: as its drag ends, or is
///   cancelled, if the drag has spoken; else as the hold's press ends,
///   unless the tuning keeps it up then (`pressEndSettlesLiftedItem`). The
///   press may end while the drag goes on, as the hand moves off the item,
///   and the item stays up then.
/// - **The release tap**: a pinch that lifted its item lets the item's tap
///   fire as it's let go, which isn't a tap (`swallowsReleaseTap`). A pinch
///   let go before its hold is the item's tap.
///
/// Each word answers with what the item does, and leaves why in `why`, for
/// a trace. Distances are in the item's points, with +z toward the viewer.
public struct PluckPress: Equatable, Sendable {
    /// Why a pinch's item stays down, lifting and pulling nothing.
    public enum StayDown: String, Equatable, Sendable, Codable {
        /// The pull's drag said the pinch moved past the hold's stillness
        /// before its hold came: a yank, or a scroll the container's scroll
        /// view hasn't said it makes.
        case movedFirst
        /// Its container scrolled during the pinch, as one that caught it
        /// coasting.
        case containerScrolled
    }

    /// What the item does as the pinch is told.
    public enum Action: Equatable, Sendable {
        /// The item lifts, its pinch held.
        case lift
        /// Its pull arms: the next move the pull rule takes pulls it out.
        case pullArmed
        /// A pull begins where the drag is, the caller making what the item
        /// pulls out in the room.
        case beginPull
        /// The pull moves to where the drag is.
        case movePull
        /// The pull lands where the drag was let go.
        case endPull
        /// The pull's drag was cancelled: what it pulled out is taken away.
        case cancelPull
        /// The item settles back into its container.
        case settle
        /// The item stays down for the rest of the pinch: nothing to do,
        /// but worth saying.
        case stayDown(StayDown)
    }

    /// The tuning this pinch is judged by, the one it began with.
    public let tuning: PluckTuning

    /// Whether its hold has lifted its item, which hasn't settled yet.
    public private(set) var isHeld = false
    /// Whether its pull has armed.
    public private(set) var isArmed = false
    /// Whether its pull is under way.
    public private(set) var isPulling = false
    /// Whether it has pulled.
    public private(set) var hasPulled = false
    /// Whether the pull's drag has said it moved past the hold's stillness,
    /// at any time; at a stillness no greater than the drag's start, whether
    /// it has spoken at all.
    public private(set) var hasMoved = false
    /// Where the pull's drag last said the pinch is, from where it touched,
    /// in the item's points; nil until it speaks.
    public private(set) var dragTranslation: SIMD3<Double>?
    /// Where the pinch stood as its pull armed, from where it touched, in
    /// the item's points: the drag's last word then, or zero, the touch,
    /// should the drag not have spoken by then, since the pinch stood within
    /// the drag's start of the touch. Nil until the pull arms.
    public private(set) var armedAt: SIMD3<Double>?
    /// Whether the pull's drag has the pinch: it has spoken, and not yet
    /// ended or been cancelled.
    public private(set) var isDragging = false
    /// Whether its hold lifted its item.
    public private(set) var liftedByHold = false
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

    public init(tuning: PluckTuning = PluckTuning()) {
        self.tuning = tuning
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
        armedAt = dragTranslation ?? .zero
        why = .armed
        return [.pullArmed]
    }

    /// The pull's drag moved, `translation` from where the pinch touched, in
    /// the item's points, where the caller measures `pointsPerMeter`: before
    /// the hold, past the stillness, the pinch is a scroll for good; lifted,
    /// nothing until the pull arms; armed, a pull begins once the pull rule
    /// takes the move, from where the pinch stood as it armed or from the
    /// touch, as tuned, and moves with the drag after. A move that isn't a
    /// number moves nothing.
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
            why = .pullMoved
            return [.movePull]
        }
        if !liftedByHold, stayedDown == nil {
            guard breaksStillness else {
                why = .withinStillness(distance: distance, stillness: tuning.holdStillness)
                return []
            }
            // Moved before its hold: the container's scroll, for the rest
            // of the pinch.
            stayedDown = .movedFirst
            why = .movedFirst(distance: distance, stillness: tuning.holdStillness)
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
        guard isArmed else {
            why = .notArmedYet
            return []
        }
        let judgement = tuning.judgePull(translation, armedAt: armedAt ?? .zero, pointsPerMeter: pointsPerMeter)
        guard judgement.isPull else {
            why = .notAPull(judgement)
            return []
        }
        isPulling = true
        hasPulled = true
        why = .pulled(judgement)
        return [.beginPull]
    }

    /// The pull's drag was let go, the pinch with it: a pull lands, and the
    /// item settles.
    public mutating func dragEnded() -> [Action] {
        isDragging = false
        var actions: [Action] = []
        if isPulling {
            isPulling = false
            actions.append(.endPull)
        }
        why = .dragEnded
        return actions + letDown()
    }

    /// The pull's drag was cancelled: what a pull took out is taken away,
    /// and the item settles at once, so its container scrolls again,
    /// whatever the hold's press says.
    public mutating func dragCancelled() -> [Action] {
        isDragging = false
        var actions: [Action] = []
        if isPulling {
            isPulling = false
            actions.append(.cancelPull)
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
        return [.settle]
    }
}
