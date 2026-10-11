# Pluck

A pinch held still a quarter second on an item of the lab's scrolling grid
lifts it, and the grid's scroll stops under it. Lifted, it stays in the
grid on a sticky tether, following the hand a little, until the hand has
gone 2.5 cm and two tenths of a second have passed; then it breaks free,
spawns a card in the room at the hand, and settles back into the grid. From
the spawn the same pinch carries the card 1:1 by the carry's rules, and
lets it go where it was carried; the card keeps a grab handle of its own,
and the grid's scroll comes back on as the pinch lets go. Let go short of
the break-free, the item settles, and nothing spawns.

## Sub-features

- `pluck-tap` a quick pinch on an item is its tap, and the lab hears which item, by its title or its id.
- `pluck-sticky` a lift whose hand stops short of the break-free distance holds on its tether and settles back, spawning nothing.
- `pluck-break-free` a lift pulled past the break-free distance spawns a card at the hand, and the item settles.
- `pluck-handoff` the same pinch carries what spawned 1:1 with the hand and lets it go where it was carried.
- `pluck-scroll-back` once the pinch lets go, the grid's scroll is on again, nothing lifted, and no alarm raised.
- `pluck-card-handle` the card stands with a grab handle of its own, which carries it afterwards.
- `pluck-not-made` an item the grid hasn't made is refused, saying to scroll to it.

## How to get to it (user POV)

- Choose Pluck in the lab window's station list; the grid opens in a window of its own, the trace in an ornament beside it.
- Pinch an item and hold still until it lifts; pull toward you, or any way but along the scroll, and let go where the card should stand.
- Pinch an item and let go at once to tap it.
- Pinch the pill under a card standing in the room to carry the card again.

## Driving it with gesturekit-drive

Preconditions:

- A run launched with `--station pluck`, or `$V drive RUN_DIR station pluck`, and `$V doctor RUN_DIR` passing.
- The grid at its top, items 1 to 12 made: `$V drive RUN_DIR targets` lists them.
- No cards in the room: `.app.lab.pluck.cards == 0` in `$V drive RUN_DIR state --json`, else relaunch with `$V drive RUN_DIR relaunch --station pluck`.

- **Tap.** Tap item 2. Run `$V capture RUN_DIR pluck-tap --expect '.outcome == "tapped" and .result.item == "item 2" and .app.lab.pluck.lastTapped == 2' tap "item 2"`. Then by its id: `$V capture RUN_DIR pluck-tap-by-id --expect '.outcome == "tapped" and .result.item == "item 5" and .app.lab.pluck.lastTapped == 5' tap 5`.
- **Sticky stage.** Hold item 8 until it lifts, pull 8 mm toward you, short of the break-free, and let go. Run `$V capture RUN_DIR pluck-sticky --expect '.outcome == "lifted" and .result.lifted and .result.settled and (.result.reported | index("spawned") | not) and .app.lab.pluck.cards == 0 and ([.trace[].events[] | select(.name == "settle") | .detail] | join(" ") | test("not broken free"))' pluck "item 8" pull=0,0,0.008`. The trace's `held` lines say how far the hand went of what it needs ("… pt of 18.1 to break free"), and its `settle` line "held to 10.9 pt of 18.1, not broken free".
- **Break free, hand off, and let go.** Hold item 6 until it lifts, pull 5 cm toward you, carry what spawns 10 cm right and 5 cm up, and let go. Run `$V capture RUN_DIR pluck-break-free --expect '.outcome == "spawned" and (.result.reported | index("spawned") < index("settled")) and (.result.spawnedAt | length == 3) and .app.lab.pluck.cards == 1 and ([.trace[] | select(.gesture == "Pluck" and .outcome == "pull")] | length == 1)' pluck "item 6" carry=0.1,0.05,0`. The trace's `broke free` line says how far and where it spawned.
- **The hand-off carries 1:1.** Check the same answer: the middle went from where it spawned exactly as far as the hand moved since, and was let go there. Run `jq -e '([.result.carriedTo, .result.spawnedAt, ([.events[] | select(.event == "carried")] | last | (.lastDetail // .detail).handMoved)] | transpose | all(.[0] - .[1] - .[2] | fabs < 0.002)) and .result.releasedAt == .result.carriedTo' RUN_DIR/pluck-break-free.json`. `handMoved` is in the room's meters, the window's points scaled up, so it's larger than the `carry` asked for.
- **The scroll comes back.** Check the same answer: `jq -e '.result.grid.scrollIsHeldOff == false and .result.grid.lifted == null and .result.grid.alarms == 0 and ([.events[] | select(.source == "grid") | .event] == ["scroll held off", "scroll on again"])' RUN_DIR/pluck-break-free.json`.
- **The card's own handle.** Read its id, then carry the card by it. Run `handle=$($V drive RUN_DIR targets --json | jq -r '.result.handles[0].id')` and `$V capture RUN_DIR pluck-card-handle --expect '.outcome == "carried" and ([.result.stood, .result.asked] | transpose | all(.[0] - .[1] | fabs < 0.002))' carry "$handle" by=0.1,0.05,0`. `targets --json` lists one handle per card in the room.
- **An item not made.** Run `$V capture RUN_DIR pluck-not-made --expect '.ok == false and (.error | test("scroll to it"))' pluck "item 9999"`.
- **Proof.** `RUN_DIR/pluck-break-free.png` shows the grid, "Scroll on", and "1 card"; the `.json`, `.check.txt`, and `.state.json` beside it carry the proof.

## Gotchas

- The break-free distance is the hand's 2.5 cm, but the grid's window is drawn larger in the simulator (the trace's `tuning` line: "725 pt to a meter of the hand, the window at 1.88×"), and the automation turns its meters into 1,360 points a meter. So the break-free comes at about 1.3 cm of a `pull`: keep a sticky pull under 1 cm, and a break-free pull at 5 cm. Read the threshold from the `tuning` line's "breaks free at 2.5 cm, N pt".
- `pull` with no `carry` still spawns at 5 cm; the carry then has nothing to move, and `carriedTo` equals `spawnedAt`.
- `hold` defaults to the item's hold plus 0.1 s, and the pull waits to see the lift; `hold=0` is a yank, the grid's scroll ([Scroll first](./scroll-first.md)).
- A lazy grid makes only the items near its view: scroll to an item first (`scroll to="item 41"`) or the pluck is refused.
- Cards stay until the lab relaunches, and each adds a handle to `targets`; count before and after, or relaunch for a clean baseline.
- `outcome` is told from the adapters' events, so it reads the same with tracing off; the `trace` checks need tracing on, as a launch leaves it.
- Whether SwiftUI lets the item's drag in mid-pinch, and whether the real pan takes the pinch after, is the headset's to say: the stand-in speaks for both.
