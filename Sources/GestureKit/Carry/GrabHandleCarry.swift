#if os(visionOS)
import GestureCore
import os
import RealityKit
import SwiftUI

private let grabHandleCarryLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "GrabHandleCarry")

/// What a carry by a grab handle says to the app at each of its steps: what
/// it carries, where its middle goes, how far the hand has moved, the handle
/// pinched, and the interaction's trace, if it's traced, for the app to add
/// its own events to.
@MainActor
public struct GrabHandleCarryMoment<ID: Equatable & Sendable> {
    /// What's carried, as the app's `grab` named it.
    public let id: ID
    /// Where the hand puts its middle, in meters in the frame the carry is
    /// measured in, its parent's: as it began, where it was grabbed; as it
    /// carries, where it was grabbed plus the hand's translation since the
    /// touch, 1:1; as it ends, where the last step put it.
    public let middle: SIMD3<Float>
    /// How far the hand has moved since the pinch touched, in meters in the
    /// same frame.
    public let handMoved: SIMD3<Float>
    /// The grab handle pinched.
    public let handle: Entity
    /// The interaction's trace, while it's traced.
    public let trace: InteractionTrace?
}

/// A carry by grab handles: an entity-targeted drag on every entity marked
/// with `Marker`, PhotoFinder's drag, a `DragGesture` from 0 pt, each pinch
/// of which a `CarryPinch` tells. It waits `tuning.startDistance` from the
/// touch, then grabs the thing under the handle, as `grab` finds it then,
/// its id and its middle in the frame `parent` names, and carries the middle
/// with the hand, 1:1, the hand's translation converted from the gesture's
/// space into that frame, as PhotoFinder converts it into its picture's
/// parent. The app is told each step through `onBegin`, which may refuse
/// the carry, `onCarry`, and `onEnd`, and keeps its own state: it stands the
/// thing where `onCarry` says, clear of the head and facing it as it likes,
/// or through `CarriedEntity.stand`.
///
/// It's simultaneous with the view's other gestures, so it sees every pinch
/// on a handle whatever they take, and targets no other entity. Its gesture
/// state tells a cancel, which calls no `onEnded`; whichever of the release
/// and the reset comes first ends the pinch, and the other finds nothing to
/// end. A carry begun always ends, once: released, cancelled, or as the view
/// goes.
///
/// Each pinch is traced, given a recorder: its touch; its start, after how
/// many points, carrying what from where; a step each time the hand has
/// gone another 10 cm; and its release, with how far the hand and the
/// middle went and where the middle ended up; its outcome "carried 0.42
/// m", "nothing", "under nothing", or "refused". Its start, refusal, and end
/// are logged at info level, each step at debug level.
public struct GrabHandleCarry<Marker: Component, ID: Equatable & Sendable>: ViewModifier {
    private let tuning: CarryTuning
    private let recorder: TraceRecorder?
    private let gestureName: String
    private let parent: @MainActor (Entity) -> Entity?
    private let grab: @MainActor (Entity) -> CarryPinch<ID>.Grabbed?
    private let onBegin: @MainActor (GrabHandleCarryMoment<ID>) -> Bool
    private let onCarry: @MainActor (GrabHandleCarryMoment<ID>) -> Void
    private let onEnd: @MainActor (GrabHandleCarryMoment<ID>) -> Void

    /// The pinch under way on a handle, from its first change to its end;
    /// nil between pinches.
    @State private var underWay: UnderWay?

    /// True while a pinch on a handle is under way. SwiftUI resets it both
    /// when the pinch ends and when it's cancelled, and only the end calls
    /// `onEnded`, in no promised order.
    @GestureState private var isDragging = false

    /// How far the hand goes between the steps the trace shows, in meters.
    private static var tracedStep: Float { 0.1 }

