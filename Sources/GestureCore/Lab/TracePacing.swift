/// When a trace shows the changes to its log: the first change after a quiet
/// spell at once, then at most once every `interval`, the changes that came
/// meanwhile shown together as it ends. A gesture can write its trace many
/// times a second, as a pull's drag notes do, and each showing draws the
/// trace again, so a burst draws it a few times a second rather than at
/// every event, each event showing within `interval` of when it came.
///
/// It's told each change and each showing, with their times on the clock the
/// caller keeps, and says when to show:
///
///     switch pacing.changed(at: now) {
///     case .now: show()
///     case .at(let time): schedule(show, at: time)
///     case .alreadyDue: break
///     }
///     // and in show():
///     pacing.shown(at: now)
public struct TracePacing: Sendable, Equatable {
    /// When to show a change.
    public enum Showing: Sendable, Equatable {
        /// At once: nothing was shown within the interval before it.
        case now
        /// At this time, the interval after the last showing.
        case at(ContinuousClock.Instant)
        /// With the showing already due, which shows it too.
        case alreadyDue
    }

    /// The least time between two showings: a tenth of a second unless it's
    /// told otherwise.
    public let interval: Duration

    /// When it last showed; nil before it has.
    private var lastShown: ContinuousClock.Instant?
    /// Whether a showing is due, told to the caller and not yet done.
    private var isDue = false

    public init(interval: Duration = .milliseconds(100)) {
        self.interval = interval
    }

    /// The log changed at `time`: when to show it.
    public mutating func changed(at time: ContinuousClock.Instant) -> Showing {
        if isDue { return .alreadyDue }
        guard let lastShown, time < lastShown.advanced(by: interval) else { return .now }
        isDue = true
        return .at(lastShown.advanced(by: interval))
    }

    /// The log was shown at `time`, whatever showing was due with it.
    public mutating func shown(at time: ContinuousClock.Instant) {
        lastShown = time
        isDue = false
    }
}
