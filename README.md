# GestureKit

GestureKit is a set of content-agnostic gestures for Apple Vision Pro:
carrying things by a handle, turning them to face you, placing panels below
your gaze, pulling items out of a scrolling grid into the room, and telling
one pinch on a surface as a tap, a drag, a pickup, or a hold. Each gesture's
rules live in `GestureCore`, plain Swift tested on the Mac, and its visionOS
adapters, the components, systems, and view modifiers that carry those rules
out on any RealityKit entity or SwiftUI view, live in `GestureKit`. Every
number they go by was settled on the headset, in GestureLab, the app in this
repository.

## Installation

Add the package with Swift Package Manager. In `Package.swift`:

<!-- Not compiled: a package manifest. -->
```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.visionOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/alxrod/GestureKit.git", branch: "main"),
    ],
    targets: [
        .target(name: "MyApp", dependencies: [
            .product(name: "GestureKit", package: "GestureKit"),
        ]),
    ]
)
```

In Xcode, choose File > Add Package Dependencies…, enter
`https://github.com/alxrod/GestureKit.git`, and add the `GestureKit` library
to your visionOS target.

- **`GestureKit`** needs visionOS 26. It re-exports `GestureCore`, so
  `import GestureKit` is all an app needs.
- **`GestureCore`** builds for visionOS 26 and macOS 14, so the rules run,
  and are tested, on the Mac. On the Mac, `GestureKit` builds empty.
- Both are Swift 6, built with Swift 6.2 tools.

## The gestures

