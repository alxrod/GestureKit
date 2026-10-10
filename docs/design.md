# GestureKit's design

## Why

Vignette, the visionOS app these gestures come from, grew them one round at
a time: carrying a panel by its grab handle, keeping it turned to face you,
placing controls below your gaze, pulling an item out of a scrolling grid,
telling a pinch on a surface as a tap, a drag, a pickup, or a hold. They
kept failing on the headset, and every change was blind, since the
simulator can't pinch.

GestureKit takes that logic out of the app, makes it content-agnostic, and
puts each gesture on a station in a lab app on the headset, with a live trace
of what it did and live tuning of the numbers it goes by. The app then
depends on GestureKit rather than its own copies.

## Two libraries

- **GestureCore**: each gesture's rules and math as plain Swift values,
  with no SwiftUI, RealityKit, or ARKit, building for macOS 14 and visionOS
  26 and tested with `swift test` on the Mac. A rule is told what happened,
  each word with its time on a clock the caller gives
  (`ContinuousClock.Instant`, or seconds), and says what that means: a
  state machine for a pinch, a function for where something stands. Each
  takes a tuning, a struct of every number it goes by, whose defaults are
  the ones settled on the headset.
- **GestureKit**: the visionOS adapters that carry GestureCore's rules out
  on any RealityKit entity or SwiftUI view: components and their
  entity-targeted drags, systems, view modifiers, head tracking, and lift
  visuals. It knows nothing of what it moves: each adapter takes a tuning,
  reports what happens through closures, and leaves the app's state to the
  app. Each takes a `TraceRecorder` too, optionally, so an app that doesn't
  trace passes nothing. Its sources are wrapped in `#if os(visionOS)`, so
  the package builds on the Mac. It re-exports GestureCore.

Nothing in either library names what an app works on: they speak of items,
surfaces, panels, handles, grids, and carried things.

## The gestures

