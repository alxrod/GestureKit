#!/bin/bash
# gesture-verify.sh: an app on GestureKit, launched in a visionOS simulator of
# its own with its gestures' automation on, checked, driven through
# gesturekit-drive, its evidence captured, and cleaned up. The verify-gestures
# skill's helper; every run keeps its facts in RUN_DIR/run.env and its
# evidence beside them, and cleanup never removes RUN_DIR.
#
#   gesture-verify.sh up --scheme SCHEME (--project P.xcodeproj | --workspace W.xcworkspace)
#                        --bundle-id ID [--run NAME] [--port N] [--gesturekit DIR] [-- APP ARGUMENTS…]
#       Makes the simulator "GestureKit-Verify-NAME", builds the scheme's Debug
#       build for it into a throwaway DerivedData (signing off), installs it,
#       builds gesturekit-drive from GestureKit's checkout (the build's
#       SourcePackages/checkouts/GestureKit, or --gesturekit for a local
#       package), and launches the app with automation on, on a free port from
#       48800. RUN_DIR is artifacts/verify-gestures/NAME (GESTURE_EVIDENCE_ROOT
#       changes artifacts/verify-gestures); the build goes in
#       $TMPDIR/gesture-verify/NAME (GESTURE_VERIFY_WORK_ROOT). Prints RUN_DIR.
#   gesture-verify.sh doctor RUN_DIR
#       Read-only: the run's simulator booted, the app running in it, the
#       port listened on by that app and no other, the installed build the
#       one built, the checkout unchanged since, and the automation answering
#       ready on that port. Exits 1 at anything wrong.
#   gesture-verify.sh drive RUN_DIR COMMAND [ARGS…]
#       Any gesturekit-drive command against the run's app.
#   gesture-verify.sh capture RUN_DIR LABEL [--expect JQ_FILTER] COMMAND [ARGS…]
#       Runs the command with --json and keeps, in RUN_DIR: LABEL.json (the
#       answer: ok, outcome, result, events, trace, app), LABEL.trace.txt (each
#       interaction's summary), LABEL.check.txt (the filter and PASS or FAIL),
#       LABEL.state.json (everything registered, after), LABEL.png (what the
#       simulator shows, after), LABEL.console.txt (GestureKit's log lines
#       meanwhile), and a line in captures.txt. Exits 1 if the check failed,
#       or, with no check, if the command did; a check may expect a refusal.
#   gesture-verify.sh down RUN_DIR
#       Quits the app and deletes the run's simulator, only the one the run
#       made, by its UDID and name, and the run's build folder; keeps RUN_DIR
#       and lists what's in it.
#
# Sourced rather than run, it defines its functions and runs nothing, for a
# repository's own launcher (GestureKit's verify-gesturelab does so).
set -euo pipefail

JQ="$(command -v jq || echo /usr/bin/jq)"
gesture_verify_lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

say() { echo "gesture-verify: $*" >&2; }
die() { say "$*"; exit 1; }

# A free port for the automation, from a random start in 48800-48899, so two
# runs launched together rarely try the same one.
free_port() {
  local start=$((RANDOM % 100)) offset port
  for offset in $(seq 0 99); do
    port=$((48800 + (start + offset) % 100))
    if [ -z "$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null)" ]; then
      echo "$port"
      return 0
    fi
  done
  die "no free port in 48800-48899"
}

# Makes and boots a visionOS simulator named $1, on the newest visionOS
# runtime, refusing a name a simulator already has: a run drives and deletes
# only what it made. Prints its UDID.
make_simulator() {
  local name="$1" runtime type udid
  if xcrun simctl list devices -j | "$JQ" -e --arg name "$name" '[.devices[][] | select(.name == $name)] | length > 0' >/dev/null; then
    die "a simulator named $name already exists; a run makes its own, so choose another run name"
  fi
  runtime="$(xcrun simctl list runtimes -j | "$JQ" -c '[.runtimes[] | select((.platform == "visionOS" or .platform == "xrOS") and .isAvailable)] | last // empty')"
  [ -n "$runtime" ] || die "no visionOS simulator runtime is installed"
  type="$("$JQ" -r '.supportedDeviceTypes[0].identifier // empty' <<<"$runtime")"
  runtime="$("$JQ" -r '.identifier' <<<"$runtime")"
  udid="$(xcrun simctl create "$name" "$type" "$runtime")" || die "couldn't create the simulator $name"
  say "made the simulator $name ($udid)"
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null || die "the simulator $name didn't boot"
  echo "$udid"
}

