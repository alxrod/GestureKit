# Carry

A panel, or a card plucked out of the grid, is carried by the grab handle
under it: a pinch on the handle waits 8 pt, then carries the panel's middle
1:1 with the hand, turned to face the viewer, and never nearer the head than
0.3 m, pushed out along the line from the head. A pinch that never goes 8 pt
carries nothing. However the carry ends, the app's `onEnd` hears how:
released, cancelled, or its view gone. The carry and face station stands three panels, A, B, and
C, each with its handle; the below-the-gaze station's panel and every card
the pluck spawns have one too.

## Sub-features

- `carry-by` a handle carries its panel as far as the hand moves.
- `carry-to` a handle carries its panel's middle to a point.
- `carry-head-clearance` a panel carried into the head stops 0.3 m from it.
- `carry-start` a pinch that moves less than 8 pt carries nothing.
- `carry-cancelled` a carry whose gesture is cancelled says it was cancelled.
- `carry-view-went` a carry ended by its view going isn't drivable, and is refused.
- `carry-unknown` a handle not on screen is refused, naming those that are.
- `carry-smoke` every handle on the station carried up 5 cm and back.

## How to get to it (user POV)

- Choose Carry and face in the lab window's station list; three panels stand in the room, each with a pill under it.
- Pinch a panel's pill and move your hand; let go where it should stand.
- The same on the below-the-gaze panel's pill ([Below the gaze](./below-the-gaze.md)), and on a plucked card's pill ([Pluck](./pluck.md)).

## Driving it with gesturekit-drive

Preconditions:

- A run on the carry and face station (`--station carry-and-face`, or `$V drive RUN_DIR station carry-and-face`), and `$V doctor RUN_DIR` passing.
- `$V drive RUN_DIR targets` lists the handles `panel-a`, `panel-b`, and `panel-c`, each carrying its panel.
- The panels where the station stands them, from a fresh launch or relaunch: A at (-0.5, 1.3, -0.85), B at (0, 1.35, -1), C at (0.5, 1.3, -0.85) m.

- **Carry by.** Pinch B's pill and move 10 cm right and 20 cm toward you. Run `$V capture RUN_DIR carry-by --expect '.outcome == "carried" and .result.ending == "released" and ([.result.stood, .result.asked] | transpose | all(.[0] - .[1] | fabs < 0.002)) and .result.reported == ["touch", "begin", "carry", "end"] and (.app.lab.carryAndFace.lastStood | test("^Panel B"))' carry panel-b by=0.1,0,0.2`. The trace says "carried 0.22 m", and its `begin` line "after 10.4 pt".
- **Carry to a point.** Carry C's middle to (0.3, 1.4, -0.9) m. Run `$V capture RUN_DIR carry-to --expect '.outcome == "carried" and ([.result.stood, [0.3, 1.4, -0.9]] | transpose | all(.[0] - .[1] | fabs < 0.002))' carry panel-c to=0.3,1.4,-0.9`.
- **Stops 0.3 m from the head.** Carry A toward the simulator's head, at (0, 1.6, 0), to 10 cm from it. Run `$V capture RUN_DIR carry-head-clearance --expect '.outcome == "carried" and (.result.fromTheHead - 0.3 | fabs < 0.002) and ([.result.stood, [0, 1.6, -0.3]] | transpose | all(.[0] - .[1] | fabs < 0.002))' carry panel-a to=0,1.6,-0.1`. It asked for (0, 1.6, -0.1) and stood at (0, 1.6, -0.3): `aboutTheHead` reads "0.30 m from the head".
- **Short of the start.** Pinch B's pill and move 4 mm, 5.4 pt. Run `$V capture RUN_DIR carry-start --expect '.outcome == "nothing" and .result.reported == ["touch", "release"] and .result.stood == .result.from' carry panel-b by=0.004,0,0`.
- **Cancelled.** After carry by, carry B back the way it came, its gesture cancelled at the end. Run `$V capture RUN_DIR carry-cancelled --expect '.outcome == "carried" and .result.ending == "cancelled" and ([.result.stood, .result.asked] | transpose | all(.[0] - .[1] | fabs < 0.002)) and ([.trace[] | select(.gesture == "Carry") | .outcome] | any(test("cancelled")))' carry panel-b by=-0.1,0,-0.2 ending=cancelled`. The trace says "carried 0.22 m, cancelled".
- **Its view gone.** Run `$V capture RUN_DIR carry-view-went --expect '.ok == false and (.error | test("released or cancelled"))' carry panel-b ending=viewWent`.
- **A handle not on screen.** Run `$V capture RUN_DIR carry-unknown --expect '.ok == false and (.error | test("panel-a, panel-b, panel-c"))' carry panel-z`.
- **Smoke.** Run `$V capture RUN_DIR carry-smoke --expect '.ok and .result.failed == 0 and .result.passed == 6' smoke`.
- **Proof.** `RUN_DIR/carry-head-clearance.png` shows panel A close in front of the view; the `.json` carries `fromTheHead` and `stood`.

## Gotchas

- `to` is in the carried thing's parent's frame, which on this station is the space's; `by` is the hand's move, and the answer's `asked` is where it would stand unclamped.
- 8 pt is about 5.9 mm of the automation's meters, at 1,360 pt a meter; a move under that is `nothing`, not a failure.
- Facing turns the panel every frame toward the head; no answer field gives its rotation, so the screenshot shows it and the headset judges it.
- The handle's hit test, and the entity-targeted drag's conversion from the gesture's space, are stood in for: the move is given in the parent's frame. Whether a pinch lands on the pill is the headset's to say.
- The head is the simulator's untracked one, 1.6 m up at the origin looking down -z; on a headset the clearance follows the real head.
- The lab's panels use the simple form, `grabHandlesCarryEntities`, so a cancelled carry stands where the hand last put it, like a released one. An app that puts a cancelled carry back does so in its own `onEnd`; check that in the app, through its own state.
- Only the app can make a carry's view go, by closing it mid-carry, so `ending=viewWent` is refused.
- Carried panels stay where they were left until a relaunch; relaunch before a recipe that assumes where they stand.
