---
name: verify-gesturelab
description: Launch GestureLab, GestureKit's visionOS lab app, in a visionOS simulator of the run's own, and prove a gesture works by driving it through gesturekit-drive, GestureKit's no-hand automation, keeping the JSON answer, trace, screenshot, and app state as evidence. Use after changing a gesture's rules in GestureCore, an adapter in GestureKit, the automation, or a lab station, before calling the change done; or to reproduce a gesture bug in the simulator.
---

# Verify GestureLab

GestureLab (`Lab/`) has a station for each gesture. The simulator can't
pinch, so GestureKit's automation drives each adapter as a hand's gestures
would, through `gesturekit-drive`, and answers in JSON. This skill launches
the lab in a simulator the run makes, checks that it's the run's own and
current, drives a feature from the map in [`features/`](features/README.md),
keeps the evidence in `artifacts/verify-gesturelab/<run>/`, and deletes
everything the run made but the evidence.

Run every command from the repository's root. `$V` stands for
`.agents/skills/verify-gestures/scripts/gesture-verify.sh`, the shared
helper, and `RUN_DIR` for the folder the launch prints, as
`artifacts/verify-gesturelab/20261010-164500`. Each shell is fresh, so name
`RUN_DIR` in every command rather than relying on exported variables.

## Launch

```sh
<your build lock> .agents/skills/verify-gesturelab/scripts/launch-lab.sh --station pluck
```

It builds the lab and `gesturekit-drive`, so wrap it in the build lock your
coordinator names, if any; it takes about three minutes, most of it the
build. It:

1. picks the run's name, the time unless `--run NAME`, and a free port from
   48800;
2. makes the simulator `GestureLab-Verify-<run>`, refusing a name that
   exists;
3. writes `RUN_DIR/run.env`: the simulator's name and UDID, the port, the
   build folder `build/verify-gesturelab/<run>/`, the driver, and the
   commit and digest of `Sources`, `Lab`, and `Package.swift` it builds
   from;
4. runs `scripts/gesture-drive.sh up --station pluck` with that
   environment, logging to `RUN_DIR/launch.log`.

By hand, the same launch is:

```sh
GESTURE_SIM=GestureLab-Verify-<run> GESTUREKIT_AUTOMATION_PORT=<port> \
  GESTURE_DRIVE_WORK=build/verify-gesturelab/<run> \
  scripts/gesture-drive.sh up --station pluck
```

