# GestureKit Agent Guide

GestureKit is a public Swift package of content-agnostic gestures for Apple
Vision Pro, and GestureLab, a visionOS app for trying each one on the
headset with a live trace and live tuning. `docs/design.md` has the design:
the two libraries, the gesture areas, the lab, tracing and tuning, and the
order the areas arrive in; `docs/automation-design.md` has driving the
gestures without a hand.

Its verification conventions, a skill per app that launches, checks,
drives, and proves, with a feature map, follow
[pstack](https://github.com/backnotprop/pstack)'s, by Lauren Tan (MIT).

## Done means proven

A change isn't done until it's proven on the real thing, not by "it
compiles":

1. **The gates**, each through your build lock: `swift test` at the
   package's root, `scripts/build-check.sh`, and `scripts/build-check.sh
   release`.
2. **Driven.** A change to a gesture's rules, an adapter, the automation,
   or a lab station is driven through `gesturekit-drive` with the
   [`verify-gesturelab`](.agents/skills/verify-gesturelab/SKILL.md) skill:
   launch, doctor, then every sub-feature of the feature file the change
   touches, each a capture with its `--expect` filter, and cleanup. The
   evidence, each answer's JSON, trace, state, screenshot, and console,
   stays in `artifacts/verify-gesturelab/<run>/`. A change to the automation
   itself also runs `scripts/gesture-selftest.sh` under a simulator name and
   port of its own (the skill's Helpers say how).
3. **The map kept.** A new or changed behavior updates its feature file in
   the same change (`features/README.md`, "Keeping the map honest").
4. **Reported plainly**: each sub-feature's ID, capture, filter, and
   verdict; what couldn't be reached and why; and what the automation
   stands in for. The real UIKit pan taking or missing a pinch, RealityKit's
   hit testing, hand and head tracking, and the feel of a gesture are a
   person's to judge on a headset: say what's left for Alex there, rather
   than calling it proven.

## Skills

Skills live in `.agents/skills/`, every harness's; `.claude/skills` is a
link to it for Claude Code.

- [`verify-gesturelab`](.agents/skills/verify-gesturelab/SKILL.md): launch
  GestureLab in a simulator of the run's own, check it, drive a feature
  from its map, keep the evidence, clean up. Its map,
  [`features/`](.agents/skills/verify-gesturelab/features/README.md): pluck,
  scroll first, carry, below the gaze, surface press, hold watch, tuning,
  and tracing and alarms, and how the map is kept honest.
- [`verify-gestures`](.agents/skills/verify-gestures/SKILL.md): the same
  for any app on GestureKit, with its helper,
  `scripts/gesture-verify.sh` (`up`, `doctor`, `drive`, `capture`, `down`),
  which the lab's skill shares. `gesturekit-drive install-skill` copies it
  into an adopter's repository.

## Rules

- **Public.** The repository is public: never commit `Local.xcconfig`, a
  team id, a personal path, or a secret. The lab gets its team through
  `Lab/Signing.xcconfig`'s optional include of the gitignored
  `../Local.xcconfig`; wiring it into `project.yml` directly has xcodegen
  write the team into the committed project.
- **Swift 6** language mode. Tests use Swift Testing (`import Testing`,
  `@Suite`, `@Test`, `#expect`). Rules take their time from a clock the
  caller gives, so tests step it; tests never sleep.
- **Names say what things do**, never a version number. The API speaks of
  items, surfaces, panels, handles, grids, and carried things, never of
  what an app works on. Doc comments are plain, concrete prose: what a
  thing does, and why.
- **Platforms.** GestureCore imports no SwiftUI, RealityKit, or ARKit;
  Foundation and simd are fine. GestureKit's sources are wrapped whole in
  `#if os(visionOS)` … `#endif`, so the package builds on the Mac.
- **Tunings.** Every area's tuning conforms to `Tunable`, and its tests
  expect `parameterProblems` to be empty. An adapter takes its area's tuning
  and a `TraceRecorder?`, and reports through closures, leaving the app's
  state to the app.
- **Shared modules.** Several areas share each module: give a file-private
  helper a name no other area would use, and add no internal extensions on
  standard types, since two files' helpers of one name make each other's
  uses ambiguous.
- **Logging.** `os.Logger(subsystem: "net.alexbrodriguez.gesturekit",
  category: <type name>)`, at info level for what a person's console should
  show: at most one line for each finished interaction, the trace's summary
  when it's traced, otherwise the adapter's own; nothing at info for each
  word of a drag, and no words made for a trace that isn't recording (test
  the `InteractionTrace?`, as `if let trace`, before working them out). Name
  an entity by its name: `String(describing:)` writes out every component
  and child. What an app hands in, such as a trace's titles, logs at the
  default privacy unless the app asks otherwise.
