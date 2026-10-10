# GestureKit

Content-agnostic gestures for Apple Vision Pro, settled on the headset
rather than in the simulator, which can't pinch.

- **Carry**: a grab handle carries a thing 1:1 with the hand, never nearer
  your head than 0.3 m: a clear handle entity with a hover glow, and an
  entity-targeted drag that tells you each step, or moves the entity for
  you.
- **Facing**: a thing turns to face you, standing on a point or hanging
  from one, once or every frame as you move, with world tracking for where
  your head is.
- **Placement**: a panel opens below your gaze, tilted up to you, and stays
  put until you carry it by the pill under it.
- **Pluck**: pull an item out of a scrolling grid into the room. A pinch
  is a scroll unless it's a hold: one that moves the grid at all, or moves
  a little along its scroll, scrolls; held still a quarter second, the item
  lifts and the scroll stops, until your hand moves along the scroll, which
  gives the pinch back to it; lifted, it follows your hand a little, held,
  until you've gone about 2.5 cm any other way, when it breaks free into
  the room at your hand and the item settles back into the grid. Nothing
  on the item competes with the scroll before the lift: its drag is held
  back until then, or the lifted pinch is followed by your hand through
  hand tracking, as tuned. However a pinch's words come, or don't, the
  grid's scroll is never held for long past it: a safety net lets it go.
  From there the same pinch carries it by Carry's own rules. Mark the
  scroll view `pluckContainer` and each item `pluckable`, and act on what
  each reports: its tap, its lift, where it spawns, and each step of its
  carry, which `CarriedEntity.stand` stands for you.
- **Lift**: a view lifted off what it lies on, scaled up and brought toward
  you on a spring, over its shadow, and drawn a little way along as a pinch
  tugs it.
- **HandPinch**: a hand's pinch from hand tracking's fingertips, and the
  hand a press came from; `PinchTracker` follows a pinching hand, as a
  pluckable item can follow its lifted pinch.
- **Press**: one pinch on a surface, told as a tap, a drag along or across,
  a pickup and carry, or a hold. Held still, what you pinched lifts toward
  you, and a move then carries it.
- **Coast**: a scroll let go on the move coasts on, slowing, and a pinch
  catches it.
- **Hold watch**: a still hold on a handle or control, beside its own drag
  and tap, never in front of them.

Work in progress: some of these are still on their way in, in the order
`docs/design.md` gives.

## Two libraries

- `GestureCore`: each gesture's rules and math, plain Swift for macOS 14+
  and visionOS 26, tested on the Mac. Each takes a tuning, a struct of the
  numbers it goes by, with defaults.
- `GestureKit`: the visionOS side, components, systems, and view
  modifiers that work on any RealityKit entity or SwiftUI view, reporting
  what happens through closures, so your app keeps its own state. It
  re-exports `GestureCore`.

## Adding the package

In `Package.swift`:

```swift
.package(url: "https://github.com/alxrod/GestureKit.git", branch: "main"),
```

and `.product(name: "GestureKit", package: "GestureKit")` in your visionOS
target's dependencies, or `GestureCore` alone for the rules. In Xcode, add
the package by its URL.

## GestureLab

`Lab/` holds GestureLab, a visionOS app with a station for each gesture: a
window listing them, and an immersive space where the chosen one stands.
Beside each, a live trace shows every interaction as a timeline, a drag's
run of words folded into one line, and a tuning panel changes its numbers as
you try it; Copy tuning puts them on the pasteboard as Swift, ready to become
the defaults. A switch in the window's toolbar turns tracing off for the
whole lab, and one in each trace for its station, to feel the gestures with
no trace at all.

To run it:

1. Copy `Local.xcconfig.example` to `Local.xcconfig` and set
   `DEVELOPMENT_TEAM` to your team.
2. Open `Lab/GestureLab.xcodeproj`.
3. Run the GestureLab scheme on your Vision Pro, or on the simulator, where
   a click is a pinch.

## Developing

`swift test` runs the core's tests on the Mac; `scripts/build-check.sh`
compile-checks the lab and GestureKit's visionOS side. `AGENTS.md` has the
layout and conventions, and how to add a gesture or a lab station.

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
- `scripts/gesture-drive.sh up` keeps a simulator of its own, builds the
  lab and the driver, and launches the lab with automation on.
- `scripts/gesture-drive.sh <command>` runs any of the driver's commands
  against it.
- `scripts/gesture-selftest.sh` drives every gesture in a fresh simulator,
  checks each outcome, and exits non-zero at the first failure.

## License

MIT; see `LICENSE`.
