#if os(visionOS)
import GestureCore
import SwiftUI

/// What happens to a pluckable item, for the app to act on: its tap, its
/// lift and settling, and its breaking free, where the pluck's part ends.
/// From the spawn on, the pinch carries what spawned by GestureCore's carry
/// (`PluckHandoff`, `CarryPinch`), 1:1 with the hand from where it spawned,
/// each step reported as `carried`, for the app to stand the thing by the
/// carry's and facing's rules, as `CarriedEntity.stand` does: clear of the
/// head (`HandCarry`), facing the viewer (`Facing`). Once let go, it's the
/// app's, and a later pinch moves it by a grab handle of its own
/// (`grabHandlesCarryEntities`). Places are in meters in the immersive
/// space, y up, or nil while they can't be told, as with the space closed.
public enum PluckEvent: Equatable, Sendable {
    /// A pinch let go before anything else: the item's tap.
    case tapped
    /// The item lifted, held still; it shows lifted, following the hand a
    /// little, until it breaks free or settles.
    case lifted
    /// The item settled back into its container.
    case settled
    /// The item broke free: spawn what it pulls out here, the drag's place
    /// pushed toward the viewer (`PluckTuning.pushTowardViewer`). The rest
    /// of the pinch carries it (`carried`).
    case spawned(at: SIMD3<Float>?)
    /// The pinch carries what spawned, by the carry's own rule: its middle
    /// where it spawned plus the hand's translation since, 1:1, `handMoved`.
    /// Stand it there, clear of the head and facing the viewer, as
    /// `CarriedEntity.stand` does.
    case carried(middle: SIMD3<Float>, handMoved: SIMD3<Float>)
    /// The pinch let go of what spawned: it stays where its carry last put
    /// its middle, given here, which a later pinch moves by a grab handle of
    /// its own.
    case released(at: SIMD3<Float>?)
    /// The pull's drag was cancelled after the spawn: take away what
    /// spawned.
    case spawnCancelled
}

extension View {
    /// Makes this view an item a pinch can pluck out of the scrolling
    /// container around it, which `pluckContainer(_:tuning:trace:)` marks:
    /// a pinch the container scrolls with, or that moves far first, is the
    /// container's scroll; held still, a quarter second by default, the
    /// item lifts, and the container's scroll stops under it, as tuned;
    /// lifted, it follows the hand a little, held to its place, until the
    /// hand has gone 2.5 cm, when it breaks free and spawns into the room
    /// at the hand, reported through `perform`. From there the pinch carries
    /// what spawned by GestureCore's carry, each step reported as
    /// `PluckEvent.carried`. A pinch let go before anything else is the
    /// item's tap; one let go while the item is held, short of breaking
    /// free, settles it, no tap.
    ///
    /// `id` names the item among its container's; `title` names it in the
    /// trace and the log. The item draws its own lift and follow
    /// (`liftEffect`, `liftFollowEffect`), so only the drawing moves, and
    /// stands above its neighbors while it's up; apply this last, after the
    /// item's size, as the container's direct child:
    ///
    ///     ItemView(item)
    ///         .aspectRatio(1, contentMode: .fit)
    ///         .pluckable(item.id, title: item.name) { event in
    ///             switch event {
    ///             case .tapped: open(item)
    ///             case .spawned(let place): room.spawn(item, at: place)
    ///             case .carried(let middle, _):
    ///                 CarriedEntity.stand(room.entity(of: item), carriedTo: middle,
    ///                                     facingHeadAt: HeadTracker.shared.viewerPosition())
    ///             case .released: room.letGo(item)
    ///             case .spawnCancelled: room.takeBack(item)
    ///             case .lifted, .settled: break
    ///             }
    ///         }
    ///
    /// The item is a button whose press the hold counts from, unless the
    /// tuning counts the hold from the drag (`PluckTuning.holdsFromTheDrag`),
    /// so give it a hover effect of its own.
    public func pluckable<ID: Hashable & Sendable>(_ id: ID, title: String, perform: @escaping (PluckEvent) -> Void) -> some View {
        modifier(PluckableItemModifier(id: AnyHashable(id), title: title, perform: perform))
    }
}

