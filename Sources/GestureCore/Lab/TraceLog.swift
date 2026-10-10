import Foundation

/// How far something reached, for a trace to keep the farthest of a run of
/// events: a value and its unit, "0.42 m", told with as many decimals as it
/// says.
public struct TraceMeasure: Sendable, Hashable {
    /// How far, in `unit`.
    public var value: Double
    /// Its unit, a word or a symbol: "m", "pt", "cm".
    public var unit: String
    /// How many decimals it's told with.
    public var decimals: Int

    public init(_ value: Double, _ unit: String, decimals: Int = 2) {
        self.value = value
        self.unit = unit
        self.decimals = decimals
    }

    /// The measure in words: "0.42 m".
    public var text: String {
        String(format: "%.\(max(0, decimals))f", value) + (unit.isEmpty ? "" : " \(unit)")
    }
}

/// One line of a traced interaction: one thing that happened, a name, such
/// as "touch", "lift", or "release", and a detail saying what it was, such
/// as "held still 0.50 s" or "moved 2.1 cm toward the viewer", at a time
/// counted from the interaction's beginning; or a run of things of one name
/// that came one after another, as a drag's words do, folded into one line:
/// how many, the first's time and detail, the latest's, and the farthest
/// any of them reached, where they said.
public struct TraceEvent: Sendable, Hashable {
    /// How long after its interaction began it happened, or the first of
    /// its run did.
    public var offset: Duration
    /// What happened, in a word or two.
    public var name: String
    /// What it was, in a few words, or the first of its run; empty for
    /// nothing more to say.
    public var detail: String
    /// How many things of its name it stands for: 1 for one alone.
    public var count: Int
    /// When the latest of its run happened; its own offset for one alone.
    public var latestOffset: Duration
    /// What the latest of its run said; nil for one alone.
    public var latestDetail: String?
    /// The farthest any of its run reached, where they said; for things
    /// that measure in different units, the latest's.
    public var farthest: TraceMeasure?

    public init(offset: Duration, name: String, detail: String = "", measure: TraceMeasure? = nil) {
        self.offset = offset
        self.name = name
        self.detail = detail
        count = 1
        latestOffset = offset
        latestDetail = nil
        farthest = measure
    }

    /// Whether it stands for a run of things of its name.
    public var isFolded: Bool { count > 1 }

    /// Folds into it another thing of its name, at `offset`, saying
    /// `detail`, having reached `measure`.
    mutating func fold(at offset: Duration, detail: String, measure: TraceMeasure?) {
        count += 1
        latestOffset = max(latestOffset, offset)
        latestDetail = detail
        if let measure {
            if let farthest, farthest.unit == measure.unit {
                if measure.value > farthest.value { self.farthest = measure }
            } else {
                farthest = measure
            }
        }
    }

    /// Its time, as a trace shows it: "+0.12 s", or for a run, "+0.20–1.10 s".
    public var timeText: String {
        isFolded
            ? "+\(traceSeconds(offset))–\(traceSeconds(latestOffset)) s"
            : "+\(traceSeconds(offset)) s"
    }

    /// Its name, as a trace shows it: "drag", or for a run, "drag ×14".
    public var nameText: String {
        isFolded ? "\(name) ×\(count)" : name
    }

