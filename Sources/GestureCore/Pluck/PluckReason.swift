/// Why one word told to a pinch on an item did what it did, or nothing, for
/// a trace: each stage of a pluck, and why it came or didn't. Every word a
/// pinch is told, the hold's press and its end, the hold's count, the
/// arming, and each word of the pull's drag, answers with one.
public enum PluckReason: Equatable, Sendable {
    // MARK: The pinch's start

    /// The word began a pinch.
    case began
    /// The hold's press came while the drag has the pinch: the press came
    /// back to the item, as the hand moved off it and back, or joined a
    /// pinch the drag began; the same pinch either way.
    case pressJoined

    // MARK: The hold

    /// Held for the hold's time, the container not having scrolled during
    /// the pinch: the item lifts.
    case heldStill
    /// The hold's time came, but the container scrolled during the pinch,
    /// as one that caught it coasting: a scroll, and the item stays down.
    case containerScrolled
    /// The hold's time came for a pinch already told: lifted already, or a
    /// scroll.
    case toldAlready
    /// The hold's time came with neither the press nor the drag having the
    /// pinch: let go, or its press ended, before its hold, which lifts
    /// nothing.
    case letGoBeforeTheHold

    // MARK: The arming

    /// The pull arms, its time since the lift come: the next move that
    /// counts pulls.
    case armed
    /// The pull's arming isn't due: its time since the lift hasn't come, or
    /// it armed already.
    case armingNotDue

    // MARK: The pull's drag

    /// A move that isn't a number, which moves nothing.
    case notANumber
    /// Before the hold, a move this far from the touch, in the item's
    /// points, breaks the stillness: the container's scroll, for the rest
    /// of the pinch.
    case movedFirst(distance: Double)
    /// Before the hold, a move this far from the touch, within the
    /// stillness: the hold goes on.
    case withinStillness(distance: Double)
    /// A move of a pinch told as the container's scroll, which lifts and
    /// pulls nothing.
    case scrolling(PluckPress.StayDown)
    /// A move of a lifted pinch whose pull hasn't armed: nothing.
    case notArmedYet
    /// A word for a lifted item, the arming or a move, while the pinch's
    /// item isn't lifted: never lifted, or settled already, as when its
    /// press ended before its drag spoke. Nothing.
    case notLifted
    /// An armed move the pull rule turned down.
    case notAPull(PluckPullJudgement)
    /// An armed move the pull rule took: the pull begins.
    case pulled(PluckPullJudgement)
    /// The pull moves with its drag.
    case pullMoved
    /// A move after the pinch's pull landed: one pinch pulls once.
    case pulledAlready

    // MARK: The pinch's end

    /// The pull's drag ended, the pinch let go.
    case dragEnded
    /// The pull's drag was cancelled.
    case dragCancelled
    /// The hold's press ended, let go or cancelled.
    case pressEnded
    /// The hold's press ended while the drag has the pinch: the item stays
    /// as it is, and the drag's end settles it.
    case dragHasThePinch
    /// The hold's press ended with the item lifted and the drag not having
    /// the pinch, and the tuning keeps it lifted
    /// (`PluckTuning.pressEndSettlesLiftedItem`).
    case liftOutlivesItsPress
    /// The item went mid-pinch: its pull is taken away, and it's let down.
    case itemWent
    /// The word came with no pinch under way, and changed nothing.
    case noPinch
}