/// An item's side of a pluck: its button, whose press is the hold's, its
/// pull's drag, its geometry, for where the item spawns in the space and
/// where the hand carries it from there, and its lift and follow, all
/// telling one `PluckItemDriver`.
///
/// The drag's location converts through the item's transform into the
/// immersive space, which includes the window's scale, then from points to
/// meters, with y negated, since SwiftUI's y runs down and RealityKit's up.
/// The lift and the follow move only what the item draws, inside the views
/// the gestures and the reader are on, so neither the drag's points nor the
/// transform change as it lifts or follows; the follow is read by a view of
/// its own (`PluckFollowDrawing`), so the hand's every step draws only that.
private struct PluckableItemModifier: ViewModifier {
    let id: AnyHashable
    let title: String
    let perform: (PluckEvent) -> Void

    @Environment(\.pluckContainerContext) private var context
    @Environment(\.physicalMetrics) private var physicalMetrics
    @State private var driver = PluckItemDriver()

    /// True while the drag is under way. SwiftUI resets it both when the drag
    /// ends and when it's cancelled, and only the end calls `onEnded`, so its
    /// going false with the drag still having the pinch means a cancel, as
    /// when the container's scroll view takes the pinch.
    @GestureState private var dragIsActive = false

    func body(content: Content) -> some View {
        let tuning = context?.tuning ?? .defaults
        let isLifted = context?.model.liftedItem == id
        let lift = LiftStyle(scale: CGFloat(tuning.liftScale), depth: CGFloat(tuning.liftDepth))
        let drawn = content
            .modifier(PluckFollowDrawing(follow: driver.follow, isLifted: isLifted))
            .liftEffect(isLifted, style: lift)
        let drag = DragGesture(minimumDistance: CGFloat(tuning.dragStartDistance), coordinateSpace: .local)
            .updating($dragIsActive) { _, isActive, _ in isActive = true }
            .onChanged { driver.dragChanged($0, setting(tuning)) }
            .onEnded { driver.dragEnded($0, setting(tuning)) }
        return pressable(drawn, tuning: tuning)
            .contentShape(Rectangle())
            .background {
                GeometryReader3D { proxy in
                    let _ = driver.remember(proxy)
                    Color.clear
                }
            }
            // One drag, attached beside the button's press, or as an
            // ordinary gesture the button takes precedence over, as tuned.
            .simultaneousGesture(drag, including: tuning.pullDragIsSimultaneous ? .all : .subviews)
            .gesture(drag, including: tuning.pullDragIsSimultaneous ? .subviews : .all)
            .onChange(of: dragIsActive) { _, isActive in
                if !isActive { driver.dragStopped(setting(tuning)) }
            }
            // An item that leaves mid-pinch never sees its drag end, so what
            // it spawned is taken away here, and it's let down.
            .onDisappear { driver.itemWent() }
            .raisedWhileLifted(isLifted)
    }

    /// The item as its press is heard: a button, whose press the hold counts
    /// from and whose tap is the item's, or, with the hold counted from the
    /// drag, the drawing alone.
    @ViewBuilder
    private func pressable(_ drawn: some View, tuning: PluckTuning) -> some View {
        if tuning.holdsFromTheDrag {
            drawn
        } else {
            Button {
                driver.tapped(setting(tuning))
            } label: {
                drawn
            }
            .buttonStyle(PluckPressButtonStyle { driver.pressChanged($0, setting(tuning)) })
        }
    }

    private func setting(_ tuning: PluckTuning) -> PluckItemDriver.Setting {
        PluckItemDriver.Setting(
            id: id,
            title: title,
            tuning: tuning,
            model: context?.model,
            recorder: context?.recorder,
            perform: perform,
            metrics: physicalMetrics
        )
    }
}

/// Where a lifted item is drawn as its pinch tugs it, read here alone, so a
/// drag's every step draws this and nothing else of the item; none while
/// it isn't lifted.
private struct PluckFollowDrawing: ViewModifier {
    let follow: PluckItemFollow
    let isLifted: Bool

    func body(content: Content) -> some View {
        content.liftFollowEffect(isLifted ? follow.offset : .zero)
    }
}

/// A pluckable item's button: just its label, with no hover effect or press
/// dimming of its own, which tells `pressChanged` as its pinch presses it
/// and as the press ends, let go or cancelled, as when the container's
/// scroll view takes the pinch: what the item's hold counts from, which
/// claims nothing the button doesn't have already. A button that goes while
/// pressed tells its press ended, so no item stays lifted, its container's
/// scroll off, for a press whose end nothing would tell.
private struct PluckPressButtonStyle: ButtonStyle {
    let pressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, isPressed in
                pressChanged(isPressed)
            }
            .onDisappear {
                if configuration.isPressed {
                    pressChanged(false)
                }
            }
    }
}
#endif
