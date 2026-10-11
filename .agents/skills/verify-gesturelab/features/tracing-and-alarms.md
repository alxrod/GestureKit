# Tracing and alarms

Each station traces every pinch from its touch to its end: its timed
events, its outcome, and a one-line summary, shown in the station's trace
and logged as one info line for the console. A switch in the window's
toolbar turns tracing off for the whole lab, and one in each trace's header
for its station; off, the gestures work the same and record nothing. On the
pluck station, the grid's watch raises an alarm, a red line in the trace,
an info line, and a count under the grid, whenever its scroll is held with
no pinch behind it, or its safety net lets the scroll go.

## Sub-features

- `trace-in-answer` every gesture command's answer carries the interactions traced while it ran.
- `trace-read` the traces read back, all or one gesture's, newest first.
- `trace-clear` the traces cleared.
- `trace-console` each finished interaction is one info line in the console, beside the automation's own.
- `trace-off` with tracing off, gestures answer the same outcomes and trace nothing.
- `alarm-raised` a scroll held with no pinch behind it raises an alarm, counted by the grid and traced in red.

## How to get to it (user POV)

- Choose any station: its trace stands beside its tuning, the newest two interactions in full; on the pluck station, in an ornament beside the grid's window.
- Flip Tracing in the window's toolbar, or in a trace's header, to turn it off.
- On the pluck station, the status line under the grid shows the scroll's hold and the last alarm, in red.

## Driving it with gesturekit-drive

Preconditions:

- A run on the press station, tracing on as a launch leaves it, and `$V doctor RUN_DIR` passing; its state says `"tracing": true`.

- **In each answer.** Tap the surface. Run `$V capture RUN_DIR trace-in-answer --expect '(.trace | length == 1) and .trace[0].gesture == "Press" and .trace[0].outcome == "tap at 0.400 m" and (.trace[0].events | map(.name) | index("tap")) and (.trace[0].summary | test("^#[0-9]+ Press · Pinch on the surface → tap"))' tap surface at=0.4`.
- **Read back.** Hold the tab, then read the hold watch's traces. Run `$V drive RUN_DIR hold tab --brief`, then `$V capture RUN_DIR trace-read --expect '.outcome == "read" and (.result.interactions | length >= 1) and all(.result.interactions[]; .gesture == "HoldWatch")' trace gesture=HoldWatch`.
- **Cleared.** Run `$V drive RUN_DIR trace clear=true --brief`, then `$V capture RUN_DIR trace-clear --expect '.result.interactions == []' trace`.
- **In the console.** Check the tap's capture: `grep -c 'Automation: tap → tap' RUN_DIR/trace-in-answer.console.txt` and `grep -c 'Press · Pinch on the surface → tap' RUN_DIR/trace-in-answer.console.txt` each count one or more; nothing at info for each word of a drag.
- **Tracing off.** Relaunch with it off, and tap. Run `$V drive RUN_DIR launch net.alexbrodriguez.gesturelab -- -station press -labTracing off`, then `$V capture RUN_DIR trace-off --expect '.outcome == "tap" and .trace == [] and .app.lab.tracing == false' tap surface at=0.4`, then `$V drive RUN_DIR relaunch --station press`, which turns it on again.
- **An alarm.** Relaunch the pluck station with the lab's stuck load, which says a pluck's end words in the orders that once held the grid's scroll, through the real adapters. Run `$V drive RUN_DIR launch net.alexbrodriguez.gesturelab -- -station pluck -labLoad stuck -labTracing on`, wait until the grid counts an alarm, `until [ "$($V drive RUN_DIR targets --json | jq '.result.grids[0].alarms')" -gt 0 ]; do sleep 2; done`, at most a minute, then `$V capture RUN_DIR alarm-raised --expect '([.result.interactions[] | select(.alarm == true)] | length >= 1) and ([.result.interactions[] | select(.alarm == true) | .title] | join(" ") | test("Scroll held"))' trace gesture=Pluck`. The grid's `lastAlarm` reads as "Net let go: scroll held by item 3 for 1.06 s, pinch unheard for 1.06 s; …". Relaunch with `$V drive RUN_DIR relaunch --station pluck` after.
- **Proof.** `RUN_DIR/alarm-raised.state.json` has the grid's `alarms` and `lastAlarm`; `alarm-raised.png` shows the red line under the grid; `trace-in-answer.console.txt` the info lines.

## Gotchas

- `trace` reads only the traces of what's on screen: the pluck's trace isn't read from the press station, and a station switch takes its trace with it.
- Outcomes are told from what the adapters report, not from the trace, so they hold with tracing off; any check on `.trace` needs tracing on.
- A trace keeps its last 12 interactions; read or clear it before a long recipe, or assert on the command's own `.trace`, which holds only what it began.
- The stuck load runs once, a few seconds after launch, and drives the grid itself: drive nothing on the pluck station until it's done, and relaunch before the next recipe. Its steps log as "Lab load stuck: …" in the console.
- `-labTracing` is the lab's switch at launch; `$V drive RUN_DIR relaunch` launches with it on.
- The console lines come from the simulator's log, `xcrun simctl spawn <udid> log show`, at info level under the subsystem `net.alexbrodriguez.gesturekit`; the capture keeps them from its command's start.
