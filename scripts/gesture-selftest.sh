#!/bin/bash
# Drive every gesture GestureLab has, in a fresh simulator of its own, with no
# hand, and check what each came to; exit non-zero at the first that doesn't.
#
#   scripts/gesture-selftest.sh
#
# It deletes any simulator named "GestureLab-Selftest" (GESTURE_SIM), makes
# it afresh, builds the lab and gesturekit-drive into build/gesture-selftest/
# (GESTURE_DRIVE_WORK), launches the lab with GestureKit's automation on
# 127.0.0.1:48766 (GESTUREKIT_AUTOMATION_PORT), and drives each station: a
# pluck, a tap, scrolls, a lift let go, a yank that stays a scroll, a lift
# given back to the scroll, and the card carried, on the grid; a tap, a drag,
# a flick and its coast, a pickup and carry, holds, a drag across, and a
# tuning on the press's surface and tab; carries, one stopped short of the
# head, on the panels; placements below two gazes; the smoke on every
# station; and a script run at launch. Whatever happens, it then deletes the
# simulator and the build, unless GESTURE_SELFTEST_KEEP=1. Run it through
# your build lock where agents share the machine: it builds.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GESTURE_SIM="${GESTURE_SIM:-GestureLab-Selftest}"
export GESTUREKIT_AUTOMATION_PORT="${GESTUREKIT_AUTOMATION_PORT:-48766}"
export GESTURE_DRIVE_WORK="${GESTURE_DRIVE_WORK:-$root/build/gesture-selftest}"
drive="$root/scripts/gesture-drive.sh"
jq=/usr/bin/jq
checks=0
answer=""

finish() {
  local status=$?
  if [ "${GESTURE_SELFTEST_KEEP:-0}" != 1 ]; then
    "$drive" down >/dev/null 2>&1 || true
  fi
  if [ "$status" -eq 0 ]; then
    echo "gesture-selftest: all $checks checks passed"
  else
    echo "gesture-selftest: FAILED after $checks checks passed" >&2
  fi
}
trap finish EXIT

# Runs one driver command and keeps its whole answer: run pluck "item 6".
run() {
  answer="$("$drive" "$1" --json "${@:2}" || true)"
}

# Checks the last answer against a jq expression, saying what it checks.
check() {
  local what="$1" filter="$2"
  if ! $jq -e "$filter" >/dev/null 2>&1 <<<"$answer"; then
    echo "FAIL  $what" >&2
    echo "      expected: $filter" >&2
    $jq -c '{ok, outcome, error, result, events: [.events[]? | "\(.source) \(.target) \(.event)"]}' <<<"$answer" >&2 2>/dev/null || echo "$answer" >&2
    exit 1
  fi
  checks=$((checks + 1))
  echo "ok    $what"
}

# Runs a command and checks its answer: expect "what" 'filter' command args…
expect() {
  local what="$1" filter="$2"
  shift 2
  run "$@"
  check "$what" "$filter"
}

echo "gesture-selftest: a fresh simulator, $GESTURE_SIM, and a fresh build"
"$drive" down >/dev/null 2>&1 || true
"$drive" up --station pluck

# The grid: pluck, tap, scroll, and the pinches that stay its scroll.
expect "the pluck station lists its grid and the items it has made" \
  '.ok and (.result.grids | length == 1) and (.result.items | length > 4)' targets
expect "a tap on an item is its tap, and the app hears it" \
  '.outcome == "tapped" and .app.lab.pluck.lastTapped == 2' tap "item 2"
expect "a pinch on an item that scrolls first is the grid's scroll, and the grid moves" \
  '.outcome == "scrolled" and .result.scrolledBy >= 590 and .result.itemOutcome == "stayed down" and .result.gridNow.alarms == 0' \
  scroll by=600 on="item 3"
expect "scrolling to an item further down makes it" \
  '.outcome == "scrolled" and .result.madeItem == "item 41"' scroll to="item 41"
expect "scrolling to the top lands at the top" \
  '.outcome == "scrolled" and .result.to == .result.gridNow.minOffset' scroll to=top
expect "a hold and a pull spawn what the item pulls out, carried and let go, the scroll on again" \
  '.outcome == "spawned" and (.result.releasedAt | length == 3) and .result.grid.scrollIsHeldOff == false and .result.grid.alarms == 0 and .app.lab.pluck.cards == 1 and ([.trace[] | select(.gesture == "Pluck" and .outcome == "pull")] | length == 1)' \
  pluck "item 6" carry=0,0,0.05
expect "a hold let go without moving lifts the item and settles it, spawning nothing" \
  '.outcome == "lifted" and .result.settled and (.result.reported | index("spawned") | not)' \
  pluck "item 7" pull=0,0,0
expect "a yank before the hold stays the grid's scroll" \
  '.outcome == "stayed down" and .result.lifted == false' \
  pluck "item 8" hold=0 pull=0,0,0.08 pullTime=0.1
expect "a lifted pinch moved along the scroll is given back to it, spawning nothing" \
  '.outcome == "lifted" and .result.settled and (.result.reported | index("spawned") | not) and ([.trace[].summary] | join(" ") | test("given back"))' \
  pluck "item 9" pull=0,0.03,0
run targets
handle="$($jq -r '.result.handles[0].id // empty' <<<"$answer")"
check "the card that spawned has a grab handle of its own" '.result.handles | length == 1'
expect "the card is carried by its handle where the hand puts it" \
  '.outcome == "carried" and ([.result.stood, .result.asked] | transpose | all(.[0] - .[1] | fabs < 0.002))' \
  carry "$handle" by=0.1,0.05,0
