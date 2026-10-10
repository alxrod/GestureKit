# Driving the gestures without a hand

## Why

The simulator can't pinch, so until now only Alex on the headset could say
whether a gesture worked. Agents need to drive every gesture themselves, in
a simulator, with no human: pluck an item out of a grid, scroll it, carry a
handle, place a panel below the gaze, tap, drag, flick, pick up, and hold a
surface, hold a tab, and read back what happened. Alex asked for it on
October 10: "we need modes so that agents can drive the gestures without
complex pinch and drag logics for all the supported gestures".

## The shape

An agent sends one command at the gesture's level, "pluck item 7", and the
app answers with what happened, in JSON. Between the two, the command says
the words a hand's gestures would say, at a hand's pace, through the hand's
stand-in (`PinchStandIn`), so each adapter's own logic runs as with a hand,
and so do GestureCore's rules beneath it. Nothing calls an app's model
directly: the app hears what the adapter tells it, as it would from a hand.

Everything is in debug builds only, behind `@_spi(GestureAutomation)`:

- **GestureCore** (`Automation/`, `#if DEBUG`): the values with no
  platform in them, tested with `swift test`: a JSON value
  (`AutomationJSON`), lenient readers for a command's arguments
  (`AutomationArguments`: "0,0,0.05" or `[0, 0, 0.05]` for a vector, "true"
  for a switch), the HTTP framing the server speaks (`AutomationHTTP`), the
  steps of a hand's move (`AutomationPath`), and the run of what the
  adapters reported, folded (`AutomationEventLog`).
- **GestureKit** (`Automation/`, visionOS and `#if DEBUG`): `GestureAutomation`,
  the hub: what's registered, the commands, the server, and the script
  runner; and each adapter's ear for the stand-in, which now knows its
  name, whether a pinch is under way on it, and what it goes by.

## Names

Everything is addressed by name, as registered:

| What | Named by |
| --- | --- |
| A pluckable item | its `title`, as `pluckable(_:title:perform:)` was given it: "item 7" |
| A pluckable grid | `.gestureAutomationName("grid")` on the scroll view, outside `pluckContainer` |
| A surface | `.gestureAutomationName("surface")` outside `.surfacePress` |
| A tab watched for a hold | `.gestureAutomationName("tab")` outside `.holdWatch` |
| A grab handle | its carried thing's id, for one `GrabHandle.make` marks with a `GrabHandleComponent`, else its entity's name; or `register(handle:named:)` |
| A panel to place | `register(panel:named:tuning:recorder:placed:)` |
| A tuning | its `TuningStore`'s namespace, registered as the store is made: "GestureLab.pluck", or any unique end of it, "pluck" |
| A trace | `register(trace:named:)` |

An app adds its own commands (`register(command:help:_:)`), its own state
(`register(state:_:)`), and what keeps it busy (`register(busy:_:)`), as
the lab adds `station`, each station's facts, and the press's coast.

## The commands

Vectors are a hand's move in meters, x right, y up, z toward the viewer,
1,360 of an adapter's points to the meter, as visionOS draws a view in a
space; times are seconds. Every command answers
`{"ok", "command", "outcome", "result", "events", "trace", "app", "elapsed"}`:
`events` what the adapters reported while it ran, a run of one kind folded
into one line; `trace` each interaction the registered traces recorded
meanwhile, with its summary; `app` the app's registered state. A failure
answers `"ok": false` and an `"error"` in a sentence.

| Command | Arguments, defaults | Says, through | Outcome |
| --- | --- | --- | --- |
| `pluck` | `item`; `hold` its hold + 0.1; `pull` [0, 0, 0.05]; `pullTime` 0.4; `carry` [0, 0, 0]; `carryTime` 0.4; `release` true | the item's press, held; its drag, only once past the drag's start for the stage it's in, as the real drag would; then its end | `spawned`, `lifted`, `tapped`, or `stayed down` |
| `tap` | `item`, or `surface` with `at` 0.1 m along | the item's press and tap; the surface's two drags, touched and let go | `tapped`, `tap` |
| `scroll` | `grid`; `by` 400 pt, or `to` "top", "end", points, or an item's title; `on` an item; `time` 0.5 | the scroll view's phases, and its content moved by SwiftUI's `ScrollPosition`, so `onScrollGeometryChange` reports each step; the item's press, cancelled as a pan would | `scrolled` |
| `carry` | `handle`; `by` [x, y, z], or `to` in the carried thing's parent's frame; `time` 0.6 | the handle's entity-targeted drag's words, on that handle | `carried`, `nothing`, `refused` |
| `place` | `panel`; `head` "tracker", "untracked", or `{"at", "yaw", "pitch"}` in degrees | `GazePanel.stand` itself, for that head | `placed` |
| `drag` | `surface`; `along` 0.3, `across` 0; `at`; `time` 0.6 | the surface's two drags | `scroll`, `drag along`, `drag across` |
| `flick` | `surface`; `along` 0.25; `time` 0.12 | the same, let go on the move | `scroll`, coasting |
| `pickup` | `surface`; `by` [0.1, 0.05, 0.05]; `at`; `time` 0.5 | held still past the pickup, then moved | `carry`, or `pickup, put down` |
| `hold` | `surface` or `tab`; `seconds` its hold + 0.2; `waver` 1.5 pt; `moveFirst` [0, 0, 0] | held still, wavering, then let go | `hold`, `the control's`, `let go before its hold` |
| `tune` | `tuning`; `key` and `value`, or `reset` true | `TuningStore.set`, as the panel's slider does | `tuned` |
| `trace` | `trace` all; `clear` false | the recorders | the interactions |
| `wait` | `timeout` 10; `quiet` 0.3 | every adapter and the app's busy checks | `idle` |
| `state` | | everything registered | |
| `help` | | | the commands |
| `station` (lab) | `id` | the lab's chosen station, as its list | `chosen` |