Every gesture works the same way. Its rules are plain values in
`GestureCore`, told what happened and when. Its adapter in `GestureKit`
takes a tuning, a struct of every number the gesture goes by, whose defaults
are the ones settled on the headset, and, optionally, a `TraceRecorder`
(see [Tuning and tracing](#tuning-and-tracing)). It reports what happens
through closures and leaves your app's state to your app. Distances on a
view are in its points, about 1,360 to the meter at a window's own size;
distances in the room are in meters, y up; times are in seconds.

### Setting up

Register GestureKit's RealityKit components and systems once, before
anything uses them, and start `HeadTracker` as your immersive space opens.
Carry keeps what it carries clear of the head, Facing turns things to it, and
Placement stands panels below its gaze, each asking `HeadTracker.shared`
where the head is. In your app, the type you mark `@main`:

```swift
import GestureKit
import RealityKit
import SwiftUI

struct RoomApp: App {
    init() {
        // Before anything uses them: an entity-targeted drag finds its
        // handles by their component, which RealityKit wants registered.
        GrabHandle.registerComponents()
        FacesTheViewerSystem.registerComponentsAndSystem()
    }

    var body: some SwiftUI.Scene {
        ImmersiveSpace(id: "room") {
            RealityView { _ in }
                // Where the head is, for Carry, Facing, and Placement.
                .task { await HeadTracker.shared.start() }
                .onDisappear { HeadTracker.shared.stop() }
        }
    }
}
```

`HeadTracker` uses ARKit's world tracking, so your Info.plist needs
`NSWorldSensingUsageDescription`. Where world tracking can't place the head,
as in the simulator, things face and are placed for a stand-in head 1.6 m up
at the space's origin, looking down −z (`UntrackedHead`). Register any
component of your own the same way, as a marker for your own handles
(`grabHandleCarry(of:)`). The body says `SwiftUI.Scene`, since RealityKit
has a `Scene` of its own.

### Carry

A grab handle carries a thing 1:1 with the hand, by its middle, never nearer
your head than 0.3 m, turning it to face you as it goes. The handle is a
clear RealityKit entity over a grabber you draw: it takes the looks and
pinches there, glows where it's looked at, and its entity-targeted drag waits
8 pt before it carries, so a touch moves nothing.

Use it for anything in the room people move by hand: panels, cards, boards.
Of four drags tried side by side on the headset, an entity-targeted drag on
an entity was the only one that followed the hand.

| `CarryTuning` | Default | |
| --- | --- | --- |
| `startDistance` | 8 pt | How far a pinch moves before it carries. |
| `nearestToHead` | 0.3 m | The nearest a carried middle comes to the head. |

`grabHandlesCarryEntities` moves the entity itself: each handle carries the
ancestor its `GrabHandleComponent` names, in that ancestor's parent's frame,
through `CarriedEntity.stand`.

```swift
import GestureKit
import RealityKit
import SwiftUI

/// A box in the room, carried by the handle under it, 1:1 with the hand.
struct CarriedBoxView: View {
    var body: some View {
        RealityView { content in
            let box = ModelEntity(
                mesh: .generateBox(size: 0.2),
                materials: [SimpleMaterial(color: .orange, isMetallic: false)]
            )
            box.name = "box"
            box.position = [0, 1.3, -1]
            // A clear handle that takes the pinch and glows where it's
            // looked at; it carries the ancestor its component names.
            let handle = GrabHandle.make(carrying: "box", size: [0.16, 0.025])
            handle.position.y = -0.13
            box.addChild(handle)
            content.add(box)
        }
        .grabHandlesCarryEntities(tuning: CarryTuning(nearestToHead: 0.4)) { box in
            // Let go: it stands at box.position, in its parent's frame.
        }
    }
}
```

To keep where things stand in your own state, mark your handles with a
component of your own and use `grabHandleCarry(of:)`. `grab` finds what a
handle carries and where its middle is; `onBegin` may refuse; `onCarry` is
told each step, its `middle` and how far the hand has moved; and `onEnd` the
last. `HandCarry` gives the carry's rules for standing it.

```swift
import GestureKit
import RealityKit
import SwiftUI

/// Marks the handles of boards whose places the app keeps. Register it at
/// launch, as `BoardHandle.registerComponent()`.
struct BoardHandle: Component {
    var board: Int
}

@MainActor @Observable
final class Boards {
    var middles: [Int: SIMD3<Float>] = [1: [-0.4, 1.3, -1], 2: [0.4, 1.3, -1]]
}

struct BoardsView: View {
    let boards: Boards

    var body: some View {
        RealityView { content in
            for (board, middle) in boards.middles {
                let entity = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.3), materials: [SimpleMaterial()])
                entity.name = "board \(board)"
                entity.position = middle
                let handle = GrabHandle.make(named: "handle", size: [0.2, 0.025], marking: BoardHandle(board: board))
                handle.position.y = -0.18
                entity.addChild(handle)
                content.add(entity)
            }
        } update: { content in
            for (board, middle) in boards.middles {
                content.entities.first { $0.name == "board \(board)" }?.position = middle
            }
        }
        .grabHandleCarry(
            of: BoardHandle.self,
            grab: { handle -> CarryPinch<Int>.Grabbed? in
                guard let board = handle.components[BoardHandle.self]?.board,
                      let middle = boards.middles[board] else { return nil }
                return CarryPinch.Grabbed(id: board, middle: middle)
            },
            onCarry: { step in
                // Where the hand puts it, but never nearer the head than 0.3 m.
                let head = HeadTracker.shared.viewerPosition() ?? UntrackedHead.eye
                let before = boards.middles[step.id] ?? step.middle
                boards.middles[step.id] = HandCarry.middle(carriedTo: step.middle, clearOf: head, from: before)
            }
        )
    }
}
```

### Facing

A thing turns to face you by yaw and pitch alone, never rolled, so its sides
stay level and its top stays up. Straight above or below it, where which way
to turn has no meaning, it keeps the way it faced rather than swinging round.

Use `Facing.orientation(from:toward:)` to turn something once, as it's
placed, and a `FacesTheViewerComponent` to keep it turned every frame as you
move; give the component a `pivot` to turn it about a point it hangs from.
Carry and Placement use the same rule.

| `FacingTuning` | Default | |
| --- | --- | --- |
| `verticalTolerance` | 0.001 m | How near straight above or below counts as overhead, where it keeps its way. |

```swift
import GestureKit
import RealityKit
import SwiftUI

/// Two signs: one turned to face the viewer once, as it's placed, and one
/// turned every frame as the viewer walks around it.
struct FacingSignsView: View {
    var body: some View {
        RealityView { content in
            let head = HeadTracker.shared.viewerPosition() ?? UntrackedHead.eye

            let placed = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.25), materials: [SimpleMaterial()])
            placed.position = [-0.6, 1.4, -1.2]
            placed.orientation = Facing.orientation(from: placed.position, toward: head)
            content.add(placed)

            let following = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.25), materials: [SimpleMaterial()])
            following.position = [0.6, 1.4, -1.2]
            following.components.set(FacesTheViewerComponent())
            content.add(following)
        }
    }
}
```

### Placement

A panel opens below your gaze: 0.7 m out, 20° below where you look, straight
down from the gaze, tilted up to you, and drawn at 0.7 so it looks as big as
it would a meter out. It stays put as you look around, until you carry it by
the pill under it.

Use it for controls that should come to the viewer wherever they look, as
playback controls in an immersive view. `GazePanel.standBelowTheGaze` waits
up to 1.5 s for world tracking, as while a space that has just opened starts
it; `GazePanel.stand(_:forHead:)` stands a panel for a head transform you
give. `PanelHandleRig` hangs a pill under any panel, as visionOS's window bar
hangs under a window, with a grab handle in front of it; tell it the panel's
height as that changes (`panelResized(toHeight:)`).

| `PlacementTuning` | Default | |
| --- | --- | --- |
| `distance` | 0.7 m | How far out the panel's middle stands. |
| `belowTheGazeDegrees` | 20° | How far below the gaze. |
| `steepestDegrees` | 60° | The steepest below or above level, for a gaze at the floor or the sky. |
| `looksAsBigAsAt` | 1 m | How far out it looks as big as drawn whole. |
| `handleWidth`, `handleHeight` | 128 × 16 pt | The pill. |
| `handleGap` | 12 pt | Between the panel's bottom edge and the pill. |
| `handleReachBeyondEnds`, `handleReachHeight` | 22 pt, 60 pt | Where the handle takes pinches. |

```swift
import GestureKit
import RealityKit
import SwiftUI

/// Controls that open below the viewer's gaze, tilted up to them, and stay
/// put until carried by the pill under them.
struct GazeControlsView: View {
    @State private var panel = Entity()

    var body: some View {
        RealityView { content, attachments in
            panel.name = "controls"
            content.add(panel)
            if let controls = attachments.entity(for: "controls") {
                panel.addChild(controls)
            }
            // The pill under a panel 200 pt tall, and the grab handle on it.
            let rig = PanelHandleRig(under: panel, carrying: "controls", panelHeight: 200)
            if let pill = attachments.entity(for: "pill") {
                rig.hang(pill: pill)
            }
        } attachments: {
            Attachment(id: "controls") {
                HStack(spacing: 24) {
                    Button("Back", systemImage: "backward.fill") {}
                    Button("Play", systemImage: "play.fill") {}
                    Button("Next", systemImage: "forward.fill") {}
                }
                .labelStyle(.iconOnly)
                .frame(width: 480, height: 200)
                .glassBackgroundEffect()
            }
            Attachment(id: "pill") {
                PanelHandlePill(label: "Move the controls")
            }
        }
        .grabHandlesCarryEntities()
        .task {
            await HeadTracker.shared.start()
            await GazePanel.standBelowTheGaze(panel)
        }
    }
}
```

### Pluck

Pull an item out of a scrolling grid into the room. A pinch is the grid's
scroll unless it's a hold: one that moves the grid at all, or moves 10 pt
along the scroll first, scrolls. Held still a quarter second, the item lifts
and the scroll stops under it. Lifted, it follows the hand a little, held to
its place, until the hand has gone 2.5 cm, when it breaks free and spawns
into the room at the hand, the item settling back into the grid; a move
mostly along the scroll instead gives the pinch back to the scroll.

Use it for libraries, palettes, and pickers whose items become things in the
room. Mark the scroll view `pluckContainer` with a `PluckContainerModel`,
and each item `pluckable`, applied last, after the item's size. Each item
reports:

| `PluckEvent` | |
| --- | --- |
| `.tapped` | Let go before anything else: the item's tap. |
| `.lifted`, `.settled` | It lifted, or settled back into the grid. |
| `.spawned(at:)` | It broke free: make what it pulls out there, in the space's meters, or nil with the space closed. |
| `.carried(middle:handMoved:)` | The same pinch carries what spawned, a step at a time. |
| `.released(at:)` | The pinch let go: it's yours. |
| `.spawnCancelled` | The pull was cancelled: take what spawned away. |

The pluck owns its pinch up to the spawn. From there the same pinch is a
carry's, by Carry's own rules (`PluckHandoff` runs `CarryPinch`): what
spawned goes 1:1 with the hand from where it spawned, and you stand it at
each step, clear of the head and facing it, with `CarriedEntity.stand`. Let
go, it's yours: give it a grab handle, and `grabHandlesCarryEntities`
carries it from then on. The grid's scroll stays held off until that pinch
lets go.

| `PluckTuning` | Default | |
| --- | --- | --- |
| `holdDuration` | 0.25 s | How long a pinch is held still before its item lifts. |
| `holdStillnessAlongScroll` | 10 pt | A move along the scroll before the hold that makes the pinch a scroll. |
| `holdStillness` | 40 pt | A move any way before the hold that makes the pinch a scroll. |
| `scrollOffsetStillness` | 1 pt | How far the grid's content may move before the hold. |
| `breakFreeDistance` | 0.025 m | How far the hand goes from the lift before the item breaks free. |
| `pullArmDelay` | 0.2 s | The soonest after the lift it may break free. |
| `followShare`, `followCap` | 0.5, 20 pt | How far a lifted item follows the hand. |
| `heldBackDragStart` | 60 pt | The item's drag held back until the lift, so it never competes with the scroll. |
| `quietRelease` | 0.5 s | A lift whose pinch has gone quiet settles. |
| `unheardHoldRelease` | 1 s | The safety net lets a hold with nothing heard from its pinch go. |
| `pushTowardViewer` | 100 pt | How far toward you from the hand it spawns. |
| `liftScale`, `liftDepth` | 1.08, 36 pt | How the lifted item looks. |

Its switches choose how a lifted pinch is followed (`liftedTracking`): by
the item's drag, held back by its 60 pt start and brought down at the lift,
the default; by the drag held back by its gesture mask
(`holdsDragBackByItsMask`); or by the pinching hand, through hand tracking
(`tracksLiftedPinchByHand`, with `PinchTracker`, which needs
`NSHandsTrackingUsageDescription`). `pluckContainer`'s `scrollAxes` says
which way the grid scrolls, vertical by default. The container's `status`
says whether the scroll is held and for which item, and the alarms it raised,
for a status line.

```swift
import GestureKit
import RealityKit
import SwiftUI

/// The cards in the room, one for each item pulled out of the grid.
@MainActor @Observable
final class PluckedCards {
    /// Add it to the immersive space's content, at the space's origin.
    let root = Entity()
    @ObservationIgnored private var carried: [Int: Entity] = [:]

    func handle(_ event: PluckEvent, item: Int) {
        switch event {
        case .spawned(let place):
            // The pluck's part ends here: make what the item pulls out.
            let card = ModelEntity(
                mesh: .generateBox(width: 0.2, height: 0.2, depth: 0.01),
                materials: [SimpleMaterial(color: .systemTeal, isMetallic: false)]
            )
            card.name = "card \(item)"
            card.position = place ?? [0, 1.3, -0.8]
            root.addChild(card)
            carried[item] = card
        case .carried(let middle, _):
            // The same pinch carries it, by Carry's rules: 1:1 with the
            // hand, clear of the head, facing it.
            guard let card = carried[item] else { return }
            CarriedEntity.stand(card, carriedTo: middle, facingHeadAt: HeadTracker.shared.viewerPosition())
        case .released:
            // Let go, it's the app's: a grab handle carries it from now on.
            guard let card = carried.removeValue(forKey: item) else { return }
            let handle = GrabHandle.make(carrying: card.name, size: [0.15, 0.025])
            handle.position.y = -0.13
            card.addChild(handle)
            card.components.set(FacesTheViewerComponent())
        case .spawnCancelled:
            carried.removeValue(forKey: item)?.removeFromParent()
        case .tapped, .lifted, .settled:
            break
        }
    }
}

/// A window's grid of items, each pulled out into the room by a pinch held
/// still a quarter second; a pinch that moves first scrolls.
struct PluckGridView: View {
    let cards: PluckedCards
    @State private var container = PluckContainerModel()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 4)], spacing: 4) {
                ForEach(1...60, id: \.self) { item in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.teal)
                        .overlay { Text("\(item)").font(.largeTitle) }
                        .hoverEffect()
                        .aspectRatio(1, contentMode: .fit)
                        .pluckable(item, title: "item \(item)") { event in
                            cards.handle(event, item: item)
                        }
                }
            }
        }
        .pluckContainer(container)
    }
}

/// The room the cards stand in, each carried by its grab handle once let go.
struct PluckedCardsSpace: View {
    let cards: PluckedCards

    var body: some View {
        RealityView { content in
            content.add(cards.root)
        }
        .grabHandlesCarryEntities()
    }
}
```

### Lift

A view lifted off what it lies on: scaled up about its middle and brought
toward you on a spring that overshoots a little, over a soft shadow left
where it was, above its neighbors while it's up, and down again without the
bounce. `liftFollowEffect` draws it a little way along as a pinch tugs it.
Only the drawing moves, so a gesture or a geometry reader around it measures
the same points lifted or not.

Use it for anything a pinch picks up in a window or a grid. Pluckable items
draw it themselves.

| `LiftStyle` | Default | |
| --- | --- | --- |
| `scale` | 1.08 | How much larger it shows lifted. |
| `depth` | 36 pt | How far toward you, about 2.6 cm. |
| `castsShadow` | true | Its shadow on what it lies on. |

It springs up on `LiftStyle.springUp`, 0.32 s with a bounce of 0.4, comes
down on `springDown`, the same without the bounce, and follows a tug on
`followSpring`, 0.12 s.

```swift
import GestureKit
import SwiftUI

/// A photo that lifts off its page while it's held, drawn a little way
/// along as the pinch tugs it.
struct LiftingPhoto: View {
    let isHeld: Bool
    /// How far the pinch has tugged it, in its points, x across, y down,
    /// z toward the viewer.
    let tug: SIMD3<Double>

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(.indigo)
            .frame(width: 300, height: 300)
            .liftFollowEffect(isHeld ? tug : .zero)
            .liftEffect(isHeld, style: LiftStyle(scale: 1.08, depth: 36))
            .raisedWhileLifted(isHeld)
    }
}
```

### Surface press

One pinch on a surface, from its touch, told as a tap, a drag along, a
scroll, a drag across, a pickup and carry, or a hold, by how far it moves and
how long it's still. Held still half a second, it picks up, lifting what's
drawn; moved 2 cm then, it carries; held a second, it holds. Two plain drags
from 0 pt feed it, so no gesture stands in front of another.

Use it for timelines, strips, and bars where one pinch means several things:
scrub along it, carry the whole thing, or hold for more. Places along the
surface are in meters from its leading edge. `dragAlongScrolls` makes a drag
along scroll by the hand's moves, for Coast; a carry's steps give the hand's
move in the space, and `event.refuseCarry(because:)` refuses one; `onMagnify`
hands you a two-handed pinch.

| `SurfacePress.Tuning` | Default | |
| --- | --- | --- |
| `stillDistance` | 10 pt | How far a pinch may move and still be held still. |
| `dragDistance` | 15 pt | How far it moves before it's a drag rather than a tap. |
| `depthWeight` | 0.5 | How much a move in depth counts. |
| `carryDistance` | 27 pt | How far a picked-up pinch moves before it carries, about 2 cm. |
| `pickUpDelay` | 0.5 s | Held still this long, it picks up. |
| `holdDuration` | 1 s | Held still this long, it holds. |
| `lift` | 1.05, 0.025 m | How much larger and nearer it shows picked up; 1.06 and 0.03 m as it holds (`HoldLift.Tuning`). |

```swift
import GestureKit
import SwiftUI

/// A bar where a tap drops a mark, a drag along moves the playhead, and a
/// hold of a second flags it; a drag across does nothing.
struct MarkingBar: View {
    @Environment(\.physicalMetrics) private var metrics
    /// Meters from the bar's leading edge, as the press gives places along it.
    @State private var playhead = 0.0
    @State private var marks: [Double] = []
    @State private var isFlagged = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isFlagged ? Color.orange : Color.gray)
            .frame(width: metrics.convert(0.8, from: .meters), height: 80)
            .overlay(alignment: .leading) {
                ForEach(marks.indices, id: \.self) { index in
                    Circle()
                        .fill(.cyan)
                        .frame(width: 16, height: 16)
                        .offset(x: metrics.convert(marks[index], from: .meters) - 8)
                }
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 4)
                    .offset(x: metrics.convert(playhead, from: .meters) - 2)
            }
            .surfacePress(canHold: true, canPickUp: false) { event in
                switch event.action {
                case .tap(let along):
                    marks.append(along)
                case .beginDragAlong(_, let along), .moveDragAlong(let along):
                    playhead = along
                case .fireHold:
                    isFlagged.toggle()
                default:
                    break
                }
            }
    }
}
```

### Coast

A scroll let go on the move coasts on from the hand's speed, slowing by e
every 0.8 s, and comes to rest at an end rather than stopping dead. A pinch
on it while it still goes 5 cm a second catches it, and is no tap.

Use it wherever a hand scrolls something by its moves. `ReleaseVelocity`
measures the hand's speed over the last tenth of a second; `CoastRun` runs a
coast on your clock, within your bounds, and says where it is and whether a
pinch catches it; `CoastEasing` animates SwiftUI by it.

| `Coast.Tuning` | Default | |
| --- | --- | --- |
| `timeConstant` | 0.8 s | It slows by e every this long. |
| `slowestRelease` | 0.05 m/s | The slowest let-go that coasts. |
| `slowestCatch` | 0.05 m/s | The slowest coast a pinch catches rather than taps. |
| `stoppingSpeed` | 0.01 m/s | Where it stops. |
| `sampleSpan` | 0.1 s | How far back the hand's speed is measured. |

```swift
import GestureKit
import SwiftUI

/// A strip of tiles scrolled by the hand, coasting on as it's let go on the
/// move, until a pinch catches it.
@MainActor @Observable
final class CoastingStrip {
    /// How far it has scrolled, in meters, from 0 to 2.
    var offset = 0.0

    @ObservationIgnored private var run: CoastRun?
    @ObservationIgnored private var release = ReleaseVelocity()
    @ObservationIgnored private var scrollStart = 0.0
    @ObservationIgnored private let clockStart = ContinuousClock.now

    /// Seconds on the strip's own clock, which its coasts run on.
    private func now() -> Double {
        (ContinuousClock.now - clockStart) / .seconds(1)
    }

    /// A pinch touched the strip: a coast still on the move stops where it
    /// is, and the pinch is that catch, not a tap.
    func catchCoast() -> Bool {
        let time = now()
        guard let run, !run.isOver(at: time) else { return false }
        self.run = nil
        // Set without an animation, which ends the coast's.
        offset = run.position(at: time)
        return run.pinchCatches(at: time)
    }

    func perform(_ event: SurfacePressEvent) {
        switch event.action {
        case .beginScroll(let handMoved):
            scrollStart = offset
            release = ReleaseVelocity()
            scroll(by: handMoved)
        case .moveScroll(let handMoved):
            scroll(by: handMoved)
        case .endScroll(coasting: true):
            let time = now()
            guard let run = CoastRun(releasedAt: release.velocity(at: time), from: offset, at: time, within: 0...2) else { return }
            self.run = run
            withAnimation(Animation(CoastEasing(run.coast))) {
                offset = run.end
            }
        default:
            break
        }
    }

    private func scroll(by handMoved: SIMD3<Double>) {
        offset = min(max(scrollStart - handMoved.x, 0), 2)
        release.record(offset, at: now())
    }
}

struct CoastingStripView: View {
    let strip: CoastingStrip
    @Environment(\.physicalMetrics) private var metrics

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<40, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8)
                    .fill(.mint)
                    .frame(width: 96, height: 96)
            }
        }
        .offset(x: -metrics.convert(strip.offset, from: .meters))
        .frame(width: 800, alignment: .leading)
        .clipped()
        .surfacePress(canPickUp: false, dragAlongScrolls: true, catchCoast: { strip.catchCoast() }) { event in
            strip.perform(event)
        }
    }
}
```

### Hold watch

A pinch held still 0.6 s on a handle or a control asks whether the hold
means anything there, watched beside the control's own drag and tap, never
in front of them. If it does, the drag and tap do nothing for the rest of the
pinch. On the headset, a long press standing in front of other gestures took
their pinches; the watch stands beside them.

Use it to give a control that already drags or taps a second meaning: a
handle that resizes and, held, splits. Tell it when the control's own drag
begins (`dragHasBegun`), and check `isHeld` in your drag and tap.

| `HoldWatch.Tuning` | Default | |
| --- | --- | --- |
| `duration` | 0.6 s | How long a pinch is held still before it asks. |
| `stillDistance` | 10 pt | How far it may move and still hold. |
| `depthWeight` | 0.5 | How much a move in depth counts. |
| `heldTapGrace` | 0.25 s | How long after a hold the control's tap is still the hold's. |

```swift
import GestureKit
import SwiftUI

/// A handle whose own drag resizes something, and whose still hold asks a
/// question instead, its drag and tap doing nothing for the rest of the
/// pinch.
struct ResizeHandle: View {
    @Binding var width: Double
    @State private var isHeld = false
    @State private var asksToSplit = false
    @State private var widthAtStart: Double?
    @GestureState private var isDragging = false

    var body: some View {
        Capsule()
            .fill(isHeld ? Color.orange : Color.yellow)
            .frame(width: 44, height: 136)
            .gesture(
                DragGesture(minimumDistance: 15)
                    .updating($isDragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        guard !isHeld else { return }
                        let start = widthAtStart ?? width
                        widthAtStart = start
                        width = max(start + value.translation.width, 100)
                    }
                    .onEnded { _ in widthAtStart = nil }
            )
            .holdWatch(isHeld: $isHeld, dragHasBegun: isDragging) {
                asksToSplit = true
                return true
            }
            .alert("Split here?", isPresented: $asksToSplit) {
                Button("Split") {}
                Button("Cancel", role: .cancel) {}
            }
    }
}
```

## Tuning and tracing

Every gesture's tuning conforms to `Tunable`: `CarryTuning`, `FacingTuning`,
`PlacementTuning`, `PluckTuning`, `HandPinchTuning`, `SurfacePress.Tuning`,
`HoldLift.Tuning`, `Coast.Tuning`, and `HoldWatch.Tuning`. Its `defaults`
are GestureKit's, and its `parameters` describe each value, a key (the
property's name), a short title, a unit, and a slider's range and step or a
switch, so a panel can tune it without knowing the gesture.

- **`TuningStore`** keeps a tuning live and observable, saving the values
  that differ from the defaults in `UserDefaults` under a namespace. Hand its
  `tuning` to the adapter, which reads it as each pinch touches.
- **`TuningPanel`** shows a slider or a switch for each value, a yellow dot
  and the default beside one that's changed, **Defaults**, and **Copy
  tuning**.
- **`TraceRecorder`** keeps the last 12 interactions, each a timeline of what
  the gesture did and why, a drag's run of steps folded into one line; each
  finished one's summary is logged at info level under the subsystem
  `net.alexbrodriguez.gesturekit`. **`TraceView`** shows them, white on
  black, sized to read in a recording made on the headset.
- **Tracing off**: pass no recorder, as a release build should, or set its
  `isRecording` to false. Either way an adapter does no tracing work, and the
  console gets at most one line for each finished interaction.

```swift
import GestureKit
import RealityKit
import SwiftUI

/// The carry, tuned live as it's tried, each pinch traced.
@MainActor @Observable
final class CarryWorkbench {
    /// Saves the values that differ from the defaults in UserDefaults.
    let tuning = TuningStore<CarryTuning>(namespace: "MyApp.carry")
    /// Keeps the last 12 pinches; isRecording = false traces nothing.
    let trace = TraceRecorder()
}

/// A window: a slider for each number, Defaults, Copy tuning, and the trace.
struct CarryWorkbenchWindow: View {
    let bench: CarryWorkbench

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            TuningPanel(bench.tuning, title: "Carry")
                .frame(width: 480)
            TraceView(bench.trace)
        }
        .padding(24)
    }
}

/// The room: the adapter reads the tuning as each pinch touches.
struct CarryWorkbenchSpace: View {
    let bench: CarryWorkbench

    var body: some View {
        RealityView { _ in }
            .grabHandlesCarryEntities(tuning: bench.tuning.tuning, recorder: bench.trace)
    }
}

/// Numbers of your own, tuned in the same panel.
struct BadgeTuning: Tunable {
    var size = 0.2
    var spins = true

    static let defaults = BadgeTuning()

    static let parameters: [TuningParameter<BadgeTuning>] = [
        .number(\.size, key: "size", title: "Size", unit: "m", range: 0.05...0.6, step: 0.01),
        .toggle(\.spins, key: "spins", title: "Spins"),
    ]
}
```

Once a tuning feels right, **Copy tuning** puts it on the pasteboard as the
Swift that makes it, each changed value marked with the default it replaces,
and logs it:

```
CarryTuning(
    startDistance: 12.0, // default 8.0
    nearestToHead: 0.3
)
```

Pass that to the adapter, or make it GestureKit's defaults in a commit of
its own.

## GestureLab

GestureLab, in `Lab/`, is a visionOS app with a station for each gesture: a
window listing them, and a mixed immersive space where the chosen one
stands, with its tuning panels and a live trace beside it. A switch in the
window's toolbar turns tracing off for the whole lab, and one in each trace
for its station, to feel a gesture with no trace at all.

To run it:

1. Copy `Local.xcconfig.example` to `Local.xcconfig` at the repository's
   root and set `DEVELOPMENT_TEAM` to your team. It's gitignored;
   `Lab/Signing.xcconfig` includes it.
2. Open `Lab/GestureLab.xcodeproj`.
3. Run the GestureLab scheme on your Vision Pro. It runs in the simulator
   too, where a click is a pinch, but nothing tracks your head or hands
   there.

The stations:

- **Trace check**: a cube to pinch, proving the trace and live tuning end to
  end.
- **Carry and face**: three panels, each carried by the pill under it,
  turning to face you.
- **Below the gaze**: a panel placed below your gaze by a button, and carried
  by its pill.
- **Press**: a surface to tap, drag, flick, pick up, or hold, and a tab at
  its end whose hold is watched.
- **Pluck**: a grid in a window of its own, whose items you pull out into
  the room as cards.

`AGENTS.md` has the repository's layout and conventions, how to add a
gesture or a station, and how a change is proven, with the skills in
`.agents/skills/`.

## Testing

- **`swift test`**, at the package's root, runs GestureCore's tests on the
  Mac: every rule, on a clock each test steps, never sleeping. It also checks
  that each Swift block in this README is, exactly, code the lab compiles,
  in `Lab/GestureLab/ReadmeSnippets/`.
- **`scripts/build-check.sh`** compile-checks GestureLab, and with it
  GestureKit's visionOS side and this README's code, for the visionOS
  Simulator, in a throwaway DerivedData with signing off, so it needs no
  team. `scripts/build-check.sh release` builds Release.
- **The lab's measurement loads.** The simulator can't pinch, so a debug
  build of the lab takes launch arguments that stand in for a hand:
  `-station <id>` chooses a station (`trace-check`, `carry-and-face`,
  `below-the-gaze`, `press`, or `pluck`); `-labLoad <kinds>`,
  comma-separated, puts a load on it 3 s in, from a stream of trace events
  (`trace`) or a slider swept 60 times a second (`tuning`) to the pluck's
  pull and scroll (`pull`, `scroll`) and the adapters driven through a
  hand's stand-in (`surface`, `tab`, `handle`, `stuck`, `lifted`); and
  `-labTracing off` starts with tracing off. Read the app's CPU time from
  `ps` as a load runs; `AGENTS.md` has every load and how to measure.

  ```sh
  xcrun simctl launch <device> net.alexbrodriguez.gesturelab -station pluck -labLoad pull
  ```

## Automation

Every app on GestureKit can have its gestures driven in a visionOS simulator
with no hand: by an agent testing a change, or by you. In a debug build,
each adapter registers what it drives as its view appears, under the ids you
already give it, and goes as its view does. A release build compiles none of
it.

A command names a gesture and what it's on. The automation then says the
words that gesture's adapter would hear from a hand, at a hand's pace, so
the adapter and GestureCore's rules run as they would on the headset. Your
app hears the gesture as it would from a hand, and the answer, in JSON,
says what happened.

1. **Turn it on.** There's no code to write. Launch with
   `GESTUREKIT_AUTOMATION=1` in the environment, or `-GestureKitAutomation
   YES` as an argument, and GestureKit serves commands on 127.0.0.1:48765,
   which the simulator shares with your Mac. `gesturekit-drive launch` does
   this for you.
2. **Launch your app in a simulator.** Build a debug build for the
   simulator and install it, then run the package's driver from your
   package's root. From an Xcode project, run it from GestureKit's
   checkout, with `swift run --package-path <checkout> gesturekit-drive`.

   ```sh
   swift run gesturekit-drive launch com.example.app
   ```

3. **See what's drivable, and smoke it.** `targets` lists each target by
   kind and id. `smoke` drives every one once with its default command and
   reports each outcome.

   ```sh
   swift run gesturekit-drive targets
   swift run gesturekit-drive smoke
   ```

4. **Drive one gesture, and read the result.**

   ```sh
   swift run gesturekit-drive pluck "item 7" pull=0,0,0.06
   swift run gesturekit-drive carry panel-b by=0.1,0,0.2
   swift run gesturekit-drive hold surface seconds=1.2
   swift run gesturekit-drive trace
   swift run gesturekit-drive screenshot
   ```

   Each prints the app's answer:
   - `ok`;
   - its `outcome`, such as `spawned`, `carried`, or `hold`;
   - a `result` to assert on, such as where a carried thing stood;
   - the `events` the adapters reported;
   - the `trace` of each interaction;
   - your app's `state`.

   It exits 1 when a command fails, and the answer's `error` says why.
   `--brief` prints only the outcome and result.

5. **Give your agents the skill.** `install-skill` copies GestureKit's
   `verify-gestures` skill into your repository's `.agents/skills/`, or the
   folder `--into` names, refusing to replace one already there unless
   `--replace`. It tells an agent how to launch your app in a simulator of
   its own, check that it's driving the right build, drive each gesture with
   a check written first, keep each answer, trace, screenshot, and state as
   evidence, clean up only what it made, and grow a map of your app's
   gestures. Its helper, `scripts/gesture-verify.sh`, does each step.

   ```sh
   swift run gesturekit-drive install-skill
   ```

   For Claude Code, link `.claude/skills` to `.agents/skills`.

### How things are named

| What | Driven by |
| --- | --- |
| A pluckable item | its title or its id |
| A pluckable grid | its `automationID`, "grid" unless you give one |
| A surface or a hold watch | its `automationID`, else its trace title |
| A grab handle | what it carries |
| A panel stood below the gaze | its entity's name |
| A tuning store | its namespace |

The commands are `pluck`, `tap`, `scroll`, `carry`, `place`, `drag`,
`flick`, `pickup`, `hold`, and `tune`. Vectors are meters: x right, y up, z
toward you. `gesturekit-drive help` lists the commands, and
`docs/automation-design.md` says what each runs for real and what it stands
in for.

Naming a target, adding your own state to every answer, and adding commands
of your own are optional:

```swift
import GestureKit
import SwiftUI

/// A surface the automation drives as "strip" rather than by its trace's
/// title, and, in a debug build, the app's own state in every answer.
struct AutomationNamedStrip: View {
    let clipCount: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .frame(width: 600, height: 120)
            .surfacePress(traceTitle: "Pinch on the strip", automationID: "strip") { _ in }
            #if DEBUG
            .onAppear {
                GestureAutomation.shared.register(state: "editor") { ["clips": .number(Double(clipCount))] }
            }
            #endif
    }
}
```

An app that shows no GestureKit adapter at launch can call
`GestureAutomation.start()`.

GestureLab drives itself the same way:
- The `verify-gesturelab` skill, in `.agents/skills/`, proves a change to
  a gesture there: a run's own simulator, a doctor, a feature map with a
  recipe per gesture, and the evidence kept in `artifacts/`.
- `scripts/gesture-drive.sh up` keeps a simulator of its own, builds the
  lab and the driver, and launches the lab with automation on.
- `scripts/gesture-drive.sh <command>` runs any of the driver's commands
  against it.
- `scripts/gesture-selftest.sh` drives every gesture in a fresh simulator,
  checks each outcome, and exits non-zero at the first failure.

## License

MIT; see [`LICENSE`](LICENSE).
