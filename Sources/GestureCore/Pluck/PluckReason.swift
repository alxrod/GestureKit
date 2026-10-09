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
    /// The container scrolled during the pinch, as one that caught it
    /// coasting, or that the scroll view took: before the hold, a scroll,
    /// and the item stays down; lifted, the item settles, as the tuning says
    /// (`PluckTuning.scrollSettlesLiftedItem`).
    case containerScrolled
    /// The container scrolled with the item lifted, and the pull under way,
    /// or the tuning, keeps it up.
    case scrollLeftTheItemUp
    /// A word for a pinch already told what it is, lifted already or a
    /// scroll, which changes nothing.
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
    /// The item's tap came as the pinch was let go, its lift kept past its
    /// press: it settles.
    case releasedByItsTap
    /// A pinch began elsewhere in the container while this one's item was
    /// kept up past its press, neither gesture having it: its end went
    /// unseen, and its item settles.
    case pinchElsewhere
    /// The item went mid-pinch: its pull is taken away, and it's let down.
    case itemWent
    /// The word came with no pinch under way, and changed nothing.
    case noPinch
}

extension PluckReason: CustomStringConvertible {
    /// The reason's name, as its case is spelled, for telling one kind of
    /// reason from another whatever its numbers, as a trace does to note a
    /// drag's words only as their reason changes.
    public var name: String {
        switch self {
        case .began: "began"
        case .pressJoined: "pressJoined"
        case .heldStill: "heldStill"
        case .containerScrolled: "containerScrolled"
        case .scrollLeftTheItemUp: "scrollLeftTheItemUp"
        case .toldAlready: "toldAlready"
        case .letGoBeforeTheHold: "letGoBeforeTheHold"
        case .armed: "armed"
        case .armingNotDue: "armingNotDue"
        case .notANumber: "notANumber"
        case .movedFirst: "movedFirst"
        case .withinStillness: "withinStillness"
        case .scrolling: "scrolling"
        case .notArmedYet: "notArmedYet"
        case .notLifted: "notLifted"
        case .notAPull(let judgement): "notAPull.\(judgement.verdict.rawValue)"
        case .pulled: "pulled"
        case .pullMoved: "pullMoved"
        case .pulledAlready: "pulledAlready"
        case .dragEnded: "dragEnded"
        case .dragCancelled: "dragCancelled"
        case .pressEnded: "pressEnded"
        case .dragHasThePinch: "dragHasThePinch"
        case .liftOutlivesItsPress: "liftOutlivesItsPress"
        case .releasedByItsTap: "releasedByItsTap"
        case .pinchElsewhere: "pinchElsewhere"
        case .itemWent: "itemWent"
        case .noPinch: "noPinch"
        }
    }

    /// The reason in a few plain words, with its numbers, for a trace.
    public var description: String {
        switch self {
        case .began: "a pinch began"
        case .pressJoined: "the press joined the pinch the drag has"
        case .heldStill: "held still: the item lifts"
        case .containerScrolled: "the container scrolled during the pinch"
        case .scrollLeftTheItemUp: "the container scrolled, the item kept up"
        case .toldAlready: "told already"
        case .letGoBeforeTheHold: "let go before the hold: no lift"
        case .armed: "the pull armed"
        case .armingNotDue: "the arming isn't due"
        case .notANumber: "a move that isn't a number"
        case .movedFirst(let distance): "moved \(pluckPoints(distance)) before the hold: a scroll"
        case .withinStillness(let distance): "\(pluckPoints(distance)) from the touch, within the stillness"
        case .scrolling(let why): "a scroll (\(why == .movedFirst ? "moved first" : "the container scrolled"))"
        case .notArmedYet: "lifted, the pull not armed yet"
        case .notLifted: "the item isn't lifted"
        case .notAPull(let judgement): "no pull: \(judgement)"
        case .pulled(let judgement): "pull: \(judgement)"
        case .pullMoved: "the pull moved"
        case .pulledAlready: "pulled already"
        case .dragEnded: "the drag ended"
        case .dragCancelled: "the drag was cancelled"
        case .pressEnded: "the press ended"
        case .dragHasThePinch: "the press ended, the drag has the pinch"
        case .liftOutlivesItsPress: "the press ended, the lift kept past it"
        case .releasedByItsTap: "the release tap came: settles"
        case .pinchElsewhere: "a pinch began elsewhere: settles, its end unseen"
        case .itemWent: "the item went"
        case .noPinch: "no pinch under way"
        }
    }
}

extension PluckPullJudgement: CustomStringConvertible {
    /// The judgement in a few words: "too slanted, 30.0 deep, 120.0 across,
    /// needs 27.0 pt".
    public var description: String {
        let verdict = switch verdict {
        case .pulls: "pulls"
        case .tooShallow: "too shallow"
        case .tooSlanted: "too slanted"
        case .tooShort: "too short"
        case .notANumber: "not a number"
        }
        return "\(verdict), \(pluckOneDecimal(depth)) deep, \(pluckOneDecimal(drift)) across, needs \(pluckPoints(threshold))"
    }
}

/// A distance in points to one decimal: "16.0 pt".
private func pluckPoints(_ points: Double) -> String {
    "\(pluckOneDecimal(points)) pt"
}

/// A number to one decimal, "-3.5", without Foundation's formatting.
private func pluckOneDecimal(_ number: Double) -> String {
    guard number.isFinite else { return "\(number)" }
    let tenths = (number * 10).rounded()
    let sign = tenths < 0 ? "-" : ""
    let whole = Int(abs(tenths)) / 10
    let tenth = Int(abs(tenths)) % 10
    return "\(sign)\(whole).\(tenth)"
}
