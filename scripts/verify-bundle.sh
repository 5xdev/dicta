#!/bin/bash
# Check that a signed Dicta.app is one users can actually install and keep their permissions on.
#
#   scripts/verify-bundle.sh path/to/Dicta.app <adhoc|apple-development|developer-id> [team]
#
# Shared by `make dist` and the CI *Verify bundle* step so the release gate has one definition.
#
# The mode is decided by the certificate, not by this script (README → Signing). What each one must satisfy:
#   adhoc              no cert chain, so there is nothing to pin and no point asking Gatekeeper — it rejects
#                      every ad-hoc build by definition.
#   apple-development  the designated requirement MUST be pinned to the team; Gatekeeper still says no, which
#                      is expected and not a failure.
#   developer-id       notarized upstream of here, so Gatekeeper accepting it IS the contract.
#
# Under GitHub Actions the failures are emitted as ::error:: annotations; locally they are plain stderr.
set -euo pipefail

APP=${1:?usage: $0 path/to/Dicta.app <adhoc|apple-development|developer-id> [team]}
MODE=${2:?usage: $0 path/to/Dicta.app <adhoc|apple-development|developer-id> [team]}
TEAM=${3:-}

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  err()  { echo "::error::$*" >&2; }
  note() { echo "::notice::$*"; }
else
  err()  { echo "verify-bundle: $*" >&2; }
  note() { echo "ℹ︎ $*"; }
fi
die() { err "$@"; exit 1; }

[[ -d "$APP" ]] || die "no app bundle at $APP"
case "$MODE" in
  adhoc|apple-development|developer-id) ;;
  *) die "unknown mode '$MODE' (expected adhoc, apple-development or developer-id)" ;;
esac

# The seal itself, then the same seal over nested code: the embedded Sparkle.framework and its XPC helpers are
# what an update runs as, so a bundle whose outer signature verifies but whose framework does not is not shippable.
codesign --verify --strict --verbose=2 "$APP"
codesign --verify --strict --deep "$APP"

# Printed, not just tested: this line is the thing that decides whether the next build counts as the same app.
# Ad-hoc bundles have no explicit requirement and codesign reports theirs commented out, as `# designated =>
# cdhash H"…"` — so match both forms, and never let a formatting difference fail the run.
codesign -d --requirements - "$APP" 2>&1 | grep -E '^#? *designated' || true

# Guards against the app's own identifier being stamped onto the embedded framework (what `-r` in
# OTHER_CODE_SIGN_FLAGS would do), which breaks `--verify --deep`. Only meaningful where there is a cert chain
# to anchor an identifier to: ad-hoc signing yields cdhash-based requirements for the app and the framework
# alike, and pin-designated-requirement.sh bows out for ad-hoc too, so there is nothing here to protect.
if [[ "$MODE" != adhoc ]]; then
  codesign -d --requirements - "$APP/Contents/Frameworks/Sparkle.framework" 2>&1 \
    | grep -q 'identifier "org.sparkle-project.Sparkle"' \
    || die "Sparkle.framework requirement does not carry its own identifier"
fi

case "$MODE" in
  developer-id)
    spctl --assess --type execute --verbose=2 "$APP"
    ;;
  apple-development)
    [[ -n "$TEAM" ]] || die "apple-development mode needs the team as the third argument"
    # Must be the team, not a specific leaf cert, or TCC grants reset whenever the certificate changes.
    codesign -d --requirements - "$APP" 2>&1 | grep -q "leaf\[subject.OU\] = \"\?$TEAM\"\?" \
      || die "designated requirement is not pinned to team $TEAM"
    spctl --assess --type execute --verbose=2 "$APP" \
      || note "Gatekeeper rejects it (expected without Developer ID + notarization): recipients open it once via System Settings → Privacy & Security → Open Anyway."
    ;;
esac
