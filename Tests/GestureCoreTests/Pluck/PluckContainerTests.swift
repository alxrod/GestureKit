import Testing
@testable import GestureCore

/// A container whose items a pinch plucks: which item is lifted, whether
/// its scroll is held off under it, as the tuning says, and its scrolls.
@Suite struct PluckContainerTests {
    let start = ContinuousClock.now

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    /// At the default, a lifted item holds its container's scroll off until
    /// it settles.
    @Test func aLiftedItemHoldsTheScrollOffUntilItSettles() {
        var container = PluckContainer<String>()
        #expect(!container.holdsItsScroll)
        #expect(container.lift("a", at: at(0)) == .init(settled: nil, holdsItsScroll: true, scrollHoldChanged: true))
        #expect(container.liftedItem == "a")
        #expect(container.settle("a") == .init(settled: "a", holdsItsScroll: false, scrollHoldChanged: true))
        #expect(container.liftedItem == nil)
    }

    /// Tuned not to, the container goes on scrolling under a lifted item.
    @Test func tunedNotToTheScrollGoesOnUnderALiftedItem() {
        var container = PluckContainer<String>(tuning: PluckTuning(stopsScrollUnderLiftedItem: false))
        #expect(container.lift("a", at: at(0)) == .init(settled: nil, holdsItsScroll: false))
        #expect(container.liftedItem == "a")
        #expect(!container.holdsItsScroll)
    }

    /// An item lifted while another is takes its place, the other settling,
    /// the scroll held off throughout; lifting the same item again changes
    /// nothing.
    @Test func aSecondLiftTakesTheFirstsPlace() {
        var container = PluckContainer<String>()
        _ = container.lift("a", at: at(0))
        #expect(container.lift("b", at: at(1)) == .init(settled: "a", holdsItsScroll: true))
        #expect(container.liftedItem == "b")
        #expect(container.lift("b", at: at(2)) == .init(settled: nil, holdsItsScroll: true))
    }

    /// Settling an item that isn't lifted leaves the lifted one up.
    @Test func settlingAnotherItemChangesNothing() {
        var container = PluckContainer<String>()
        _ = container.lift("a", at: at(0))
        #expect(container.settle("b") == .init(settled: nil, holdsItsScroll: true))
        #expect(container.liftedItem == "a")
        #expect(container.settleLiftedItem() == .init(settled: "a", holdsItsScroll: false, scrollHoldChanged: true))
        #expect(container.settleLiftedItem() == .init(settled: nil, holdsItsScroll: false))
    }

    /// A lift is no scroll: a scroll whose stop went unheard is taken as
    /// stopped, so it keeps no later hold from lifting.
    @Test func aLiftTakesTheScrollAsStopped() {
        var container = PluckContainer<String>()
        _ = container.scrollPhaseChanged(to: .interacting, at: at(0))
        #expect(container.scrolls.isScrolling)
        _ = container.lift("a", at: at(1))
        #expect(!container.scrolls.isScrolling)
        #expect(!container.scrolled(since: at(1.5)))
    }

    /// Its scroll view's phases tell its scrolls: tracking a pinch isn't a
    /// scroll, moving with one is, and a hold asks whether it scrolled since
    /// its touch.
    @Test func thePhasesTellItsScrolls() {
        var container = PluckContainer<String>()
        _ = container.scrollPhaseChanged(to: .tracking, at: at(0))
        #expect(!container.scrolled(since: at(0)))
        _ = container.scrollPhaseChanged(to: .interacting, at: at(0.2))
        #expect(container.scrolled(since: at(0)))
        _ = container.scrollPhaseChanged(to: .decelerating, at: at(0.4))
        _ = container.scrollPhaseChanged(to: .idle, at: at(1))
        #expect(container.phase == .idle)
        #expect(container.scrolled(since: at(0.9)))
        #expect(!container.scrolled(since: at(1.1)))
    }

    /// At the default, the container beginning to scroll settles a lifted
    /// item; tracking a pinch doesn't.
    @Test func aScrollBeginningSettlesALiftedItem() {
        var container = PluckContainer<String>()
        _ = container.lift("a", at: at(0))
        #expect(container.scrollPhaseChanged(to: .tracking, at: at(0.1)) == .init(settled: nil, holdsItsScroll: true))
        #expect(container.scrollPhaseChanged(to: .interacting, at: at(0.2)) == .init(settled: "a", holdsItsScroll: false, scrollHoldChanged: true))
    }

    /// Tuned not to, a scroll leaves a lifted item up.
    @Test func tunedNotToAScrollLeavesALiftedItemUp() {
        var container = PluckContainer<String>(tuning: PluckTuning(stopsScrollUnderLiftedItem: false, scrollSettlesLiftedItem: false))
        _ = container.lift("a", at: at(0))
        #expect(container.scrollPhaseChanged(to: .interacting, at: at(0.2)) == .init(settled: nil, holdsItsScroll: false))
        #expect(container.liftedItem == "a")
    }

    /// A container leaving the screen no longer scrolls.
    @Test func aContainerThatWentNoLongerScrolls() {
        var container = PluckContainer<String>()
        _ = container.scrollPhaseChanged(to: .decelerating, at: at(0))
        _ = container.disappeared(at: at(1))
        #expect(!container.scrolls.isScrolling)
        #expect(container.phase == .idle)
        #expect(!container.scrolled(since: at(1.5)))
    }
}
