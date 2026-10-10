/// How a pinch on a pluckable item is followed once its item has lifted,
/// and whether anything on the item hears the pinch before then, as the
/// tuning chooses (`PluckTuning.liftedTracking`).
///
/// Until October 10 the item's drag was attached from the touch, beside its
/// button, so it heard the pinch from its 15 pt start and told the hold how
/// the hand moved. But it competed with the grid's scroll view for the
/// pinch: in Alex's clip that day, the scroll view's pan failed in the
/// instant the item's drag first spoke, and the scroll was eaten, the rules
/// telling it as a scroll the scroll view never took. So nothing on the
/// item but its button need hear the pinch before the lift: the scroll view
/// has it to scroll, and the hold is given up by what the scroll view says,
/// its phase, its offset moving, or the button's press it cancels as it
/// takes the pinch. From the lift, with the scroll held off, the pinch is
/// followed by the item's drag, attached only then, or by the pinching
/// hand, through hand tracking, which no gesture competes with.
public enum PluckLiftedTracking: Equatable, Sendable {
    /// How the item's drag is kept from hearing the pinch until the lift.
    public enum HeldBack: String, Equatable, Sendable, Codable {
        /// The drag is left out of the item's gestures by its mask until
        /// the item lifts, then let in. Whether a gesture let in mid-touch
        /// hears the pinch already under way, only the headset can say.
        case byItsGestureMask
        /// The drag is attached from the touch with a start no pinch reaches
        /// before the lift (`PluckLiftedTracking.unreachableStart`), then
        /// brought down to nothing, should the drag's recognizer take its
        /// new start without beginning again.
        case byItsStartDistance
    }

    /// The item's drag, attached from the touch, beside its button, from its
    /// start distance, as until October 10: it hears every move before the
    /// hold, and may take the pinch from the scroll view.
    case dragFromTheTouch
    /// The item's drag, held back until the item lifts, then hearing the
    /// pinch from where it stood then.
    case dragOnceLifted(HeldBack)
    /// The pinching hand, followed by hand tracking from the lift: the hand
    /// whose pinch closed nearest the item's press, its thumb and index
    /// fingertips' midpoint the pinch's place, and its fingers opening its
    /// release. The drag is held back as for `dragOnceLifted` and attached
    /// at the lift too, so where the hand can't be followed, as in the
    /// simulator, without hand tracking's permission, or with no hand
    /// pinched, the drag follows the pinch instead.
    case handOnceLifted(HeldBack)

    /// A start no pinch reaches before the lift, in points: 100,000, some
    /// 70 m at a window's own size.
    public static var unreachableStart: Double { 100_000 }

    /// Whether the item's drag hears a pinch before its item has lifted.
    public var dragHearsThePinchBeforeTheLift: Bool {
        if case .dragFromTheTouch = self { return true }
        return false
    }

    /// Whether the pinching hand is followed by hand tracking from the lift.
    public var followsTheHand: Bool {
        if case .handOnceLifted = self { return true }
        return false
    }

    /// How the drag is held back until the lift; nil where it isn't.
    public var heldBack: HeldBack? {
        switch self {
        case .dragFromTheTouch: nil
        case .dragOnceLifted(let heldBack), .handOnceLifted(let heldBack): heldBack
        }
    }

    /// How the item's drag is made, `attached` once its pinch has lifted the
    /// item, at `tuning`: its start distance, in points, and whether its
    /// gesture mask lets it in.
    public func drag(attached: Bool, tuning: PluckTuning) -> (startDistance: Double, isLetIn: Bool) {
        switch heldBack {
        case nil: (tuning.dragStartDistance, true)
        case .byItsGestureMask: (0, attached)
        case .byItsStartDistance: (attached ? 0 : Self.unreachableStart, true)
        }
    }

    /// The choice in a few words, for a trace.
    public var description: String {
        let heldBackWords = switch heldBack {
        case .byItsGestureMask: "held back by its gesture mask"
        case .byItsStartDistance: "held back by an unreachable start"
        case nil: ""
        }
        return switch self {
        case .dragFromTheTouch: "the drag from the touch"
        case .dragOnceLifted: "the drag once lifted, \(heldBackWords)"
        case .handOnceLifted: "the hand once lifted, by hand tracking, else the drag once lifted, \(heldBackWords)"
        }
    }
}

extension PluckTuning {
    /// How a lifted pinch is followed, as the tuning's switches choose, in
    /// order: the drag from the touch while the hold counts from the drag
    /// (`holdsFromTheDrag`), the item having no button then; else the hand
    /// once lifted (`tracksLiftedPinchByHand`); else the drag once lifted
    /// (`attachesDragOnceLifted`); else the drag from the touch. Held back by
    /// its start distance (`holdsDragBackByItsStart`), or else its gesture
    /// mask.
    public var liftedTracking: PluckLiftedTracking {
        let heldBack: PluckLiftedTracking.HeldBack = holdsDragBackByItsStart ? .byItsStartDistance : .byItsGestureMask
        if holdsFromTheDrag { return .dragFromTheTouch }
        if tracksLiftedPinchByHand { return .handOnceLifted(heldBack) }
        if attachesDragOnceLifted { return .dragOnceLifted(heldBack) }
        return .dragFromTheTouch
    }
}
