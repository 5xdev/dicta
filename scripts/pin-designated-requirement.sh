#!/bin/bash
# Re-sign the *outer* app bundle with a team-pinned designated requirement.
#
#   scripts/pin-designated-requirement.sh build/Build/Products/Release/Dicta.app [extra codesign flags, e.g. --timestamp]
#
# Why: codesign's default requirement for Apple Development certs pins the individual leaf certificate, so a
# renewed cert (or a CI build signed with a different cert from the same team) would reset every user's TCC grants
# and Keychain ACL. Pinning to the team (leaf[subject.OU]) survives that — README → Signing has the full story.
#
# Why here and not in Xcode: Xcode signs the product *after* every build phase, so a post-build script's signature
# is overwritten; and putting `-r` in OTHER_CODE_SIGN_FLAGS leaks the app's identifier into the requirement Xcode
# stamps on the embedded Sparkle.framework, which then fails `codesign --verify --strict --deep`.
#
# Only the outer bundle is re-signed (never --deep — Sparkle explicitly warns against it): nested code keeps its own
# valid signature and the outer seal covers it. Ad-hoc signed bundles are left alone (no cert chain to anchor to).
# Must run before notarization: re-signing changes the cdhash.
set -euo pipefail

APP=${1:?usage: $0 path/to/Dicta.app [codesign flags…]}
shift

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")
SIGNATURE=$(codesign -dvv "$APP" 2>&1)
TEAM=$(sed -n 's/^TeamIdentifier=//p' <<<"$SIGNATURE")
IDENTITY=$(sed -n 's/^Authority=//p' <<<"$SIGNATURE" | head -1)   # leaf certificate's common name

if [[ -z "$TEAM" || "$TEAM" == "not set" || -z "$IDENTITY" ]]; then
  echo "pin-designated-requirement: $APP is ad-hoc signed — leaving codesign's default requirement"
  exit 0
fi

REQUIREMENT="=designated => identifier \"$BUNDLE_ID\" and anchor apple generic and certificate leaf[subject.OU] = \"$TEAM\""
codesign --force --sign "$IDENTITY" --preserve-metadata=entitlements --options runtime "$@" -r "$REQUIREMENT" "$APP"
codesign --verify --strict "$APP"
codesign -d --requirements - "$APP" 2>&1 | grep '^designated'