| Area | What it does |
| --- | --- |
| Carry | A grab handle carries a thing 1:1 with the hand, by its middle, never nearer the head than 0.3 m. A pinch waits 8 pt before it carries. Core: `CarryPinch`, `HandCarry`, `ViewerCenteredFrame`, `CarryTuning`. Kit: `GrabHandle` and `GrabHandleComponent`, the drag `grabHandleCarry(of:…)` reporting each step through closures, and `grabHandlesCarryEntities(…)` with `CarriedEntity`, which move the entity themselves. Station: Carry and face. |
| Facing | A thing turns to face the viewer, standing on a point or hanging from one, and keeps its way when the viewer is straight above or below it. Core: `Facing`, `Pose`, `FacingTuning`. Kit: `FacesTheViewerComponent` and its system, frame by frame, and `HeadTracker`, world tracking with the simulator's stand-in (`UntrackedHead`). Station: Carry and face. |
| Placement | A panel opens below the gaze, a set distance out, tilted up to the head, and stays put until carried by its handle. Core: `GazePlacement`, `PanelHandle`, `PlacementTuning`. Kit: `GazePanel`, which stands a panel below the gaze, and `PanelHandleRig` with `PanelHandlePill`, the pill under a panel and its grab handle. Station: Below the gaze. |
| Pluck | An item pulled out of a scrolling grid. A pinch is the grid's scroll unless it's a hold, as Alex asked: one the grid's scroll view scrolls with, or whose scroll offset moves a point from where it stood at the touch, whatever phase the scroll view says it's in, or that moves 10 pt along the scroll, the axes the container gives, vertical by default, or 40 pt any way, before its hold, is the grid's scroll for good; tracking, which the scroll view reports for every pinch from its touch, isn't scrolling. Held still a quarter second with none of those, the item lifts and the scroll stops under it. Lifted, it stays in the grid, held: it follows the hand a little, half the move at first and easing toward 20 pt, as a scroll view's content follows a pinch past its end (`PluckTether`), and the trace says how far the hand has gone of what it needs ("15.0 pt of 34.0 to break free"). A move mostly along the scroll, 10 pt and twice as far along it as across it and in depth, settles the item and gives the pinch back to the scroll (`givesLiftBackToScroll`, on by default), so by default an item can't be pulled out mostly along the scroll axis: up or down out of a grid that scrolls vertically. Whether the scroll view takes up a pinch given back to it, begun while its scroll was off, only the headset can say; if not, the pinch does nothing until it's let go, and nothing spawns. Once the hand has gone 2.5 cm, 34 pt at a window's own size, any other way from where it stood as the item lifted, and two tenths of a second have passed since the lift, the item breaks free and spawns into the room at the hand; let go before that, it settles, with nothing spawned and no tap. The break-free distance is the hand's: the drag's points are divided by the scale the window is drawn at. The pluck ends at the spawn, handing the pinch to a carry (below). Alex asked for the quarter second and the sticky lift on October 9, the half-second hold having felt long and the 6 mm pull then spawning the item the instant it lifted; that tuning, and the first-shipped 2 cm toward the viewer from the touch, stay a few values away. A pinch that moves less than the drag's 15 pt start in its first quarter second, then scrolls, still lifts, and the lift holds the scroll off until its move along the scroll gives the pinch back. `pluckContainer` marks the scroll view, with its scroll axes, `pluckable` each item, reporting its tap, its lift, `.spawned(at:)`, each `.carried(middle:handMoved:)` step, and `.released(at:)`. A lift stays up past a press that stopping the scroll may cancel, until the pinch is known to be let go. |
| Lift | A view lifted off what it lies on: scaled up and brought toward the viewer on a spring, over its shadow, above its neighbors, coming down without the bounce; and drawn a little way along with a pinch that tugs it, on a quick spring, springing back as it lets go (`liftFollowEffect`). The pluck's items show it, and anything a press picks up can. |
| Press | One pinch on a surface, from its touch, told as a tap, a drag along, a scroll, a drag across, a pickup and carry, or a hold, by how far it moves and how long it's still: held still half a second it picks up, lifting what's drawn; moved 2 cm then, it carries; held a second, it holds. `.surfacePress` on any SwiftUI view or attachment. |
| Coast | A scroll let go on the move coasts on from the hand's speed, slowing by e every 0.8 s and coming to rest at an end rather than stopping dead; a pinch on it while it still goes 5 cm a second catches it, and is no tap. `CoastRun` runs one on a clock, `CoastEasing` animates by it. |
| HoldWatch | A pinch on a handle or control held still 0.6 s asks whether the hold means anything there, watched beside the control's own drag and tap, never in front of them, which then do nothing for the rest of the pinch. `.holdWatch` on any SwiftUI view. |

Each area is a folder of its own in GestureCore and in GestureKit, named as
above, with its tests in `Tests/GestureCoreTests/<Area>/`; Lift, which has no
rules of its own, is in GestureKit alone.

### How a pluck hands over to a carry

A pluck owns its pinch up to the spawn: the hold, the lift, the held
stretch, the break-free, and where what breaks free spawns, the drag's place
pushed 100 pt toward the viewer, in the immersive space's meters. From the
spawn on, the same pinch is a carry's, and the pluck has no movement math of
its own:

    pinch ── held 0.25 s ──▶ lifted, held: the item follows on its tether
          ── 2.5 cm, armed ──▶ .spawned(at:): the pluck's part ends
          ── each move ──▶ PluckHandoff → CarryPinch → .carried(middle:handMoved:)
                                                     → CarriedEntity.stand
          ── let go ──▶ .released(at:); later pinches: its own grab handle

- `PluckHandoff`, in GestureCore, begins GestureCore's `CarryPinch` at the
  spawn, its middle where it spawned, and hands it each of the hand's
  moves, so the middle goes 1:1 with the hand from where it spawned, by the
  carry's rule. Its tests run a pluck through its break-free into the
  handoff, and the handoff's middle through `HandCarry.pose`.
- The adapter reports each of the carry's steps as
  `.carried(middle:handMoved:)`, which the app stands by the carry's and
  facing's own code, `CarriedEntity.stand`: clear of the head (`HandCarry`),
  facing the viewer (`Facing`). Where the app keeps state of its own, it
  stands the thing there instead, by `HandCarry.pose`.
