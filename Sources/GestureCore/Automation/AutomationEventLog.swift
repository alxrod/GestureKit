#if DEBUG
import Foundation

/// One thing an adapter reported while a command ran: when, in seconds from
/// the command's start; which adapter, "pluck", "press", "carry",
/// "hold watch", "grid"; what it was on, by name; what happened, "lifted",
/// "spawned", "tap"; and what it said of it.
public struct AutomationEvent: Sendable, Equatable {
    public var time: Double
    public var source: String
    public var target: String
    public var name: String
    public var detail: AutomationJSON

    public init(time: Double, source: String, target: String, name: String, detail: AutomationJSON = .null) {
        self.time = time
        self.source = source
        self.target = target
        self.name = name
        self.detail = detail
    }
}

/// What the adapters reported while a command ran, in order, a run of one
/// thing on one target, as a carry's steps or a drag's moves, folded into
/// one line: how many, the first's time, and the last's time and detail. So
/// a 90-word drag answers in a line, and an agent asserting on "spawned"
/// finds it among a handful.
public struct AutomationEventLog: Sendable, Equatable {
    /// One line: an event, or a run of one thing on one target.
    public struct Line: Sendable, Equatable {
        public var first: AutomationEvent
        public var count: Int
        public var lastTime: Double
        public var lastDetail: AutomationJSON
    }

    /// The most lines it keeps; past that it counts what it drops.
    public static let lineLimit = 400

    public private(set) var lines: [Line] = []
    /// How many events it dropped past `lineLimit`.
    public private(set) var dropped = 0

    public init() {}

    /// Keeps `event`, folding it into the line before it for the same thing
    /// on the same target.
    public mutating func record(_ event: AutomationEvent) {
        if var last = lines.last, last.first.source == event.source, last.first.target == event.target, last.first.name == event.name {
            last.count += 1
            last.lastTime = event.time
            last.lastDetail = event.detail
            lines[lines.count - 1] = last
            return
        }
        guard lines.count < Self.lineLimit else {
            dropped += 1
            return
        }
        lines.append(Line(first: event, count: 1, lastTime: event.time, lastDetail: event.detail))
    }

    /// Whether any event from `source` was `name`, on `target` if given.
    public func contains(_ name: String, from source: String, on target: String? = nil) -> Bool {
        lines.contains { $0.first.name == name && $0.first.source == source && (target == nil || $0.first.target == target) }
    }

    /// The last detail of the last line of `name` from `source`, on `target`
    /// if given.
    public func lastDetail(of name: String, from source: String, on target: String? = nil) -> AutomationJSON? {
        lines.last { $0.first.name == name && $0.first.source == source && (target == nil || $0.first.target == target) }?.lastDetail
    }

    /// The names of what `source` reported, in order, each run once, on
    /// `target` if given.
    public func names(from source: String, on target: String? = nil) -> [String] {
        lines.filter { $0.first.source == source && (target == nil || $0.first.target == target) }.map(\.first.name)
    }

    /// The lines as an answer gives them: each with its source, target,
    /// name, time, and detail, and a run's count and last time and detail.
    public var json: AutomationJSON {
        var array: [AutomationJSON] = lines.map { line in
            var object: [String: AutomationJSON] = [
                "source": .string(line.first.source),
                "target": .string(line.first.target),
                "event": .string(line.first.name),
                "time": .number(line.first.time, decimals: 3),
            ]
            if line.first.detail != .null { object["detail"] = line.first.detail }
            if line.count > 1 {
                object["count"] = .number(Double(line.count))
                object["lastTime"] = .number(line.lastTime, decimals: 3)
                if line.lastDetail != .null { object["lastDetail"] = line.lastDetail }
            }
            return .object(object)
        }
        if dropped > 0 {
            array.append(["event": "dropped", "count": .number(Double(dropped))])
        }
        return .array(array)
    }
}

/// What a command's drive came to, told from what the adapters reported, so
/// it reads the same with the trace switched off.
public enum AutomationOutcome {
    /// A pinch on a pluckable item: it broke free, `spawned`; it lifted and
    /// settled short of that, `lifted`; its hold was given up, the grid's
    /// scroll, `stayed down`, whatever came as it was let go; it was the
    /// item's tap, `tapped`; or nothing came of it, `nothing`.
    public static func pluck(_ names: [String]) -> String {
        if names.contains("spawned") { return "spawned" }
        if names.contains("lifted") { return "lifted" }
        if names.contains("stayed down") { return "stayed down" }
        if names.contains("tapped") { return "tapped" }
        return "nothing"
    }

    /// A pinch on a surface, as `SurfacePress` told it: a tap, a drag
    /// along, a scroll, a catch, a carry, a carry refused, a pickup put
    /// down, a hold, a drag across, or nothing.
    public static func surface(_ names: [String]) -> String {
        if names.contains("tap") { return "tap" }
        if names.contains("endCarry") || names.contains("cancelCarry") { return "carry" }
        if names.contains("carryRefused") { return "carry refused" }
        if names.contains("endHold") || names.contains("fireHold") { return "hold" }
        if names.contains("putDown") { return "pickup, put down" }
        if names.contains("endScroll") { return "scroll" }
        if names.contains("endCatch") { return "catch" }
        if names.contains("endDragAlong") { return "drag along" }
        if names.contains("ignoreDragAcross") { return "drag across" }
        return "nothing"
    }

    /// A pinch watched for a hold: it held, it was the control's, or it was
    /// let go before its hold.
    public static func holdWatch(_ names: [String]) -> String {
        if names.contains("held") { return "hold" }
        if names.contains("moved off") || names.contains("drag began") || names.contains("asked nothing") { return "the control's" }
        return "let go before its hold"
    }

    /// A pinch on a grab handle: it carried, its carry was refused, its
    /// handle was under nothing, or it never moved far enough.
    public static func carry(_ names: [String]) -> String {
        if names.contains("refused") { return "refused" }
        if names.contains("begin") { return "carried" }
        if names.contains("ignored") { return "under nothing" }
        return "nothing"
    }
}
#endif
