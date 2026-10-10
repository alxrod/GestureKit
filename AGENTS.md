# GestureKit Agent Guide

## What this is

A public Swift package of content-agnostic gestures for Apple Vision Pro,
and GestureLab, a visionOS app for trying each one on the headset with a
live trace and live tuning. `docs/design.md` has the design: the two
libraries, the gesture areas, how the lab, tracing, and tuning work, and
the order the areas arrive in.

- **GestureCore**: each gesture's rules and math, plain Swift, macOS 14+
  and visionOS 26, tested with `swift test` on the Mac. Areas: Carry,
  Facing, Placement, Pluck, Press, Coast, and HoldWatch, and Lab, the
  tuning and trace model the lab shares.
- **GestureKit**: the visionOS adapters that carry those rules out on any
  RealityKit entity or SwiftUI view, reporting through closures, and the
  lab's shared views. It re-exports GestureCore.
- **GestureLab**: the app in `Lab/`, a window listing a station per
  gesture and a mixed immersive space where the chosen one stands.

## Layout

- `Package.swift`: the two libraries and GestureCore's tests, in the Swift
  6 language mode.
- `Sources/GestureCore/<Area>/`: an area's rules, as values, and its
  tuning.
- `Sources/GestureCore/Lab/`: what a tuning and a trace are, for every
  area and the lab.
  - `Tunable`: a tuning struct's defaults and its parameters; the values
    that differ from the defaults (`tunedValues`), a tuning made again
    from them (`init(defaultsTunedWith:)`), its Swift
    (`swiftInitializer()`), and what's wrong with its parameters'
    descriptions (`parameterProblems`).
  - `TuningParameter`: one tunable value: a key, its property's name; a
    title; a unit; a slider's range and step, or a switch; read and written
    through its key path, a `Double`, `Float`, `CGFloat`, `Duration`, or
    `Bool`; fitted to its range and step, and shown with its unit.
  - `TuningValue`: a number or a switch, coded as a bare JSON value.
  - `TraceLog`: the last 12 interactions with a gesture, newest first
    (`TracedInteraction`), each with its timed events (`TraceEvent`), its
    outcome, and a one-line summary. An event of the same name as the one
    before it, within a second, folds into its line, as a drag's words do:
    how many, the first's and the latest's time and detail, and the
    farthest any reached (`TraceMeasure`); a change of name always begins a
    line, and an interaction with ten lines folds a name it has had into
    that name's latest line.
  - `TracePacing`: when a trace shows its log's changes: the first after a
    quiet spell at once, then at most once a tenth of a second.
- `Sources/GestureKit/<Area>/`: an area's adapters, wrapped whole in
  `#if os(visionOS)`.
- `Sources/GestureKit/Lab/`: the lab's shared views, also visionOS only.
  - `TraceRecorder` and `InteractionTrace`: an observable trace an adapter
    is handed, optionally, which logs each finished interaction's summary,
    and gives what a trace shows of it paced (`shownLog`, `TracePacing`).
    While it isn't recording (`isRecording`), `begin` gives nil, making no
    title, so an adapter does no tracing work, as one with no recorder.
  - `TraceView`: a recorder's interactions, the newest two in full and the
    rest a line or two each, white on black at 14-17 pt, laid out in the
    room it's offered alone, so an event lays out nothing beside it, and
    changes its own line or adds one; given a switch, it shows it in its
    header.
  - `PinchStandIn`, DEBUG only, behind `@_spi(PinchStandIn)`: a hand's
    stand-in, whose steps `.surfacePress`, `.holdWatch`, and
    `.grabHandleCarry` take as their own drag's words while it listens, for
    the lab's loads (see "Measuring the lab").
  - `TuningStore`: a tuning tuned live, saved in `UserDefaults` under a
    namespace; a set that changes nothing tells no one.
  - `TuningPanel`: any tuning's sliders and switches, Defaults, and Copy
    tuning; each row drawn again only as its value changes, and each slider
    unstepped, its value fitted to the step as it's set, since a stepped
    slider's marks made every slider in a window cost as any one moved.
