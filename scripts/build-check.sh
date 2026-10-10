#!/bin/bash
# Compile-check GestureLab, and with it GestureKit's visionOS side, from the
# command line, without touching Xcode's DerivedData or leaving
# LaunchServices registrations behind.
#
#   scripts/build-check.sh           # GestureLab, visionOS Simulator SDK, Debug
#   scripts/build-check.sh release   # the same, in the Release configuration
#
# Builds the Debug configuration unless `release` is given, which compiles
# out what's DEBUG-only, so code that left `#if DEBUG` is checked without
# it, and checks the built app carries none of GestureKit's automation. Builds into a throwaway DerivedData directory with code signing off,
# so it needs no development team, prints the compiler diagnostics from
# this repository's sources and the result line, then unregisters any
# built .app from LaunchServices and deletes the directory, whatever the
# outcome. Running xcodebuild against Xcode's own DerivedData poisons the
# bundle Xcode launches next; see AGENTS.md.
set -euo pipefail

usage="usage: scripts/build-check.sh [debug|release]"
case "${1:-debug}" in
  debug) configuration=Debug ;;
  release) configuration=Release ;;
  *) echo "$usage" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
derived="$(mktemp -d "${TMPDIR:-/tmp}/gesturekit-build-check.XXXXXX")"
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister

cleanup() {
  find "$derived" -type d -name '*.app' -prune -print 2>/dev/null | while IFS= read -r app; do
    "$lsregister" -u "$app" >/dev/null 2>&1 || true
  done
  rm -rf "$derived"
}
trap cleanup EXIT

log="$derived/build.log"
status=0
xcodebuild \
  -project "$root/Lab/GestureLab.xcodeproj" \
  -scheme GestureLab \
  -configuration "$configuration" \
  -destination 'generic/platform=visionOS Simulator' \
  -derivedDataPath "$derived" \
  CODE_SIGNING_ALLOWED=NO \
  build >"$log" 2>&1 || status=$?

# Diagnostics from this repository's sources, the app's and the package's,
# deduplicated.
grep -E '^/.*: (error|warning): ' "$log" | grep -F "$root/" | sort -u || true
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "$log" || tail -n 20 "$log"

# A release build carries none of the debug-only automation or the hand's
# stand-in: no symbol of theirs, and none of the launch's switches.
if [ "$status" -eq 0 ] && [ "$configuration" = Release ]; then
  app="$(find "$derived/Build/Products" -type d -name 'GestureLab.app' -prune -print -quit)"
  found=""
  while IFS= read -r binary; do
    file "$binary" | grep -q 'Mach-O' || continue
    found+="$( { nm "$binary" 2>/dev/null; strings -a "$binary" 2>/dev/null; } | grep -E 'GestureAutomation|PinchStandIn|GESTUREKIT_AUTOMATION|GestureKitAutomation' | head -n 3 || true)"
  done < <(find "$app" -type f -perm -u+x)
  if [ -n "$found" ]; then
    echo "The release build carries debug-only automation:" >&2
    echo "$found" >&2
    exit 1
  fi
  echo "The release build carries no automation."
fi
exit "$status"