    /// A carry by the handles marked with `marker`; see
    /// `View.grabHandleCarry(of:tuning:recorder:gesture:in:grab:onBegin:onCarry:onEnd:)`.
    public init(
        of marker: Marker.Type,
        tuning: CarryTuning = .standard,
        recorder: TraceRecorder? = nil,
        gesture: String = "Carry",
        in parent: @escaping @MainActor (Entity) -> Entity? = { _ in nil },
        grab: @escaping @MainActor (Entity) -> CarryPinch<ID>.Grabbed?,
        onBegin: @escaping @MainActor (GrabHandleCarryMoment<ID>) -> Bool = { _ in true },
        onCarry: @escaping @MainActor (GrabHandleCarryMoment<ID>) -> Void,
        onEnd: @escaping @MainActor (GrabHandleCarryMoment<ID>) -> Void = { _ in }
    ) {
        self.tuning = tuning
        self.recorder = recorder
        self.gestureName = gesture
        self.parent = parent
        self.grab = grab
        self.onBegin = onBegin
        self.onCarry = onCarry
        self.onEnd = onEnd
    }

    /// A pinch under way: its rule, the handle it's on, its trace, and what
    /// it has done so far.
    private struct UnderWay {
        var pinch: CarryPinch<ID>
        let handle: Entity
        let trace: InteractionTrace?
        /// The farthest it has moved from its touch, in the gesture's points.
        var farthest: Double = 0
        /// Where the carried middle was grabbed; nil until it is.
        var grabbedAt: SIMD3<Float>?
        /// Where the last step put the middle, and how far the hand had
        /// moved then.
        var middle: SIMD3<Float>?
        var handMoved: SIMD3<Float> = .zero
        /// How far the hand had moved at the last step the trace shows.
        var tracedHand: SIMD3<Float> = .zero
        /// How many steps it has carried.
        var steps = 0
        /// Whether the app refused its carry.
        var refused = false
    }

    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .targetedToEntity(where: .has(Marker.self))
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged { pinchChanged($0) }
                    .onEnded { _ in pinchEnded(how: "released") }
            )
            .onChange(of: isDragging) { _, dragging in
                if !dragging {
                    pinchEnded(how: "ended as its gesture reset, a cancel or a release told in that order")
                }
            }
            .onDisappear {
                pinchEnded(how: "ended as its view went")
            }
    }

    /// Tells the pinch under way how far it has moved, beginning one on its
    /// first change: its translation in the gesture's points says when it
    /// has moved far enough to carry, and, converted into the carried
    /// thing's parent, how far it carries the middle.
    private func pinchChanged(_ value: EntityTargetValue<DragGesture.Value>) {
        let points = value.translation3D
        let distance = (points.x * points.x + points.y * points.y + points.z * points.z).squareRoot()
        let handle = value.entity
        let translation: SIMD3<Float>
        if let frame = parent(handle) {
            translation = value.convert(value.translation3D, from: .local, to: frame)
        } else {
            translation = value.convert(value.translation3D, from: .local, to: .scene)
        }
        var pinch = underWay ?? begin(on: handle)
        if distance.isFinite { pinch.farthest = max(pinch.farthest, distance) }
        let actions = pinch.pinch.move(distance: distance, translation: translation) { grab(handle) }
        underWay = pinch
        perform(actions, distance: distance)
    }

    /// A pinch touching `handle`: its rule, at the tuning as it is now, and
    /// its trace.
    private func begin(on handle: Entity) -> UnderWay {
        let title = handle.name.isEmpty ? "Pinch on a grab handle" : "Pinch on \(handle.name)"
        let trace = recorder?.begin(gestureName, title: title)
        trace?.event("touch", "carries after \(Self.points(tuning.startDistance)) pt")
        return UnderWay(pinch: CarryPinch(tuning: tuning), handle: handle, trace: trace)
    }

    /// Does what the pinch is told to do, the pinch having moved `distance`
    /// points.
    private func perform(_ actions: [CarryPinch<ID>.Action], distance: Double) {
        for action in actions {
            guard var pinch = underWay else { return }
            switch action {
            case .beginCarry(let id):
                guard case .moving(let grabbed) = pinch.pinch.stage else { continue }
                pinch.grabbedAt = grabbed.middle
                underWay = pinch
                grabHandleCarryLogger.info("""
                    A pinch on \(pinch.handle.name) moved \(distance, format: .fixed(precision: 1), privacy: .public) pt; \
                    it carries \(String(describing: id)) from \(carryPlaceText(grabbed.middle), privacy: .public)
                    """)
                pinch.trace?.event("begin", "after \(Self.points(distance)) pt, carries \(id) from \(carryPlaceText(grabbed.middle))")
                let moment = GrabHandleCarryMoment(id: id, middle: grabbed.middle, handMoved: .zero, handle: pinch.handle, trace: pinch.trace)
                guard onBegin(moment) else {
                    grabHandleCarryLogger.info("The carry of \(String(describing: id)) by \(pinch.handle.name) couldn't begin; the rest of the pinch carries nothing")
                    pinch.trace?.event("refused", "the carry couldn't begin")
                    pinch.pinch.refuse()
                    pinch.refused = true
                    underWay = pinch
                    return
                }
            case .carry(let id, let middle, let handMoved):
                pinch.middle = middle
                pinch.handMoved = handMoved
                pinch.steps += 1
                if simd_distance(handMoved, pinch.tracedHand) >= Self.tracedStep {
                    pinch.tracedHand = handMoved
                    pinch.trace?.event("carry", "hand \(Self.meters(simd_length(handMoved))) m from the touch, middle to \(carryPlaceText(middle))")
                }
                underWay = pinch
                grabHandleCarryLogger.debug("""
                    The pinch on \(pinch.handle.name) carries \(String(describing: id))'s middle to \(carryPlaceText(middle), privacy: .public), \
                    the hand having moved \(simd_length(handMoved), format: .fixed(precision: 3), privacy: .public) m
                    """)
                onCarry(GrabHandleCarryMoment(id: id, middle: middle, handMoved: handMoved, handle: pinch.handle, trace: pinch.trace))
            case .ignore:
                grabHandleCarryLogger.info("""
                    A pinch on \(pinch.handle.name) moved \(distance, format: .fixed(precision: 1), privacy: .public) pt, \
                    but the handle is under nothing to carry; it carries nothing
                    """)
                pinch.trace?.event("ignored", "after \(Self.points(distance)) pt, under nothing to carry")
            case .endCarry:
                // Ended by `pinchEnded(how:)`, which tells the app.
                break
            }
        }
    }

    /// The pinch ended, `how` saying how: a carry it began ends, the app
    /// told where its middle was last put, and the trace finished.
    private func pinchEnded(how: String) {
        guard var pinch = underWay else { return }
        underWay = nil
        let stage = pinch.pinch.stage
        _ = pinch.pinch.end()
        switch stage {
        case .moving(let grabbed):
            let middle = pinch.middle ?? grabbed.middle
            let went = simd_distance(middle, grabbed.middle)
            grabHandleCarryLogger.info("""
                The pinch on \(pinch.handle.name) \(how, privacy: .public), letting \(String(describing: grabbed.id)) go, its middle at \
                \(carryPlaceText(middle), privacy: .public), \(went, format: .fixed(precision: 3), privacy: .public) m from where it was grabbed, \
                the hand having moved \(simd_length(pinch.handMoved), format: .fixed(precision: 3), privacy: .public) m
                """)
            pinch.trace?.event("release", """
                \(how): the hand \(Self.meters(simd_length(pinch.handMoved))) m from the touch, \
                the middle \(Self.meters(went)) m from where it was grabbed, at \(carryPlaceText(middle)), \
                in \(pinch.steps) steps
                """)
            onEnd(GrabHandleCarryMoment(id: grabbed.id, middle: middle, handMoved: pinch.handMoved, handle: pinch.handle, trace: pinch.trace))
            pinch.trace?.finish("carried \(Self.meters(went)) m")
        case .waiting:
            pinch.trace?.event("release", "\(how), after only \(Self.points(pinch.farthest)) pt")
            pinch.trace?.finish("nothing")
        case .ignored:
            pinch.trace?.event("release", how)
            pinch.trace?.finish(pinch.refused ? "refused" : "under nothing")
        case .over:
            pinch.trace?.finish("nothing")
        }
    }

    private static func points(_ value: Double) -> String {
        value.isFinite ? value.formatted(.number.precision(.fractionLength(1))) : "?"
    }

    private static func meters(_ value: Float) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }
}

