# Tuning

Every number a gesture goes by is in its tuning, which each station shows
as a panel of sliders and switches beside its trace, with Defaults and Copy
tuning. A slider's change takes effect at once, on the next pinch, and is
saved under the station's namespace, as `GestureLab.press`, so it outlasts
a relaunch until Defaults puts it back. The automation's `tune` sets a value
as the slider does, fitted to its range and step, and `state` lists every
tuning's values.

## Sub-features

- `tune-set` a number set as its slider would, fitted and reported back.
- `tune-takes-effect` the next pinch goes by the new value.
- `tune-saved` the value outlasts a relaunch.
- `tune-switch` a switch set on or off.
- `tune-reset` a tuning put back to its defaults, as Defaults does.
- `tune-refused` an unknown key, or a name several tunings end in, is refused, naming what there is.

## How to get to it (user POV)

- Choose a station in the lab window's list; its tuning panels stand under its window content, one per tuning, each slider with its value and unit.
- Slide a slider or flip a switch, then pinch the gesture; press Defaults to put the panel back.

## Driving it with gesturekit-drive

Preconditions:

- A run on the press station, and `$V doctor RUN_DIR` passing.
- `$V drive RUN_DIR state --json` lists the tunings by namespace under `.result.tunings`, `GestureLab.press` among them with `"pickUpDelay": 0.5`.

- **Set a number.** Slide the press's pickup to 0.3 s. Run `$V capture RUN_DIR tune-set --expect '.outcome == "tuned" and .result.tuning == "GestureLab.press" and .result.key == "pickUpDelay" and .result.value == 0.3 and .result.tuned == {"pickUpDelay": 0.3}' tune press key=pickUpDelay value=0.3`. A store is named by its namespace or the one namespace ending in it after a dot: `press` is `GestureLab.press`.
- **It takes effect.** Hold the surface still and let go. Run `$V capture RUN_DIR tune-takes-effect --expect '.outcome == "pickup, put down" and ([.trace[].summary] | join(" ") | test("picks up at 0.3 s"))' pickup surface by=0,0,0`. The pickup came at 0.3 s, not 0.5.
- **It's saved.** Relaunch, and read it back. Run `$V drive RUN_DIR relaunch --station press`, then `$V capture RUN_DIR tune-saved --expect '.result.tunings["GestureLab.press"].pickUpDelay == 0.3' state`.
- **A switch.** Turn the pluck's give-back off, and on again. Run `$V capture RUN_DIR tune-switch --expect '.outcome == "tuned" and .result.value == false and .result.tuned == {"givesLiftBackToScroll": false}' tune pluck key=givesLiftBackToScroll value=false`, then `$V drive RUN_DIR tune pluck reset=true`.
- **Put back.** Run `$V capture RUN_DIR tune-reset --expect '.outcome == "tuned" and .result.tuned == {}' tune press reset=true`, and `state` shows `pickUpDelay` 0.5 again.
- **Refused.** An unknown key: `$V capture RUN_DIR tune-unknown-key --expect '.ok == false and (.error | test("has no nope; it has .*pickUpDelay"))' tune press key=nope value=1`. A name several end in: `$V capture RUN_DIR tune-ambiguous --expect '.ok == false and (.error | test("names several tunings"))' tune carry key=startDistance value=10`.
- **Proof.** `RUN_DIR/tune-saved.json` reads the value back after the relaunch; `tune-takes-effect.json`'s trace says when the pickup came.

## Gotchas

- Tunings are saved in the app's container and outlast relaunches: put back every tuning a recipe changes (`tune <store> reset=true`), or later recipes run on it. A fresh run's simulator starts at the defaults.
- A value is fitted to its parameter's range and step, so read `.result.value` back rather than assuming what was asked.
- The lab's namespaces: `GestureLab.trace-check`, `.carry-and-face.carry`, `.carry-and-face.facing`, `.below-the-gaze.placement`, `.below-the-gaze.carry`, `.press`, `.press.lift`, `.press.coast`, `.press.hold-watch`, `.pluck`, `.pluck.carry`, and `.pluck.hand`. `carry` names three of them; name the one you mean, as `pluck.carry`.
- Whether a tuned number feels right is the headset's to say; Copy tuning there turns it into the area's new defaults.
