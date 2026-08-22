#!/bin/bash
# The numbers that name a build, read from project.yml and git. Shared by the Makefile and CI (*Read version*)
# so the two definitions cannot drift.
#
#   scripts/version.sh version   MARKETING_VERSION (CFBundleShortVersionString), validated as x.y.z
#   scripts/version.sh build     commit count (CFBundleVersion): monotonic on main, identical locally and in CI
#   scripts/version.sh sparkle   the pinned Sparkle package version — CI downloads the matching CLI tools for the
#                                appcast so the framework in the app and the tool that signs its feed match
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  die() { echo "::error::$*" >&2; exit 1; }
else
  die() { echo "version.sh: $*" >&2; exit 1; }
fi

case "${1:-}" in
  version)
    v=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml)
    [[ -n "$v" ]] || die "MARKETING_VERSION not found in project.yml"
    [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "MARKETING_VERSION must be x.y.z, got '$v'"
    echo "$v"
    ;;
  build)
    git rev-list --count HEAD
    ;;
  sparkle)
    v=$(sed -nE 's/^[[:space:]]*exactVersion:[[:space:]]*"([^"]+)".*/\1/p' project.yml)
    [[ -n "$v" ]] || die "Sparkle exactVersion not found in project.yml"
    echo "$v"
    ;;
  *)
    echo "usage: $0 version|build|sparkle" >&2
    exit 2
    ;;
esac
