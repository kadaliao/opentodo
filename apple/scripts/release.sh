#!/bin/bash
# Builds the macOS app for release: signed with Developer ID, notarized and
# stapled, as a disk image and a zip, into apple/build/release/.
#
#   ./scripts/release.sh            # build, sign, notarize
#   ./scripts/release.sh --publish  # …then tag, GitHub Release, Homebrew tap
#
# The version is MARKETING_VERSION in project.yml; the build number is the
# commit count, so it only grows. --publish wants a clean tree that's on
# origin/main and a `## [<version>]` section in CHANGELOG.md (the release
# notes); it tags v<version>, creates the GitHub Release with the files and
# asks the tap (kadaliao/homebrew-tap) to pick the new version up.
#
# Notarizing takes one of (as suck-my-disk's release script):
#   - an App Store Connect API key: NOTARY_KEY (the .p8 file), NOTARY_KEY_ID
#     and NOTARY_ISSUER. When none of these is set they're read from
#     ~/.appstoreconnect/notary.env, if it exists. Nothing in a keychain.
#   - notarytool's keychain profile: NOTARY_PROFILE, with NOTARY_KEYCHAIN
#     naming the keychain file it is in when that isn't the login keychain.
# NOTARIZE=0 skips it (a local try only; such a build isn't published).
# SIGN_IDENTITY: the certificate. Steps in docs/apple.md (发布).
set -euo pipefail
APPLE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$APPLE/.." && pwd)"
cd "$APPLE"

publish=""
case "${1:-}" in
  "") ;;
  --publish) publish=1 ;;
  *) echo "usage: $0 [--publish]" >&2; exit 2 ;;
esac

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: "?([^"]+)"?$/\1/p' project.yml)
BUILD=$(git rev-list --count HEAD)
TAG="v$VERSION"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Xingyi Liao (HMDAVG9B8J)}"
OUT="$APPLE/build/release"
STAGE="$OUT/stage"
DERIVED="$APPLE/build/ReleaseData"
APP="$STAGE/OpenTodo.app"
[ -n "$VERSION" ] || { echo "no MARKETING_VERSION in project.yml" >&2; exit 1; }

NOTARY_ENV="$HOME/.appstoreconnect/notary.env"
if [ -z "${NOTARY_PROFILE:-}${NOTARY_KEY:-}" ] && [ "${NOTARIZE:-1}" != 0 ] && [ -r "$NOTARY_ENV" ]; then
  # shellcheck disable=SC1090
  . "$NOTARY_ENV"
fi
NOTARY=()
if [ "${NOTARIZE:-1}" = 0 ]; then
  :
elif [ -n "${NOTARY_KEY:-}" ]; then
  : "${NOTARY_KEY_ID:?NOTARY_KEY needs NOTARY_KEY_ID}" "${NOTARY_ISSUER:?NOTARY_KEY needs NOTARY_ISSUER}"
  [ -r "$NOTARY_KEY" ] || { echo "can't read NOTARY_KEY: $NOTARY_KEY" >&2; exit 1; }
  NOTARY=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
