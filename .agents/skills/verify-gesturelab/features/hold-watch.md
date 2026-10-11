# Hold watch

A pinch on a handle or control held still 0.6 s, within 10 pt, asks
whether the hold means anything there. The watch stands beside the
control's own drag and tap, never in front of them: a pinch that moves off
first, or is let go before the hold, is the control's, and a hold, once it
fires, takes the rest of the pinch. The press station's tab, at the
surface's right end, is watched so; its own drag resizes the surface.

## Sub-features

- `holdwatch-hold` a still pinch on the tab holds, and the rest of the pinch is the hold's.
- `holdwatch-short` a pinch let go before 0.6 s holds nothing.
- `holdwatch-moved-first` a pinch that moves off first is the control's, and holds nothing however long it stays.
- `holdwatch-tuned` the hold's duration, tuned shorter, holds sooner.
- `holdwatch-smoke` the station's smoke holds the tab.

## How to get to it (user POV)

- Choose Press in the lab window's station list; the tab is the grip at the surface's right end.
- Pinch the tab and hold still; or let go at once; or drag it, which resizes the surface.

## Driving it with gesturekit-drive

Preconditions:

- A run on the press station, and `$V doctor RUN_DIR` passing.
- `$V drive RUN_DIR targets --json` lists the tab: `.result.tabs[0]` has `"id": "tab"`, `"duration": 0.6`, and `"stillDistance": 10`.
- The hold watch's tuning at its defaults: `$V drive RUN_DIR tune hold-watch reset=true`.

- **Hold.** Hold the tab still 0.8 s, wavering 1.5 pt. Run `$V capture RUN_DIR holdwatch-hold --expect '.outcome == "hold" and .result.reported == ["touch", "held", "release"]' hold tab`. The trace: "held still 0.69 s within 1.6 pt: the rest of the pinch is the hold's".
- **Too short.** Let go after 0.2 s. Run `$V capture RUN_DIR holdwatch-short --expect '.outcome == "let go before its hold" and (.result.reported | index("held") | not)' hold tab seconds=0.2`.
- **Moved first.** Move 2 cm first, then hold still. Run `$V capture RUN_DIR holdwatch-moved-first --expect '(.outcome | startswith("the control")) and (.result.reported | index("moved off")) and (.result.reported | index("held") | not)' hold tab moveFirst=0.02,0,0`. The event `moved off` says "10.7 pt", past the 10.
- **Tuned shorter.** Set the hold to 0.3 s, hold 0.45 s, and put it back. Run `$V capture RUN_DIR holdwatch-tune --expect '.outcome == "tuned" and .result.value == 0.3' tune hold-watch key=duration value=0.3`, `$V capture RUN_DIR holdwatch-tuned --expect '.outcome == "hold" and ([.trace[].summary] | join(" ") | test("holds at 0.30 s"))' hold tab seconds=0.45`, and `$V drive RUN_DIR tune hold-watch reset=true`.
- **Smoke.** Run `$V capture RUN_DIR holdwatch-smoke --expect '.ok and .result.failed == 0 and ([.result.drives[] | select(.kind == "tab") | .outcome] == ["hold"])' smoke`.
- **Proof.** `RUN_DIR/holdwatch-hold.json` carries the watch's events, `touch`, `held`, and `release` with "hold", and the HoldWatch interaction's summary.

## Gotchas

- The tab's own drag and tap are the app's and never move in the simulator: the stand-in speaks for the watch's drag alone, so "the control's" means the watch let the pinch go, not that the surface resized.
- `seconds` defaults to the watch's duration plus 0.2 s; a tuning left set changes it.
- The outcome "the control's" holds an apostrophe, which a single-quoted filter can't: match it with `startswith("the control")`.
- `hold` with no target holds the surface when one is on screen: name `tab`.
