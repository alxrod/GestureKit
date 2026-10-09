import Testing
@testable import GestureCore

/// Whether a container scrolled during a pinch on one of its items: it did
/// if it scrolls now, or stopped scrolling since the pinch touched, as a
/// pinch that caught it coasting.
@Suite struct PluckScrollsTests {
    let start = ContinuousClock.now

    func at(_ seconds: Double) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    @Test func aContainerThatNeverScrolledDidntScroll() {
        let scrolls = PluckScrolls()
        #expect(!scrolls.isScrolling)
        #expect(!scrolls.scrolled(since: at(0)))
    }

    @Test func aContainerScrollingNowScrolled() {
        var scrolls = PluckScrolls()
        scrolls.scrolling(true, at: at(0.2))
        #expect(scrolls.isScrolling)
        #expect(scrolls.scrolled(since: at(1)))
    }

    /// A scroll over before the pinch touched isn't the pinch's.
    @Test func aScrollOverBeforeTheTouchDoesntCount() {
        var scrolls = PluckScrolls()
        scrolls.scrolling(true, at: at(0))
        scrolls.scrolling(false, at: at(0.5))
        #expect(!scrolls.scrolled(since: at(0.6)))
    }

    /// One that stopped after the touch, as a coast the pinch caught, or
    /// that began and ended within the pinch, counts.
    @Test func aScrollThatStoppedSinceTheTouchCounts() {
        var caught = PluckScrolls()
        caught.scrolling(true, at: at(0))
        caught.scrolling(false, at: at(0.6))
        #expect(caught.scrolled(since: at(0.5)))

        var within = PluckScrolls()
        within.scrolling(true, at: at(0.6))
        within.scrolling(false, at: at(0.7))
        #expect(within.scrolled(since: at(0.5)))
    }

    /// Saying it stopped when it wasn't scrolling changes nothing.
    @Test func stoppingWhenNotScrollingChangesNothing() {
        var scrolls = PluckScrolls()
        scrolls.scrolling(false, at: at(1))
        #expect(!scrolls.scrolled(since: at(0)))
        scrolls.scrolling(true, at: at(2))
        scrolls.scrolling(false, at: at(3))
        scrolls.scrolling(false, at: at(5))
        #expect(!scrolls.scrolled(since: at(4)))
    }

    /// A scroll view moving with a pinch, coasting, or easing scrolls; one
    /// at rest, or tracking a pinch that hasn't moved it, doesn't, so an
    /// item's hold can come then.
    @Test func whichPhasesScroll() {
        #expect(PluckScrollPhase.allCases.filter(\.isScrolling) == [.interacting, .decelerating, .animating])
    }
}
