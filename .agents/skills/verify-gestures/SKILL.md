---
name: verify-gestures
description: Prove the gestures of a visionOS app built on GestureKit work, in a visionOS simulator of the run's own, by driving them through gesturekit-drive, GestureKit's no-hand automation, and keeping the JSON answer, trace, screenshot, and app state as evidence. Use after changing anything an item, grid, surface, tab, grab handle, panel, or tuning on GestureKit touches, before calling the change done; or to reproduce a gesture bug without a headset.
---

# Verify gestures on GestureKit

GestureKit's adapters, in a debug build, register what they drive as their
views appear: pluckable items and grids, surfaces with a press, tabs
watched for a hold, grab handles, panels stood below the gaze, and tuning
stores. With the automation on, `gesturekit-drive`, a Mac tool shipped with
the package, drives each one as a hand's gestures would, through the real
adapter and GestureCore's rules, and the app answers in JSON with the
outcome, what the adapters reported, the traces, and the app's own state.
This skill launches your app in a simulator the run makes, checks that it's
the run's own and current, drives it, keeps the evidence in
`artifacts/verify-gestures/<run>/`, and deletes everything the run made but
the evidence.

Run every command from your repository's root. `$V` stands for
`.agents/skills/verify-gestures/scripts/gesture-verify.sh`, this skill's
helper (wherever `gesturekit-drive install-skill` put the skill), and
`RUN_DIR` for the folder the launch prints. Each shell is fresh, so name
`RUN_DIR` in every command.

## Turning the automation on

There's no code to write. A debug build serves the automation when it's
launched with `-GestureKitAutomation YES`, or `GESTUREKIT_AUTOMATION=1` in
its environment, on 127.0.0.1:48765 unless `-GestureKitAutomationPort` or
`GESTUREKIT_AUTOMATION_PORT` says otherwise; the simulator shares the
Mac's 127.0.0.1. `gesturekit-drive launch <bundle-id>` turns it on for you
(`SIMCTL_CHILD_GESTUREKIT_AUTOMATION=1`). An app that shows no GestureKit
adapter, handle, panel, or tuning store at launch calls
`GestureAutomation.start()` in a debug build. A release build compiles none
of it.

## Launch

```sh
<your build lock> $V up --scheme MyApp --project MyApp.xcodeproj --bundle-id com.example.myapp -- <app arguments>
```

Use `--workspace MyApp.xcworkspace` for a workspace. It:

1. picks the run's name, the time unless `--run NAME`, and a free port from
   48800 unless `--port`;
2. makes the simulator `GestureKit-Verify-<run>` on the newest visionOS
   runtime, refusing a name that exists;
3. writes `RUN_DIR/run.env`, `RUN_DIR` being
   `artifacts/verify-gestures/<run>` (`GESTURE_EVIDENCE_ROOT` changes
   `artifacts/verify-gestures`): the simulator's name and UDID, the port, the
   bundle id, the commit and a digest of the checkout's changes;
4. builds the scheme's Debug build for that simulator into a throwaway
   DerivedData, `$TMPDIR/gesture-verify/<run>/DerivedData`, with signing
   off, never Xcode's own DerivedData, and installs it;
5. builds `gesturekit-drive` from GestureKit's checkout, which Xcode
   resolved into that DerivedData's `SourcePackages/checkouts/GestureKit`,
   into `$TMPDIR/gesture-verify/<run>/driver`; for GestureKit as a local
   package, give its folder with `--gesturekit <path>`;
6. launches the app with the automation on, through `gesturekit-drive
   launch`, and waits until it's ready.

It's ready when it prints `<bundle-id> is ready on 127.0.0.1:<port>`, then
`RUN_DIR` as its last line. It builds, so wrap it in your build lock if
agents share the machine. Should it fail, read `RUN_DIR/launch.log` and
`$TMPDIR/gesture-verify/<run>/build.log`, then run `$V down RUN_DIR`.

By hand, the same launch is:

```sh
udid=$(xcrun simctl create GestureKit-Verify-<run> "Apple Vision Pro" <visionOS runtime>)
xcrun simctl boot "$udid"
xcodebuild -project MyApp.xcodeproj -scheme MyApp -configuration Debug \
  -destination "platform=visionOS Simulator,id=$udid" \
  -derivedDataPath "$TMPDIR/gesture-verify/<run>/DerivedData" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$udid" "$TMPDIR/gesture-verify/<run>/DerivedData/Build/Products/Debug-xrsimulator/MyApp.app"
swift run --package-path "$TMPDIR/gesture-verify/<run>/DerivedData/SourcePackages/checkouts/GestureKit" \
  --scratch-path "$TMPDIR/gesture-verify/<run>/driver" \
  gesturekit-drive --device "$udid" --port <port> launch com.example.myapp
```

From a Swift package that depends on GestureKit, `swift run
gesturekit-drive …` runs the driver from your own checkout, GestureKit's
in `.build/checkouts/GestureKit`. Elsewhere, clone GestureKit at the
revision your `Package.resolved` pins and give `--package-path` that
clone. Keep `--scratch-path` out of the checkout, so it stays as resolved.

