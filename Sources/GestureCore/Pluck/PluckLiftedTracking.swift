/// How a pinch on a pluckable item is followed once its item has lifted,
/// and how its drag is kept from competing with the grid's scroll view
/// before then, as the tuning chooses (`PluckTuning.liftedTracking`).
///
/// Until October 10 the item's drag was attached from the touch, beside its
/// button, from a 15 pt start, so it heard the pinch early and told the hold
/// how the hand moved. But it competed with the grid's scroll view for the
/// pinch: in Alex's clip that day the scroll view's pan failed in the
/// instant the item's drag first spoke, and the scroll was eaten. On the
/// headset, a 60 pt start fixed it ("Putting drag start to like 60pt does
/// actually fix the problem"): the pan, starting at about 10 pt, takes a
/// scroll long before the drag could. But a drag that first speaks at 60 pt,
/// 4.4 cm from the touch, does so past the 2.5 cm break-free distance, and
/// the lifted item's sticky stage is lost.
///
/// So the drag is held back until the lift, then let in to hear the pinch
/// from there, the scroll being held off from the lift on: by its start,
/// the known-safe 60 pt, brought down to nothing at the lift, should the
/// drag's recognizer take its new start mid-pinch; or by its gesture mask,
/// left out until the lift, should a gesture let in mid-pinch hear it. Or
/// the pinching hand is followed by hand tracking from the lift, which no
/// gesture competes with, the drag held back beneath it. Before the lift,
/// the hold is given up by the scroll view: its phase, its offset, or the
/// button's press it cancels as it takes the pinch, its pan starting at
/// about the hold's 10 pt along the scroll; and, held back by its start,
/// by the drag's word at 60 pt, a move that far being a scroll or a yank.
public enum PluckLiftedTracking: Equatable, Sendable {
    /// How the item's drag is kept from competing with the scroll view until
    /// the lift.
    public enum HeldBack: Equatable, Sendable {
        /// Attached from the touch, its start the tuning's held-back start,
        /// 60 pt, which keeps it from competing (`heldBackDragStart`), and
        /// brought down to nothing at the lift, `lowered`, or kept there
        /// throughout, the known-safe fallback, as Alex tried it.
        case byItsStart(lowered: Bool)
        /// Left out of the item's gestures by its mask until the lift, then
        /// let in, from nothing.
        case byItsGestureMask
    }

    /// The item's drag, attached from the touch at the tuning's
    /// `dragStartDistance`, 15 pt, as until October 10, which competes with
    /// the scroll view; to compare.
    case dragFromTheTouch
    /// The item's drag, held back until the lift as `HeldBack` says.
    case dragHeldBack(HeldBack)
    /// The pinching hand, by hand tracking, from the lift: the hand whose
    /// pinch closed nearest the item's press, its thumb and index fingertips'
    /// midpoint the pinch's place, and their opening its release. The drag
    /// is held back beneath it, as `HeldBack` says, and follows the pinch
    /// where the hand can't be followed: as in the simulator, without hand
    /// tracking's permission, with the space closed, or with no hand
    /// pinched.
    case handFromTheLift(HeldBack)

    /// How the drag is held back; nil where it's attached from the touch.
    public var heldBack: HeldBack? {
        switch self {
        case .dragFromTheTouch: nil
        case .dragHeldBack(let heldBack), .handFromTheLift(let heldBack): heldBack
        }
    }

    /// Whether the pinching hand is followed by hand tracking from the lift.
    public var followsTheHand: Bool {
        if case .handFromTheLift = self { return true }
        return false
    }

    /// Whether the drag is let in at the lift to hear the pinch from there:
    /// its start brought down, or its mask opened. Its first word after the
    /// lift, should it come before the held-back start, stands for where the
    /// pinch was as its item lifted.
    public var letsDragInAtTheLift: Bool {
        switch heldBack {
        case .byItsStart(let lowered): lowered
        case .byItsGestureMask: true
        case nil: false
        }
    }

    /// How the item's drag is made, `attached` once its pinch has lifted the
    /// item, at `tuning`: its start distance, in points, and whether its
    /// gesture mask lets it in.
    public func drag(attached: Bool, tuning: PluckTuning) -> (startDistance: Double, isLetIn: Bool) {
        switch heldBack {
        case nil: (tuning.dragStartDistance, true)
        case .byItsStart(let lowered): (attached && lowered ? 0 : tuning.heldBackDragStart, true)
        case .byItsGestureMask: (0, attached)
        }
    }

    /// The choice in a few words, for a trace.
    public var description: String {
        let heldBackWords = switch heldBack {
        case .byItsStart(lowered: true): "held back by its start, brought down at the lift"
        case .byItsStart(lowered: false): "held back by its start throughout"
        case .byItsGestureMask: "held back by its gesture mask, let in at the lift"
        case nil: ""
        }
        return switch self {
        case .dragFromTheTouch: "the drag from the touch"
        case .dragHeldBack: "the drag \(heldBackWords)"
        case .handFromTheLift: "the hand from the lift, by hand tracking, over the drag \(heldBackWords)"
        }
    }
}

extension PluckTuning {
    /// How a lifted pinch is followed, as the tuning's switches choose, in
    /// order: the drag from the touch while the hold counts from the drag
    /// (`holdsFromTheDrag`), the item having no button then; else the hand
    /// from the lift (`tracksLiftedPinchByHand`); else the drag held back
    /// (`holdsDragBack`); else the drag from the touch. The drag is held
    /// back by its mask (`holdsDragBackByItsMask`), or else by its start,
    /// brought down at the lift unless `lowersDragStartAtTheLift` is off.
    public var liftedTracking: PluckLiftedTracking {
        let heldBack: PluckLiftedTracking.HeldBack = holdsDragBackByItsMask
            ? .byItsGestureMask
            : .byItsStart(lowered: lowersDragStartAtTheLift)
        if holdsFromTheDrag { return .dragFromTheTouch }
        if tracksLiftedPinchByHand { return .handFromTheLift(heldBack) }
        if holdsDragBack { return .dragHeldBack(heldBack) }
        return .dragFromTheTouch
    }
}