expect "nothing is left under way" '.outcome == "idle"' wait
expect "the trace has every pluck" '.ok and ([.result.interactions[] | select(.gesture == "Pluck")] | length >= 5)' trace gesture=Pluck
expect "the grid's smoke passes" '.ok and .result.failed == 0 and .result.passed >= 3' smoke

# The press: a surface and a tab.
expect "the press station is chosen" '.outcome == "chosen"' station press
expect "the press lists its surface and its tab" \
  '([.result.surfaces[].id] == ["surface"]) and ([.result.tabs[].id] == ["tab"])' targets
expect "a tap on the surface drops a marker where it touched" \
  '.outcome == "tap" and (.result.tappedAt - 0.4 | fabs < 0.01) and .app.lab.press.markers == 1' tap surface at=0.4
expect "a drag along scrolls the playhead with the hand, and comes to rest" \
  '.outcome == "scroll" and .app.lab.press.coasting == false and (.app.lab.press.playhead - 0.5 | fabs < 0.02)' drag surface along=0.2
expect "a flick coasts on" '.outcome == "scroll" and .result.letGo == true and .app.lab.press.coasting == true' flick surface along=-0.15
expect "the coast comes to rest" '.outcome == "idle" and .app.lab.press.coasting == false' wait
expect "held still, the surface picks up, and moved, it's carried" \
  '.outcome == "carry" and (.result.reported | index("pickUp")) and ([.app.lab.press.center, [0.1, 1.35, -0.95]] | transpose | all(.[0] - .[1] | fabs < 0.01))' \
  pickup surface by=0.1,0.05,0.05
expect "held a full second, the surface holds" '.outcome == "hold" and (.result.reported | index("fireHold"))' hold surface
expect "a drag across the surface does nothing" '.outcome == "drag across"' drag surface along=0 across=0.1
expect "a still hold on the tab holds, beside its own gestures" '.outcome == "hold"' hold tab
expect "let go before its hold, the tab holds nothing" '.outcome == "let go before its hold"' hold tab seconds=0.2
expect "moved first, the tab's pinch is the control's" '.outcome == "the control'"'"'s"' hold tab moveFirst=0.02,0,0
expect "tuning the press's pickup sets it as its slider would" \
  '.outcome == "tuned" and .result.value == 0.3 and .result.tuning == "GestureLab.press"' tune press key=pickUpDelay value=0.3
expect "the tuned pickup comes sooner, and held still without moving it's put down" \
  '.outcome == "pickup, put down" and ([.trace[].summary] | join(" ") | test("picks up at 0.3 s"))' pickup surface by=0,0,0
expect "the press's tuning goes back to its defaults" '.outcome == "tuned" and .result.tuned == {}' tune press reset=true
expect "the press's smoke passes" '.ok and .result.failed == 0 and .result.passed == 2' smoke

# The panels: carried, and stood clear of the head.
expect "the carry and face station is chosen" '.outcome == "chosen"' station carry-and-face
expect "a panel is carried by its handle where the hand puts it" \
  '.outcome == "carried" and ([.result.stood, .result.asked] | transpose | all(.[0] - .[1] | fabs < 0.002))' carry panel-b by=0.1,0,0.2
expect "a panel carried into the head stops 0.3 m from it" \
  '.outcome == "carried" and (.result.fromTheHead - 0.3 | fabs < 0.002)' carry panel-a to=0,1.6,-0.1
expect "the panels' smoke passes" '.ok and .result.failed == 0 and .result.passed == 6' smoke

# Below the gaze: placed for the untracked head and for a head turned.
expect "the below-the-gaze station is chosen" '.outcome == "chosen"' station below-the-gaze
expect "the panel stands 0.7 m out, 20° below the untracked head's gaze" \
  '.outcome == "placed" and (.result.distance - 0.7 | fabs < 0.001) and (.result.belowTheGaze - 20 | fabs < 0.1)' place
expect "for a head turned 30° right and 40° down, it stands below that gaze, tilted up 60°" \
  '.outcome == "placed" and (.result.gazeAcross - 30 | fabs < 0.1) and (.result.tilt - 60 | fabs < 0.1)' \
  place gaze-panel 'head={"at":[0,1.6,0],"yaw":30,"pitch":-40}'
expect "the placed panel is carried by its pill's handle" '.outcome == "carried"' carry gaze-panel by=0,0.1,0
expect "the below-the-gaze smoke passes" '.ok and .result.failed == 0 and .result.passed == 3' smoke

# What can't be done says so.
expect "an unknown command is refused, naming the commands" '.ok == false and (.error | test("help"))' pluk
expect "an item no grid has made is refused, saying to scroll to it" \
  '.ok == false and (.error | test("scroll"))' pluck "item 9999"

# A script, run at launch, through -GestureKitAutomationScript.
script="$GESTURE_DRIVE_WORK/selftest-script.json"
cat >"$script" <<'JSON'
[
  {"command": "station", "id": "press"},
  {"command": "tap", "surface": "surface", "at": 0.5},
  {"command": "hold", "tab": "tab"},
  {"command": "station", "id": "pluck"},
  {"command": "pluck", "item": "item 4"}
]
JSON
answer="$("$drive" script "$script" || true)"
check "a script run at launch answers each command" \
  '.finished and .failed == 0 and ([.results[].outcome] == ["chosen", "tap", "hold", "chosen", "spawned"])'
expect "after its script, the app still answers" '.ok and .outcome == "ready"' targets