- **State in an adapter.** What changes at each word of a drag lives in a
  reference held once in `@State`, never in `@State` itself, whose every
  change runs the modifier's body again, its gestures and all; what it
  draws from a pinch, as a press's lift, is an observable read by a
  modifier of its own. A view that changes at a hand's every step lays out
  nothing beside it and is read by nothing that doesn't show it.
- **Automation.** A new adapter registers through `PinchStandInEar`, under
  the id its app gives it, telling whether a pinch is under way on it and
  what it goes by, and reports what it does (`GestureAutomation.heard`) only
  while a command listens. A command for it goes in
  `GestureAutomation+Drives`, its checks in `scripts/gesture-selftest.sh`,
  and its recipe in the feature map. All of it under `#if DEBUG`.
- **RealityKit.** Register every custom `Component` and `System` before
  anything uses it: a station does so in its `registerComponents()`, which
  the app calls in its `init()`.
- **Builds.** Where agents share the machine, run every build and test
  through the build lock your coordinator names; the self-test and the
  skills' launches build too. Never run `xcodebuild` against Xcode's
  default DerivedData, and never `xcodebuild test` an app target.
- **Simulators.** Make your own, by a name and port of the run's own, and
  delete only what you made; never touch one you didn't, such as a booted
  CI simulator or another agent's.
- **Commits** in logical steps, staging files by name.

## Building and testing

- **The core**: `swift build` and `swift test` at the package's root, on
  the Mac. The Mac builds GestureKit empty, its sources being visionOS
  only. `swift test` also checks that each Swift block in `README.md` is a
  file of `Lab/GestureLab/ReadmeSnippets/` and the reverse
  (`ReadmeSnippetsTests`), and the skills' shape (`AgentSkillsTests`).
- **The lab**, and with it GestureKit's visionOS side:
  `scripts/build-check.sh`, or `scripts/build-check.sh release`. It builds
  for the generic visionOS Simulator into a throwaway DerivedData with
  signing off, so it needs no team, prints this repository's diagnostics and
  the result line, and cleans up. In Release it also checks that the app
  carries none of the automation.
- **The project**: after changing `Lab/project.yml`, run `xcodegen
  generate` in `Lab/` and commit the project with it. A new file under
  `Lab/GestureLab/` needs no regeneration.
- **On the headset**: copy `Local.xcconfig.example` to `Local.xcconfig` at
  the root, set `DEVELOPMENT_TEAM`, open `Lab/GestureLab.xcodeproj`, and
  run the GestureLab scheme on a Vision Pro, or the simulator, where a
  click is a pinch.

## Driving the gestures

The simulator can't pinch, so GestureKit's automation drives the gestures:
a command at the gesture's level says the words a hand's gestures would,
through the real adapters, and answers in JSON.

- **One feature, with evidence**: the `verify-gesturelab` skill, above.
- **Everything at once**: `scripts/gesture-selftest.sh` makes a simulator
  afresh, "GestureLab-Selftest" unless `GESTURE_SIM` says otherwise, builds
  the lab and the driver into `build/gesture-selftest/`, launches the lab on
  port 48766, drives every station, checking each outcome with `jq`, runs
  the smoke on each and a script at launch, and prints `ok` for each check.
  At the first failure it prints the answer and exits non-zero. Whatever
  happens, it deletes its simulator and build, unless
  `GESTURE_SELFTEST_KEEP=1`. About three minutes, most of it the build.
