#if os(visionOS)
import ARKit
import GestureCore
import os

private let pinchTrackerLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "PinchTracker")

/// The hands' pinches, from ARKit's hand tracking: for each hand, whether
/// its thumb and index fingertips are pinched, since when, and where, in the
/// immersive space's own meters (`HandPinch`); which hand a press came from;
/// and each pinched hand's every update, for whoever follows it, as a
/// pluckable item follows its lifted pinch without a gesture
/// (`PluckLiftedTracking.handOnceLifted`).
///
/// Hand tracking runs only while an immersive space is open, and asks the
/// person first, so `start()` asks for its permission and begins a fresh
/// session whenever none is running, as each opening of the space should
/// call it, and `stop()` ends it. Where it can't run, as in the simulator,
/// which has no hand tracking, or without its permission, it says so in its
/// `state`, and follows nothing; a debug build's hand stand-in can feed it
/// as hand tracking would (`standIn(_:thumbTip:indexTip:)`).
///
/// It needs `NSHandsTrackingUsageDescription` in the app's Info.plist.
@MainActor
public final class PinchTracker {
    /// The tracker an app shares.
    public static let shared = PinchTracker()

    /// Where hand tracking stands.
    public enum State: Equatable, Sendable {
        /// Not started, or stopped.
        case stopped
        /// Asking for permission and starting.
        case starting
        /// Running: the hands' updates come.
        case running
        /// This device has no hand tracking, as the simulator.
        case unsupported
        /// The person didn't allow hand tracking.
        case notAllowed
        /// It failed to start, for the reason given.
        case failed(String)
        /// A debug build's stand-in feeds it, as hand tracking would.
        case standIn

        /// Whether hands' updates come, from hand tracking or its stand-in.
        public var follows: Bool { self == .running || self == .standIn }

        /// The state in a few words, for a trace.
        public var description: String {
            switch self {
            case .stopped: "hand tracking isn't running"
            case .starting: "hand tracking is starting"
            case .running: "hand tracking is running"
            case .unsupported: "this device has no hand tracking"
            case .notAllowed: "hand tracking isn't allowed"
            case .failed(let reason): "hand tracking failed: \(reason)"
            case .standIn: "the hand's stand-in feeds hand tracking"
            }
        }
    }

    /// One update of a followed hand: its pinch, where it is, and what the
    /// update did to it.
    public struct Sample: Sendable {
        public var side: HandSide
        public var pinch: HandPinch
        /// What this update did: closed, opened, or lost its pinch; nil for
        /// a move.
        public var change: HandPinch.Change?
        public var at: ContinuousClock.Instant
    }

    /// Where hand tracking stands.
    public private(set) var state = State.stopped
    /// The numbers its pinches are told by.
    public var tuning = HandPinchTuning()
    /// Each hand's pinch, as last seen.
    public private(set) var hands: [HandSide: HandPinch] = [:]

    private var session: ARKitSession?
    private var updates: Task<Void, Never>?
    /// Looks for a followed hand gone unseen, while one is followed.
    private var lostWatch: Task<Void, Never>?
    /// Bumped by every start and stop, so a start whose run returns after a
    /// stop, or after a newer start, stops its own session instead of
    /// keeping it.
    private var generation = 0
    private var followers: [UUID: (side: HandSide, tell: @MainActor (Sample) -> Void)] = [:]

    public init() {}

    /// Starts hand tracking for the space that's open, asking the person
    /// first, unless it's running already. Where it can't run, it says why
    /// in `state`, and logs it.
    public func start() async {
        guard state != .running, state != .starting, state != .standIn else { return }
        stop()
        generation += 1
        let started = generation
        guard HandTrackingProvider.isSupported else {
            state = .unsupported
            pinchTrackerLogger.info("This device has no hand tracking; a lifted pinch is followed by its drag")
            return
        }
        state = .starting
        let session = ARKitSession()
        let allowed = await session.requestAuthorization(for: [.handTracking])
        guard started == generation else { return }
        guard allowed[.handTracking] == .allowed else {
            state = .notAllowed
            pinchTrackerLogger.info("Hand tracking isn't allowed; a lifted pinch is followed by its drag")
            return
        }
        let provider = HandTrackingProvider()
        do {
            try await session.run([provider])
        } catch {
            guard started == generation else { return }
            state = .failed(String(describing: error))
            pinchTrackerLogger.error("Couldn't start hand tracking: \(String(describing: error), privacy: .public)")
            return
        }
        guard started == generation else {
            session.stop()
            return
        }
        self.session = session
        state = .running
        pinchTrackerLogger.info("Hand tracking started")
        updates = Task { @MainActor [weak self] in
            for await update in provider.anchorUpdates {
                self?.saw(update.anchor)
            }
            guard let self, started == self.generation else { return }
            self.state = .stopped
            pinchTrackerLogger.info("Hand tracking's updates ended")
        }
    }