extension View {
    /// Carries what grab handles marked with `marker` are under, 1:1 with
    /// the hand, as `GrabHandleCarry` tells: `grab` finds, from the handle
    /// pinched, what it carries and where its middle is, in the frame
    /// `parent` names for that handle, the carried thing's parent, or the
    /// scene's for nil; `onBegin` may refuse the carry; `onCarry` stands the
    /// thing at each step; and `onEnd` lets it go. `tuning` is read as each
    /// pinch touches, so a change takes effect at the next one; `recorder`,
    /// given, traces each pinch under `gesture`'s name.
    ///
    ///     content
    ///         .grabHandleCarry(of: GrabHandleComponent.self, tuning: tuning, recorder: trace,
    ///                          in: { handle in CarriedEntity.carried(byHandle: handle)?.parent },
    ///                          grab: { handle in
    ///                              CarriedEntity.carried(byHandle: handle).map { CarriedEntity.grabbed($0, as: $0) }
    ///                          },
    ///                          onCarry: { step in
    ///                              CarriedEntity.stand(step.id, carriedTo: step.middle,
    ///                                                  facingHeadAt: HeadTracker.shared.viewerPosition(), tuning: tuning)
    ///                          })
    public func grabHandleCarry<Marker: Component, ID: Equatable & Sendable>(
        of marker: Marker.Type,
        tuning: CarryTuning = .standard,
        recorder: TraceRecorder? = nil,
        gesture: String = "Carry",
        in parent: @escaping @MainActor (Entity) -> Entity? = { _ in nil },
        grab: @escaping @MainActor (Entity) -> CarryPinch<ID>.Grabbed?,
        onBegin: @escaping @MainActor (GrabHandleCarryMoment<ID>) -> Bool = { _ in true },
        onCarry: @escaping @MainActor (GrabHandleCarryMoment<ID>) -> Void,
        onEnd: @escaping @MainActor (GrabHandleCarryMoment<ID>) -> Void = { _ in }
    ) -> some View {
        modifier(GrabHandleCarry(
            of: marker, tuning: tuning, recorder: recorder, gesture: gesture, in: parent,
            grab: grab, onBegin: onBegin, onCarry: onCarry, onEnd: onEnd
        ))
    }

