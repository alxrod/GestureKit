# GestureLab verification map

This folder is the maintained source for verifying GestureKit's gestures in
GestureLab. Read this index before driving the lab, then use the feature's
file as the recipe. `$V` is `.agents/skills/verify-gestures/scripts/gesture-verify.sh`
and `RUN_DIR` the folder `launch-lab.sh` printed, as in the skill.

## Baseline preconditions

- A run launched by `.agents/skills/verify-gesturelab/scripts/launch-lab.sh
  --station <the feature's station>`, through your build lock, from the
  checkout you're verifying.
- `$V doctor RUN_DIR` passes: the run's own simulator and port, the build
  of the checkout as it is now, the automation ready.
- `jq` on the `PATH` (macOS has `/usr/bin/jq`).
- Never drive a lab this run didn't launch, nor any simulator it didn't
  make.

## Driving conventions

- Start each feature on its station, fresh: launch on it, or `$V drive
  RUN_DIR relaunch --station <id>`, which clears the app's state but
  keeps saved tunings.
- Drive through `$V capture RUN_DIR <label> --expect '<filter>' <command> …`,
  one label per sub-feature, its ID or its ID and a step, as
  `pluck-break-free`; `$V drive` only for setting up, or where a capture's
  few seconds would spoil timing, as the press's catch.
- Treat every command as literal: keep item titles quoted, `"item 6"`, and
  vectors as `x,y,z` in meters, x right, y up, z toward you.
- Name targets as `targets` lists them; read a card's handle id from
  `targets --json` rather than guessing it.
- Put back what a recipe changes that outlives a relaunch: `tune <store>
  reset=true` after any tuning.
- Doctor again after any drive that surprised you, and before driving a
  change you've made since the launch (it fails, and you launch afresh).
- A FAIL whose trace shows a timer firing late, a hold or a pickup long
  after the touch, is a loaded machine stalling the app's main actor: check
  `uptime`, doctor, and drive it again before calling it a regression.

## Proof and skip reporting

- Write the `--expect` filter from the feature file before driving; the
  verdict in `<label>.check.txt` is the proof, the answer in `<label>.json`
  its record.
- The outcome and the numbers come from the JSON: `outcome`, `result`,
  `events`, `trace`, and `app`. The screenshot shows the app, the station,
  and how it looked; it proves no outcome.
- Prove the state a gesture leaves as well as its outcome: the lab's state
  in `app`, `<label>.state.json`, and, after a pluck, the grid's scroll on
  again with no alarm.
- Record with each verdict the sub-feature's ID, the capture label, and the
  command; `captures.txt` keeps them in order.
- Report a path you couldn't reach with the command tried and the
  precondition unmet. Never report a sub-feature verified through another's
  path.
- Report what the automation stood in for, from the skill's table, and
  leave the feel, the UIKit pan, RealityKit's hit testing, and hand and
  head tracking to a person on the headset.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the
gesture as a person meets it. It then has exactly four H2 sections, in this
order:

1. `Sub-features`: short IDs, one line each, one behavior each.
2. `How to get to it (user POV)`: every way a person reaches it in the lab,
   on the headset.
3. `Driving it with gesturekit-drive`: `Preconditions:` first, then
   labeled bullets, each pairing a person's action with an exact command
   and the JSON fields and values that prove it.
4. `Gotchas`: what can waste or invalidate a run.

Name user paths, targets, commands, and the JSON that proves them; keep the
implementation out, but for the names a trace or an answer shows.

## Features

- [Pluck](./pluck.md): an item pulled out of the grid, its sticky stage,
  break-free, spawn, and hand-off to a carry.
- [Scroll first](./scroll-first.md): pinches on the grid that stay its
  scroll, a yank among them, and a lift given back to the scroll.
- [Carry](./carry.md): a panel or a card carried by its grab handle, 1:1,
  stopping 0.3 m from the head.
- [Below the gaze](./below-the-gaze.md): a panel placed below a gaze,
  tilted up, and carried by its pill.
- [Surface press](./surface-press.md): a tap, a drag along, a flick and
  its coast, a catch, a pickup and carry, a hold, and a drag across.
- [Hold watch](./hold-watch.md): a still hold on a tab, watched beside the
  tab's own gestures.
- [Tuning](./tuning.md): a tuning set as its slider would, taking effect,
  saved, and put back.
- [Tracing and alarms](./tracing-and-alarms.md): each interaction's trace,
  read and cleared, tracing switched off, and the pluck's alarms.

## Keeping the map honest

A map rots as the gestures change. After the conventions of pstack's
[`maintain-verification-skill`](https://github.com/backnotprop/pstack/blob/main/skills/maintain-verification-skill/SKILL.md),
scaled to this repository:

- **With every change.** A change to a gesture, an adapter, a station, or a
  command updates the feature files it touches in the same branch: a new
  behavior gets a sub-feature and a recipe, a renamed target or field its
  commands and filters, a new station or area a file of its own and a line
  above. Drive what you changed through the map before you call it done.
- **A pass over the whole map**, when it's asked for or after a run of
  changes: check this index against the files beside it, read each
  feature's source for what changed, then launch once and drive every
  feature's recipes in one run, doctor first and again after any surprise.
  Then sort what failed:
  - a description or filter that's wrong is drift: fix the map;
  - a behavior the harness can't drive is a harness gap: fix
    `launch-lab.sh`, `gesture-verify.sh`, or the automation, and drive it
    again;
  - a gesture that's really broken is a product bug: report it with the
    capture, and leave the map saying what it should do.
- **One outcome**: clean, every feature driven and nothing to change;
  changed, the proven corrections committed; or blocked, saying what
  stopped it. Keep the run's evidence in `artifacts/`, uncommitted.
- `swift test` checks the map's shape: every skill's frontmatter, this
  index against its files, and each file's four sections in order
  (`AgentSkillsTests`).
