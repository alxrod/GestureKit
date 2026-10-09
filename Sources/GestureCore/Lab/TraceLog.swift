import Foundation

/// One thing that happened in a traced interaction: a name, such as
/// "touch", "lift", or "release", and a detail saying what it was, such as
/// "held still 0.50 s" or "moved 2.1 cm toward the viewer", at a time
/// counted from the interaction's beginning.
public struct TraceEvent: Sendable, Hashable {
    /// How long after its interaction began it happened.
    public var offset: Duration
    /// What happened, in a word or two.
    public var name: String
    /// What it was, in a few words; empty for nothing more to say.
    public var detail: String

    public init(offset: Duration, name: String, detail: String = "") {
        self.offset = offset
        self.name = name
        self.detail = detail
    }
}

/// One interaction with a gesture, from its first event to its outcome, as
/// GestureLab's trace shows it and the console logs it: which gesture, what
/// it was on, when it began, what happened in it, and what it came to.
public struct TracedInteraction: Sendable, Hashable, Identifiable {
    /// Its number in its log, counting from 1, which the trace and the
    /// console show as "#12".
    public let id: Int
    /// Which gesture it was, such as "Pluck" or "Trace check".
    public let gesture: String
    /// What it was on, or what it was, such as "Pinch on item 4".
    public let title: String
    /// When it began, by the wall clock, for the trace to show.
    public let date: Date
    /// When it began, by the clock its events are timed on.
    public let began: ContinuousClock.Instant
    /// What happened in it, in order.
    public fileprivate(set) var events: [TraceEvent] = []
    /// What it came to, such as "tap", "scroll", or "pull"; nil while it's
    /// under way.
    public fileprivate(set) var outcome: String?
    /// How long it lasted, from its beginning to its outcome; nil while it's
    /// under way.
    public fileprivate(set) var lasted: Duration?

    /// Whether it has no outcome yet.
    public var isUnderWay: Bool { outcome == nil }

    /// The interaction on one line, for the console:
    ///
    ///     #3 Trace check · Pinch on the cube → tap, 0.12 s: touch +0.00 s (size 0.20 m); release +0.12 s (moved 0.2 cm)
    public var summary: String {
        var line = "#\(id) \(gesture) · \(title) → "
        if let outcome, let lasted {
            line += "\(outcome), \(traceSeconds(lasted)) s"
        } else {
            line += "under way"
        }
        guard !events.isEmpty else { return line }
        let events = events.map { event in
            var text = "\(event.name) +\(traceSeconds(event.offset)) s"
            if !event.detail.isEmpty { text += " (\(event.detail))" }
            return text
        }
        return line + ": " + events.joined(separator: "; ")
    }

    init(id: Int, gesture: String, title: String, date: Date, began: ContinuousClock.Instant) {
        self.id = id
        self.gesture = gesture
        self.title = title
        self.date = date
        self.began = began
    }
}

/// The last few interactions with a gesture, newest first, as GestureLab's
/// trace keeps them: each begun, given its events, and finished with its
/// outcome by whoever watches the gesture, with times from a clock the
/// caller gives, so a test steps it.
///
/// It keeps at most `capacity`, the oldest going as a new one begins past
/// that, whether it has finished or not, so an interaction whose end went
/// unseen goes in time too.
public struct TraceLog: Sendable, Equatable {
    /// How many interactions a log keeps unless it's told otherwise.
    public static let defaultCapacity = 30

    /// The most interactions it keeps.
    public let capacity: Int
    /// The interactions it keeps, newest first.
    public private(set) var interactions: [TracedInteraction] = []
    private var lastID = 0

    /// A log keeping the last `capacity` interactions, at least one.
    public init(capacity: Int = TraceLog.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// Begins an interaction with `gesture`, on what `title` says, at `time`
    /// on the events' clock and `date` on the wall clock, and gives its id.
    @discardableResult
    public mutating func begin(_ gesture: String, title: String, at time: ContinuousClock.Instant, date: Date) -> TracedInteraction.ID {
        lastID += 1
        interactions.insert(TracedInteraction(id: lastID, gesture: gesture, title: title, date: date, began: time), at: 0)
        if interactions.count > capacity { interactions.removeLast(interactions.count - capacity) }
        return lastID
    }

    /// Adds an event named `name` to the interaction `id`, at `time`, no
    /// earlier than its beginning. An interaction may take events after its
    /// outcome, as a coast that goes on after its release; one the log no
    /// longer keeps takes none.
    public mutating func record(_ name: String, detail: String = "", in id: TracedInteraction.ID, at time: ContinuousClock.Instant) {
        guard let index = interactions.firstIndex(where: { $0.id == id }) else { return }
        let offset = max(.zero, interactions[index].began.duration(to: time))
        interactions[index].events.append(TraceEvent(offset: offset, name: name, detail: detail))
    }

    /// Gives the interaction `id` its outcome, at `time`, and returns it
    /// finished, for the console; nil, changing nothing, for one already
    /// finished or no longer kept.
    @discardableResult
    public mutating func finish(_ id: TracedInteraction.ID, outcome: String, at time: ContinuousClock.Instant) -> TracedInteraction? {
        guard let index = interactions.firstIndex(where: { $0.id == id }),
              interactions[index].isUnderWay else { return nil }
        interactions[index].outcome = outcome
        interactions[index].lasted = max(.zero, interactions[index].began.duration(to: time))
        return interactions[index]
    }

    /// The interaction `id`, if the log still keeps it.
    public func interaction(withID id: TracedInteraction.ID) -> TracedInteraction? {
        interactions.first { $0.id == id }
    }

    /// Forgets every interaction; the next one's number follows on from the
    /// last, so the console's numbers never repeat.
    public mutating func clear() {
        interactions.removeAll()
    }
}

/// A duration in seconds, to two decimals: "0.50".
private func traceSeconds(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.2f", Double(seconds) + Double(attoseconds) / 1e18)
}
