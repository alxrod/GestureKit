#if os(visionOS)
import GestureCore
import os
import SwiftUI

private let holdWatchLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "HoldWatchModifier")

extension View {
    /// Watches every pinch on this view for a hold, beside the view's own
    /// drag and tap, never in front of them (`HoldWatch`): a plain drag from
    /// 0 pt that stands beside them as a simultaneous gesture. Held still
    /// for the tuning's duration, within its still distance, the pinch asks
    /// `onHeldStill`, which does what the hold does here and says whether it
    /// did; if it did, `isHeld` turns true, and the view's own drag and tap
    /// should do nothing for the rest of the pinch, nor for its release's
    /// tap, which SwiftUI may call just after the watch hears the release,
    /// so `isHeld` stays true for the tuning's held-tap grace after it. A
    /// pinch that moves farther first, or whose own drag has begun, which
    /// `dragHasBegun` tells it, is the view's, as ever.
    ///
    /// A long press standing in front of a drag holds the drag back until it
    /// fails; on the headset one standing in front of other gestures took
    /// their pinches, which is why the watch stands beside them.
    ///
    ///     TabView()
    ///         .gesture(trimDrag.exclusively(before: tap))
    ///         .holdWatch(isHeld: $held, dragHasBegun: isTrimming, recorder: recorder) {
    ///             showMergeQuestion()
    ///             return true
    ///         }
    ///
    /// - Parameters:
    ///   - isHeld: set true once the pinch under way holds, and false again
    ///     once its release's tap has passed.
    ///   - dragHasBegun: whether the view's own drag has begun, which gives
    ///     the hold up for the rest of the pinch.
    ///   - isEnabled: whether it watches at all.
    ///   - tuning: the numbers it goes by, read as each pinch touches.
    ///   - recorder: where each pinch is traced; nil traces nothing.
    ///   - traceTitle: what each pinch's trace is called.
    ///   - onHeldStill: asked once the pinch has been held still long
    ///     enough: does what the hold does, and says whether it did.
    public func holdWatch(
        isHeld: Binding<Bool> = .constant(false),
        dragHasBegun: Bool = false,
        isEnabled: Bool = true,
        tuning: HoldWatch.Tuning = .defaults,
        recorder: TraceRecorder? = nil,
        traceTitle: String = "Pinch on a control",
        onHeldStill: @escaping @MainActor () -> Bool
    ) -> some View {
        modifier(HoldWatchModifier(
            isHeld: isHeld,
            dragHasBegun: dragHasBegun,
            isEnabled: isEnabled,
            tuning: tuning,
            recorder: recorder,
            traceTitle: traceTitle,
            onHeldStill: onHeldStill
        ))
    }
}

/// `.holdWatch`'s modifier: the watch on the pinch under way, its timer, and
/// its trace.
private struct HoldWatchModifier: ViewModifier {
    @Binding var isHeld: Bool
    let dragHasBegun: Bool
    let isEnabled: Bool
    let tuning: HoldWatch.Tuning
    let recorder: TraceRecorder?
    let traceTitle: String
    let onHeldStill: @MainActor () -> Bool