    /// Stops hand tracking, as the space closes. Its followers hear no more.
    public func stop() {
        generation += 1
        updates?.cancel()
        updates = nil
        session?.stop()
        session = nil
        if state != .standIn { state = .stopped }
    }

    /// Which hand a press at `press` came from: the one pinched now whose
    /// pinch closed nearest it; nil should neither be pinched.
    public func hand(pinchedNearest press: ContinuousClock.Instant) -> HandSide? {
        HandPinch.hand(pinchedNearest: press, among: hands)
    }

    /// Tells `tell` each update of the hand on `side`, until
    /// `stopFollowing(_:)` with what this gives.
    public func follow(_ side: HandSide, _ tell: @escaping @MainActor (Sample) -> Void) -> UUID {
        let id = UUID()
        followers[id] = (side, tell)
        watchForLostHands()
        return id
    }

    /// Stops telling the follower `id`.
    public func stopFollowing(_ id: UUID) {
        followers[id] = nil
        if followers.isEmpty {
            lostWatch?.cancel()
            lostWatch = nil
        }
    }

    // MARK: The hands' updates

    private func saw(_ anchor: HandAnchor) {
        let side: HandSide = anchor.chirality == .left ? .left : .right
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else {
            unseen(side, at: .now)
            return
        }
        let thumb = skeleton.joint(.thumbTip)
        let index = skeleton.joint(.indexFingerTip)
        guard thumb.isTracked, index.isTracked else {
            unseen(side, at: .now)
            return
        }
        seen(
            side,
            thumbTip: pinchTrackerPosition(anchor.originFromAnchorTransform * thumb.anchorFromJointTransform),
            indexTip: pinchTrackerPosition(anchor.originFromAnchorTransform * index.anchorFromJointTransform),
            at: .now
        )
    }

    private func seen(_ side: HandSide, thumbTip: SIMD3<Float>, indexTip: SIMD3<Float>, at now: ContinuousClock.Instant) {
        var pinch = hands[side] ?? HandPinch()
        let change = pinch.saw(thumbTip: thumbTip, indexTip: indexTip, at: now, tuning: tuning)
        hands[side] = pinch
        tell(side, change: change, at: now)
    }

    private func unseen(_ side: HandSide, at now: ContinuousClock.Instant) {
        guard var pinch = hands[side] else { return }
        let change = pinch.unseen(at: now, tuning: tuning)
        hands[side] = pinch
        if change != nil { tell(side, change: change, at: now) }
    }

    private func tell(_ side: HandSide, change: HandPinch.Change?, at now: ContinuousClock.Instant) {
        guard let pinch = hands[side] else { return }
        let sample = Sample(side: side, pinch: pinch, change: change, at: now)
        for follower in followers.values where follower.side == side {
            follower.tell(sample)
        }
    }

    /// While a hand is followed, looks a tenth of a second apart for one
    /// gone unseen, as a hand leaving the tracking's view sends no update.
    private func watchForLostHands() {
        guard lostWatch == nil else { return }
        lostWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                for side in Set(self.followers.values.map(\.side)) {
                    self.unseen(side, at: .now)
                }
            }
        }
    }

    #if DEBUG
    /// The hand's stand-in, in a debug build: the hand on `side` seen now,
    /// its fingertips at `thumbTip` and `indexTip`, in meters in the space,
    /// as hand tracking would see it.
    @_spi(PinchStandIn) public func standIn(_ side: HandSide, thumbTip: SIMD3<Float>, indexTip: SIMD3<Float>) {
        if !state.follows { state = .standIn }
        seen(side, thumbTip: thumbTip, indexTip: indexTip, at: .now)
    }
    #endif
}

/// The translation of a transform, as a point.
private func pinchTrackerPosition(_ transform: simd_float4x4) -> SIMD3<Float> {
    SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
}
#endif
