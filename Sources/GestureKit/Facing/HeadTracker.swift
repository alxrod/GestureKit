#if os(visionOS)
import ARKit
import GestureCore
import os
import QuartzCore

private let headTrackerLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "HeadTracker")

/// Where the viewer's head is, from ARKit's world tracking: for turning
/// things to face the viewer (`FacesTheViewerSystem`), carrying them clear
/// of the head (`CarriedEntity`), and placing a panel below the gaze
/// (`GazePanel`). In an immersive space, whose origin is ARKit's, its
/// positions and transforms are in the space's own frame.
///
/// World tracking runs only while an immersive space is open, and a
/// provider, once stopped, can't run again, so `start()` begins a fresh
/// session whenever none is running, as each opening of the space should
/// call it, and `stop()` ends it as the space closes. Where world tracking
/// can't say where the head is, as in the simulator, whose device anchor
/// stays on the floor wherever its camera is, things face and are placed
/// for a stand-in (`UntrackedHead`), 1.6 m up at the origin, looking down
/// −z, as the simulator's camera stands.
///
/// It needs `NSWorldSensingUsageDescription` in the app's Info.plist.
@MainActor
public final class HeadTracker {
    /// The tracker an app shares, and the one `FacesTheViewerSystem` asks
    /// unless it's told another.
    public static let shared = HeadTracker()

    private var session: ARKitSession?
    private var provider: WorldTrackingProvider?
    /// Bumped by every start and stop, so a start whose run returns after a
    /// stop, or after a newer start, stops its own session instead of
    /// keeping it.
    private var generation = 0

    public init() {}

    /// Whether world tracking here says where the head is: not in the
    /// simulator, which runs world tracking but keeps its device anchor on
    /// the floor.
    public static var tracksTheHead: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        WorldTrackingProvider.isSupported
        #endif
    }

    /// Whether a session is running and its provider with it.
    public var isRunning: Bool {
        provider?.state == .running
    }

    /// Starts world tracking for the space that's open, unless it's running
    /// already: a fresh session and provider, since one stopped, as by the
    /// space closing, can't run again. Where world tracking can't say where
    /// the head is, it logs so and starts nothing.
    public func start() async {
        guard !isRunning else { return }
        stop()
        generation += 1
        let started = generation
        guard Self.tracksTheHead else {
            headTrackerLogger.info("World tracking can't say where the head is here; things face and are placed for the untracked head, 1.6 m up at the origin looking down -z")
            return
        }
        let session = ARKitSession()
        let provider = WorldTrackingProvider()
        do {
            try await session.run([provider])
        } catch {
            headTrackerLogger.error("Couldn't start world tracking: \(String(describing: error), privacy: .public)")
            return
        }
        guard started == generation else {
            headTrackerLogger.info("World tracking was stopped or started again while it started; stopping this session")
            session.stop()
            return
        }
        self.session = session
        self.provider = provider
        headTrackerLogger.info("World tracking started")
    }

    /// Stops world tracking, as the space closes. Stopping when nothing runs
    /// does nothing.
    public func stop() {
        generation += 1
        guard let session else { return }
        session.stop()
        self.session = nil
        provider = nil
        headTrackerLogger.info("World tracking stopped")
    }

    /// The head's transform from the space's origin: where it is, its −z
    /// the way the face points, and its +y the way the top of the head
    /// points. Nil while it isn't tracked.
    public func headTransform() -> simd_float4x4? {
        guard let provider, provider.state == .running,
              let anchor = provider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()),
              anchor.isTracked
        else { return nil }
        return anchor.originFromAnchorTransform
    }

    /// The head's transform, as `headTransform()` gives it, waiting up to
    /// `patience` for it to be tracked, as while the session for a space
    /// just opened starts. Nil at once where world tracking can't say where
    /// the head is, and nil if it isn't tracked by then, or the task is
    /// cancelled meanwhile.
    public func headTransform(waitingAtMost patience: Duration) async -> simd_float4x4? {
        guard Self.tracksTheHead else { return nil }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: patience)
        while true {
            if let head = headTransform() { return head }
            guard !Task.isCancelled, clock.now < deadline else { return nil }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Where the head is, in meters from the space's origin; nil while it
    /// isn't tracked.
    public func headPosition() -> SIMD3<Float>? {
        guard let head = headTransform() else { return nil }
        return SIMD3(head.columns.3.x, head.columns.3.y, head.columns.3.z)
    }

    /// Where things face and keep clear of: the head, tracked; the untracked
    /// head's eyes where world tracking can't say where the head is, as in
    /// the simulator (`UntrackedHead.eye`); and nil where it can, but hasn't
    /// the head now, as while it starts or loses track for a moment, so
    /// nothing swings round to face a stand-in.
    public func viewerPosition() -> SIMD3<Float>? {
        guard Self.tracksTheHead else { return UntrackedHead.eye }
        return headPosition()
    }
}
#endif
