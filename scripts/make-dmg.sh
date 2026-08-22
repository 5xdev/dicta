#!/bin/bash
# Build the drag-to-Applications disk image users download for a fresh install.
#
#   scripts/make-dmg.sh build/Build/Products/Release/Dicta.app dist/Dicta-0.1.0.dmg [--timestamp]
#
# Deliberately plain: a volume named "Dicta" holding Dicta.app and a symlink to /Applications, built with hdiutil
# alone. No background art or icon positioning — those need `create-dmg` or Finder AppleScript, both of which are
# flaky on headless CI runners, and neither changes what the user has to do.
#
# The image is signed with the identity read off the app (a disk image carries its own signature and, once
# notarized, its own stapled ticket); ad-hoc apps yield none, so their image is left unsigned. What a DMG does and
# does not change about Gatekeeper, and why it must stay out of the appcast directory, is in README → Distribution
# and README → Releasing.
set -euo pipefail

APP=${1:?usage: $0 path/to/Dicta.app path/to/out.dmg [--timestamp]}
OUT=${2:?usage: $0 path/to/Dicta.app path/to/out.dmg [--timestamp]}
shift 2

TIMESTAMP=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timestamp) TIMESTAMP=(--timestamp); shift ;;
    *)           echo "make-dmg: unknown argument '$1'" >&2; exit 1 ;;
  esac
done

[[ -d "$APP" ]] || { echo "make-dmg: no app bundle at $APP" >&2; exit 1; }

STAGE=$(mktemp -d)
MOUNT=$(mktemp -d)
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || hdiutil detach "$MOUNT" -force -quiet 2>/dev/null || true
  rm -rf "$STAGE" "$MOUNT"
}
trap cleanup EXIT

# ditto, not cp -R: preserves the signature, extended attributes and any stapled notarization ticket.
ditto "$APP" "$STAGE/Dicta.app"
ln -s /Applications "$STAGE/Applications"
find "$STAGE" -name .DS_Store -delete

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"                       # hdiutil refuses to overwrite

# HFS+, not APFS: nothing here needs APFS and an APFS image mounts on fewer systems.
# ULFO (LZFSE) compresses smaller and faster than UDZO and is supported far below this app's deployment target.
# Retried because hdiutil intermittently fails with "Resource busy" on CI when an earlier image is still detaching.
for attempt in 1 2 3; do
  if hdiutil create -volname Dicta -srcfolder "$STAGE" -fs HFS+ -format ULFO -quiet "$OUT"; then
    break
  fi
  [[ $attempt -lt 3 ]] || { echo "make-dmg: hdiutil create failed after 3 attempts" >&2; exit 1; }
  echo "make-dmg: hdiutil create failed (attempt $attempt), retrying…" >&2
  rm -f "$OUT"
  sleep 5
done

IDENTITY=$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)   # leaf certificate's common name
if [[ -n "$IDENTITY" ]]; then
  # ${arr[@]+…}: expanding an empty array is an "unbound variable" error under set -u in bash 3.2 (/bin/bash).
  codesign --force --sign "$IDENTITY" ${TIMESTAMP[@]+"${TIMESTAMP[@]}"} "$OUT"
  codesign --verify --verbose=2 "$OUT"
else
  echo "make-dmg: $APP is ad-hoc signed — leaving the image unsigned"
fi

# Verify what the user will actually mount rather than what we think we staged: a copy that damaged the signature,
# or an image whose contents are not the app we were pointed at, has to fail here and not on someone's Mac.
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" -quiet "$OUT"
[[ -d "$MOUNT/Dicta.app" ]] || { echo "make-dmg: mounted image has no Dicta.app" >&2; exit 1; }
[[ "$(readlink "$MOUNT/Applications")" == /Applications ]] \
  || { echo "make-dmg: mounted image has no /Applications symlink" >&2; exit 1; }
codesign --verify --strict --deep "$MOUNT/Dicta.app"   # nested Sparkle.framework must survive the copy too
EXPECTED=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ACTUAL=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$MOUNT/Dicta.app/Contents/Info.plist")
[[ "$EXPECTED" == "$ACTUAL" ]] \
  || { echo "make-dmg: image contains version $ACTUAL, expected $EXPECTED" >&2; exit 1; }

# stat, not du: codesign leaves the image sparse and du reports the allocated blocks, not the download size.
echo "→ $OUT ($(awk -v b="$(stat -f%z "$OUT")" 'BEGIN { printf "%.1f MB", b / 1048576 }'), Dicta $ACTUAL)"