    /// Carries entities by GestureKit's grab handles (`GrabHandleComponent`),
    /// moving each itself, for an app that keeps no state of its own about
    /// where they stand: the entity a handle carries is its ancestor its
    /// component names (`CarriedEntity.carried(byHandle:)`), carried in its
    /// parent, its middle its origin, 1:1 with the hand, never nearer the
    /// head `headTracker` follows than `tuning.nearestToHead`, and turned to
    /// face it (`CarriedEntity.stand`). Each pinch's trace ends with where
    /// the entity stood about the head. `onEnd` is told as each is let go.
    public func grabHandlesCarryEntities(
        tuning: CarryTuning = .standard,
        facing: FacingTuning = .standard,
        recorder: TraceRecorder? = nil,
        gesture: String = "Carry",
        headTracker: HeadTracker = .shared,
        onEnd: @escaping @MainActor (Entity) -> Void = { _ in }
    ) -> some View {
        grabHandleCarry(
            of: GrabHandleComponent.self,
            tuning: tuning,
            recorder: recorder,
            gesture: gesture,
            in: { handle in CarriedEntity.carried(byHandle: handle)?.parent },
            grab: { handle in
                CarriedEntity.carried(byHandle: handle).map { CarriedEntity.grabbed($0, as: $0) }
            },
            onCarry: { step in
                CarriedEntity.stand(step.id, carriedTo: step.middle, facingHeadAt: headTracker.viewerPosition(), tuning: tuning, facing: facing)
            },
            onEnd: { step in
                step.trace?.event("stood", CarriedEntity.describe(step.id, aboutHeadAt: headTracker.viewerPosition()))
                onEnd(step.id)
            }
        )
    }
}
#endif