# What a checkout's build came from: its commit and a digest of what differs
# from it, under the paths given ($2, words, "." unless given), leaving out
# artifacts/. "unknown" outside git.
built_from() {
  local repo="$1" paths="${2:-.}" head digest
  # shellcheck disable=SC2086
  head="$(git -C "$repo" rev-parse --short=12 HEAD 2>/dev/null)" || { echo unknown; return 0; }
  # shellcheck disable=SC2086
  digest="$( { git -C "$repo" diff HEAD -- $paths ':(exclude)artifacts'; git -C "$repo" ls-files --others --exclude-standard -- $paths ':(exclude)artifacts'; } | shasum | cut -c1-12)"
  echo "$head+$digest"
}

# Appends KEY=VALUE lines to the run's env file ($1), quoted for the shell.
write_env() {
  local file="$1" pair
  shift
  for pair in "$@"; do
    printf '%s=%q\n' "${pair%%=*}" "${pair#*=}" >>"$file"
  done
}

# Loads a run's facts from RUN_DIR/run.env, exported for the driver.
load_run() {
  local dir="${1:?give the RUN_DIR, the folder under artifacts/ that launching printed}"
  [ -f "$dir/run.env" ] || die "no run.env in $dir: is it a run's folder?"
  GESTURE_RUN_DIR="$(cd "$dir" && pwd)"
  set -a
  # shellcheck disable=SC1091
  . "$GESTURE_RUN_DIR/run.env"
  set +a
  export GESTURE_RUN_DIR
}

# The app's process in the run's simulator, or nothing.
app_pid() {
  xcrun simctl spawn "$GESTURE_SIM_UDID" launchctl list 2>/dev/null \
    | awk -v label="UIKitApplication:$GESTURE_APP_BUNDLE" 'index($3, label) == 1 && $1 != "-" { print $1; exit }'
}

