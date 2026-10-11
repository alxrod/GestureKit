#if os(visionOS)
import GestureCore
import os
import RealityKit
import SwiftUI

private let grabHandleCarryLogger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "GrabHandleCarry")

/// What a carry by a grab handle says to the app at each of its steps: what
/// it carries, where its middle goes, how far the hand has moved, the handle
/// pinched, as it ends how it ended, and the interaction's trace, if it's
/// traced, for the app to add its own events to.
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
    /// How the carry ended, in `onEnd`: `.released`, the pinch let go;
    /// `.cancelled`, its gesture cancelled, as when the system takes the
    /// pinch away; or `.viewWent`, the view the carry is on gone mid-carry,
    /// as when its immersive space closes. An app that saves where a thing
    /// was let go may put it back where it was lifted from on either of the
    /// last two, since no one chose where it stands. Nil in `onBegin` and
    /// `onCarry`, as the carry hasn't ended.
    public let ending: CarryEnding?
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
/// on a handle whatever they take, and targets no other entity. A carry
/// begun always ends, once, and `onEnd` is told how (`CarryEnding`):
/// `.released` as the drag's `onEnded` comes; `.cancelled` as its gesture
/// state resets with no `onEnded`, which SwiftUI may tell before or after a
/// release's, so a reset waits a turn of the main actor and is a cancel only
/// if no release has ended the pinch by then; and `.viewWent` as the view
/// goes mid-carry. Whichever comes first ends the pinch, and the others find
/// nothing to end.
///
/// Each pinch is traced, given a recorder that's recording: its touch; its
/// start, after how many points, carrying what from where; a step each time
/// the hand has gone another 10 cm, the steps folding into one line with
/// the farthest the hand went (`TraceLog`); and its end, named for how it
/// ended, a release, a cancel, or its view gone, with how far the hand and
/// the middle went and where the middle ended up; its outcome "carried 0.42
/// m", "carried 0.42 m, cancelled", "carried 0.42 m, view went", "nothing",
/// "under nothing", or "refused". A pinch that carried, was refused, or
/// found nothing to carry and wasn't traced is logged at info level in one
/// line as it ends, saying how it ended; a traced one leaves the console its
/// trace's summary. Its steps are logged not at all, as an app's
/// `onCarry` can log them if it likes. A carried entity is named in both by
/// its name, never described whole.
public struct GrabHandleCarry<Marker: Component, ID: Equatable & Sendable>: ViewModifier {
    private let tuning: CarryTuning
    private let recorder: TraceRecorder?
    private let gestureName: String
    private let parent: @MainActor (Entity) -> Entity?
    private let grab: @MainActor (Entity) -> CarryPinch<ID>.Grabbed?
    private let onBegin: @MainActor (GrabHandleCarryMoment<ID>) -> Bool
    private let onCarry: @MainActor (GrabHandleCarryMoment<ID>) -> Void
    private let onEnd: @MainActor (GrabHandleCarryMoment<ID>) -> Void

    /// The pinch under way on a handle, kept in a reference made once for
    /// the view: each of a drag's words changes it, and as `@State` each
    /// change made SwiftUI run this modifier's body again, its gesture and
    /// all, as a hand moved; through a reference, nothing SwiftUI watches
    /// changes until the app's own state does.
    @State private var pinches = Pinches()

    /// True while a pinch on a handle is under way. SwiftUI resets it both
    /// when the pinch ends and when it's cancelled, and only the end calls
    /// `onEnded`, in no promised order, so its going false with the pinch
    /// still under way a turn later means a cancel.
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

    /// Where the pinch under way is kept, from its first change to its end.
    @MainActor
    private final class Pinches {
        /// The pinch under way; nil between pinches.
        var underWay: UnderWay?
        /// The last pinch's number, counting from 1, so a reset's wait for
        /// a release ends only the pinch it was waiting on.
        var serial = 0
    }