## Doctor

```sh
$V doctor RUN_DIR
```

Read-only. It passes only when the run's simulator, by UDID and name, is
booted; the app runs in it; the automation's port is listened on by that
very process, so no other agent's app answers you; the installed app is the
run's build; the checkout is as it was built; and the automation answers
`state` ready on the run's port. It ends with `doctor: this run is ours, …
and worth driving`, the targets it counts, and your app's registered state.
Run it before the first drive and after any drive that surprised you; if
the checkout changed since the build, launch a new run.

By hand: `xcrun simctl spawn <udid> launchctl list | grep <bundle-id>`
gives the app's pid, `lsof -nP -iTCP:<port> -sTCP:LISTEN` must show that
pid, and `gesturekit-drive --port <port> state` must answer `"ready": true`
and `"port": <port>`.

## Drive

```sh
$V capture RUN_DIR <label> --expect '<jq filter>' <command> [args…]   # with evidence
$V drive RUN_DIR <command> [args…] [--json|--brief]                     # plainly
```

`$V drive` runs the run's `gesturekit-drive` with its simulator and port
(`GESTUREKIT_SIMULATOR` and `GESTUREKIT_AUTOMATION_PORT` from `run.env`).

1. **See what's there.** `$V drive RUN_DIR targets` lists every target by
   kind and id, with its default command; `--json` gives each one's facts.
2. **Smoke it.** `$V capture RUN_DIR smoke --expect '.ok and .result.failed
   == 0' smoke` drives each target once with its default command: each grid
   scrolled and back, its first item plucked, each surface tapped, each tab
   held, each handle carried up 5 cm and back, each panel placed.
3. **Drive each kind of target.** Targets go by the names your app gives:

| Target | Named by | Commands | Outcomes |
| --- | --- | --- | --- |
| A pluckable item | its title, or its id | `pluck "item 7" [hold=S] [pull=x,y,z] [carry=x,y,z]`, `tap "item 7"` | `spawned`, `lifted`, `stayed down`, `tapped`, `nothing` |
| A pluckable grid | its `automationID`, `grid` unless given | `scroll [grid] by=600`, `to=top`, `to=end`, `to="item 41"`, `on="item 3"` | `scrolled` |
| A surface | its `automationID`, else its trace title | `tap surface at=0.4`, `drag surface along=0.3 [across=0.1]`, `flick surface along=0.25`, `pickup surface by=0.1,0.05,0.05`, `hold surface` | `tap`, `scroll`, `catch`, `drag along`, `drag across`, `carry`, `pickup, put down`, `hold` |
| A tab watched for a hold | its `automationID`, else its trace title | `hold tab [seconds=S] [moveFirst=x,y,z]` | `hold`, `the control's`, `let go before its hold` |
| A grab handle | what it carries, else its entity's name | `carry panel by=0.1,0,0`, `carry panel to=x,y,z` | `carried`, `nothing`, `under nothing`, `refused` |
| A panel below the gaze | its entity's name | `place [panel] [head=untracked]`, `head={"at":[0,1.6,0],"yaw":30,"pitch":-40}` | `placed` |
| A tuning store | its namespace, or a unique end of it | `tune store key=K value=V`, `tune store reset=true` | `tuned` |

   Vectors are a hand's move in meters, x right, y up, z toward you, at
   1,360 of an adapter's points to the meter; times are seconds; a value
   starting `{` or `[` is JSON. `$V drive RUN_DIR help` lists the commands,
   and `commands` your app's own among them.
4. **Read and wait.** `trace [gesture=Pluck] [clear=true]` reads the traces;
   `wait` waits until nothing is under way; `state` gives everything
   registered and your app's state; `screenshot FILE.png` what the
   simulator shows.

Each gesture command answers `ok`, `command`, `outcome`, `result`,
`events` (what the adapters reported, a run of one kind folded into a
line), `trace` (each interaction traced meanwhile), `app` (the state your
app registered), and `elapsed`; a failure answers `"ok": false` and an
`error` saying what to do. `gesturekit-drive` exits 1 when a command fails.

Make your app's own state part of every answer, so a check can see what
the gesture did to it:

```swift
#if DEBUG
GestureAutomation.shared.register(state: "editor") { ["items": .number(Double(items.count))] }
#endif
```

`register(command:takes:help:_:)` adds a command, as GestureLab's `station`,
and `register(busy:_:)` something `wait` waits for, as a coast.

## Evidence

`$V capture` writes, in `RUN_DIR`: `<label>.json`, the whole answer;
`<label>.trace.txt`, each traced interaction's summary; `<label>.check.txt`,
the filter and its verdict, PASS or FAIL; `<label>.state.json`, everything
registered after; `<label>.png`, what the simulator shows after;
`<label>.console.txt`, GestureKit's info lines meanwhile (set
`GESTURE_LOG_PREDICATE` in `run.env` to add your app's subsystem); and a
line in `captures.txt`. With a filter, the verdict decides its exit, so a
refusal you expect passes. Add `/artifacts` to your `.gitignore`.

The proof standards, for gestures:

