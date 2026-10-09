/// A scrolling container's scrolls, as its scroll view says it begins and
/// stops scrolling, by a hand, coasting, or easing: what a hold on one of
/// its items asks, whether the container scrolled at any time during its
/// pinch, so a pinch that caught the container coasting, or scrolled it and
/// came to rest, lifts nothing (`PluckPress`). Scroll first.
public struct PluckScrolls: Equatable, Sendable {
    /// Whether the container scrolls now.
    public private(set) var isScrolling = false
    /// When it last stopped scrolling; nil if it never has.
    public private(set) var lastStopped: ContinuousClock.Instant?

    public init() {}

    /// The container began scrolling, `scrolls`, or stopped, at `now`;
    /// saying it stopped while it wasn't scrolling changes nothing.
    public mutating func scrolling(_ scrolls: Bool, at now: ContinuousClock.Instant) {
        guard scrolls != isScrolling else { return }
        isScrolling = scrolls
        if !scrolls {
            lastStopped = now
        }
    }

    /// Whether the container scrolled at any time since `touch`, a pinch's
    /// touch: it scrolls now, or stopped since.
    public func scrolled(since touch: ContinuousClock.Instant) -> Bool {
        if isScrolling {
            return true
        }
        guard let lastStopped else { return false }
        return lastStopped >= touch
    }
}

/// What a scroll view says it's doing, as SwiftUI's `ScrollPhase` does,
/// in plain values a trace can keep.
public enum PluckScrollPhase: String, Equatable, Sendable, Codable, CaseIterable {
    /// At rest.
    case idle
    /// Following a pinch that hasn't moved it yet.
    case tracking
    /// Moving with a pinch.
    case interacting
    /// Coasting after a pinch let go.
    case decelerating
    /// Easing to a scroll the code asked of it.
    case animating

    /// Whether the container scrolls in this phase: moving with a pinch,
    /// coasting, or easing. Tracking a pinch that hasn't moved it yet
    /// isn't, so an item's hold can come then.
    public var isScrolling: Bool {
        switch self {
        case .interacting, .decelerating, .animating: true
        case .idle, .tracking: false
        }
    }
}
