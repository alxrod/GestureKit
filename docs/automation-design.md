# Driving the gestures without a hand

## Why

The simulator can't pinch, so until now only Alex on the headset could say
whether a gesture worked. Alex asked for this on October 10:

> "we need modes so that agents can drive the gestures without complex
> pinch and drag logics for all the supported gestures"

And then:

> "automation for agents needs to be inherited and accessible for adopters
> of GestureKit"

So driving the gestures is a feature of GestureKit, not of its lab. Every app
on GestureKit can be driven in a simulator by an agent, with no code of its
own.

## The shape

An agent sends one command at the gesture's level, such as "pluck item 7",
and the app answers in JSON with what happened. In between, the command says
the words a hand's gestures would say, at a hand's pace, through the hand's
stand-in (`PinchStandIn`). So each adapter's own logic runs as it would with
a hand, and GestureCore's rules run beneath it. Nothing calls an app's model
directly: the app hears what the adapter tells it, as it would from a hand.

It exists only in debug builds. A release build compiles none of it, and
`scripts/build-check.sh release` checks that the built app carries none of
its symbols or strings. The API is public under `#if DEBUG`; the stand-in
underneath stays behind its SPI.

- **GestureCore**, `Automation/`, under `#if DEBUG`: the values that need
  no platform, tested with `swift test`.
  - A JSON value (`AutomationJSON`).
  - Lenient readers for a command's arguments (`AutomationArguments`): a
    vector as "0,0,0.05" or `[0, 0, 0.05]`, a switch as "true".
  - The HTTP the server speaks (`AutomationHTTP`).
  - The steps of a hand's move (`AutomationPath`).
  - What the adapters reported, folded, and each gesture's outcome told
    from it (`AutomationEventLog`, `AutomationOutcome`).
- **GestureKit**, `Automation/`, on visionOS under `#if DEBUG`:
  `GestureAutomation`, which holds what's registered, the commands, the
  server, and the script runner. Each adapter's ear for the stand-in knows
  its id, whether a pinch is under way on it, what it goes by, and the
  trace it writes to.
- **gesturekit-drive**, a SwiftPM executable product, a Mac tool: launches
  an app in a simulator with automation on, and sends it commands.

## Inherited by default

Each adapter registers what it drives as its view appears, under the ids
its app already gives it, and goes as its view does.

| What | Registered by | Driven by |
| --- | --- | --- |
| A pluckable item | `.pluckable(id, title:)` | its title, "item 7", or its id as text, "7" |
| A pluckable grid | `.pluckContainer(…, automationID:)` | its `automationID`, "grid" unless given |
| A surface | `.surfacePress(…, automationID:)` | its `automationID`, else its trace title |
| A control watched for a hold | `.holdWatch(…, automationID:)` | its `automationID`, else its trace title |
| A grab handle | `GrabHandle.make`, and so `PanelHandleRig` | its `GrabHandleComponent`'s carried id, else its entity's name, while it's in a scene |
| A panel placed below the gaze | `GazePanel.stand` | its entity's name, re-stood with the tuning and trace it was last stood with |
| A tuning | `TuningStore` | its namespace, or a unique end of it after a dot |
| A trace | each adapter's `TraceRecorder` | every answer carries the interactions recorded during its command |

An app may add commands of its own (`register(command:takes:help:_:)`), its
own state (`register(state:_:)`), and what keeps it busy
(`register(busy:_:)`). GestureLab adds a `station` command, its stations'
facts, and the press's coast. That's the whole of its automation code, and
any adopter could write the same.

## One switch

Automation is off until asked for, in one of three ways:

- The launch: `-GestureKitAutomation YES`.
- The environment: `GESTUREKIT_AUTOMATION=1`. A simulator's launch passes
  it as `SIMCTL_CHILD_GESTUREKIT_AUTOMATION=1`, which `gesturekit-drive
  launch` does.
- A call: `GestureAutomation.start()`.

GestureKit reads the switch itself, as its first adapter appears or its
first handle, panel, or tuning store is made. An app that shows none of them
at launch can call `start()`.

Once on, it serves HTTP on 127.0.0.1 only, which a visionOS simulator shares
with its Mac. The port is 48765 unless `-GestureKitAutomationPort` or
`GESTUREKIT_AUTOMATION_PORT` says otherwise:

- `POST /` with a command's JSON.
- `GET /targets`, `GET /state`, `GET /help`.

Commands run one at a time, in order. A script is the other transport:
`-GestureKitAutomationScript <file>`, or `GESTUREKIT_AUTOMATION_SCRIPT`,
runs a JSON list of commands once the app has settled. "Settled" means
something is registered, and nothing has registered or gone for 0.7 s. The
results are written beside the file as `<file>.results.json`.

## The commands

Vectors are a hand's move in meters: x right, y up, z toward the viewer, at
1,360 of an adapter's points to the meter, as visionOS draws a view in a
space. Times are in seconds. Every command takes `target` for what it's on.

Each gesture command answers with these fields:

- `ok`
- `command`
- `outcome`
- `result`
- `events`: what the adapters reported, a run of one kind folded into a line
- `trace`: each interaction recorded meanwhile, with its summary
- `app`: the app's registered state
- `elapsed`

A failure answers `"ok": false` and an `"error"` in a sentence that says
what to do.