- `Tests/GestureCoreTests/<Area>/` and `Tests/GestureCoreTests/Lab/`: the
  core's tests, a folder per area.
- `Lab/`: GestureLab.
  - `project.yml`: the xcodegen spec, the source of truth for
    `GestureLab.xcodeproj`, which is committed.
  - `Signing.xcconfig`: includes the gitignored `../Local.xcconfig` if it's
    there, for the development team.
  - `Support/Info.plist`: generated from `project.yml`.
  - `GestureLab/`: the app's sources, a synchronized folder, so adding a
    file needs no regeneration.
    - `GestureLabApp`: the window, a station's own window, and the
      immersive space; registers every station's components as it starts.
    - `LabStation`: what a station is. `LabStations`: the registry, one
      line per station.
    - `LabModel`: the stations, the chosen one, remembered, whether the
      space is open, and which stations trace: a switch for the whole lab
      and one for each station, remembered, which set each station's
      recorder's `isRecording`.
    - `LabWindow`: the station list and the chosen station's window
      content, tuning, and trace, with the whole lab's trace switch in its
      toolbar and the station's in its trace's header; it opens the chosen station's own window,
      if it has one, and closes it as another is chosen
      (`StationOwnWindow`, its trace in an ornament beside it). `LabSpace`:
      the space's view, and where stations stand (`LabSpace.front`).
    - `Stations/<Area>/`: each station. `Stations/TraceCheck/` is the
      starter, a cube to pinch, traced, its size tuned live.
    - `LabLoad`, DEBUG only: a load the lab puts on itself, as a hand
      would, for measuring in the simulator (see "Measuring the lab").
- `scripts/build-check.sh`: the lab's compile check.
- `docs/design.md`: the design.
- `Local.xcconfig.example`: copy to `Local.xcconfig`, gitignored, and set
  your team to run the lab on a device.

## Conventions

- This repository is public. Never commit `Local.xcconfig`, a team id, a
  personal path, or a secret. The lab's project gets its team through
  `Lab/Signing.xcconfig`'s optional include: wiring `Local.xcconfig` into
  `project.yml` directly has xcodegen write the team into the committed
  project's target attributes.
- Swift 6 language mode. Tests use Swift Testing (`import Testing`,
  `@Suite`, `@Test`, `#expect`). Rules take their time from a clock the
  caller gives, so tests step it; tests never sleep.
- Name things for what they do, never by a version number. The API speaks
  of items, surfaces, panels, handles, grids, and carried things, never of
  what an app works on.
- Doc comments in plain, concrete prose: what a thing does, and why.
- GestureCore imports no SwiftUI, RealityKit, or ARKit; Foundation and simd
  are fine. GestureKit's sources are wrapped whole in `#if os(visionOS)` …
  `#endif`, so the package builds on the Mac.
- Every area's tuning conforms to `Tunable`, and its tests expect
  `parameterProblems` to be empty. An adapter takes its area's tuning and a
  `TraceRecorder?`, and reports what happens through closures, leaving the
  app's state to the app.
- Several areas share each module, so give a file-private helper a name no
  other area would use, and add no internal extensions on standard types:
  two files' helpers of one name make each other's uses ambiguous.
- Log with `os.Logger(subsystem: "net.alexbrodriguez.gesturekit", category:
  <type name>)`, at info level for what a person's console should show:
  at most one line for each finished interaction, the trace's summary when
  it's traced, and otherwise the adapter's own; nothing at info for each
  word of a drag, and no words made for a trace that isn't recording (test
  the `InteractionTrace?`, as `if let trace`, before working them out).
  Name an entity by its name: `String(describing:)` writes out every
  component and child it has. Anything an app hands in, such as a trace's
  titles, logs at the default privacy unless the app asks otherwise.