    /// What it said, as a trace shows it: its detail; for a run, the
    /// farthest any reached first, so a line cut short keeps it, then the
    /// first's detail and the latest's; empty for nothing.
    public var detailText: String {
        var parts: [String] = []
        if isFolded, let farthest {
            parts.append("farthest \(farthest.text)")
        }
        if isFolded, let latestDetail, latestDetail != detail {
            parts.append(detail.isEmpty ? "… \(latestDetail)" : "\(detail) … \(latestDetail)")
        } else if !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: "; ")
    }

    /// The line, as the console shows it: "release +0.12 s (moved 0.2 cm)",
    /// or "drag ×14 +0.20–1.10 s (farthest 3.0 cm; first … latest)".
    public var text: String {
        let detail = detailText
        return "\(nameText) \(timeText)" + (detail.isEmpty ? "" : " (\(detail))")
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

    /// How many things happened in it, every one a run stands for counted.
    public var eventsRecorded: Int {
        events.reduce(0) { $0 + $1.count }
    }

    /// What it was on and what it came to, in a line: "#3 Trace check ·
    /// Pinch on the cube → tap, 0.12 s".
    public var headline: String {
        var line = "#\(id) \(gesture) · \(title) → "
        if let outcome, let lasted {
            line += "\(outcome), \(traceSeconds(lasted)) s"
        } else {
            line += "under way"
        }
        return line
    }

    /// The interaction on one line, for the console, each run of one name
    /// folded into one part:
    ///
    ///     #3 Trace check · Pinch on the cube → tap, 0.12 s: touch +0.00 s (size 0.20 m); release +0.12 s (moved 0.2 cm)
    public var summary: String {
        guard !events.isEmpty else { return headline }
        return headline + ": " + events.map(\.text).joined(separator: "; ")
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
///
/// An interaction keeps a line for each change of what happens, and folds
/// the rest: an event of the same name as the one before it, within
/// `foldSpan` of it, as a drag's words come, folds into that one's line,
/// which keeps how many, the first's and the latest's time and detail, and
/// the farthest any reached. A change of name, a stage of the gesture, always
/// begins a line of its own. Once an interaction has `lineLimit` lines, an
/// event of a name it has had folds into the latest line of that name
/// instead, so a gesture that goes back and forth between two kinds of word
/// keeps its lines too; only a name it hasn't had yet adds another.
public struct TraceLog: Sendable, Equatable {
    /// How many interactions a log keeps unless it's told otherwise.
    public static let defaultCapacity = 12
    /// How many lines an interaction keeps unless it's told otherwise,
    /// before it folds an event of a name it has had into that name's line.
    public static let defaultLineLimit = 10
    /// How long after the one before it an event of the same name still
    /// folds into its line unless it's told otherwise: a second.
    public static let defaultFoldSpan: Duration = .seconds(1)

    /// The most interactions it keeps.
    public let capacity: Int
    /// How many lines an interaction keeps before it folds an event of a
    /// name it has had into that name's line.
    public let lineLimit: Int
    /// How long after the one before it an event of the same name still
    /// folds into its line.
    public let foldSpan: Duration
    /// The interactions it keeps, newest first.
    public private(set) var interactions: [TracedInteraction] = []
    private var lastID = 0

    /// A log keeping the last `capacity` interactions, at least one, each
    /// with `lineLimit` lines, at least one, before it folds what comes
    /// apart, and folding an event into the line before it within
    /// `foldSpan`.
    public init(
        capacity: Int = TraceLog.defaultCapacity,
        lineLimit: Int = TraceLog.defaultLineLimit,
        foldSpan: Duration = TraceLog.defaultFoldSpan
    ) {
        self.capacity = max(1, capacity)
        self.lineLimit = max(1, lineLimit)
        self.foldSpan = max(.zero, foldSpan)
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
    /// earlier than its beginning, saying `detail`, having reached `measure`,
    /// where it says: a line of its own, or folded into one of its name, as
    /// the log's rules say. An interaction may take events after its
    /// outcome, as a coast that goes on after its release; one the log no
    /// longer keeps takes none.
    public mutating func record(
        _ name: String,
        detail: String = "",
        measure: TraceMeasure? = nil,
        in id: TracedInteraction.ID,
        at time: ContinuousClock.Instant
    ) {
        guard let index = interactions.firstIndex(where: { $0.id == id }) else { return }
        let offset = max(.zero, interactions[index].began.duration(to: time))
        let events = interactions[index].events
        let into: Int?
        if let last = events.indices.last, events[last].name == name,
           offset - events[last].latestOffset <= foldSpan {
            into = last
        } else if events.count >= lineLimit {
            into = events.lastIndex { $0.name == name }
        } else {
            into = nil
        }
        if let into {
            interactions[index].events[into].fold(at: offset, detail: detail, measure: measure)
        } else {
            interactions[index].events.append(TraceEvent(offset: offset, name: name, detail: detail, measure: measure))
        }
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