cmd_up() {
  local scheme="" project="" workspace="" bundle="" run="" port="" gesturekit="" app_arguments=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --scheme) scheme="${2:?}"; shift 2 ;;
      --project) project="${2:?}"; shift 2 ;;
      --workspace) workspace="${2:?}"; shift 2 ;;
      --bundle-id) bundle="${2:?}"; shift 2 ;;
      --run) run="${2:?}"; shift 2 ;;
      --port) port="${2:?}"; shift 2 ;;
      --gesturekit) gesturekit="${2:?}"; shift 2 ;;
      --) shift; app_arguments=("$@"); break ;;
      *) die "up takes --scheme, --project or --workspace, --bundle-id, --run, --port, --gesturekit, and -- with the app's arguments; not $1" ;;
    esac
  done
  [ -n "$scheme" ] && [ -n "$bundle" ] && { [ -n "$project" ] || [ -n "$workspace" ]; } \
    || die "up needs --scheme, --bundle-id, and --project or --workspace"
  run="${run:-$(date +%Y%m%d-%H%M%S)}"
  [[ "$run" =~ ^[A-Za-z0-9._-]+$ ]] || die "a run's name is letters, digits, dots, dashes, and underscores"
  local evidence_root="${GESTURE_EVIDENCE_ROOT:-artifacts/verify-gestures}"
  mkdir -p "$evidence_root"
  local dir
  dir="$(cd "$evidence_root" && pwd)/$run"
  [ ! -e "$dir" ] || die "$dir exists: choose another run name"
  local work="${GESTURE_VERIFY_WORK_ROOT:-${TMPDIR:-/tmp}/gesture-verify}/$run"
  local repo
  repo="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  port="${port:-$(free_port)}"
  local name="GestureKit-Verify-$run" udid
  udid="$(make_simulator "$name")"
  mkdir -p "$dir" "$work"
  write_env "$dir/run.env" \
    "RUN=$run" "GESTURE_RUN_MADE=1" \
    "GESTURE_SIM_NAME=$name" "GESTURE_SIM_UDID=$udid" "GESTUREKIT_SIMULATOR=$udid" \
    "GESTUREKIT_AUTOMATION_PORT=$port" "GESTURE_APP_BUNDLE=$bundle" \
    "GESTURE_VERIFY_WORK=$work" "GESTURE_REPO=$repo" "GESTURE_BUILD_PATHS=." \
    "GESTURE_LOG_PREDICATE=subsystem BEGINSWITH \"net.alexbrodriguez.gesturekit\""
  write_env "$dir/run.env" "GESTURE_BUILT_FROM=$(built_from "$repo" .)"

  say "building $scheme into $work/DerivedData"
  local container=(-project "$project")
  [ -n "$workspace" ] && container=(-workspace "$workspace")
  local status=0
  xcodebuild "${container[@]}" -scheme "$scheme" -configuration Debug \
    -destination "platform=visionOS Simulator,id=$udid" \
    -derivedDataPath "$work/DerivedData" CODE_SIGNING_ALLOWED=NO \
    build >"$work/build.log" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    grep -E '^/.*: error: ' "$work/build.log" | sort -u >&2 || true
    tail -n 5 "$work/build.log" >&2
    die "the build failed; its log is $work/build.log; clean up with: $0 down $dir"
  fi
  local app="" candidate
  while IFS= read -r candidate; do
    if [ "$(plutil -extract CFBundleIdentifier raw -o - "$candidate/Info.plist" 2>/dev/null)" = "$bundle" ]; then
      app="$candidate"
      break
    fi
  done < <(find "$work/DerivedData/Build/Products" -maxdepth 2 -type d -name '*.app' -prune 2>/dev/null)
  [ -n "$app" ] || die "the build made no app with the bundle id $bundle"
  xcrun simctl install "$udid" "$app"

  gesturekit="${gesturekit:-$work/DerivedData/SourcePackages/checkouts/GestureKit}"
  [ -f "$gesturekit/Package.swift" ] \
    || die "GestureKit's checkout isn't at $gesturekit; for a local package, give --gesturekit <its folder>"
  say "building gesturekit-drive from $gesturekit"
  swift build --package-path "$gesturekit" --scratch-path "$work/driver" --product gesturekit-drive >"$work/driver-build.log" 2>&1 \
    || { tail -n 20 "$work/driver-build.log" >&2; die "gesturekit-drive didn't build"; }
  local driver
  driver="$(swift build --package-path "$gesturekit" --scratch-path "$work/driver" --show-bin-path)/gesturekit-drive"
  write_env "$dir/run.env" "GESTURE_APP_PATH=$app" "GESTURE_DRIVE=$driver"

  "$driver" --device "$udid" --port "$port" --timeout 120 launch "$bundle" -- "${app_arguments[@]+"${app_arguments[@]}"}" \
    | tee "$dir/launch.log"
  echo "$dir"
}

