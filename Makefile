# Dicta — build helpers. Requires: Xcode 26+, xcodegen (brew install xcodegen)
SHELL := /bin/bash -o pipefail
# Signing team from project.yml so it is declared once; `make build TEAM=XXXXXXXXXX` still overrides.
TEAM   ?= $(shell sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM:[[:space:]]*([A-Z0-9]+).*/\1/p' project.yml)
CONFIG ?= Debug
DERIVED := build
APP     := $(DERIVED)/Build/Products/$(CONFIG)/Dicta.app
RELEASE_APP := $(DERIVED)/Build/Products/Release/Dicta.app
# Both from scripts/version.sh, which CI reads too, so the numbers are defined once.
VERSION := $(shell scripts/version.sh version)
BUILD   := $(shell scripts/version.sh build)
ZIP     := dist/Dicta-$(VERSION).zip
DMG     := dist/Dicta-$(VERSION).dmg
# Sparkle CLI tools (generate_keys / generate_appcast / sign_update), unpacked from a Sparkle release tarball.
SPARKLE_BIN ?= $(HOME)/bin/sparkle/bin

.PHONY: gen help build test run stop clean open log icon dist dmg release

gen:            ## Regenerate Dicta.xcodeproj from project.yml
	xcodegen generate --quiet

# Listed after `gen` on purpose: the first target is the default goal, and bare `make` should still regenerate.
help:           ## List these targets
	@grep -hE '^[a-z][a-z-]*:.*##' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN { FS = ":.*## " } { printf "  %-8s %s\n", $$1, $$2 }'

build: gen      ## Build the app (Debug by default)
	xcodebuild -project Dicta.xcodeproj -scheme Dicta -configuration $(CONFIG) \
	  -derivedDataPath $(DERIVED) DEVELOPMENT_TEAM=$(TEAM) CURRENT_PROJECT_VERSION=$(BUILD) build 2>&1 \
	  | grep -E "error:|warning: .*Dicta/|BUILD|Signing Identity"; exit $${PIPESTATUS[0]}
	@echo "→ $(APP) ($(VERSION) build $(BUILD))"

test: gen       ## Run the unit tests (DictaTests)
	xcodebuild -project Dicta.xcodeproj -scheme Dicta -configuration Debug -derivedDataPath $(DERIVED) \
	  -destination 'platform=macOS' DEVELOPMENT_TEAM=$(TEAM) CURRENT_PROJECT_VERSION=$(BUILD) test 2>&1 \
	  | grep -E "error:|failed|Executed|\*\* TEST"; exit $${PIPESTATUS[0]}

dist:           ## Release build → pin team requirement → verify signature → dist/Dicta-<version>.zip (the Sparkle enclosure)
	$(MAKE) build CONFIG=Release
	scripts/pin-designated-requirement.sh "$(RELEASE_APP)"
	scripts/verify-bundle.sh "$(RELEASE_APP)" apple-development "$(TEAM)"
	mkdir -p dist && rm -f "$(ZIP)"
	ditto -c -k --keepParent --sequesterRsrc "$(RELEASE_APP)" "$(ZIP)"
	@echo "→ $(ZIP) ($$(du -h "$(ZIP)" | cut -f1))"

# What a new user downloads; the zip stays the Sparkle enclosure. Gatekeeper caveats: README → Distribution.
dmg: dist        ## Package the release build as dist/Dicta-<version>.dmg (drag-to-Applications installer)
	scripts/make-dmg.sh "$(RELEASE_APP)" "$(DMG)"

run: stop build ## Build and launch
	open "$(APP)"

stop:           ## Quit a running instance
	-pkill -x Dicta 2>/dev/null

log:            ## Stream the app's log output
	log stream --level info --predicate 'subsystem == "com.honeyyadav.dicta"' --style compact

open: gen       ## Open in Xcode
	open Dicta.xcodeproj

icon:           ## Re-render Dicta/Resources/AppIcon.icns from scripts/make-icon.swift
	swift scripts/make-icon.swift

# Optional shortcut for the owner: merging a PR that bumps MARKETING_VERSION does exactly the same thing.
# Deliberately does not tag — CI tags the commit after the build passes. Pushing main and the tag together
# would start two runs that race to create the same release.
release:        ## make release VERSION=0.1.0 → bump project.yml, commit, push main (CI tags v0.1.0 and publishes)
	@test "$(origin VERSION)" = "command line" || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || { echo "VERSION must be x.y.z, got '$(VERSION)'"; exit 1; }
	@test "$$(git rev-parse --abbrev-ref HEAD)" = main || { echo "release from main, not $$(git rev-parse --abbrev-ref HEAD)"; exit 1; }
	@git diff --quiet && git diff --cached --quiet || { echo "working tree not clean"; exit 1; }
	@! git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null || { echo "tag v$(VERSION) already exists"; exit 1; }
	sed -i '' -E 's/^([[:space:]]*MARKETING_VERSION:[[:space:]]*")[^"]+"/\1$(VERSION)"/' project.yml
	git commit -am "Release $(VERSION)"
	git push origin main

clean:          ## Remove build/, dist/ and the generated Dicta.xcodeproj
	rm -rf $(DERIVED) dist Dicta.xcodeproj