    /// The watch on the pinch under way; nil between pinches.
    @State private var watch: HoldWatch?
    /// Counts the pinches, so a timer never acts on a later pinch than its
    /// own.
    @State private var serial = 0
    /// Asks once the pinch under way has been held still long enough.
    @State private var timer: Task<Void, Never>?
    /// When the pinch under way touched.
    @State private var touchedAt: ContinuousClock.Instant?
    /// The pinch's trace, while one is under way and there's a recorder.
    @State private var trace: InteractionTrace?
    /// True while a pinch is under way, from its touch; SwiftUI resets it as
    /// the pinch ends and as it's cancelled.
    @GestureState private var isPressing = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(watchGesture, including: isEnabled ? .all : .none)
            .onChange(of: isPressing) { _, pressing in
                guard !pressing else { return }
                pinchEnded()
            }
            .onChange(of: dragHasBegun) { _, begun in
                guard begun, var watched = watch, watched.stage == .waiting else { return }
                watched.dragBegan()
                watch = watched
                trace?.event("drag began", "after \(holdWatchSeconds(elapsed)): the pinch is the control's")
            }
            .onDisappear { pinchEnded() }
    }

    /// Every pinch, from its touch, standing beside the view's own gestures.
    private var watchGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isPressing) { _, isPressing, _ in isPressing = true }
            .onChanged { pinchMoved($0) }
            .onEnded { _ in pinchEnded() }
    }

    /// How long the pinch under way has lasted, in seconds.
    private var elapsed: Double {
        touchedAt.map { (ContinuousClock.now - $0) / .seconds(1) } ?? 0
    }

    /// The pinch touched, on its first change, or moved: the watch is told
    /// how far it's gone, which gives the hold up once it's too far.
    private func pinchMoved(_ value: DragGesture.Value) {
        if watch == nil {
            pinchBegan()
        }
        let moved = value.translation3D
        guard var watched = watch else { return }
        let gaveUp = watched.move(SIMD3(moved.x, moved.y, moved.z))
        watch = watched
        guard gaveUp else { return }
        trace?.event("moved off", String(format: "%.1f pt, past %.1f, after %@: the pinch is the control's", watched.farthest, tuning.stillDistance, holdWatchSeconds(elapsed)))
    }

    /// A pinch touched: its timer starts, which asks once it's been held
    /// still long enough, if it hasn't moved off or begun the view's drag.
    private func pinchBegan() {
        serial += 1
        isHeld = false
        watch = HoldWatch(tuning: tuning)
        touchedAt = .now
        trace = recorder?.begin("HoldWatch", title: traceTitle)
        trace?.event("touch", "holds at \(holdWatchSeconds(tuning.duration)) within \(String(format: "%.1f pt", tuning.stillDistance))")
        if dragHasBegun {
            watch?.dragBegan()
            trace?.event("drag began", "as it touched: the pinch is the control's")
        }
        timer?.cancel()
        let counting = serial
        timer = Task { @MainActor in
            try? await Task.sleep(for: .seconds(tuning.duration))
            guard !Task.isCancelled, serial == counting, var watched = watch, watched.stage == .waiting else { return }
            let held = watched.timeIsUp(asking: onHeldStill)
            watch = watched
            if held {
                isHeld = true
                trace?.event("hold", String(format: "held still %@ within %.1f pt: the rest of the pinch is the hold's", holdWatchSeconds(elapsed), watched.farthest))
                holdWatchLogger.info("A pinch on \(traceTitle) held, still for \(watched.tuning.duration, format: .fixed(precision: 2), privacy: .public) s")
            } else {
                trace?.event("asked nothing", "after \(holdWatchSeconds(elapsed)): the pinch is the control's")
            }
        }
    }

    /// The pinch was let go, or cancelled, or the view went: its timer stops,
    /// and a pinch that held keeps `isHeld` for the held-tap grace, so its
    /// release's tap, whichever way SwiftUI orders the release's callbacks,
    /// is the hold's.
    private func pinchEnded() {
        timer?.cancel()
        timer = nil
        guard let watched = watch else { return }
        watch = nil
        let outcome: String = switch watched.stage {
        case .held: "hold"
        case .gaveUp: "the control's"
        case .waiting: "let go before its hold"
        }
        trace?.event("release", "after \(holdWatchSeconds(elapsed)), \(String(format: "%.1f pt", watched.farthest)) at the farthest")
        trace?.finish(outcome)
        trace = nil
        touchedAt = nil
        guard watched.holds else { return }
        let counting = serial
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(watched.tuning.heldTapGrace))
            if serial == counting {
                isHeld = false
            }
        }
    }
}

/// `seconds` for a trace: "0.60 s".
private func holdWatchSeconds(_ seconds: Double) -> String {
    String(format: "%.2f s", seconds)
}
#endif