- **By hand**: `scripts/gesture-drive.sh up --station pluck` (the simulator
  "GestureLab-Auto", port 48765, `build/gesture-drive/`; `GESTURE_SIM`,
  `GESTUREKIT_AUTOMATION_PORT`, and `GESTURE_DRIVE_WORK` choose others),
  then any of the driver's commands: `targets`, `smoke`, `pluck "item 7"
  pull=0,0,0.06`, `scroll by=600 on="item 3"`, `carry panel-b
  by=0.1,0,0.2`, `place`, `tap surface at=0.4`, `drag surface`, `flick
  surface`, `pickup surface`, `hold tab`, `tune press key=pickUpDelay
  value=0.3`, `station press`, `trace`, `wait`, `screenshot FILE.png`, and
  `script FILE.json`, which relaunches the lab running FILE's commands.
  `--json` prints the whole answer, `--brief` its outcome and result.
  `scripts/gesture-drive.sh down` deletes the simulator `GESTURE_SIM` names,
  whoever made it, and the build.
- **Another app on GestureKit**: the `verify-gestures` skill, or `swift run
  gesturekit-drive launch <bundle-id>` and the same commands against the
  booted simulator, or `--device`.
- **Under load**: a debug lab takes `-station`, `-labLoad`, and
  `-labTracing` at launch to stand in for a hand and measure what a gesture
  costs; [`docs/measuring-the-lab.md`](docs/measuring-the-lab.md) has every
  load, how to read the app's CPU, and what each station cost.

## Layout

- `Package.swift`: the libraries `GestureCore` and `GestureKit`, the
  executable `gesturekit-drive`, and GestureCore's tests, in the Swift 6
  language mode.
- **GestureCore**, each gesture's rules and math, plain Swift, macOS 14+ and
  visionOS 26:
  - `Sources/GestureCore/<Area>/`: an area's rules, as values, and its
    tuning. The areas: Carry, Facing, Placement, Pluck, Press, Coast,
    HoldWatch, and HandPinch.
  - `Sources/GestureCore/Lab/`: what a tuning and a trace are. `Tunable`: a
    tuning's defaults and parameters, the values that differ from the
    defaults (`tunedValues`), a tuning made again from them
    (`init(defaultsTunedWith:)`), its Swift (`swiftInitializer()`), and
    what's wrong with its parameters (`parameterProblems`).
    `TuningParameter`: one value's key (its property's name), title, unit,
    and a slider's range and step or a switch, read and written through its
    key path as a `Double`, `Float`, `CGFloat`, `Duration`, or `Bool`,
    fitted to its range and step, and shown with its unit. `TuningValue`: a
    number or a switch, coded as a bare JSON value. `TraceLog`: the last 12
    interactions, newest first (`TracedInteraction`), each with its timed
    events (`TraceEvent`), outcome, and one-line summary; an event of the
    same name as the one before it within a second folds into its line, how
    many, the first's and latest's time and detail, and the farthest any
    reached (`TraceMeasure`); a change of name begins a line, and an
    interaction with ten lines folds a name it has had into that name's
    latest line. `TracePacing`: a trace shows its log's first change after a
    quiet spell at once, then at most ten a second.
  - `Sources/GestureCore/Automation/`, `#if DEBUG`, public in debug builds:
    a JSON value (`AutomationJSON`), a command's arguments read leniently
    (`AutomationArguments`, `AutomationError`), the server's HTTP
    (`AutomationHTTP`), a hand's steps in meters and an adapter's points
    (`AutomationPath`), and what the adapters reported, folded, with each
    gesture's outcome told from it (`AutomationEventLog`,
    `AutomationOutcome`).
