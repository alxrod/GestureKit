# Surface press

One pinch on a surface, told from its touch by how far it moves and how
long it's still: let go at once, a tap; moved along, a drag along, which on
the press station scrolls the playhead with the hand and, let go on the
move, coasts on, slowing, until a pinch catches it; moved across, nothing;
held still half a second, a pickup, lifted, and moved 2 cm then, a carry of
the whole surface; held a second, a hold. The press station's surface is a
bar with a playhead, markers dropped where it's tapped, and a tab at its
end ([Hold watch](./hold-watch.md)).

## Sub-features

- `press-tap` a quick pinch drops a marker where it touched.
- `press-drag-along` a drag along moves the playhead with the hand and comes to rest without coasting.
- `press-flick-coast` a flick let go on the move coasts the playhead on, until it comes to rest.
- `press-catch` a pinch on a coasting playhead catches it, and is no tap.
- `press-pickup-carry` held still past the pickup, then moved, the surface is carried with the hand.
- `press-pickup-put-down` held still past the pickup and let go without moving, it's put down.
- `press-hold` held still a second, the pinch holds.
- `press-drag-across` a drag across the surface does nothing.
- `press-smoke` the station's smoke: the surface tapped, the tab held.

## How to get to it (user POV)

- Choose Press in the lab window's station list; the surface stands in front of you with its tab at its right end.
- Pinch the surface and let go, drag along it, flick along it, pinch it while it coasts, hold it still, or drag up or down across it.

## Driving it with gesturekit-drive

Preconditions:

- A run on the press station (`--station press`, or `$V drive RUN_DIR station press`), freshly launched or relaunched, and `$V doctor RUN_DIR` passing.
- The press's state as the station starts: `$V drive RUN_DIR state --json` shows `.result.app.lab.press` with `"playhead": 0.3`, `"markers": 0`, `"center": [0, 1.3, -1]`, and `"coasting": false`.
- The press's tunings at their defaults: `$V drive RUN_DIR tune press reset=true`.

- **Tap.** Pinch 0.4 m along and let go. Run `$V capture RUN_DIR press-tap --expect '.outcome == "tap" and (.result.tappedAt - 0.4 | fabs < 0.01) and .app.lab.press.markers == 1' tap surface at=0.4`.
- **Drag along.** Drag 20 cm along, come to rest, let go. Run `$V capture RUN_DIR press-drag-along --expect '.outcome == "scroll" and (.app.lab.press.playhead - 0.5 | fabs < 0.02) and .app.lab.press.coasting == false and (.result.reported | index("beginScroll"))' drag surface along=0.2`. The playhead goes from 0.3 to 0.5 m.
- **Flick, and its coast.** Flick 15 cm back in 0.12 s. Run `$V capture RUN_DIR press-flick --expect '.outcome == "scroll" and .result.letGo == true and .app.lab.press.coasting == true' flick surface along=-0.15`, then `$V capture RUN_DIR press-coast-rests --expect '.outcome == "idle" and .app.lab.press.coasting == false' wait`. The answer's `trace` has a Coast interaction, "from 0.350 m at -1.40 m/s, to rest at 0.000 m in 1.25 s".
- **Catch.** Flick again, without a capture, and catch it at once. Drag the playhead well along first, so the flick's coast has room to run. Run `$V drive RUN_DIR drag surface along=0.6 --brief`, then `$V drive RUN_DIR flick surface along=-0.15 --brief` and straight after `$V capture RUN_DIR press-catch --expect '.outcome == "catch" and .result.reported == ["endCatch"] and .app.lab.press.coasting == false and .app.lab.press.markers == 1' tap surface at=0.5`. Caught, the tap drops no marker, and the trace says "caught a coast", "let go after … s, no tap".
- **Pickup and carry.** Hold still past the half-second pickup, then move 10 cm right, 5 up, 5 toward you. Run `$V capture RUN_DIR press-pickup-carry --expect '.outcome == "carry" and (.result.reported | index("pickUp") < index("beginCarry")) and ([.app.lab.press.center, [0.1, 1.35, -0.95]] | transpose | all(.[0] - .[1] | fabs < 0.01))' pickup surface by=0.1,0.05,0.05`.
- **Pickup, put down.** Run `$V capture RUN_DIR press-pickup-put-down --expect '.outcome == "pickup, put down" and .result.reported == ["pickUp", "putDown"]' pickup surface by=0,0,0`.
- **Hold.** Hold still 1.2 s. Run `$V capture RUN_DIR press-hold --expect '.outcome == "hold" and (.result.reported | index("fireHold"))' hold surface`.
- **Drag across.** Drag 10 cm up across it. Run `$V capture RUN_DIR press-drag-across --expect '.outcome == "drag across" and (.result.reported | index("ignoreDragAcross")) and (.app.lab.press.lastEvent | test("ignored"))' drag surface along=0 across=0.1`.
- **Smoke.** Run `$V capture RUN_DIR press-smoke --expect '.ok and .result.failed == 0 and .result.passed == 2' smoke`.
- **Proof.** `RUN_DIR/press-pickup-carry.png` shows the surface moved up and right; each `.json` has the press's events, `beginScroll`, `endScroll`, `pickUp`, `beginCarry`, and the lab's `press` state.

## Gotchas

- A capture takes a few seconds after its command, for the state, the screenshot, and the log, and a coast is over in about a second: drive the flick with `$V drive` and capture the catch straight after, or the tap lands after the coast and is a tap, dropping a marker.
- On a loaded machine the app's main actor can stall, and its timers fire late: a trace whose pickup and hold come at the same moment, long after the touch ("pick up +1.66 s (held still 1.66 s …); hold +1.66 s"), turns a `pickup` into a `hold`. That's the machine, not the gesture: check `uptime`, doctor, and drive it again; report it only if it repeats on a quiet machine.
- The press's playhead, markers, and center stay until a relaunch: relaunch before a recipe whose filter names them, or assert on the change rather than the value.
- `at` is meters along the surface's leading edge; a `drag` without it touches at 0.1 m; `hold` touches where the stand-in's first word puts it.
- The pickup and hold times come from the press's tuning: a `tune` left set changes every recipe after it ([Tuning](./tuning.md)).
- The stand-in says the surface's two drags, touched where told and moving from the space's origin; the two-handed magnify isn't driven, and the feel of the lift and the coast is the headset's.
