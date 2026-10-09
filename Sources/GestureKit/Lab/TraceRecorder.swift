#if os(visionOS)
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "TraceRecorder")

/// Where a gesture's adapters write what each interaction with it did, for
/// GestureLab's trace (`TraceView`) and the console: an observable
/// `TraceLog` of the last few interactions, newest first, timed on the
/// continuous clock, each finished one's summary logged at info level.
///
/// Every adapter takes one optionally, so an app that doesn't trace passes
/// nothing and pays nothing:
///
///     var trace: InteractionTrace?
///     // as a pinch touches:
///     trace = recorder?.begin("Pluck", title: "Pinch on item 4")
///     trace?.event("lift", "held still 0.50 s")
///     // as it ends:
///     trace?.finish("pull")
@MainActor @Observable
public final class TraceRecorder {
    /// The interactions it keeps, with their events and outcomes.
    public private(set) var log: TraceLog

    /// Whether the summaries it logs show in full wherever the log is read,
    /// as from `log stream` on a Mac; otherwise, at the default privacy,
    /// only a debugger's console shows them, since an app's titles may name
    /// what a person is working on. GestureLab's say only what its gestures
    /// do, so it logs them publicly.
    @ObservationIgnored public let logsSummariesPublicly: Bool

    /// A recorder keeping the last `capacity` interactions.
    public init(capacity: Int = TraceLog.defaultCapacity, logsSummariesPublicly: Bool = false) {
        log = TraceLog(capacity: capacity)
        self.logsSummariesPublicly = logsSummariesPublicly
    }

    /// The interactions it keeps, newest first.
    public var interactions: [TracedInteraction] { log.interactions }

    /// Begins an interaction with `gesture`, on what `title` says, now, and
    /// gives the trace its events and outcome are written through.
    public func begin(_ gesture: String, title: String) -> InteractionTrace {
        let id = log.begin(gesture, title: title, at: .now, date: .now)
        return InteractionTrace(id: id, recorder: self)
    }

    /// Forgets every interaction, as the trace's Clear does.
    public func clear() {
        log.clear()
    }

    fileprivate func record(_ name: String, detail: String, in id: TracedInteraction.ID) {
        log.record(name, detail: detail, in: id, at: .now)
    }

    fileprivate func finish(_ id: TracedInteraction.ID, outcome: String) {
        guard let finished = log.finish(id, outcome: outcome, at: .now) else { return }
        if logsSummariesPublicly {
            logger.info("\(finished.summary, privacy: .public)")
        } else {
            logger.info("\(finished.summary)")
        }
    }
}

/// One interaction under way in a `TraceRecorder`: what an adapter writes
/// its events and outcome through, from its beginning to its end.
@MainActor
public struct InteractionTrace {
    /// The interaction's number in its recorder's log.
    public let id: TracedInteraction.ID
    private let recorder: TraceRecorder

    fileprivate init(id: TracedInteraction.ID, recorder: TraceRecorder) {
        self.id = id
        self.recorder = recorder
    }

    /// Records that `name` happened now, with what `detail` says of it.
    public func event(_ name: String, _ detail: String = "") {
        recorder.record(name, detail: detail, in: id)
    }

    /// Gives the interaction its outcome now, such as "tap" or "pull", and
    /// logs its summary; a second outcome changes nothing.
    public func finish(_ outcome: String) {
        recorder.finish(id, outcome: outcome)
    }
}
#endif