- **GestureKit**, the visionOS adapters, re-exporting GestureCore:
  - `Sources/GestureKit/<Area>/`: an area's adapters, wrapped whole in `#if
    os(visionOS)`.
  - `Sources/GestureKit/Lab/`, the lab's shared views:
    - `TraceRecorder` and `InteractionTrace`: an observable trace an adapter
      is handed, optionally, which logs each finished interaction's summary
      and gives what it shows paced (`shownLog`). While it isn't recording
      (`isRecording`), `begin` gives nil, so an adapter does no tracing
      work.
    - `TraceView`: a recorder's interactions, the newest two in full and
      the rest a line or two, white on black at 14-17 pt, laid out in the
      room it's offered alone; given a switch, it shows it in its header.
    - `TuningStore`: a tuning tuned live, saved in `UserDefaults` under a
      namespace; a set that changes nothing tells no one. `TuningPanel`:
      any tuning's sliders and switches, Defaults, and Copy tuning, each row
      drawn again only as its value changes, each slider unstepped, its
      value fitted to the step as it's set, since a stepped slider's marks
      made every slider in a window cost as any one moved.
    - `PinchStandIn`, DEBUG, behind `@_spi(PinchStandIn)`: a hand's
      stand-in, whose steps `.surfacePress`, `.holdWatch`, and
      `.grabHandleCarry` take as their drag's words while it listens, and a
      pluckable item, by its title, and its container take as their
      gestures' and scroll view's words (`PluckStep`), the container moving
      its content through SwiftUI's scroll position
      (`PluckContainerStandIn`); a step goes to every adapter of its kind,
      or those of one id. Each adapter's ear (`PinchStandInEar`) listens
      while its view is on screen and the stand-in or the automation is on,
      with its id, whether a pinch is under way, what it goes by, and its
      trace. `PinchTracker.standIn` is the hands' stand-in, fed as hand
      tracking would feed it.
    - `pluckScrollViewProbe`, DEBUG, in `Sources/GestureKit/Pluck/`: inside
      a pluckable scroll view's content, it reads what the UIKit scroll
      view behind SwiftUI's has, its scrolling, its pan and the pan's
      state, for the container's status line and alarms.
  - `Sources/GestureKit/Automation/`, visionOS and `#if DEBUG`, public:
    `GestureAutomation`, the hub: what's registered; the switch it reads
    (`GestureAutomationSwitch`: `-GestureKitAutomation`,
    `GESTUREKIT_AUTOMATION`, their port and script); the commands' drives
    (`GestureAutomation+Drives`); the server on 127.0.0.1
    (`GestureAutomationServer`); a script run at launch
    (`GestureAutomation+Script`); and what each adapter reports
    (`GestureAutomationReports`). Each adapter registers itself through its
    ear, `GrabHandle.make` its handle, `GazePanel.stand` its panel, and
    `TuningStore` itself.
- `Sources/GestureKitDrive/`: `gesturekit-drive`, the Mac tool an app's own
  repository runs with `swift run`: `launch`, `targets`, `smoke`, each
  gesture's command, `trace`, `wait`, `state`, `commands`, `send`,
  `screenshot`, and `install-skill`.
- `Tests/GestureCoreTests/<Area>/` and `Tests/GestureCoreTests/Lab/`: the
  core's tests, a folder per area; `ReadmeSnippetsTests` and
  `AgentSkillsTests` check the README's code and the skills.
- `Lab/`, GestureLab:
  - `project.yml`: the xcodegen spec, the source of truth for the committed
    `GestureLab.xcodeproj`. `Signing.xcconfig`: includes the gitignored
    `../Local.xcconfig` if it's there. `Support/Info.plist`: generated from
    `project.yml`.
  - `GestureLab/`, a synchronized folder, so a new file needs no
    regeneration:
    - `GestureLabApp`: the window, a station's own window, and the
      immersive space; registers every station's components as it starts.
    - `LabStation`: what a station is. `LabStations`: the registry, a line
      per station.
    - `LabModel`: the stations, the chosen one, remembered, whether the
      space is open, and which stations trace: a switch for the whole lab
      and one for each station, remembered, setting each recorder's
      `isRecording`.
    - `LabWindow`: the station list and the chosen station's window
      content, tuning, and trace, the whole lab's trace switch in its
      toolbar and the station's in its trace's header; it opens the chosen
      station's own window, if it has one, closing it as another is chosen
      (`StationOwnWindow`, its trace in an ornament beside it).
      `LabSpace`: the space's view, and where stations stand
      (`LabSpace.front`).
    - `LabAutomation`: what the lab adds to the automation, as any app may:
      the `station` command, the lab's state in every answer, and the
      press's coast for `wait`.
    - `Stations/<Area>/`: each station. `Stations/TraceCheck/` is the
      starter, a cube to pinch, traced, its size tuned live.
    - `LabLoad`, DEBUG: the loads the lab puts on itself, as a hand would
      ([`docs/measuring-the-lab.md`](docs/measuring-the-lab.md)).
    - `ReadmeSnippets/`: the README's code, a file per Swift block, its text
      after the file's leading comment the block's exactly, compiled with
      the lab so it can't drift from the API, and used by nothing. Change a
      snippet here, build the lab, then put the file's text in the README. A
      block that can't compile here, as the package manifest, has `<!-- Not
      compiled: … -->` on the line before its fence.
- `scripts/`: `build-check.sh`, the lab's compile check;
  `gesture-drive.sh`, the lab's own simulator and the driver's commands
  against it; `gesture-selftest.sh`, every gesture driven and checked in a
  fresh simulator.
- `.agents/skills/`: the skills, above. `.claude/skills` links to it.
- `artifacts/`, gitignored: what verification runs keep.
- `docs/`: `design.md`, `automation-design.md`, and `measuring-the-lab.md`.
- `Local.xcconfig.example`: copy to `Local.xcconfig`, gitignored, and set
  your team to run the lab on a device.

## Adding a gesture area

1. Its rules in `Sources/GestureCore/<Area>/`, as values, told what
   happened with its times, and its tuning, conforming to `Tunable`:

   ```swift
   extension CarryTuning: Tunable {
       public static var defaults: CarryTuning { .standard }

       public static let parameters: [TuningParameter<CarryTuning>] = [
           .number(\.startDistance, key: "startDistance", title: "Start distance",
                   unit: "pt", range: 0...40, step: 1),
           .number(\.nearestToHead, key: "nearestToHead", title: "Nearest the head",
                   unit: "m", range: 0.1...1, step: 0.01),
       ]
   }
   ```

   Each key is the property's name, which the tuning's initializer takes as
   its label, so Copy tuning's Swift compiles. Each title is a few plain
   words, its unit apart: the panel shows no help text.
2. Its tests in `Tests/GestureCoreTests/<Area>/`, among them
   `#expect(CarryTuning.parameterProblems.isEmpty)`.
