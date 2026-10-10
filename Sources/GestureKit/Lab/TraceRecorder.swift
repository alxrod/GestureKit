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
/// nothing and pays nothing; and a recorder that isn't recording
/// (`isRecording`) gives no trace, so an adapter handed one pays nothing
/// either:
///
///     var trace: InteractionTrace?
///     // as a pinch touches:
///     trace = recorder?.begin("Pluck", title: "Pinch on item 4")
///     trace?.event("lift", "held still 0.50 s")
///     // as it ends:
///     trace?.finish("pull")
///
/// Its log folds a run of events of one name into one line, as a drag's
/// words come, and keeps a line for each stage (`TraceLog`), so a pinch's
/// trace, and the summary the console gets, stay a few lines long however
/// long the hand moves.
///
/// What a trace shows (`shownLog`) follows the log paced (`TracePacing`):
/// at once after a quiet spell, then at most ten times a second. With
/// events written 20 times a second, as a gesture writes them while a hand
/// moves, a trace drawn again at every event cost the app 17% of a core in
/// the simulator, and the render server more; paced, 11%.
@MainActor @Observable
public final class TraceRecorder {
    /// The interactions it keeps, with their events and outcomes, as they
    /// stand.
    public private(set) var log: TraceLog {
        didSet { logChanged() }
    }

    /// Whether it writes anything down. Off, `begin` gives no trace, so an
    /// adapter handed it builds no title or detail, times nothing, and logs
    /// no summary, as though it had no recorder; and it forgets what it
    /// kept, which a trace shows at once. An interaction begun before it
    /// went off writes nothing more.
    public var isRecording = true {
        didSet {
            guard isRecording != oldValue, !isRecording else { return }
            clear()
        }
    }

    /// The log as a trace shows it: `log`, at most `TracePacing`'s interval
    /// behind it.
    public private(set) var shownLog: TraceLog

    @ObservationIgnored private var pacing = TracePacing()
    /// The showing due, while one is.
    @ObservationIgnored private var showing: Task<Void, Never>?

    /// Whether the summaries it logs show in full wherever the log is read,
    /// as from `log stream` on a Mac; otherwise, at the default privacy,
    /// only a debugger's console shows them, since an app's titles may name
    /// what a person is working on. GestureLab's say only what its gestures
    /// do, so it logs them publicly.
    @ObservationIgnored public let logsSummariesPublicly: Bool

    /// A recorder keeping the last `capacity` interactions, recording
    /// unless `isRecording` says otherwise.
    public init(capacity: Int = TraceLog.defaultCapacity, logsSummariesPublicly: Bool = false, isRecording: Bool = true) {
        log = TraceLog(capacity: capacity)
        shownLog = TraceLog(capacity: capacity)
        self.logsSummariesPublicly = logsSummariesPublicly
        self.isRecording = isRecording
    }

    /// The interactions it keeps, newest first.
    public var interactions: [TracedInteraction] { log.interactions }

    /// The interactions a trace shows, newest first (`shownLog`).
    public var shownInteractions: [TracedInteraction] { shownLog.interactions }

    /// Begins an interaction with `gesture`, on what `title` says, now, and
    /// gives the trace its events and outcome are written through; nil,
    /// making no title, while it isn't recording.
    public func begin(_ gesture: String, title: @autoclosure () -> String) -> InteractionTrace? {
        guard isRecording else { return nil }
        let id = log.begin(gesture, title: title(), at: .now, date: .now)
        return InteractionTrace(id: id, recorder: self)
    }

    /// Forgets every interaction, as the trace's Clear does, which the trace
    /// shows at once.
    public func clear() {
        log.clear()
        show()
    }

    /// The log changed: the trace shows it now, or once the pacing says.
    private func logChanged() {
        switch pacing.changed(at: .now) {
        case .now:
            show()
        case .at(let time):
            showing = Task { @MainActor [weak self] in
                try? await Task.sleep(until: time, clock: .continuous)
                guard !Task.isCancelled else { return }
                self?.show()
            }
        case .alreadyDue:
            break
        }
    }

    /// Shows the log as it stands, and whatever showing was due with it.
    private func show() {
        showing?.cancel()
        showing = nil
        pacing.shown(at: .now)
        shownLog = log
    }

    fileprivate func record(_ name: String, detail: String, measure: TraceMeasure?, in id: TracedInteraction.ID) {
        guard isRecording else { return }
        log.record(name, detail: detail, measure: measure, in: id, at: .now)
    }

    fileprivate func finish(_ id: TracedInteraction.ID, outcome: String) {
        guard isRecording, let finished = log.finish(id, outcome: outcome, at: .now) else { return }
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

    /// Records that `name` happened now, with what `detail` says of it and,
    /// for something that reaches, as a hand carrying, how far it reached,
    /// so a run of them keeps the farthest. A run of one name, one after
    /// another, folds into one line (`TraceLog`).
    public func event(_ name: String, _ detail: String = "", measure: TraceMeasure? = nil) {
        recorder.record(name, detail: detail, measure: measure, in: id)
    }

    /// Whether what it writes is still kept: false once its recorder has
    /// stopped recording, so an adapter can skip working out what it would
    /// write.
    public var isRecording: Bool { recorder.isRecording }

    /// Gives the interaction its outcome now, such as "tap" or "pull", and
    /// logs its summary; a second outcome changes nothing.
    public func finish(_ outcome: String) {
        recorder.finish(id, outcome: outcome)
    }
}
#endif
