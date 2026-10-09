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
  - `TraceLog`: the last interactions with a gesture, newest first
    (`TracedInteraction`), each with its timed events (`TraceEvent`), its
    outcome, and a one-line summary.
  - `TracePacing`: when a trace shows its log's changes: the first after a
    quiet spell at once, then at most once a tenth of a second.
- `Sources/GestureKit/<Area>/`: an area's adapters, wrapped whole in
  `#if os(visionOS)`.
- `Sources/GestureKit/Lab/`: the lab's shared views, also visionOS only.
  - `TraceRecorder` and `InteractionTrace`: an observable trace an adapter
    is handed, optionally, which logs each finished interaction's summary,
    and gives what a trace shows of it paced (`shownLog`, `TracePacing`).
  - `TraceView`: a recorder's interactions as timelines, large and white on
    black, laid out in the room it's offered alone, so an event lays out
    nothing beside it.
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
    - `LabModel`: the stations, the chosen one, remembered, and whether
      the space is open.
    - `LabWindow`: the station list and the chosen station's window
      content, tuning, and trace; it opens the chosen station's own window,
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
  <type name>)`, at info level for what a person's console should show.
  Anything an app hands in, such as a trace's titles, logs at the default
  privacy unless the app asks otherwise.
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
  second; `coast`, the press's playhead flicked every 2 s; and `switch`,
  the next station chosen every 4 s. What a load changes stays, as a
  hand's would: `tuning` leaves its value tuned, saved, until Defaults, and
  `switch` the station it chose last remembered.

Build the lab for the simulator into a throwaway DerivedData, install it on
a simulator of your own with `xcrun simctl install`, launch it with
`xcrun simctl launch <device> net.alexbrodriguez.gesturelab -station pluck
-labLoad pull`, and read the app's CPU from its CPU time, `ps -o time= -p
<pid>`, over 15 s or so, and where it goes with `sample <pid> 5`. In a
Debug build, each station idles at about 0% of a core, and each load costs
8-30%; until the trace and the tuning's sliders stopped laying out the
whole window, the trace load cost up to 54% and the tuning load 100%.

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
