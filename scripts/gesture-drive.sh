#!/bin/bash
# Drive GestureLab's gestures in a simulator of its own, with no hand, through
# GestureKit's automation and the package's driver, gesturekit-drive.
#
#   scripts/gesture-drive.sh up [--station ID] [--no-build]
#       Creates and boots the simulator "GestureLab-Auto" (GESTURE_SIM), builds
#       the lab into build/gesture-drive/ (never Xcode's DerivedData) and the
#       driver beside it, installs the lab, and launches it with its
#       automation on, on 127.0.0.1:48765 (GESTUREKIT_AUTOMATION_PORT), and
#       waits until it's ready.
#   scripts/gesture-drive.sh targets | smoke | state | trace | wait
#   scripts/gesture-drive.sh pluck "item 7" pull=0,0,0.06
#   scripts/gesture-drive.sh station press
#   scripts/gesture-drive.sh screenshot [FILE.png]
#       Any of gesturekit-drive's commands, on the lab's simulator and port;
#       `scripts/gesture-drive.sh help` lists them. Add --json to a command
#       to print the app's whole answer, --brief for its outcome and result.
#   scripts/gesture-drive.sh script FILE.json
#       Relaunches the lab running FILE's commands at launch, through
#       -GestureKitAutomationScript, and prints their results.
#   scripts/gesture-drive.sh relaunch [--station ID]
#   scripts/gesture-drive.sh down
#       Quits the lab, deletes the simulator, unregisters the build, and
#       deletes build/gesture-drive/.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
sim_name="${GESTURE_SIM:-GestureLab-Auto}"
port="${GESTUREKIT_AUTOMATION_PORT:-48765}"
work="${GESTURE_DRIVE_WORK:-$root/build/gesture-drive}"
bundle=net.alexbrodriguez.gesturelab
derived="$work/DerivedData"
app="$derived/Build/Products/Debug-xrsimulator/GestureLab.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

say() { echo "gesture-drive: $*" >&2; }

device() {
  xcrun simctl list devices -j | /usr/bin/jq -r --arg name "$sim_name" \
    '[.devices[][] | select(.name == $name and .isAvailable)][0].udid // empty'
}

ensure_device() {
  local udid
  udid="$(device)"
  if [ -z "$udid" ]; then
    local runtime type
    runtime="$(xcrun simctl list runtimes -j | /usr/bin/jq -c '[.runtimes[] | select((.platform == "visionOS" or .platform == "xrOS") and .isAvailable)] | last // empty')"
    [ -n "$runtime" ] || { say "no visionOS simulator runtime is installed"; exit 1; }
    type="$(/usr/bin/jq -r '.supportedDeviceTypes[0].identifier // empty' <<<"$runtime")"
    runtime="$(/usr/bin/jq -r '.identifier' <<<"$runtime")"
    say "creating the simulator $sim_name"
    udid="$(xcrun simctl create "$sim_name" "$type" "$runtime")" || { say "couldn't create the simulator $sim_name"; exit 1; }
  fi
  if ! xcrun simctl list devices -j | /usr/bin/jq -e --arg udid "$udid" '.devices[][] | select(.udid == $udid and .state == "Booted")' >/dev/null; then
    say "booting $sim_name"
    xcrun simctl boot "$udid" 2>/dev/null || true
  fi
  xcrun simctl bootstatus "$udid" -b >/dev/null || { say "the simulator $sim_name didn't boot"; exit 1; }
  echo "$udid"
}

tool() {
  local bin
  bin="$(swift build --package-path "$root" --scratch-path "$work/tool" --show-bin-path)/gesturekit-drive"
  if [ ! -x "$bin" ]; then
    build_tool
  fi
  echo "$bin"
}

build_tool() {
  say "building gesturekit-drive"
  swift build --package-path "$root" --scratch-path "$work/tool" --product gesturekit-drive >"$work/tool-build.log" 2>&1 \
    || { tail -n 20 "$work/tool-build.log" >&2; exit 1; }
}

build_lab() {
  local udid="$1"
  say "building the lab into $derived"
  local status=0
  xcodebuild \
    -project "$root/Lab/GestureLab.xcodeproj" \
    -scheme GestureLab \
    -configuration Debug \
    -destination "platform=visionOS Simulator,id=$udid" \
    -derivedDataPath "$derived" \
    CODE_SIGNING_ALLOWED=NO \
    build >"$work/build.log" 2>&1 || status=$?
  if [ "$status" -ne 0 ]; then
    grep -E '^/.*: error: ' "$work/build.log" | sort -u >&2 || true
    tail -n 5 "$work/build.log" >&2
    exit "$status"
  fi
}

launch() {
  local udid="$1" station="$2"
  local arguments=(-labTracing on)
  [ -n "$station" ] && arguments+=(-station "$station")
  "$(tool)" --device "$udid" --port "$port" --timeout 120 launch "$bundle" -- "${arguments[@]}"
}

command="${1:-help}"
[ $# -gt 0 ] && shift

case "$command" in
  up)
    station=""
    build=1
    while [ $# -gt 0 ]; do
      case "$1" in
        --station) station="$2"; shift 2 ;;
        --no-build) build=0; shift ;;
        *) say "up takes --station ID and --no-build"; exit 64 ;;
      esac
    done
    mkdir -p "$work"
    udid="$(ensure_device)"
    if [ "$build" -eq 1 ] || [ ! -d "$app" ]; then build_lab "$udid"; fi
    build_tool
    xcrun simctl install "$udid" "$app"
    launch "$udid" "$station"
    ;;
  relaunch)
    station=""
    [ "${1:-}" = "--station" ] && station="${2:-}"
    launch "$(ensure_device)" "$station"
    ;;
  script)
    file="${1:?script needs a JSON file of commands}"
    udid="$(ensure_device)"
    "$(tool)" --device "$udid" --timeout 180 launch "$bundle" --script "$file" -- -labTracing on
    ;;
  down)
    udid="$(device)"
    if [ -n "$udid" ]; then
      xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
      xcrun simctl shutdown "$udid" 2>/dev/null || true
      xcrun simctl delete "$udid"
      say "deleted the simulator $sim_name"
    fi
    if [ -d "$derived" ]; then
      find "$derived" -type d -name '*.app' -prune -print 2>/dev/null | while IFS= read -r built; do
        "$lsregister" -u "$built" >/dev/null 2>&1 || true
      done
    fi
    rm -rf "$work"
    ;;
  help|-h|--help)
    sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
    echo
    "$(tool)" help
    ;;
  *)
    udid="$(device)"
    [ -n "$udid" ] || { say "no simulator $sim_name: run scripts/gesture-drive.sh up first"; exit 1; }
    # The driver's options, such as --json, right after the command.
    options=(--device "$udid" --port "$port")
    while [ $# -gt 0 ] && [[ "$1" == --* ]]; do
      case "$1" in
        --timeout) options+=("$1" "${2:?--timeout needs seconds}"); shift 2 ;;
        *) options+=("$1"); shift ;;
      esac
    done
    exec "$(tool)" "${options[@]}" "$command" "$@"
    ;;
esac
