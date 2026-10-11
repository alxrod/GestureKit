#!/bin/bash
# launch-lab.sh: a verify-gesturelab run. Makes its own simulator,
# "GestureLab-Verify-RUN", picks a free port from 48800, writes the run's
# facts to artifacts/verify-gesturelab/RUN/run.env, and launches GestureLab
# in it through scripts/gesture-drive.sh up, which builds the lab and
# gesturekit-drive into build/verify-gesturelab/RUN/. Prints the run's folder,
# RUN_DIR, which every later step names:
#
#   .agents/skills/verify-gesturelab/scripts/launch-lab.sh [--station ID] [--run RUN]
#   .agents/skills/verify-gestures/scripts/gesture-verify.sh doctor  RUN_DIR
#   .agents/skills/verify-gestures/scripts/gesture-verify.sh capture RUN_DIR LABEL [--expect JQ] COMMAND [ARGS…]
#   .agents/skills/verify-gestures/scripts/gesture-verify.sh drive   RUN_DIR COMMAND [ARGS…]
#   .agents/skills/verify-gestures/scripts/gesture-verify.sh down    RUN_DIR
#
# The station is pluck unless --station says trace-check, carry-and-face,
# below-the-gaze, or press; RUN is the time unless given. It builds, so run it
# through your build lock where agents share the machine.
set -euo pipefail

root="$(cd "$(dirname "$0")/../../../.." && pwd)"
# shellcheck source=../../verify-gestures/scripts/gesture-verify.sh
. "$root/.agents/skills/verify-gestures/scripts/gesture-verify.sh"

station=pluck
run="$(date +%Y%m%d-%H%M%S)"
while [ $# -gt 0 ]; do
  case "$1" in
    --station) station="${2:?--station needs an id}"; shift 2 ;;
    --run) run="${2:?--run needs a name}"; shift 2 ;;
    *) die "launch-lab.sh takes --station ID and --run RUN; not $1" ;;
  esac
done
[[ "$run" =~ ^[A-Za-z0-9._-]+$ ]] || die "a run's name is letters, digits, dots, dashes, and underscores"

dir="$root/artifacts/verify-gesturelab/$run"
work="$root/build/verify-gesturelab/$run"
name="GestureLab-Verify-$run"
[ ! -e "$dir" ] || die "$dir exists: choose another run name"
port="$(free_port)"
udid="$(make_simulator "$name")"
mkdir -p "$dir"
write_env "$dir/run.env" \
  "RUN=$run" "GESTURE_RUN_MADE=1" \
  "GESTURE_SIM=$name" "GESTURE_SIM_NAME=$name" "GESTURE_SIM_UDID=$udid" "GESTUREKIT_SIMULATOR=$udid" \
  "GESTUREKIT_AUTOMATION_PORT=$port" "GESTURE_APP_BUNDLE=net.alexbrodriguez.gesturelab" \
  "GESTURE_DRIVE_WORK=$work" "GESTURE_VERIFY_WORK=$work" \
  "GESTURE_APP_PATH=$work/DerivedData/Build/Products/Debug-xrsimulator/GestureLab.app" \
  "GESTURE_DRIVE=$root/scripts/gesture-drive.sh" \
  "GESTURE_REPO=$root" "GESTURE_BUILD_PATHS=Sources Lab Package.swift" \
  "GESTURE_LOG_PREDICATE=subsystem BEGINSWITH \"net.alexbrodriguez.gesturekit\"" \
  "GESTURE_BUILT_FROM=$(built_from "$root" "Sources Lab Package.swift")"

say "launching GestureLab on the $station station in $name, port $port; RUN_DIR is $dir"
say "should the launch fail: .agents/skills/verify-gestures/scripts/gesture-verify.sh down $dir"
(
  set -a
  # shellcheck disable=SC1091
  . "$dir/run.env"
  set +a
  "$root/scripts/gesture-drive.sh" up --station "$station"
) 2>&1 | tee "$dir/launch.log"
echo "$dir"