elif [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY=(--keychain-profile "$NOTARY_PROFILE")
  if [ -n "${NOTARY_KEYCHAIN:-}" ]; then NOTARY+=(--keychain "$NOTARY_KEYCHAIN"); fi
fi
if [ ${#NOTARY[@]} -gt 0 ]; then
  # Before the build, not minutes into it: the credentials must work now.
  xcrun notarytool history "${NOTARY[@]}" >/dev/null || { echo "notarytool can't sign in with these credentials" >&2; exit 1; }
elif [ -n "$publish" ]; then
  echo "a published build is notarized: give notarytool credentials (see the top of this script)" >&2; exit 1
else
  echo "▸ not notarizing: don't hand this build out"
fi

notes() {
  # The CHANGELOG section of $VERSION, without its heading.
  awk -v v="$VERSION" '
    $0 ~ "^## \\[" { if (on) exit; if (index($0, "## [" v "]") == 1) { on = 1; next } }
    on { print }
  ' "$ROOT/CHANGELOG.md" | sed -e '/./,$!d'
}

if [ -n "$publish" ]; then
  # Everything checked before the long build.
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || { echo "the tree has changes: commit them first" >&2; exit 1; }
  git -C "$ROOT" fetch -q origin
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD isn't origin/main: push first" >&2; exit 1; }
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && [ "$(git rev-parse "$TAG^{commit}")" != "$(git rev-parse HEAD)" ]; then
    echo "$TAG is already another commit: raise MARKETING_VERSION in project.yml" >&2; exit 1
  fi
  if gh release view "$TAG" >/dev/null 2>&1; then echo "the release $TAG is already out" >&2; exit 1; fi
  [ -n "$(notes)" ] || { echo "CHANGELOG.md has no section ## [$VERSION]" >&2; exit 1; }
fi

echo "▸ OpenTodo $VERSION ($BUILD)"
rm -rf "$OUT"
mkdir -p "$STAGE"
"$APPLE/scripts/generate.sh" >/dev/null
packages=()
[ -d "$APPLE/.derived/SourcePackages" ] && packages=(-clonedSourcePackagesDirPath "$APPLE/.derived/SourcePackages")
# Developer ID, no provisioning profile: the macOS App Group carries the
# team prefix, so none is needed. No get-task-allow (notarization refuses it).
if ! xcodebuild -project OpenTodo.xcodeproj -scheme OpenTodo -configuration Release \
     -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" ${packages[@]+"${packages[@]}"} \
     CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" PROVISIONING_PROFILE_SPECIFIER= \
     OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
     MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
     build >"$OUT/build.log" 2>&1; then
  grep -E "error:|BUILD FAILED" "$OUT/build.log" | sort -u | head -40 >&2
  echo "build failed; full log: $OUT/build.log" >&2
  exit 1
fi
ditto "$DERIVED/Build/Products/Release/OpenTodo.app" "$APP"
# No runnable copy left behind: it is the real app (the person's database).
rm -rf "$DERIVED/Build/Products/Release/OpenTodo.app"
codesign --verify --deep --strict "$APP"
for bundle in "$APP" "$APP"/Contents/PlugIns/*.appex; do
  codesign -d --entitlements - --xml "$bundle" 2>/dev/null | grep -q "HMDAVG9B8J.group.com.liaoxingyi.opentodo<" \
    || { echo "$(basename "$bundle"): not in the App Group" >&2; exit 1; }
done

if [ ${#NOTARY[@]} -gt 0 ]; then
  echo "▸ notarize the app"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" "${NOTARY[@]}" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute "$APP"
  rm "$OUT/notarize.zip"
fi

# The disk image: the app and a shortcut to Applications beside it.
echo "▸ dmg"
DMG="$OUT/OpenTodo-$VERSION.dmg"
mkdir -p "$OUT/dmg"
ditto "$APP" "$OUT/dmg/OpenTodo.app"
ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -quiet -volname "OpenTodo $VERSION" -srcfolder "$OUT/dmg" -fs APFS -format ULFO -ov "$DMG"
rm -rf "$OUT/dmg"
codesign --sign "$IDENTITY" --timestamp "$DMG"
if [ ${#NOTARY[@]} -gt 0 ]; then
  echo "▸ notarize the dmg"
  xcrun notarytool submit "$DMG" "${NOTARY[@]}" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature "$DMG"
fi

ditto -c -k --keepParent "$APP" "$OUT/OpenTodo-$VERSION.zip"
# Only the archives stay: a loose copy would show in Spotlight and 打开方式,
# and launch with the real data.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$APP" 2>/dev/null || true
"$LSREGISTER" -u "$DERIVED/Build/Products/Release/OpenTodo.app" 2>/dev/null || true
rm -rf "$STAGE"
(cd "$OUT" && shasum -a 256 ./*.dmg ./*.zip | sed 's| \./| |' > SHA256SUMS)
ls -lh "$OUT"

[ -n "$publish" ] || exit 0

echo "▸ publish $TAG"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  git tag -a "$TAG" -m "OpenTodo $VERSION"
fi
git push -q origin "$TAG"
notes > "$OUT/notes.md"
gh release create "$TAG" --verify-tag --title "OpenTodo $VERSION" --notes-file "$OUT/notes.md" \
  "$OUT/OpenTodo-$VERSION.dmg" "$OUT/OpenTodo-$VERSION.zip" "$OUT/SHA256SUMS"
# The tap checks every 6 hours anyway; this makes it now.
gh workflow run bump.yml -R kadaliao/homebrew-tap || echo "(the tap's bump didn't start; it runs every 6 hours anyway)" >&2
echo "▸ done: $(gh release view "$TAG" --json url -q .url)"
