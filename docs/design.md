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
| Pluck | An item pulled out of a scrolling grid: a pinch that moves first is the grid's scroll; held still, the item lifts and the scroll stops under it; a moment later its pull arms, and a move toward the viewer pulls it out. |
| Press | One pinch on a surface, told as a tap, a drag along or across, a pickup and carry, or a hold, by how far it moves and how long it's still. |
| Coast | A scroll let go on the move coasts on, slowing exponentially, and a pinch catches it. |
| HoldWatch | A still hold on a handle or control, watched beside its own drag and tap. |

Each area is a folder of its own in GestureCore and in GestureKit, named as
above, with its tests in `Tests/GestureCoreTests/<Area>/`.

## The lab

GestureLab, in `Lab/`, is a visionOS app: a window and a mixed immersive
space, opened at launch.

- **The window** lists the stations, each with a one-line summary. For the
  one chosen it shows the station's own window content (how to try it, and
  anything it shows as it's tried), its tuning panel, and its trace.
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
logged at info level, one line, for the console:

    #3 Trace check · Pinch on the cube → tap, 0.13 s: touch +0.00 s (size 0.20 m); release +0.12 s (moved 0.2 cm)

### How tuning flows

Each area's tuning conforms to `Tunable`: its defaults, and a
`TuningParameter` for each number or switch, with a key (the property's
name), a title, a unit, a range and a step, read and written through its key
path. The station keeps it in a `TuningStore`, which saves the values that
differ from the defaults in `UserDefaults` under "GestureLab.<station
id>", and shows a `TuningPanel`: a slider with its number for each number, a
switch for each switch, Defaults, and Copy tuning. The station passes
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
