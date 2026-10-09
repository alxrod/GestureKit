/// A scrolling container whose items a pinch plucks, a grid or a list: its
/// scrolls, as its scroll view tells their phases; which of its items is
/// lifted, one at most; and whether its scroll is held off under it, as
/// the tuning says (`PluckTuning.stopsScrollUnderLiftedItem`), so the lifted
/// pinch's moves belong to the item rather than the scroll.
///
/// - **An item lifts** as its pinch's hold says (`PluckPress.Action.lift`).
///   One lifted while another is, as by another hand, takes its place, the
///   other settling. A lift is no scroll, so the container's scroll is taken
///   as stopped then, lest a scroll whose stop went unheard, as its scroll
///   view went off, keep every hold after it from lifting.
/// - **It settles** as its pinch says, or as the caller settles whichever
///   is lifted, as when the container leaves the screen; and, as the tuning
///   says (`scrollSettlesLiftedItem`), as the container begins to scroll.
/// - **Its scroll is held off** while an item is lifted, if the tuning
///   stops it; the caller disables its scroll view's scrolling meanwhile.
public struct PluckContainer<Item: Hashable> {
    /// What a word to the container changed.
    public struct Change: Equatable {
        /// The item that settled, if one did.
        public var settled: Item?
        /// Whether the container's scroll is held off now.
        public var holdsItsScroll: Bool
        /// Whether the word turned the hold on the scroll on or off.
        public var scrollHoldChanged: Bool

        public init(settled: Item? = nil, holdsItsScroll: Bool, scrollHoldChanged: Bool = false) {
            self.settled = settled
            self.holdsItsScroll = holdsItsScroll
            self.scrollHoldChanged = scrollHoldChanged
        }
    }

    /// The tuning it goes by: whether its scroll stops under a lifted item,
    /// and whether its scroll beginning settles one.
    public var tuning: PluckTuning
    /// Its scrolls, which a hold asks about (`scrolled(since:)`).
    public private(set) var scrolls = PluckScrolls()
    /// Its scroll view's phase, as last told.
    public private(set) var phase = PluckScrollPhase.idle
    /// The item lifted; nil while none is.
    public private(set) var liftedItem: Item?

    public init(tuning: PluckTuning = PluckTuning()) {
        self.tuning = tuning
    }

    /// Whether its scroll is held off: an item is lifted, and the tuning
    /// stops the scroll under one.
    public var holdsItsScroll: Bool {
        tuning.stopsScrollUnderLiftedItem && liftedItem != nil
    }

    /// `item` lifted, at `now`: it takes the place of another lifted, which
    /// settles, and the container's scroll is taken as stopped.
    public mutating func lift(_ item: Item, at now: ContinuousClock.Instant) -> Change {
        changing {
            guard $0.liftedItem != item else { return nil }
            let displaced = $0.liftedItem
            $0.liftedItem = item
            $0.scrolls.scrolling(false, at: now)
            return displaced
        }
    }

    /// `item` settled, as its pinch says; an item that isn't lifted is left
    /// as it is.
    public mutating func settle(_ item: Item) -> Change {
        changing {
            guard $0.liftedItem == item else { return nil }
            $0.liftedItem = nil
            return item
        }
    }

    /// Whichever item is lifted settles, as when the container leaves the
    /// screen, or its contents change under it.
    public mutating func settleLiftedItem() -> Change {
        changing {
            let settled = $0.liftedItem
            $0.liftedItem = nil
            return settled
        }
    }

    /// Its scroll view's phase changed to `phase`, at `now`: it begins or
    /// stops scrolling, and a scroll settles a lifted item, should the
    /// tuning say so.
    public mutating func scrollPhaseChanged(to phase: PluckScrollPhase, at now: ContinuousClock.Instant) -> Change {
        changing {
            $0.phase = phase
            $0.scrolls.scrolling(phase.isScrolling, at: now)
            guard phase.isScrolling, $0.tuning.scrollSettlesLiftedItem, let lifted = $0.liftedItem else { return nil }
            $0.liftedItem = nil
            return lifted
        }
    }

    /// Its scroll view left the screen, at `now`: it no longer scrolls.
    public mutating func disappeared(at now: ContinuousClock.Instant) -> Change {
        changing {
            $0.phase = .idle
            $0.scrolls.scrolling(false, at: now)
            return nil
        }
    }

    /// Whether it scrolled at any time since `touch`, a pinch's touch on one
    /// of its items: the pinch is a scroll then, and its item stays down.
    public func scrolled(since touch: ContinuousClock.Instant) -> Bool {
        scrolls.scrolled(since: touch)
    }

    /// Makes a change, giving the item it settled, and says what it did to
    /// the hold on the scroll.
    private mutating func changing(_ change: (inout Self) -> Item?) -> Change {
        let held = holdsItsScroll
        let settled = change(&self)
        return Change(settled: settled, holdsItsScroll: holdsItsScroll, scrollHoldChanged: held != holdsItsScroll)
    }
}

extension PluckContainer: Sendable where Item: Sendable {}
extension PluckContainer.Change: Sendable where Item: Sendable {}