    /// A pinch under way: its rule, the handle it's on, its trace, and what
    /// it has done so far.
    private struct UnderWay {
        var pinch: CarryPinch<ID>
        let handle: Entity
        let trace: InteractionTrace?
        /// Its number, from `Pinches.serial`.
        let serial: Int
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
        /// How far it had moved as it began to carry, or found nothing to.
        var beganAfter: Double = 0
    }

    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .targetedToEntity(where: .has(Marker.self))
                    .updating($isDragging) { _, isDragging, _ in isDragging = true }
                    .onChanged { pinchChanged($0) }
                    .onEnded { _ in pinchEnded(.released) }
            )
            // A release calls onEnded as well as resetting the gesture state;
            // a cancel only resets it. SwiftUI doesn't promise which of the
            // two a release tells first, so a reset waits a turn of the main
            // actor, and ends the pinch as cancelled only if it's still under
            // way then, unended by a release.
            .onChange(of: isDragging) { _, dragging in
                guard !dragging, let waiting = pinches.underWay?.serial else { return }
                Task { @MainActor in
                    await Task.yield()
                    guard pinches.underWay?.serial == waiting else { return }
                    pinchEnded(.cancelled)
                }
            }
            .onDisappear {
                pinchEnded(.viewWent)
            }
            #if DEBUG
            .modifier(PinchStandInEar(
                adapter: .grabHandleCarry,
                step: { step in
                    switch step {
                    case .moved(let points, let meters, let handle, _):
                        // Only a handle this carry's drag would target: one
                        // marked with its marker.
                        guard let handle, handle.components.has(Marker.self) else { return }
                        pinchChanged(on: handle, distance: (points * points).sum().squareRoot(), translation: meters)
                    case .released:
                        pinchEnded(.released)
                    case .cancelled:
                        pinchEnded(.cancelled)
                    }
                },
                isBusy: { pinches.underWay != nil },
                facts: {
                    [
                        "marker": .string(String(describing: Marker.self)),
                        "startDistance": .number(tuning.startDistance),
                        "nearestToHead": .number(Double(tuning.nearestToHead)),
                        "pinched": .bool(pinches.underWay != nil),
                    ]
                },
                recorder: recorder
            ))
            #endif
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
        pinchChanged(on: handle, distance: distance, translation: translation)
    }

    /// Tells the pinch under way on `handle` it has moved `distance` points
    /// from its touch, `translation` in the carried thing's parent's frame.
    private func pinchChanged(on handle: Entity, distance: Double, translation: SIMD3<Float>) {
        var pinch = pinches.underWay ?? begin(on: handle)
        if distance.isFinite { pinch.farthest = max(pinch.farthest, distance) }
        let actions = pinch.pinch.move(distance: distance, translation: translation) { grab(handle) }
        pinches.underWay = pinch
        perform(actions, distance: distance)
    }

    /// A pinch touching `handle`: its rule, at the tuning as it is now, and
    /// its trace.
    private func begin(on handle: Entity) -> UnderWay {
        let trace = recorder?.begin(gestureName, title: handle.name.isEmpty ? "Pinch on a grab handle" : "Pinch on \(handle.name)")
        #if DEBUG
        GestureAutomation.shared.heard("carry", on: handle.name, "touch")
        #endif
        trace?.event("touch", "carries after \(Self.points(tuning.startDistance)) pt")
        pinches.serial += 1
        return UnderWay(pinch: CarryPinch(tuning: tuning), handle: handle, trace: trace, serial: pinches.serial)
    }

    /// Does what the pinch is told to do, the pinch having moved `distance`
    /// points.
    private func perform(_ actions: [CarryPinch<ID>.Action], distance: Double) {
        for action in actions {
            guard var pinch = pinches.underWay else { return }
            switch action {
            case .beginCarry(let id):
                guard case .moving(let grabbed) = pinch.pinch.stage else { continue }
                pinch.grabbedAt = grabbed.middle
                pinch.beganAfter = distance
                pinches.underWay = pinch
                pinch.trace?.event("begin", "after \(Self.points(distance)) pt, carries \(grabHandleCarryName(of: id)) from \(carryPlaceText(grabbed.middle))")
                #if DEBUG
                GestureAutomation.shared.heard("carry", on: pinch.handle.name, "begin", ["carries": .string(grabHandleCarryName(of: id)), "middle": .vector(grabbed.middle), "after": .number(distance, decimals: 1)])
                #endif
                let moment = GrabHandleCarryMoment(id: id, middle: grabbed.middle, handMoved: .zero, handle: pinch.handle, ending: nil, trace: pinch.trace)
                guard onBegin(moment) else {
                    pinch.trace?.event("refused", "the carry couldn't begin")
                    #if DEBUG
                    GestureAutomation.shared.heard("carry", on: pinch.handle.name, "refused")
                    #endif
                    pinch.pinch.refuse()
                    pinch.refused = true
                    pinches.underWay = pinch
                    return
                }
            case .carry(let id, let middle, let handMoved):
                pinch.middle = middle
                pinch.handMoved = handMoved
                pinch.steps += 1
                if let trace = pinch.trace, simd_distance(handMoved, pinch.tracedHand) >= Self.tracedStep {
                    pinch.tracedHand = handMoved
                    let hand = simd_length(handMoved)
                    trace.event(
                        "carry",
                        "hand \(Self.meters(hand)) m out, middle at \(carryPlaceText(middle))",
                        measure: TraceMeasure(Double(hand), "m")
                    )
                }
                pinches.underWay = pinch
                #if DEBUG
                GestureAutomation.shared.heard("carry", on: pinch.handle.name, "carry", ["middle": .vector(middle), "handMoved": .vector(handMoved)])
                #endif
                onCarry(GrabHandleCarryMoment(id: id, middle: middle, handMoved: handMoved, handle: pinch.handle, ending: nil, trace: pinch.trace))
            case .ignore:
                pinch.beganAfter = distance
                pinches.underWay = pinch
                pinch.trace?.event("ignored", "after \(Self.points(distance)) pt, under nothing to carry")
                #if DEBUG
                GestureAutomation.shared.heard("carry", on: pinch.handle.name, "ignored")
                #endif
            case .endCarry:
                // Ended by `pinchEnded(_:)`, which tells the app.
                break
            }
        }
    }

    /// The pinch ended as `ending` says: a carry it began ends, the app told
    /// where its middle was last put and how it ended, and the trace
    /// finished.
    private func pinchEnded(_ ending: CarryEnding) {
        guard var pinch = pinches.underWay else { return }
        pinches.underWay = nil
        let stage = pinch.pinch.stage
        _ = pinch.pinch.end(ending)
        let endName = Self.eventName(endedAs: ending)
        switch stage {
        case .moving(let grabbed):
            let middle = pinch.middle ?? grabbed.middle
            let went = simd_distance(middle, grabbed.middle)
            if pinch.trace == nil {
                grabHandleCarryLogger.info("""
                    A pinch on \(pinch.handle.name) carried \(grabHandleCarryName(of: grabbed.id)) \
                    \(went, format: .fixed(precision: 3), privacy: .public) m, from \(carryPlaceText(grabbed.middle), privacy: .public) \
                    to \(carryPlaceText(middle), privacy: .public), after \(pinch.beganAfter, format: .fixed(precision: 1), privacy: .public) pt, \
                    the hand \(simd_length(pinch.handMoved), format: .fixed(precision: 3), privacy: .public) m in \(pinch.steps, privacy: .public) steps; \
                    \(ending.description, privacy: .public)
                    """)
            }
            pinch.trace?.event(endName, """
                \(ending): the hand \(Self.meters(simd_length(pinch.handMoved))) m from the touch, \
                the middle \(Self.meters(went)) m from where it was grabbed, at \(carryPlaceText(middle)), \
                in \(pinch.steps) steps
                """)
            #if DEBUG
            GestureAutomation.shared.heard("carry", on: pinch.handle.name, "end", ["middle": .vector(middle), "went": .number(Double(went), decimals: 4), "ending": .string(ending.rawValue)])
            #endif
            onEnd(GrabHandleCarryMoment(id: grabbed.id, middle: middle, handMoved: pinch.handMoved, handle: pinch.handle, ending: ending, trace: pinch.trace))
            pinch.trace?.finish(Self.outcome(carried: went, endedAs: ending))
        case .waiting:
            #if DEBUG
            GestureAutomation.shared.heard("carry", on: pinch.handle.name, "release", ["after": .number(pinch.farthest, decimals: 1), "ending": .string(ending.rawValue)])
            #endif
            pinch.trace?.event(endName, "\(ending), after only \(Self.points(pinch.farthest)) pt")
            pinch.trace?.finish("nothing")
        case .ignored:
            if pinch.trace == nil {
                grabHandleCarryLogger.info("""
                    A pinch on \(pinch.handle.name) carried nothing: after \(pinch.beganAfter, format: .fixed(precision: 1), privacy: .public) pt, \
                    \(pinch.refused ? "its carry couldn't begin" : "the handle was under nothing to carry", privacy: .public); \(ending.description, privacy: .public)
                    """)
            }
            #if DEBUG
            GestureAutomation.shared.heard("carry", on: pinch.handle.name, "release", ["ending": .string(ending.rawValue)])
            #endif
            pinch.trace?.event(endName, ending.description)
            pinch.trace?.finish(pinch.refused ? "refused" : "under nothing")
        case .over:
            pinch.trace?.finish("nothing")
        }
    }

    /// The trace's name for a pinch's end: "release", "cancel", or "view
    /// went".
    private static func eventName(endedAs ending: CarryEnding) -> String {
        switch ending {
        case .released: "release"
        case .cancelled: "cancel"
        case .viewWent: "view went"
        }
    }

    /// A carry's outcome for its trace: "carried 0.42 m", and how it ended
    /// where that wasn't a release, "carried 0.42 m, cancelled" or
    /// "carried 0.42 m, view went".
    private static func outcome(carried went: Float, endedAs ending: CarryEnding) -> String {
        switch ending {
        case .released: "carried \(meters(went)) m"
        case .cancelled: "carried \(meters(went)) m, cancelled"
        case .viewWent: "carried \(meters(went)) m, view went"
        }
    }

    private static func points(_ value: Double) -> String {
        value.isFinite ? value.formatted(.number.precision(.fractionLength(1))) : "?"
    }

    private static func meters(_ value: Float) -> String {
        Double(value).formatted(.number.precision(.fractionLength(2)))
    }
}