| Command | Arguments and defaults | What it says, and through what | Outcome |
| --- | --- | --- | --- |
| `pluck` | `item`; `hold`: its hold + 0.1; `pull`: [0, 0, 0.05]; `pullTime`: 0.4; `carry`: [0, 0, 0]; `carryTime`: 0.4 | The item's press, held, waiting to see the lift. Its drag, only once past the drag's start for the stage it's in, held back or brought down as `liftedTracking` sets it. Then the drag's end and reset, the press's end, and the tap. | `spawned`, `lifted`, `stayed down`, `tapped`, or `nothing` |
| `tap` | `item`, or `surface` with `at`: 0.1 m along | The item's press and tap; the surface's two drags, touched and let go. | `tapped`, `tap` |
| `scroll` | `grid`; `by`: 400 pt, or `to`: "top", "end", points, or an item; `on`: an item; `time`: 0.5 | The scroll view's phases. Its content moved through SwiftUI's `ScrollPosition`. The item's press, cancelled as a pan would cancel it. | `scrolled` |
| `carry` | `handle`; `by`: [0.1, 0, 0], or `to` in the carried thing's parent's frame; `time`: 0.6 | The handle's entity-targeted drag's words, taken only by a carry whose marker the handle has. | `carried`, `nothing`, `under nothing`, `refused` |
| `place` | `panel`; `head`: "tracker", "untracked", or `{"at", "yaw", "pitch"}` in degrees | `GazePanel.stand` itself, for that head. | `placed` |
| `drag` | `surface`; `along`: 0.3; `across`: 0; `at`; `time`: 0.6 | The surface's two drags, coming to rest for 0.2 s before letting go. | `scroll`, `drag along`, `drag across` |
| `flick` | `surface`; `along`: 0.25; `time`: 0.12 | The same, let go on the move. | `scroll` |
| `pickup` | `surface`; `by`: [0.1, 0.05, 0.05]; `at`; `time`: 0.5 | Held still past the pickup, then moved. | `carry`, `pickup, put down` |
| `hold` | `surface` or `tab`; `seconds`: its hold + 0.2; `waver`: 1.5 pt; `moveFirst` | Held still, wavering, then let go. | `hold`, `the control's`, `let go before its hold` |
| `tune` | `tuning`; `key` and `value`, or `reset` true | `TuningStore.set`, as the panel's slider calls it. | `tuned` |
| `smoke` | | Every target on screen once, with its default command: each grid scrolled and back, its first item plucked, each surface tapped, each tab held, each handle carried up 5 cm and back, each panel placed. | `passed`, `failed`, `nothing to drive` |
| `targets`, `state`, `help`, `trace`, `wait` | | What's drivable; everything registered; the commands; the traces, read and cleared; waiting until nothing is under way. | |

## What's real, and what's stood in

| Command | Runs for real | Stands in for, or skips |
| --- | --- | --- |
| `pluck`, and `tap` on an item | <ul><li>`PluckItemDriver` and the rules (`PluckPinches`, `PluckPress`), with their counts on the real clock</li><li>The container, its watch and alarms, and `.scrollDisabled` given to the real scroll view</li><li>The item's geometry into the space, for where what it pulls out spawns</li><li>The hand-off to `CarryPinch`, the trace, and the app's `perform`</li></ul> | <ul><li>The button's press, and the item's `DragGesture`, whose words come from the stand-in, kept back as its start would keep them. Whether SwiftUI lets a drag in mid-pinch is still the headset's to say.</li><li>Hand tracking</li></ul> |
| `scroll` | <ul><li>The scroll view's content moving, and the lazy grid making its items</li><li>`onScrollGeometryChange`, the container's offset and phase rules, and the pinch on an item hearing them</li></ul> | <ul><li>UIKit's pan: its phases are said as it would say them</li><li>Deceleration</li></ul> |
| `carry` | `GrabHandleCarry`: `CarryPinch`'s start distance, `HandCarry`'s clamp, `Facing`, `CarriedEntity.stand`, the trace, and the app's closures | The entity-targeted drag: its hit test, and its conversion from the gesture's space (the move is given in the parent's frame) |
| `place` | `GazePanel.stand`, `GazePlacement`, and the trace | The head, which world tracking can't give in the simulator: the untracked head, or one given. The app isn't told; its own placement code doesn't run. |
| `drag`, `flick`, `pickup`, `hold` on a surface | `SurfacePressModifier`: `SurfacePress`, its clock, the pickup and hold timing, `HoldLift`'s lift drawn, the trace, and the app's coast | <ul><li>Its two drags, touched where told, with the hand moving from the space's origin</li><li>The two-handed magnify</li></ul> |
| `hold` on a tab | `HoldWatchModifier`: `HoldWatch`, its timer, `isHeld` and its grace, `onHeldStill`, and the trace | <ul><li>Its watch's drag</li><li>The control's own drag and tap, which are the app's and never move</li></ul> |
| `tune` | `TuningStore.set`, fitted to its range and step, and saved | The slider |

## The driver

`gesturekit-drive` is a product of the package, so an app's repository runs
it with `swift run gesturekit-drive`. It reaches the app on its port, and the
simulator through `xcrun simctl`, the booted one unless `--device` or
`GESTUREKIT_SIMULATOR` says otherwise.

    swift run gesturekit-drive launch com.example.app
    swift run gesturekit-drive targets
    swift run gesturekit-drive smoke
    swift run gesturekit-drive pluck "item 7" pull=0,0,0.06
    swift run gesturekit-drive trace
    swift run gesturekit-drive screenshot

Here's what each prints:

- A gesture command prints the app's whole answer; `--brief` prints only
  its outcome and result.
- `targets` and `smoke` print tables; `--json` prints their answers.
- A failure exits 1.
- `launch --script FILE` runs FILE's commands as the app settles, and prints
  their results.

For GestureLab, `scripts/gesture-drive.sh` keeps a simulator of its own,
"GestureLab-Auto", and builds the lab and the driver into
`build/gesture-drive/`, never Xcode's DerivedData. It hands everything else
to the driver. `scripts/gesture-selftest.sh` drives every gesture in a fresh
simulator, checks each outcome with `jq`, runs the smoke on every station and
a script at launch, and exits non-zero at the first failure.