It's ready when it prints `net.alexbrodriguez.gesturelab is ready on
127.0.0.1:<port>`, then `RUN_DIR` as its last line. `--station` takes
`trace-check`, `carry-and-face`, `below-the-gaze`, `press`, or `pluck`; the
`station` command switches later. Should the launch fail, read
`RUN_DIR/launch.log` and `build/verify-gesturelab/<run>/build.log`, then
clean up with `$V down RUN_DIR`.

Teardown is `$V down RUN_DIR`; see Cleanup.

## Doctor

```sh
$V doctor RUN_DIR
```

Read-only. It passes only when:

- the run's simulator, by its UDID and name, is booted;
- GestureLab runs in it;
- the automation's port is listened on by that very process, so no other
  agent's lab answers you;
- the installed app is the run's build;
- `Sources`, `Lab`, and `Package.swift` are as they were built, so you're
  not driving a build from before your change;
- the automation answers `state` ready on the run's port.

It ends with `doctor: this run is ours, … and worth driving`, and the lab's
state, as `{"lab":{"pluck":{"cards":0,…},"station":"pluck",…}}`. Run it
before the first drive and after any drive that surprised you. If the
checkout changed since the build, launch a new run; a relaunch doesn't
rebuild.

## Drive

Through the helper, which keeps the evidence (below):

```sh
$V capture RUN_DIR <label> --expect '<jq filter>' <command> [args…]
```

Or plainly, printing the app's answer:

```sh
$V drive RUN_DIR <command> [args…] [--json|--brief]
```

`$V drive RUN_DIR` runs `scripts/gesture-drive.sh` with the run's
environment; by hand that's `set -a; . RUN_DIR/run.env; set +a;
scripts/gesture-drive.sh <command> …`.

The commands, as GestureLab names its targets:

- `targets` lists what's drivable now: the grid and the items it has made
  (`item 1`…), the surface `surface`, the tab `tab`, the grab handles
  (`panel-a`, `panel-b`, `panel-c`, `gaze-panel`, and each card's, by its
  UUID), and the panel `gaze-panel`.
- `station <id>` chooses a station, as the window's list does, and waits
  for it to settle.
- `pluck "item 6" [hold=S] [pull=x,y,z] [pullTime=S] [carry=x,y,z]
  [carryTime=S]`, and `tap "item 2"` or `tap 2`.
- `scroll [by=600 | to=top | to=end | to="item 41"] [on="item 3"]`.
- `carry panel-b by=0.1,0,0.2` or `carry panel-a to=0,1.6,-0.1`.
- `place [gaze-panel] [head=untracked | 'head={"at":[0,1.6,0],"yaw":30,"pitch":-40}']`.
- `tap surface at=0.4`, `drag surface along=0.2 [across=0.1]`, `flick
  surface along=-0.15`, `pickup surface by=0.1,0.05,0.05`, `hold surface`.
- `hold tab [seconds=0.2] [moveFirst=0.02,0,0]`.
- `tune press key=pickUpDelay value=0.3`, `tune press reset=true`.
- `trace [gesture=Pluck] [clear=true]`, `wait`, `state`, `smoke`.
- `screenshot FILE.png`.
- `relaunch --station ID` relaunches the installed build.
- `launch net.alexbrodriguez.gesturelab -- -station pluck -labLoad stuck`
  relaunches it with the lab's own arguments, as `-labTracing off`.

Vectors are a hand's move in meters, x right, y up, z toward you, at 1,360
of an adapter's points to the meter. `--json` prints the whole answer and
`--brief` its outcome and result. Each feature file says what to drive and
which fields prove it.

## Evidence

`$V capture` writes, in `RUN_DIR`:

| File | What it holds |
| --- | --- |
| `<label>.json` | the whole answer: `ok`, `command`, `outcome`, `result`, `events` (what the adapters reported, folded), `trace` (each interaction traced meanwhile), `app` (the lab's state), `elapsed` |
| `<label>.trace.txt` | each traced interaction's summary line |
| `<label>.check.txt` | the `--expect` filter and its verdict, PASS or FAIL |
| `<label>.state.json` | everything registered after the command: targets, tunings, busy, the lab's state |
| `<label>.png` | what the simulator shows after it |
| `<label>.console.txt` | GestureKit's info lines meanwhile, from the simulator's log |
| `<label>.check.txt`, from `$V check` | a second filter's verdict on an earlier capture's answer |
| `captures.txt` | one line per capture or check: time, label, ok, outcome, verdict, command |

Beside them, `run.env` and `launch.log`. `artifacts/` is gitignored, and
cleanup never touches it.

The proof standards, for gestures:

- **Write the check first.** The `--expect` filter comes from the feature
  file before you drive, and names the outcome and the numbers that prove
  it. A filter loosened until it passes proves nothing.
- **The JSON proves, the screenshot identifies.** The outcome and its
  numbers come from `outcome`, `result`, `events`, and `app`, never from
  reading the screen. The screenshot shows which app, which station, and
  how it looked; the PNG alone proves no gesture.
- **The action and the state it left.** Keep the answer, which carries the
  adapters' events and the trace, and `state` after it. A gesture whose app
  state didn't change, a card not added, a playhead not moved, isn't proven
  by its outcome word alone.
- **Side effects too.** After a pluck, the grid's scroll is on again and no
  alarm was raised (`result.grid.scrollIsHeldOff == false`,
  `result.grid.alarms == 0`); a tuning shows in `state`'s `tunings`; a
  carried thing stands where `result.stood` says.
- **The real path.** Drive the gesture command, which speaks through the
  adapter's own stand-in, never an app's model; `tune` is the slider's own
  call, and `station` the window list's.
- **Numbers, not times.** Assert outcomes, distances, and counts. `elapsed`
  and event times swing with a loaded machine; assert a time only as the
  trace's own words for its tuning, as "picks up at 0.3 s".

Report each sub-feature driven with its ID, its capture label, the filter,
and the verdict, then what the automation stood in for (below). Report a
path you couldn't reach with the command tried and the precondition unmet,
and never report a sub-feature as verified through another's path.

## Cleanup

```sh
$V down RUN_DIR
ls RUN_DIR
```

`down` quits the lab and deletes the run's simulator, only when its UDID
and name match `run.env` and the name is `GestureLab-Verify-<run>`, then
unregisters and deletes `build/verify-gesturelab/<run>/`. It keeps
`RUN_DIR` and lists it; `ls` confirms the evidence survived. Run it after a
failed launch too.

Never:

- touch a simulator the run didn't make: not the booted `VCAD-CI`, nor
  another agent's `GestureLab-Auto` or `GestureLab-Selftest`;
- run `scripts/gesture-drive.sh down` with `GESTURE_SIM` naming a
  simulator you didn't make, since it deletes whatever simulator has that
  name;
- `xcrun simctl shutdown all`, `erase all`, or `delete all`;
- kill anything by its process name.

## Helpers

- `.agents/skills/verify-gesturelab/scripts/launch-lab.sh [--station ID]
  [--run NAME]`: the launch above. Prints `RUN_DIR`.
- `$V doctor RUN_DIR`, `$V capture RUN_DIR LABEL [--expect JQ] COMMAND
  [ARGS…]`, `$V check RUN_DIR LABEL CAPTURED_LABEL JQ` (a second filter on
  a capture's answer, for another sub-feature the same drive proves),
  `$V drive RUN_DIR COMMAND [ARGS…]`, and `$V down RUN_DIR`: the shared
  helper of the `verify-gestures` skill, which apps on GestureKit use too.
  `$V help` prints its usage.
- For the whole sweep, `scripts/gesture-selftest.sh` drives every station
  in a fresh simulator and exits non-zero at the first failure. Give it a
  name and port of the run's own, as it deletes any simulator of its name
  as it starts: `GESTURE_SIM=GestureLab-Selftest-<run>
  GESTUREKIT_AUTOMATION_PORT=<free port> GESTURE_DRIVE_WORK=build/gesture-selftest-<run>
  scripts/gesture-selftest.sh`, through your build lock.

## What the automation stands in for

A passing recipe proves the adapters and GestureCore's rules, not the
system's gesture recognizers or the feel. Per command:

| Command | Runs for real | Stands in for, so the headset must say |
| --- | --- | --- |
| `pluck`, `tap` on an item | `PluckItemDriver` and its rules on the real clock; the container, its watch and alarms, and `.scrollDisabled` given to the real scroll view; where what breaks free spawns; the hand-off to `CarryPinch`; the trace; the app's closures | The button's press and the item's `DragGesture`, whose words the stand-in says, kept back as their start would keep them; whether SwiftUI lets a drag in mid-pinch; hand tracking |
| `scroll` | The content moving, the lazy grid making items, `onScrollGeometryChange`, the container's offset and phase rules, and a pinch on an item hearing them | UIKit's pan, whose phases are said for it, and whether it takes a pinch given back to it; deceleration |
| `carry` | `GrabHandleCarry`: `CarryPinch`'s start, `HandCarry`'s clamp, `Facing`, `CarriedEntity.stand`, the trace, the app's closures | RealityKit's hit test of the handle, and the entity-targeted drag's conversion from the gesture's space; the move is given in the parent's frame |
| `place` | `GazePanel.stand`, `GazePlacement`, the trace | World tracking's head: the simulator's untracked head, or one given. The app's own placement code doesn't run |
| `tap`, `drag`, `flick`, `pickup`, `hold` on a surface | `SurfacePressModifier`: `SurfacePress` and its clock, the pickup and hold timing, `HoldLift`'s lift drawn, the trace, the app's coast | Its two drags, touched where told, the hand moving from the space's origin; the two-handed magnify |
| `hold` on a tab | `HoldWatchModifier`: `HoldWatch`, its timer, `isHeld` and its grace, `onHeldStill`, the trace | Its watch's drag; the control's own drag and tap, which never move |
| `tune` | `TuningStore.set`, fitted to its range and step, and saved | The slider |

What only a person on a headset can prove: the real UIKit pan taking or
missing a pinch; RealityKit's hit testing; hand and head tracking; and the
feel, the numbers a tuning settles on, the lift, the springs, the coast.
Say so in the report, and leave those to Alex on the headset.

## Feature map

[`features/README.md`](features/README.md) indexes the features, with the
baseline every recipe starts from and how the map is kept honest:

- [Pluck](features/pluck.md)
- [Scroll first](features/scroll-first.md)
- [Carry](features/carry.md)
- [Below the gaze](features/below-the-gaze.md)
- [Surface press](features/surface-press.md)
- [Hold watch](features/hold-watch.md)
- [Tuning](features/tuning.md)
- [Tracing and alarms](features/tracing-and-alarms.md)

A change to a gesture is verified by driving every sub-feature its feature
file lists, not one convenient entry point.