- Let go, the thing is the app's. Give it a grab handle (`PanelHandleRig`,
  `GrabHandle`) and `grabHandlesCarryEntities` carries it from then on, and
  a `FacesTheViewerComponent` keeps it facing the viewer as they move. The
  Pluck station's cards do all three.

## The lab

GestureLab, in `Lab/`, is a visionOS app: a window and a mixed immersive
space, opened at launch.

- **The window** lists the stations, each with a one-line summary. For the
  one chosen it shows the station's own window content (how to try it, and
  anything it shows as it's tried), its tuning panel, and its trace.
- **A station's own window**, for a gesture that lives in a window, as an
  item in a scrolling grid does: the lab opens it beside its own as the
  station is chosen, with a button to open it again, and closes it as
  another is chosen. It shows the station's own window content edge to edge,
  with no scrolling column around it, and its trace in an ornament beside it,
  so the trace reads while the window is pinched.
- **The space** shows the chosen station's space content, a `RealityView`
  with attachments, standing around a point a meter ahead at about eye
  height (`LabSpace.front`), made afresh as another station is chosen.
- **A station** is a class conforming to `LabStation`: an id, a title, a
  summary, its window content, its space content, its tuning panels, and its
  `TraceRecorder`. Each area adds its station's files under
  `Lab/GestureLab/Stations/<Area>/` and one line to `LabStations.all()`; the
  app's sources are a synchronized folder, so new files never touch the
  project file. A station registers the RealityKit components and systems
  it uses in `registerComponents()`, which the app calls as it starts.
- **Trace check**, the starter station, proves the spine: a cube to pinch,
  each pinch traced from its touch to its release as a tap or a drag, its
  size tuned live.

### How tracing flows

A station hands its `TraceRecorder` to the adapters it uses. An adapter
begins an interaction as a pinch touches (`recorder?.begin("Pluck", title:
"Pinch on item 4")`), writes each thing that happens to the
`InteractionTrace` that gives it (`trace?.event("lift", "held still 0.50
s")`), and finishes it with its outcome (`trace?.finish("pull")`). The
recorder keeps the last 30 interactions, newest first (`TraceLog`), the
window's `TraceView` shows each as a timeline, large and white on black so a
screen recording on the headset reads it, and each finished one's summary is
logged at info level, one line, for the console. The trace shows the log's
changes at most ten times a second (`TracePacing`), and lays itself out in
the room it's offered alone, so a gesture writing it as a hand moves draws
nothing else again:

    #3 Trace check · Pinch on the cube → tap, 0.13 s: touch +0.00 s (size 0.20 m); release +0.12 s (moved 0.2 cm)

### How tuning flows

Each area's tuning conforms to `Tunable`: its defaults, and a
`TuningParameter` for each number or switch, with a key (the property's
name), a title, a unit, a range and a step, read and written through its key
path. The station keeps it in a `TuningStore`, which saves the values that
differ from the defaults in `UserDefaults` under "GestureLab.<station
id>", and shows a `TuningPanel`: a slider with its number for each number,
unstepped, its value fitted to the step as it's set, a switch for each
switch, Defaults, and Copy tuning. The station passes
`store.tuning` to its adapters as it reads them, so a slider's change takes
effect at once.

Once a tuning feels right on the headset, Copy tuning puts it on the
pasteboard as the Swift initializer that makes it, each changed value
marked with the default it replaces, and logs it. That goes into the area's
tuning as its new defaults, in a commit of its own, and every app on
GestureKit gets them as it updates.

## How Vignette adopts it

Vignette depends on GestureKit by URL, tracking `main` at first, then a
tagged release once the gestures settle. Area by area, it deletes its own
copies of the rules and adapters and calls GestureKit's instead, mapping its
own nouns onto GestureKit's neutral ones at the call site, passing the
default tunings unless it wants others, and no recorder outside its debug
builds. Its own tests of those rules go with them; GestureKit's cover them.

## Order

1. Carry, Facing, and Placement, with their stations.
2. Pluck, with its station.
3. Vignette adopts those.
4. Press, Coast, and HoldWatch, with their stations; then Vignette adopts
   them too.