cmd_doctor() {
  load_run "$1"
  local failed=0 line name state pid listeners installed answer
  pass() { echo "ok    $*"; }
  flag() { echo "FAIL  $*"; failed=1; }

  line="$(xcrun simctl list devices -j | "$JQ" -r --arg udid "$GESTURE_SIM_UDID" '.devices[][] | select(.udid == $udid) | "\(.name)\t\(.state)"')"
  name="${line%%$'\t'*}"
  state="${line##*$'\t'}"
  if [ -z "$line" ]; then
    flag "the run's simulator $GESTURE_SIM_UDID is gone"
  elif [ "$name" != "$GESTURE_SIM_NAME" ]; then
    flag "the simulator $GESTURE_SIM_UDID is named $name, not the run's $GESTURE_SIM_NAME"
  elif [ "$state" != Booted ]; then
    flag "the run's simulator $name is $state, not booted"
  else
    pass "the run's simulator $name ($GESTURE_SIM_UDID) is booted"
  fi

  pid="$(app_pid || true)"
  if [ -n "$pid" ]; then pass "$GESTURE_APP_BUNDLE runs in it, pid $pid"; else flag "$GESTURE_APP_BUNDLE isn't running in the run's simulator"; fi

  listeners="$(lsof -nP -iTCP:"$GESTUREKIT_AUTOMATION_PORT" -sTCP:LISTEN -t 2>/dev/null | sort -u | tr '\n' ' ')"
  if [ -z "$listeners" ]; then
    flag "nothing listens on 127.0.0.1:$GESTUREKIT_AUTOMATION_PORT"
  elif [ -n "$pid" ] && [ "${listeners% }" = "$pid" ]; then
    pass "port $GESTUREKIT_AUTOMATION_PORT is the app's own, pid $pid"
  else
    flag "port $GESTUREKIT_AUTOMATION_PORT is listened on by pid ${listeners% }, not the run's app: not ours"
  fi

  if [ -n "${GESTURE_APP_PATH:-}" ]; then
    installed="$(xcrun simctl get_app_container "$GESTURE_SIM_UDID" "$GESTURE_APP_BUNDLE" app 2>/dev/null || true)"
    if [ -n "$installed" ] && diff -rq "$installed" "$GESTURE_APP_PATH" >/dev/null 2>&1; then
      pass "the installed app is the run's build, $GESTURE_APP_PATH"
    else
      flag "the installed app isn't the run's build, $GESTURE_APP_PATH"
    fi
  fi

  local now
  now="$(built_from "$GESTURE_REPO" "${GESTURE_BUILD_PATHS:-.}")"
  if [ "$now" = "$GESTURE_BUILT_FROM" ]; then
    pass "the checkout is as it was built, $now"
  else
    flag "the checkout changed since the build ($GESTURE_BUILT_FROM, now $now): launch a new run to drive the change"
  fi

  local tries=0
  while :; do
    answer="$("$GESTURE_DRIVE" state 2>/dev/null || true)"
    if "$JQ" -e '.ok and .result.ready' >/dev/null 2>&1 <<<"$answer" || [ "$tries" -ge 10 ]; then break; fi
    tries=$((tries + 1))
    sleep 0.5
  done
  if ! "$JQ" -e '.ok' >/dev/null 2>&1 <<<"$answer"; then
    flag "the automation didn't answer state on port $GESTUREKIT_AUTOMATION_PORT"
  elif ! "$JQ" -e --argjson port "$GESTUREKIT_AUTOMATION_PORT" '.result.port == $port' >/dev/null <<<"$answer"; then
    flag "the automation answering says it serves port $("$JQ" -r '.result.port' <<<"$answer")"
  elif ! "$JQ" -e '.result.ready' >/dev/null <<<"$answer"; then
    flag "the automation answers, but hasn't settled after 5 s; busy: $("$JQ" -c '.result.busy' <<<"$answer")"
  else
    pass "the automation answers ready on port $GESTUREKIT_AUTOMATION_PORT: $("$JQ" -r '.result.targets | to_entries | map(select(.value | length > 0) | "\(.value | length) \(.key)") | join(", ")' <<<"$answer")"
    echo "      app state: $("$JQ" -c '.result.app' <<<"$answer")"
  fi
  if [ "$failed" -eq 0 ]; then echo "doctor: this run is ours, built from $GESTURE_BUILT_FROM, and worth driving"; fi
  return "$failed"
}

