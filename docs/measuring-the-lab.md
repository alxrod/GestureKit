# Measuring the lab

How to put a load on GestureLab in the simulator, standing in for a hand,
and read what it costs. `AGENTS.md` links here; the loads live in
`Lab/GestureLab/LabLoad.swift`, DEBUG only.

## The loads

The simulator can't pinch, so a DEBUG build takes launch arguments that
stand in for a hand (`LabLoad`):

- `-station <id>` chooses the station at launch: `trace-check`,
  `carry-and-face`, `below-the-gaze`, `press`, or `pluck`.
- `-labLoad <kinds>`, comma-separated, begins 3 s in: `trace`, 20 trace
  events a second after 30 interactions of 15; `tuning`, the station's
  first number slid across its range, set 60 times a second; `pull`, the
  pluck's card spawned and carried, 90 steps a second; `scroll`, the
  pluck's grid scrolled at 1,500 pt a second; `drag`, the press's playhead
  moved 90 times a second; `coast`, the press's playhead flicked every 2 s;
  `switch`, the next station chosen every 4 s; and three that drive an
  adapter through the hand's stand-in (`PinchStandIn`), 90 words a second
  for 2 s, let go, and again: `surface`, a drag along the press's surface
  through `.surfacePress`; `tab`, a hold on the press's tab through
  `.holdWatch`; and `handle`, the carry and face station's middle panel
  carried round a circle through `.grabHandleCarry`. And `stuck`, with
  `-station pluck`: the pluck's end words said through `.pluckable` and
  `.pluckContainer` by the stand-in, in the orders that held its grid's
  scroll before October 9's fix and two that never did, each on an item of
  its own, logging the container's status at once, 0.6 s, and 1.2 s after
  each ("Lab load stuck: …"); then Alex's clip of October 10: a pluck
  through its break-free, carry, and release, the card carried by its own
  grab handle through `.grabHandleCarry`, and pinches told as scrolls, with
  what the UIKit scroll view has after each step, once through. And
  `lifted`, with `-station pluck`: a pull under each way a lifted pinch is
  followed (`PluckLiftedTracking`), the drag held back by its start, brought
  down, taking and not, kept at 60 pt, held back by its mask, hearing and
  not, and the hand by the hand tracker's stand-in, each pinch saying only
  what its gestures could, logging what each did ("Lab load lifted: …"),
  once through, the tuning put back after. What a load changes stays, as a
  hand's would: `tuning` leaves its value tuned, saved, until Defaults, and
  `switch` the station it chose last remembered.
- `-labTracing off` starts with the whole lab's tracing off, so a load
  measures the gestures with no trace; `on` starts with it on.

## Measuring

Build the lab for the simulator into a throwaway DerivedData, install it on
a simulator of your own (the `verify-gesturelab` skill's `launch-lab.sh`
makes one, and its `run.env` names it) with `xcrun simctl install`, launch it with
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

## What the lab costs

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

## What keeps it cheap

A view that changes at a hand's every step lays out nothing beside it and
is read by nothing that doesn't show it: the trace takes its room whatever
it shows, and the pluck station's windows read how many cards there are,
not where they stand.