- An adapter keeps what changes at each word of its drag in a reference
  held once in `@State`, never in `@State` itself, whose every change runs
  the modifier's body again, its gestures and all; what it draws from a
  pinch, as a press's lift, is an observable read by a modifier of its own.
- Register every custom RealityKit `Component` and `System` before
  anything uses it: a station does so in its `registerComponents()`, which
  the app calls in its `init()`.
- Commit in logical steps, staging files by name.

## Building and testing

- The core: `swift build` and `swift test` at the package's root, on the
  Mac. The Mac builds GestureKit empty, since its sources are visionOS
  only.
- The lab, and with it GestureKit's visionOS side:
  `scripts/build-check.sh`, or `scripts/build-check.sh release`. It builds
  for the generic visionOS Simulator into a throwaway DerivedData with
  signing off, so it needs no team, prints this repository's diagnostics
  and the result line, and cleans up.
- When several agents share the machine, run each build and test through
  the build lock your coordinator names.
- Never run `xcodebuild` against Xcode's default DerivedData, and never
  `xcodebuild test` an app target; `scripts/build-check.sh` is the way to
  build the lab from the command line.
- After changing `Lab/project.yml`, run `xcodegen generate` in `Lab/` and
  commit the project with it. A new file under `Lab/GestureLab/` needs no
  regeneration.
- Running the lab: copy `Local.xcconfig.example` to `Local.xcconfig` at the
  root, set `DEVELOPMENT_TEAM`, open `Lab/GestureLab.xcodeproj`, and run
  the GestureLab scheme on a Vision Pro or the simulator, where a click is
  a pinch.

## Measuring the lab

The simulator can't pinch, so a DEBUG build takes launch arguments that
stand in for a hand (`LabLoad`):

- `-station <id>` chooses the station at launch: `trace-check`,
  `carry-and-face`, `below-the-gaze`, `press`, or `pluck`.
- `-labLoad <kinds>`, comma-separated, begins 3 s in: `trace`, 20 trace
  events a second after 30 interactions of 15; `tuning`, the station's
  first number slid across its range, set 60 times a second; `pull`, the
  pluck's card moved 90 times a second; `scroll`, the pluck's grid scrolled
  at 1,500 pt a second; `drag`, the press's playhead moved 90 times a
  second; `coast`, the press's playhead flicked every 2 s; `switch`, the
  next station chosen every 4 s; and three that drive an adapter through
  the hand's stand-in (`PinchStandIn`), 90 words a second for 2 s, let go,
  and again: `surface`, a drag along the press's surface through
  `.surfacePress`; `tab`, a hold on the press's tab through `.holdWatch`;
  and `handle`, the carry and face station's middle panel carried round a
  circle through `.grabHandleCarry`. What a load changes stays, as a
  hand's would: `tuning` leaves its value tuned, saved, until Defaults, and
  `switch` the station it chose last remembered.
- `-labTracing off` starts with the whole lab's tracing off, so a load
  measures the gestures with no trace; `on` starts with it on.