cmd_drive() {
  load_run "$1"
  shift
  [ $# -gt 0 ] || die "drive needs a gesturekit-drive command"
  exec "$GESTURE_DRIVE" "$@"
}

cmd_capture() {
  load_run "$1"
  local label="${2:?capture needs a label, as pluck-break-free}"
  shift 2
  [[ "$label" =~ ^[A-Za-z0-9._-]+$ ]] || die "a label is letters, digits, dots, dashes, and underscores"
  local expect=""
  if [ "${1:-}" = "--expect" ]; then
    expect="${2:?--expect needs a jq filter}"
    shift 2
  fi
  local command="${1:?capture needs a gesturekit-drive command}"
  shift
  local dir="$GESTURE_RUN_DIR" base="$GESTURE_RUN_DIR/$label"
  [ ! -e "$base.json" ] || die "$base.json exists: give this capture its own label"
  local started answer status=0 check=none ok outcome
  started="$(date '+%Y-%m-%d %H:%M:%S')"
  answer="$("$GESTURE_DRIVE" "$command" --json "$@" 2>"$base.stderr.txt")" || status=$?
  printf '%s\n' "$answer" >"$base.json"
  [ -s "$base.stderr.txt" ] || rm -f "$base.stderr.txt"
  "$JQ" -r '.trace[]?.summary' <<<"$answer" >"$base.trace.txt" 2>/dev/null || true
  ok="$("$JQ" -r '.ok // false' <<<"$answer" 2>/dev/null || echo false)"
  outcome="$("$JQ" -r '.outcome // .error // "none"' <<<"$answer" 2>/dev/null || echo "no JSON answer")"
  if [ -n "$expect" ]; then
    if "$JQ" -e "$expect" >/dev/null 2>&1 <<<"$answer"; then check=PASS; else check=FAIL; fi
    printf 'filter: %s\nverdict: %s\n' "$expect" "$check" >"$base.check.txt"
  fi
  "$GESTURE_DRIVE" state >"$base.state.json" 2>/dev/null || true
  "$GESTURE_DRIVE" screenshot "$base.png" >/dev/null 2>&1 || say "no screenshot for $label"
  xcrun simctl spawn "$GESTURE_SIM_UDID" log show --start "$started" --info --style compact \
    --predicate "${GESTURE_LOG_PREDICATE:-subsystem BEGINSWITH \"net.alexbrodriguez.gesturekit\"}" 2>/dev/null \
    | grep -v '^Timestamp' >"$base.console.txt" || true
  printf '%s\t%s\tok=%s\toutcome=%s\tcheck=%s\t%s\n' "$started" "$label" "$ok" "$outcome" "$check" "$command$(printf ' %q' "$@")" >>"$dir/captures.txt"
  echo "$label: ok=$ok outcome=$outcome check=$check → $base.{json,trace.txt,state.json,png,console.txt}"
  # With a check, its verdict decides, so an expected refusal passes;
  # without one, the command's own ok does.
  if [ -n "$expect" ]; then [ "$check" = PASS ]; else [ "$ok" = true ] && [ "$status" -eq 0 ]; fi
}

cmd_down() {
  load_run "$1"
  [ "${GESTURE_RUN_MADE:-0}" = 1 ] && [ -n "${GESTURE_SIM_UDID:-}" ] || die "run.env doesn't say this run made a simulator; deleting nothing"
  [[ "$GESTURE_SIM_NAME" == *"-Verify-$RUN" ]] || die "the run's simulator, $GESTURE_SIM_NAME, isn't named for run $RUN; deleting nothing"
  local name
  name="$(xcrun simctl list devices -j | "$JQ" -r --arg udid "$GESTURE_SIM_UDID" '.devices[][] | select(.udid == $udid) | .name')"
  if [ -z "$name" ]; then
    say "the run's simulator $GESTURE_SIM_UDID is gone already"
  elif [ "$name" != "$GESTURE_SIM_NAME" ]; then
    die "the simulator $GESTURE_SIM_UDID is named $name, not the run's $GESTURE_SIM_NAME; deleting nothing"
  else
    xcrun simctl terminate "$GESTURE_SIM_UDID" "$GESTURE_APP_BUNDLE" 2>/dev/null || true
    xcrun simctl shutdown "$GESTURE_SIM_UDID" 2>/dev/null || true
    xcrun simctl delete "$GESTURE_SIM_UDID"
    say "deleted the run's simulator $GESTURE_SIM_NAME ($GESTURE_SIM_UDID)"
  fi
  if [ -n "${GESTURE_VERIFY_WORK:-}" ] && [ -d "$GESTURE_VERIFY_WORK" ]; then
    [[ "$GESTURE_VERIFY_WORK" == */"$RUN" ]] || die "the run's build folder, $GESTURE_VERIFY_WORK, isn't named for run $RUN; leaving it"
    find "$GESTURE_VERIFY_WORK" -type d -name '*.app' -prune -print 2>/dev/null | while IFS= read -r built; do
      "$gesture_verify_lsregister" -u "$built" >/dev/null 2>&1 || true
    done
    rm -rf "$GESTURE_VERIFY_WORK"
    say "deleted the run's build folder $GESTURE_VERIFY_WORK"
  fi
  say "kept the evidence in $GESTURE_RUN_DIR:"
  ls -1 "$GESTURE_RUN_DIR" >&2
}

gesture_verify_main() {
  local command="${1:-help}"
  [ $# -gt 0 ] && shift
  case "$command" in
    up) cmd_up "$@" ;;
    doctor) cmd_doctor "$@" ;;
    drive) cmd_drive "$@" ;;
    capture) cmd_capture "$@" ;;
    down) cmd_down "$@" ;;
    help|-h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' ;;
    *) die "no command $command; $0 help lists them" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  gesture_verify_main "$@"
fi
