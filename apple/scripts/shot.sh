#!/bin/bash
# Screenshots of the Debug app (docs/apple.md §5):
#
#   ./scripts/shot.sh ios <simulator name> <route> <out.png>
#   ./scripts/shot.sh macos <route> <out.png>
#
# <route> is an -OTOpen route (OpenTodoUI/App/DebugLaunch.swift), e.g.
# home, smart:today, list:<id>. Each shot starts from a fresh temporary
# database filled with -OTSeed demo.
#
# Environment:
#   OT_NO_BUILD=1         use the last build instead of building first
#   OT_SEED=<name>        seed to fill the database with (default demo; empty: none)
#   OT_APPEARANCE=dark    dark mode (iOS: the simulator's; macOS: the app's)
#   OT_SIM_TYPE=<type>    device type for a new simulator (default iPhone 18 Pro)
#   OT_QUICKADD=<text>    type this into the quick-add field (-OTQuickAdd)
#   OT_TIME=HH:MM         the app's clock stands still at this time today (-OTTime)
#   OT_MAC_METHOD=…       macOS: `window` screencaptures the app's main window
#                         (needs the screen recording permission for the
#                         terminal); `app` captures all the app's windows
#                         with ScreenCaptureKit, so popovers and sheets come
#                         out over the window (same permission); `self` has
#                         the app draw its own window into a PNG
#                         (-OTSnapshot; no permission, but materials, lists
#                         and forms come out empty). Default: window if the
#                         permission is there, else self.
#   OT_WINDOW_SIZE=WxH    macOS: the window's content size (default 1180x760)
#   OT_INTERFACE_SIZE=…   macOS: 界面大小 for the run (-OTInterfaceSize): small,
#                         standard, large, extraLarge (default: what's stored)
#   OT_SHOT_WINDOW=settings  macOS, method app: capture the Settings window
#                         (the settings[:<tab>] routes) instead of the main one
#   OT_VISIBLE=1          macOS: leave the windows where they can be seen (by
#                         default they go behind the desktop, -OTHiddenWindows)
#
# macOS: the app is started in the background (`open -g`), so it doesn't
# take the front from whatever is being used, its windows go behind the
# desktop picture (-OTHiddenWindows: nobody sees them come and go; both
# capture methods still get them), and it quits after the shot.
#
# The simulator is created if no device has that name, and left booted.
# Paths are worked out from this script's own place, so it runs unchanged in
# any worktree.
set -euo pipefail
APPLE="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID=com.liaoxingyi.opentodo.dev
seed="${OT_SEED-demo}"
run_id="ot-shot-$$-$(date +%s)"

usage() {
  echo "usage: $0 ios <simulator name> <route> <out.png>" >&2
  echo "       $0 macos <route> <out.png>" >&2
  exit 2
}

abs() { case "$1" in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }

build() {
  if [ -z "${OT_NO_BUILD:-}" ]; then "$APPLE/scripts/build.sh" "$1" >/dev/null; fi
}

# Takes screenshots with "$@" (which must write $out) until two in a row are
# the same, so animations and loading have finished.
settle() {
  local last="" now i
  for i in $(seq 1 15); do
    "$@"
    now="$(shasum "$out" | cut -d' ' -f1)"
    [ "$now" = "$last" ] && return 0
    last="$now"
    sleep 1
  done
  echo "warning: the screen kept changing; kept the last shot" >&2
}

# ---- iOS ----

sim_udid() { # name → udid of an available device with that name
  xcrun simctl list devices available -j | python3 -I -c '
import json, sys
name = sys.argv[1]
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["name"] == name:
            print(d["udid"]); sys.exit(0)
' "$1"
}