3. Its adapters in `Sources/GestureKit/<Area>/`, wrapped in `#if
   os(visionOS)`, each taking the tuning, a `TraceRecorder?`, and closures
   for what happens, tracing a pinch from its touch to its end:

   ```swift
   trace = recorder?.begin("Carry", title: "Pinch on a handle")
   trace?.event("carry", "after 8 pt")
   trace?.finish("carried 0.42 m")
   ```

4. Its automation: the adapter registered through `PinchStandInEar` and
   reporting through `GestureAutomation.heard`, a command in
   `GestureAutomation+Drives` if no existing one drives it, its outcome in
   `AutomationOutcome`, and its checks in `scripts/gesture-selftest.sh`.
5. Its row in `docs/design.md`'s table, and its section in the README: what
   it does, when to use it, its tuning's key values and defaults, and a
   snippet, compiled in `Lab/GestureLab/ReadmeSnippets/`.
6. Its station (below), its feature file in
   `.agents/skills/verify-gesturelab/features/` with a line in that
   folder's README, and the proof: the gates, then every sub-feature driven
   with `verify-gesturelab`.

## Adding a lab station

1. Its files in `Lab/GestureLab/Stations/<Area>/`: a `@MainActor
   @Observable final class` conforming to `LabStation`, with a `TuningStore`
   named "GestureLab.<id>" for each tuning and a
   `TraceRecorder(logsSummariesPublicly: true)`, its space content a
   `RealityView` with attachments around `LabSpace.front`, handing the
   adapters `store.tuning` and the recorder:

   ```swift
   @MainActor @Observable
   final class CarryStation: LabStation {
       let id = "carry"
       let title = "Carry"
       let summary = "A panel carried by its grab handle."
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
3. Its state in `LabAutomation`'s `state(of:)`, so checks can see what its
   gestures did, and its id in the `station` command's help and
   `launch-lab.sh`'s.
4. `scripts/build-check.sh`, then launch it with `launch-lab.sh --station
   <id>`, `targets` to see it registered, and its feature file's recipes.

A gesture that lives in a window, as an item in a scrolling grid does, gets
a window of its own rather than the lab window's scrolling column: give the
station an `ownWindowTitle`, "Grid", and its `ownWindowContent`, as
`Stations/Pluck/` does.

Keep a station's text short: its summary one short sentence saying what the
gesture is, its window content a sentence or two saying what to try, its
buttons and switches a word or two, and its status lines terse, a debug
read-out folded away behind Details. How the gesture works belongs in its
doc comments, `docs/design.md`, and the README, not on screen.

`Stations/TraceCheck/TraceCheckStation.swift` is a whole station to copy
from.