## What's real, and what's stood in

| Command | Runs for real | Stands in for, or skips |
| --- | --- | --- |
| `pluck`, `tap` an item | `PluckItemDriver` and the rules (`PluckPinches`, `PluckPress`) with their counts on the real clock; the container, its watch and alarms, `.scrollDisabled` given to the real scroll view; the item's geometry into the space, for where it spawns; the hand-off to `CarryPinch`; the trace; the app's `perform` | the button's press and the item's `DragGesture`: the words come from the stand-in, kept from speaking before the drag's start, as `liftedTracking` sets it, so whether SwiftUI really lets a drag in mid-pinch is the headset's to say; hand tracking |
| `scroll` | the scroll view's content moving, the lazy grid making its items, `onScrollGeometryChange`, the container's offset and phase rules, the pinch on an item hearing them | UIKit's pan: its phases are said by the stand-in, as the pan would say them; no deceleration |
| `carry` | `GrabHandleCarry`: `CarryPinch`'s start distance, `HandCarry`'s clamp, `Facing`, `CarriedEntity.stand`, the trace, the app's closures; only a modifier whose marker the handle has | the entity-targeted drag: its hit test, and its conversion from the gesture's space, the move given in the parent's frame |
| `place` | `GazePanel.stand`, `GazePlacement`, the trace | the head: world tracking, which the simulator lacks, by the untracked head or one given |
| `drag`, `flick`, `pickup`, `hold` a surface | `SurfacePressModifier`: `SurfacePress`, its clock, the pickup and hold timing, `HoldLift`'s lift drawn, the trace, the app's coast | its two drags, touched where told, the hand from the space's origin; the two-handed magnify |
| `hold` a tab | `HoldWatchModifier`: `HoldWatch`, its timer, `isHeld` and its grace, `onHeldStill`, the trace | its watch's drag; the control's own drag and tap, which are the app's, never move |
| `tune` | `TuningStore.set`, fitted, saved | the slider |

## Two transports

- **A server**, `-automationPort <port>`: HTTP on 127.0.0.1 only, which a
  visionOS simulator shares with its Mac. `POST /` with a command's JSON;
  `GET /state` and `GET /help`. Commands run one at a time, in order.
- **A script**, `-automation <file>`: a JSON array of commands run as the
  app settles, its results written beside it as `<file>.results.json`, and
  each logged at info ("Automation: pluck → spawned").

Both wait for the app to settle first: nothing registered or gone for 0.7 s.

## The CLI

`scripts/gesture-drive.sh` keeps a simulator of its own, "GestureLab-Auto",
builds the lab into `build/gesture-drive/`, never Xcode's DerivedData, and
launches it with the server:

    scripts/gesture-drive.sh up --station pluck
    scripts/gesture-drive.sh pluck item="item 7" pull=0,0,0.06
    scripts/gesture-drive.sh state
    scripts/gesture-drive.sh screenshot pluck.png
    scripts/gesture-drive.sh down

`scripts/gesture-selftest.sh` drives every gesture in a fresh simulator,
checks each outcome with `jq`, runs a script through `-automation`, and
exits non-zero on the first failure.

## Adopting it in another app

    #if DEBUG
    @_spi(GestureAutomation) import GestureKit
    #endif

    // First thing as the app starts, before any adapter appears:
    #if DEBUG
    GestureAutomation.shared.startFromLaunchArguments()
    GestureAutomation.shared.register(trace: recorder, named: "editor")
    #endif

    // Name the views whose adapters an agent drives:
    StripView()
        .surfacePress(…)
        #if DEBUG
        .gestureAutomationName("strip")
        #endif

Pluckable items are named by their titles and grab handles by what they
carry already; a panel placed below the gaze is registered with its entity.
