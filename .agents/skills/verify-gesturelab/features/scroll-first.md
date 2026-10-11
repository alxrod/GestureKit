# Scroll first

On the pluck station's grid, a pinch is the grid's scroll unless it's a
hold: one the scroll view scrolls with, whose offset moves, or that moves
10 pt along the scroll or 40 pt any way before its quarter-second hold is
the grid's scroll for good, and lifts nothing, even yanked toward you. A
lifted item moved mostly along the scroll settles and gives the pinch back
to the scroll, so an item can't be pulled out up or down. The grid scrolls
by any amount, to its top or end, or until an item is made.

## Sub-features

- `scroll-by` a pinch moved along the grid scrolls it, and its offset moves as far.
- `scroll-on-item` a pinch begun on an item that scrolls first stays the grid's scroll; the item stays down.
- `scroll-to-item` scrolling on makes an item further down.
- `scroll-ends` the grid scrolls to its top and to its end.
- `scroll-yank` a pinch yanked toward you before its hold stays the grid's scroll, lifting nothing.
- `scroll-given-back` a lifted item moved along the scroll settles and gives the pinch back, spawning nothing.
- `scroll-smoke` the grid's smoke: scrolled and back, its first item plucked.

## How to get to it (user POV)

- Choose Pluck in the lab window's station list; the grid opens in a window of its own.
- Pinch anywhere on the grid, an item or between items, and drag up or down.
- Pinch an item and pull toward you at once, before it lifts.
- Pinch an item, hold until it lifts, then move up or down.

## Driving it with gesturekit-drive

Preconditions:

- A run on the pluck station, `$V doctor RUN_DIR` passing, the grid at its top (`targets` shows "scrolled 0 of … pt").
- Tracing on, as a launch leaves it, for the give-back's trace check.

- **Scroll by.** Drag the grid 600 pt down. Run `$V capture RUN_DIR scroll-by --expect '.outcome == "scrolled" and (.result.scrolledBy - 600 | fabs < 10) and .result.gridNow.alarms == 0 and .result.gridNow.phase == "idle"' scroll by=600`.
- **Back to the top.** Run `$V capture RUN_DIR scroll-top --expect '.outcome == "scrolled" and .result.to == .result.gridNow.minOffset' scroll to=top`.
- **A pinch on an item that scrolls.** Pinch item 3 and drag 600 pt. Run `$V capture RUN_DIR scroll-on-item --expect '.outcome == "scrolled" and .result.scrolledBy >= 590 and .result.itemOutcome == "stayed down" and .result.gridNow.alarms == 0' scroll by=600 on="item 3"`. The answer's `events` have `pluck item 3 stayed down`.
- **To an item further down.** Run `$V capture RUN_DIR scroll-to-item --expect '.outcome == "scrolled" and .result.madeItem == "item 41"' scroll to="item 41"`.
- **To the end, and back.** Run `$V capture RUN_DIR scroll-end --expect '.outcome == "scrolled" and .result.to == .result.gridNow.maxOffset' scroll to=end`, then `$V drive RUN_DIR scroll to=top --brief`.
- **A yank stays the scroll.** Pinch item 8 and pull it 8 cm toward you in a tenth of a second, holding none. Run `$V capture RUN_DIR scroll-yank --expect '.outcome == "stayed down" and .result.lifted == false and (.result.reported | index("spawned") | not) and ([.events[] | select(.event == "stayed down") | .detail] | join(" ") | test("a scroll"))' pluck "item 8" hold=0 pull=0,0,0.08 pullTime=0.1`. The event's detail says how far it moved before the hold: "moved 63.4 pt before the hold, its stillness 40.0 pt: a scroll".
- **A lift given back to the scroll.** Hold item 9 until it lifts, then move 3 cm up. Run `$V capture RUN_DIR scroll-given-back --expect '.outcome == "lifted" and .result.settled and (.result.reported | index("spawned") | not) and .result.grid.scrollIsHeldOff == false and ([.trace[].summary] | join(" ") | test("given back"))' pluck "item 9" pull=0,0.03,0`. The trace's `settle` line: "moved 10.5 pt along the scroll and 0.0 pt across it and in depth: given back to the scroll".
- **Smoke.** Run `$V capture RUN_DIR scroll-smoke --expect '.ok and .result.failed == 0 and .result.passed >= 3' smoke`.
- **Proof.** `RUN_DIR/scroll-given-back.png` shows the grid with "Scroll on"; `scroll-given-back.json` and its `.check.txt` carry the proof.

## Gotchas

- `scroll` says the scroll view's phases for UIKit's pan and moves the content through SwiftUI's scroll position; whether the real pan takes a pinch, or takes one given back mid-pinch, only the headset can say.
- A pinch on an item scrolls the grid under it, so later items' titles change place; name items by title, not by place, and scroll back to the top before a recipe that expects items 1 to 12.
- `pull=0,0.03,0` is up, along the grid's vertical scroll; with the give-back switched off (`givesLiftBackToScroll`), the same pull does something else, so put tunings back first (`tune pluck reset=true`).
- `scrolledBy` can fall a point or two short of what was asked at an end; assert within a margin, or against `minOffset` and `maxOffset`.
- A scroll that never comes to rest leaves `phase` other than `idle`; `$V drive RUN_DIR wait` waits until nothing is under way.