sim_create() { # name → udid of a new device on the newest iOS runtime
  local runtime type
  read -r runtime type < <(xcrun simctl list runtimes available -j | python3 -I -c '
import json, sys
want = sys.argv[1]
ios = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
if not ios: sys.exit("no iOS simulator runtime installed")
r = ios[-1]
types = [t for t in r["supportedDeviceTypes"] if t["productFamily"] == "iPhone"]
pick = next((t for t in types if t["name"] == want), None) or types[-1]
print(r["identifier"], pick["identifier"])
' "${OT_SIM_TYPE:-iPhone 18 Pro}")
  xcrun simctl create "$1" "$type" "$runtime"
}

shot_ios() {
  local name="$1" route="$2"
  build ios
  local app="$APPLE/.derived/Build/Products/Debug-iphonesimulator/OpenTodo.app"
  local udid; udid="$(sim_udid "$name")"
  if [ -z "$udid" ]; then udid="$(sim_create "$name")"; echo "created simulator $name ($udid)" >&2; fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  xcrun simctl ui "$udid" appearance "${OT_APPEARANCE:-light}"
  xcrun simctl status_bar "$udid" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 2>/dev/null || true
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl install "$udid" "$app"
  local args=(-OTDatabasePath "$run_id/opentodo.sqlite" -OTOpen "$route")
  [ -n "$seed" ] && args+=(-OTSeed "$seed")
  [ -n "${OT_QUICKADD:-}" ] && args+=(-OTQuickAdd "$OT_QUICKADD")
  [ -n "${OT_TIME:-}" ] && args+=(-OTTime "$OT_TIME")
  xcrun simctl launch "$udid" "$BUNDLE_ID" "${args[@]}" >/dev/null
  sleep 2
  settle xcrun simctl io "$udid" screenshot --type=png "$out" >/dev/null 2>&1
  xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
}

# ---- macOS ----

app_pid=""
stop_app() {
  if [ -n "$app_pid" ]; then
    kill "$app_pid" 2>/dev/null || true
    # Not a child when started with `open`: wait for it to go.
    local i
    for i in $(seq 1 20); do kill -0 "$app_pid" 2>/dev/null || break; sleep 0.25; done
    kill -9 "$app_pid" 2>/dev/null || true
    app_pid=""
  fi
}
trap stop_app EXIT

shot_macos() {
  local route="$1"
  build macos
  local app="$APPLE/.derived/Build/Products/Debug/OpenTodo.app"
  local tmp="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp"
  local args=(-OTDatabasePath "$run_id/opentodo.sqlite" -OTOpen "$route")
  [ -n "$seed" ] && args+=(-OTSeed "$seed")
  [ -n "${OT_APPEARANCE:-}" ] && args+=(-OTAppearance "$OT_APPEARANCE")
  [ -n "${OT_QUICKADD:-}" ] && args+=(-OTQuickAdd "$OT_QUICKADD")
  [ -n "${OT_TIME:-}" ] && args+=(-OTTime "$OT_TIME")
  [ -n "${OT_INTERFACE_SIZE:-}" ] && args+=(-OTInterfaceSize "$OT_INTERFACE_SIZE")
  [ -z "${OT_VISIBLE:-}" ] && args+=(-OTHiddenWindows yes)
  args+=(-OTWindowSize "${OT_WINDOW_SIZE:-1180x760}" -ApplePersistenceIgnoreState YES)

  # An unsigned build (OT_UNSIGNED=1 ./scripts/build.sh macos) isn't
  # sandboxed: its temporary directory is the user's, not the container's.
  if ! codesign -d --entitlements - "$app" 2>/dev/null | grep -q app-sandbox; then
    tmp="$(getconf DARWIN_USER_TEMP_DIR)"; tmp="${tmp%/}"
  fi

  local helper="$APPLE/.derived/tools/windowid"
  if [ ! -x "$helper" ] || [ "$APPLE/scripts/windowid.swift" -nt "$helper" ]; then
    mkdir -p "$(dirname "$helper")"
    xcrun swiftc -O "$APPLE/scripts/windowid.swift" -o "$helper" 2>/dev/null
  fi
  local method="${OT_MAC_METHOD:-}"
  if [ -z "$method" ]; then
    if "$helper" --can-capture; then method=window; else method=self; fi
  fi
  [ "$method" = self ] && args+=(-OTSnapshot "$run_id/shot.png")
  # In the background: -g keeps the front where it is (the person may be
  # using the machine), -n a new instance, -F no restored windows.
  open -g -n -F "$app" --args "${args[@]}"
  local i
  for i in $(seq 1 40); do
    app_pid="$(pgrep -f -- "$run_id/opentodo.sqlite" | head -1 || true)"
    [ -n "$app_pid" ] && break; sleep 0.25
  done
  if [ -z "$app_pid" ]; then echo "the app didn't start" >&2; exit 1; fi
  if [ "$method" = self ]; then
    # The app draws its window into a PNG in its temporary directory and quits.
    for i in $(seq 1 40); do kill -0 "$app_pid" 2>/dev/null || break; sleep 1; done
    stop_app
    if [ ! -s "$tmp/$run_id/shot.png" ]; then echo "the app wrote no snapshot" >&2; exit 1; fi
    mv "$tmp/$run_id/shot.png" "$out"
  else
    local wid=""
    for i in $(seq 1 40); do wid="$("$helper" "$app_pid" || true)"; [ -n "$wid" ] && break; sleep 0.5; done
    if [ -z "$wid" ]; then echo "no window found" >&2; exit 1; fi
    sleep 2
    if [ "$method" = app ]; then
      settle "$helper" --shot "$app_pid" "$out" "${OT_SHOT_WINDOW:-main}"
    else
      settle screencapture -x -o -l"$wid" "$out"
    fi
    stop_app
  fi
  rm -rf "${tmp:?}/$run_id"
}

case "${1:-}" in
  ios)   [ $# -eq 4 ] || usage; out="$(abs "$4")"; shot_ios "$2" "$3" ;;
  macos) [ $# -eq 3 ] || usage; out="$(abs "$3")"; shot_macos "$2" ;;
  *) usage ;;
esac
echo "$out"
