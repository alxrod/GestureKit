# Below the gaze

A panel opens below the viewer's gaze: 0.7 m from the head, 20° below
where it looks, straight below the gaze however the head is turned, never
steeper than 60° below level, tilted up to face the head, and drawn as big
as it would look a meter out. It stays put once stood, until it's carried
by the pill under it. The below-the-gaze station stands its panel so, and
places it again from a button.

## Sub-features

- `place-untracked` the panel stands 0.7 m out and 20° below the gaze of the simulator's head.
- `place-turned-head` for a head turned right and down, it stands below that gaze, tilted up to it.
- `place-steep-gaze` a gaze steeper than 60° below level places it as for 60°.
- `place-carry-pill` the panel is carried by its pill, as any panel.
- `place-smoke` the station's smoke: its pill carried up and back, its panel placed.

## How to get to it (user POV)

- Choose Below the gaze in the lab window's station list; the panel stands below your gaze as the station opens.
- Look elsewhere and press the station's button to place it again below the new gaze.
- Pinch the pill under the panel and carry it.

## Driving it with gesturekit-drive

Preconditions:

- A run on the below-the-gaze station (`--station below-the-gaze`, or `$V drive RUN_DIR station below-the-gaze`), and `$V doctor RUN_DIR` passing.
- `$V drive RUN_DIR targets` lists the panel `gaze-panel` and its handle `gaze-panel`.

- **For the simulator's head.** Place the panel for the head tracker's head, untracked in the simulator, 1.6 m up at the origin looking down -z. Run `$V capture RUN_DIR place-untracked --expect '.outcome == "placed" and (.result.distance - 0.7 | fabs < 0.001) and (.result.belowTheGaze - 20 | fabs < 0.1) and (.result.tilt - 20 | fabs < 0.1) and (.result.head | test("untracked"))' place`. It stands at (0, 1.36, -0.66) m, and the lab's state says `"placed": "0.70 m out · 20.0° below gaze · tilted 20.0°"`.
- **For a head turned.** A head at (0, 1.6, 0) turned 30° right and 40° down. Run `$V capture RUN_DIR place-turned-head --expect '.outcome == "placed" and (.result.gazeAcross - 30 | fabs < 0.1) and (.result.gazeUp + 40 | fabs < 0.1) and (.result.tilt - 60 | fabs < 0.1) and (.result.distance - 0.7 | fabs < 0.001)' place gaze-panel 'head={"at":[0,1.6,0],"yaw":30,"pitch":-40}'`.
- **A steep gaze.** A head looking 85° down. Run `$V capture RUN_DIR place-steep-gaze --expect '.outcome == "placed" and (.result.tilt - 60 | fabs < 0.1) and (.result.belowTheGaze + 25 | fabs < 0.1)' place gaze-panel 'head={"at":[0,1.6,0],"yaw":0,"pitch":-85}'`. The panel stands 60° below level, 25° above that gaze.
- **Carried by its pill.** Run `$V capture RUN_DIR place-carry-pill --expect '.outcome == "carried" and ([.result.stood, .result.asked] | transpose | all(.[0] - .[1] | fabs < 0.002))' carry gaze-panel by=0,0.1,0`.
- **Smoke.** Run `$V capture RUN_DIR place-smoke --expect '.ok and .result.failed == 0 and .result.passed == 3' smoke`.
- **Proof.** `RUN_DIR/place-untracked.png` shows the panel below the view's middle, tilted up; the `.json` carries the distance and angles, and its `trace` the Placement interaction, "0.70 m out, 20.0° below the gaze".

## Gotchas

- `place` calls `GazePanel.stand` itself, with the tuning and trace the panel was last stood with; the station's own button and placement code don't run, and the lab's `lastStood` doesn't change.
- World tracking can't give a head in the simulator: `head=tracker`, the default, waits for the tracker and falls back to the untracked head. Give a head to test a turned one; on the headset, the real head decides.
- Angles in `head` are degrees, `yaw` to the right and `pitch` up; `gazeUp` in the answer is negative looking down.
- The panel stays where the last `place` or `carry` left it until the next, or a relaunch; a placement goes by the head alone, wherever the panel was.