Build the lab for the simulator into a throwaway DerivedData, install it on
a simulator of your own with `xcrun simctl install`, launch it with
`xcrun simctl launch <device> net.alexbrodriguez.gesturelab -station pluck
-labLoad pull`, and read the app's CPU from its CPU time, `ps -o time= -p
<pid>`, over 15 s or so, and where it goes with `sample <pid> 5`; the
render server is the simulator's `backboardd`, a child of the device's
`launchd_sim`, which idles at about 30% of a core and swings 5 points from
run to run. A `tuning` load leaves its value saved in the app's container,
not in the simulator's own defaults: clear it between runs with `xcrun
simctl spawn <device> defaults delete <container>/Library/Preferences/net.alexbrodriguez.gesturelab`,
the container from `xcrun simctl get_app_container <device>
net.alexbrodriguez.gesturelab data`.

In a Debug build, each station idles at about 0% of a core. The trace load
costs 7-11% of a core, and 41-51% in the render server; with tracing off,
nothing. Until the trace folded its runs and showed fewer, smaller lines,
it cost 11-17% and 51-62%, its text laid out again by Core Text at each
change about half of what the main thread did, and until the trace and the
tuning's sliders stopped laying out the whole window, up to 54%, with the
tuning load at 100%. The tuning loads cost 17-30%, the pluck's pull and
scroll about 20%, and the adapters' loads, traced, 5-10%: `handle` about
10%, from 25-35% while the carry described its entity whole in its info
lines and the trace drew a line at each step; `surface` about 8%, and `tab`
about 5%, each a few points less untraced. The machine was shared and busy
as these were measured, so take each to a few points.

A view that changes at a hand's every step lays out nothing beside it and
is read by nothing that doesn't show it: the trace takes its room whatever
it shows, and the pluck station's windows read how many cards there are,
not where they stand.

## Adding a gesture area

1. Its rules in `Sources/GestureCore/<Area>/`, as values, told what
   happened with its times, and its tuning, conforming to `Tunable`:

   ```swift
   extension CarryTuning: Tunable {
       public static var defaults: CarryTuning { .standard }

       public static let parameters: [TuningParameter<CarryTuning>] = [
           .number(\.startDistance, key: "startDistance", title: "Start distance",
                   unit: "pt", range: 0...30, step: 1),
           .number(\.nearestToHead, key: "nearestToHead", title: "Nearest to the head",
                   unit: "m", range: 0.1...1, step: 0.01),
       ]
   }
   ```

   Each key is the property's name, which the tuning's initializer takes as
   its label, so Copy tuning's Swift compiles.
2. Its tests in `Tests/GestureCoreTests/<Area>/`, among them
   `#expect(CarryTuning.parameterProblems.isEmpty)`.
3. Its adapters in `Sources/GestureKit/<Area>/`, wrapped in `#if
   os(visionOS)`, each taking the tuning, a `TraceRecorder?`, and closures
   for what happens. An adapter traces a pinch from its touch to its end:

   ```swift
   trace = recorder?.begin("Carry", title: "Pinch on a handle")
   trace?.event("carry", "after 8 pt")
   trace?.finish("carried 0.42 m")
   ```

4. Its row in `docs/design.md`'s table and the README's list.

## Adding a lab station

1. Its files in `Lab/GestureLab/Stations/<Area>/`: a `@MainActor
   @Observable final class` conforming to `LabStation`, with a
   `TuningStore` named "GestureLab.<id>" for each tuning and a
   `TraceRecorder(logsSummariesPublicly: true)`, its space content a
   `RealityView` with attachments around `LabSpace.front`, handing the
   adapters `store.tuning` and the recorder:

   ```swift
   @MainActor @Observable
   final class CarryStation: LabStation {
       let id = "carry"
       let title = "Carry"
       let summary = "A panel carried by its grab handle, 1:1 with the hand."
       let tuning = TuningStore<CarryTuning>(namespace: "GestureLab.carry")
       let trace = TraceRecorder(logsSummariesPublicly: true)

       static func registerComponents() {
           // Each RealityKit component and system the space uses.
       }

       var windowContent: some View { Text("Pinch the handle under the panel and carry it.") }
       var spaceContent: some View { CarrySpace(station: self) }
       var tuningContent: some View { TuningPanel(tuning, title: "Carry") }
   }
   ```

2. One line in `LabStations.all()`: `CarryStation(),`.
3. `scripts/build-check.sh`.

A gesture that lives in a window, as an item in a scrolling grid does, gets
a window of its own rather than the lab window's scrolling column: give the
station an `ownWindowTitle`, "grid window", and its `ownWindowContent`, as
`Stations/Pluck/` does.

`Stations/TraceCheck/TraceCheckStation.swift` is a whole station to copy
from.
