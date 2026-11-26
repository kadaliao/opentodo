#!/bin/bash
# Builds the app: ./scripts/build.sh macos | ios
#   macos → apple/.derived/Build/Products/Debug/OpenTodo.app
#   ios   → apple/.derived/Build/Products/Debug-iphonesimulator/OpenTodo.app (simulator)
# Generates the project first. Extra arguments go to xcodebuild.
# OT_CONFIGURATION=Release builds the release configuration instead (into
# Release/ and Release-iphonesimulator/). Only to see that it compiles: the
# release build is the real app (com.liaoxingyi.opentodo) and running it
# opens the person's real database and App Group container.
# OT_ALLOW_PROVISIONING=1 lets Xcode change the developer account (register
# App IDs, the App Group, profiles): only for signing for a device, and only
# when the account's owner means to (docs/apple.md, 系统集成). Simulator and
# macOS debug builds don't need it.
# OT_UNSIGNED=1 builds without signing (macOS: no sandbox, no App Group):
# for a session that can't reach the login keychain (over ssh it is locked
# and codesign fails with errSecInternalComponent). Debug runs with
# -OTDatabasePath don't need the signature.
set -euo pipefail
APPLE="$(cd "$(dirname "$0")/.." && pwd)"
platform="${1:-}"; shift || true
config="${OT_CONFIGURATION:-Debug}"
case "$config" in Debug|Release) ;; *) echo "OT_CONFIGURATION must be Debug or Release" >&2; exit 2 ;; esac
case "$platform" in
  macos) destination="generic/platform=macOS" ;;
  ios)   destination="generic/platform=iOS Simulator" ;;
  *) echo "usage: $0 macos|ios [xcodebuild args…]" >&2; exit 2 ;;
esac
"$APPLE/scripts/generate.sh" >/dev/null
cd "$APPLE"
log="$APPLE/.derived/build-$platform$([ "$config" = Debug ] || echo "-$config").log"
mkdir -p "$APPLE/.derived"
provisioning=()
if [ -n "${OT_ALLOW_PROVISIONING:-}" ]; then provisioning=(-allowProvisioningUpdates); fi
if [ -n "${OT_UNSIGNED:-}" ]; then provisioning+=(CODE_SIGNING_ALLOWED=NO); fi
if xcodebuild -project OpenTodo.xcodeproj -scheme OpenTodo -configuration "$config" \
     -destination "$destination" -derivedDataPath "$APPLE/.derived" \
     ${provisioning[@]+"${provisioning[@]}"} "$@" build >"$log" 2>&1; then
  grep -E "warning:" "$log" | grep -v -e "^ld: warning" -e "Metadata extraction skipped" | sort -u | head -20 || true
  case "$platform" in
    macos) echo "$APPLE/.derived/Build/Products/$config/OpenTodo.app" ;;
    ios)   echo "$APPLE/.derived/Build/Products/$config-iphonesimulator/OpenTodo.app" ;;
  esac
else
  grep -E "error:|BUILD FAILED" "$log" | sort -u | head -40 >&2
  echo "build failed; full log: $log" >&2
  exit 1
fi