/// What a carry carries, named for a trace or a log: an entity by its name,
/// since describing one whole writes out every component and child it has,
/// many lines of them; anything else as Swift describes it.
@MainActor
private func grabHandleCarryName<ID>(of id: ID) -> String {
    if let entity = id as? Entity {
        return entity.name.isEmpty ? "an entity with no name" : "'\(entity.name)'"
    }
    return String(describing: id)
}

extension View {
    /// Carries what grab handles marked with `marker` are under, 1:1 with
    /// the hand, as `GrabHandleCarry` tells: `grab` finds, from the handle
    /// pinched, what it carries and where its middle is, in the frame
    /// `parent` names for that handle, the carried thing's parent, or the
    /// scene's for nil; `onBegin` may refuse the carry; `onCarry` stands the
    /// thing at each step; and `onEnd` lets it go, its moment's `ending`
    /// saying whether it was released, cancelled, or its view went. `tuning`
    /// is read as each pinch touches, so a change takes effect at the next
    /// one; `recorder`, given, traces each pinch under `gesture`'s name.
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
    /// the entity stood about the head. `onEnd` is told as each carry ends,
    /// however it ends: let go, cancelled, or its view gone mid-carry, the
    /// entity stands where the hand last put it, as each step stood it. An
    /// app that would put it back on a cancel uses `grabHandleCarry(of:…)`
    /// and its moment's `ending`.
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