- **Write the check first**, from your feature map, naming the outcome
  and the numbers that prove it. A filter loosened until it passes proves
  nothing.
- **The JSON proves, the screenshot identifies.** Outcomes and numbers come
  from `outcome`, `result`, `events`, and `app`; the screenshot shows which
  app and screen, and how it looked.
- **The action and the state it left**: the answer, and `state` after; a
  gesture that changed nothing in your app's state isn't proven by its
  outcome word.
- **The real path**: drive gesture commands, which speak through each
  adapter's own stand-in; never set your model directly to make a check
  pass.
- **Numbers, not times**: assert outcomes, distances, and counts; times
  swing with a loaded machine.

Report each check with its label, filter, and verdict, then what the
automation stood in for, and what's left to a person on a headset.

## Cleanup

```sh
$V down RUN_DIR
ls RUN_DIR
```

`down` quits the app and deletes the run's simulator, only when its UDID and
name match `run.env` and the name is `GestureKit-Verify-<run>`, then
unregisters and deletes the run's build folder. It keeps `RUN_DIR` and lists
it. Run it after a failed launch too. Never touch a simulator the run didn't
make, as a booted CI simulator or another agent's; never `xcrun simctl
shutdown all`, `erase all`, or `delete all`; never kill by process name.

## Helpers

`$V help` prints the helper's usage: `up`, `doctor`, `drive`, `capture`, and
`down`, each as above, and `check RUN_DIR LABEL CAPTURED_LABEL JQ`, which
holds an earlier capture's answer to another filter, for a second
sub-feature the same drive proves, keeping its verdict as evidence. It needs `jq` (macOS has `/usr/bin/jq`), Xcode's
command-line tools, and a visionOS simulator runtime. Sourced, it defines its
functions and runs nothing, for a launcher of your own, as GestureKit's lab
has (`verify-gesturelab`'s `launch-lab.sh`).

`gesturekit-drive install-skill [--into <dir>] [--replace]` copies this
skill into a repository, `.agents/skills/` unless `--into` says otherwise,
refusing to replace one there unless `--replace`. For Claude Code, link
it: `mkdir -p .claude && ln -s ../.agents/skills .claude/skills`.

## What the automation stands in for

A passing recipe proves the adapters and GestureCore's rules, not the
system's recognizers or the feel:

| Command | Runs for real | Stands in for, so the headset must say |
| --- | --- | --- |
| `pluck`, `tap` on an item | The item's rules on the real clock; the grid's container, watch, alarms, and `.scrollDisabled`; where what breaks free spawns; the hand-off to the carry; your app's closures | The button's press and the item's drag, whose words the stand-in says; whether SwiftUI lets a drag in mid-pinch; hand tracking |
| `scroll` | The content moving, the lazy grid making items, the container's offset and phase rules | UIKit's pan and its phases; whether it takes a pinch given back; deceleration |
| `carry` | `CarryPinch`'s start, `HandCarry`'s clamp, facing, `CarriedEntity.stand`, your app's closures | RealityKit's hit test of the handle and the drag's conversion from the gesture's space; the move is given in the parent's frame |
| `place` | `GazePanel.stand` and `GazePlacement` | World tracking's head: the simulator's untracked head, or one given; your own placement code doesn't run |
| surface commands | `SurfacePress`, its pickup and hold timing, the lift drawn, your coast | Its two drags, touched where told; the two-handed magnify |
| `hold` on a tab | `HoldWatch`, its timer, `isHeld`, `onHeldStill` | Its watch's drag; the control's own drag and tap |
| `tune` | `TuningStore.set`, fitted and saved | The slider |

Only a person on a headset can prove the real UIKit pan taking or missing a
pinch, RealityKit's hit testing, hand and head tracking, and the feel. Say
so in the report.

## Growing a feature map for your app

Keep a map beside this skill, `features/README.md` and one file per
gesture feature of your app, as GestureKit's lab does
(`.agents/skills/verify-gesturelab/features/` in GestureKit's repository):

- The README: baseline preconditions (a run launched by `$V up`, doctor
  passing, the screen and state each recipe starts from), driving
  conventions (labels, quoting, what to reset), proof and skip reporting,
  the entry contract below, and the features, a line each.
- Each feature file: an H1 and a paragraph saying what a person does and
  sees; then exactly four H2s, in order: `Sub-features` (short IDs, one
  behavior each), `How to get to it (user POV)` (every way a person reaches
  it), `Driving it with gesturekit-drive` (`Preconditions:`, then labeled
  bullets, each an action, an exact `$V capture … --expect '…'` command, and
  the JSON fields and values that prove it), and `Gotchas`.
- Start with the gestures `targets` lists on your main screens, a file per
  feature a person would name, and grow it as you add gestures: a change to
  a gesture updates its file in the same change, and is driven through it
  before it's done.
- Keep it honest as your app changes, after pstack's
  [`maintain-verification-skill`](https://github.com/backnotprop/pstack/blob/main/skills/maintain-verification-skill/SKILL.md):
  drive every feature's recipes in one run now and then; fix the map where
  it's wrong, the harness where it can't drive, and report a gesture that's
  really broken.
