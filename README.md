# Dicta

Push-to-talk dictation for macOS, in the spirit of [Wispr Flow](https://wisprflow.ai/): hold a key, speak, release — the text lands in whatever app you're typing in. Transcription is powered by [Sarvam AI](https://docs.sarvam.ai/api-reference-docs/speech-to-text/transcribe) (saaras), with first-class support for Indian languages.

## Install

Grab `Dicta-<version>.dmg` from the [latest release](https://github.com/5xdev/dicta/releases/latest), open it, and
drag Dicta onto **Applications**. Updates after that arrive in-app (Sparkle), so this is a one-time step.

Releases are signed with an Apple Development certificate rather than notarized, so the *first* launch needs one
detour — see [Opening a non-notarized build](#opening-a-non-notarized-build). Then grant permissions: see
[First launch](#first-launch).

## Architecture

```
┌──────────────┐  flagsChanged  ┌──────────────────────┐
│ HotkeyMonitor│ ─────────────▶ │  DictationController │  @MainActor state machine
│ (CGEventTap) │  press/release │  idle → recording →  │  idle ⇄ recording ⇄ transcribing
└──────────────┘                │  transcribing → idle │
                                └──┬───────────┬───────┘
        PCM buffers (16k mono Int16) │           │ final text
┌──────────────┐  ◀──────────────────┘           ▼
│ AudioRecorder│ ─▶ TranscriptionEngine ─▶ TextInserter (⌘V via CGEvent, clipboard restored)
│ AVAudioEngine│    └ SarvamTranscriber: buffer → WAV → POST api.sarvam.ai/speech-to-text
└──────────────┘      (multipart: file, model, language_code, mode)

UI: MenuBarExtra (status + last transcript)  ·  OverlayPanel (floating pill)  ·  Settings window
```

| Layer | Tech | Why |
|---|---|---|
| App shell | SwiftUI `MenuBarExtra` + AppKit `NSPanel`, `LSUIElement` agent | Native, tiny footprint, no Electron |
| Hotkey | `CGEventTap` (listen-only, `flagsChanged`) | Only reliable way to catch Fn / right-⌥ globally |
| Audio | `AVAudioEngine` tap → `AVAudioConverter` (system default mic); `AVCaptureSession` + `AVCaptureAudioDataOutput` when a specific mic is pinned in Settings | Standard, low latency; AVAudioEngine's input node can't be re-pointed at a non-default device on recent macOS, so pinned capture goes through AVCapture |
| STT | Sarvam AI REST `speech-to-text` (`saaras:v4`) | Strong Indic-language accuracy, auto language detection, translate/transliterate modes |
| Secrets | API key in Keychain (`Keychain.swift`) | Never in UserDefaults or the repo; `SARVAM_API_KEY` env var works for dev |
| Insert | Pasteboard + synthesized ⌘V, clipboard restored | Works everywhere (Electron, terminals, browsers, RDP) |
| Project | XcodeGen `project.yml` → `Dicta.xcodeproj` | Declarative, diff-friendly, no merge conflicts in pbxproj |

`TranscriptionEngine` is a protocol so other backends can slot in later: `DictationController` takes an engine factory (Sarvam by default, wired in `AppDelegate`) and reads the utterance cap from the engine, so a new backend is one line there.

Source layout — `Dicta/App` is the composition root, `Dicta/UI` the SwiftUI/AppKit views, and `Dicta/Core` the model, grouped by domain: `Audio/` (capture, device list), `Input/` (hotkey tap, text insertion), `Transcription/` (engine protocol, WAV + multipart encoding, `Sarvam/`), `Settings/` (`Preferences`, `MicrophoneSelection`), `Permissions/` (TCC wrappers + monitor) and `System/` (Keychain, logging, Sparkle). `DictaTests/` covers the pure parts — `make test`.

## Requirements

- macOS 26+, Apple Silicon
- Xcode 26+
- `brew install xcodegen`
- A Sarvam AI API key — https://indus.sarvam.ai

## Build & run

```sh
make run        # xcodegen → xcodebuild → open Dicta.app
make test       # run the unit tests (DictaTests)
make open       # open the generated project in Xcode
make icon       # re-render Dicta/Resources/AppIcon.icns from scripts/make-icon.swift
make log        # stream the app's os_log output
make help       # list every target
```

Packaging a build to hand to someone else is covered under [Distribution](#distribution).

### First launch

1. Grant **Microphone** when prompted.
2. Grant **Accessibility** (System Settings → Privacy & Security → Accessibility). Dicta polls and installs the hotkey automatically once granted — no relaunch needed.
3. If using Fn as the hotkey: System Settings → Keyboard → **Press 🌐 key to → Do Nothing**. Note that many third-party keyboards handle Fn in firmware and never send it to macOS (no keycode 63 event), so Fn "does nothing" on them — pick **Right ⌥ Option** in Settings → General instead.
4. Menu bar → Settings → **Sarvam AI** → paste your API key (stored in Keychain). Pick model / language / mode.
5. Optional: Settings → **General** → **Microphone** to pin a specific input device (handy with several mics connected). Defaults to the system input; if the chosen mic is unplugged, Dicta falls back to the system default until it returns.

Then hold the hotkey, talk, release.

## Signing

Two independent things matter when you hand someone a build, and only one of them needs a paid Apple Developer
account:

- **Stable identity** — whether macOS treats each new build as the *same* app, i.e. whether **Accessibility /
  Microphone grants and the Keychain ACL survive updates**.
- **Gatekeeper** — whether the app opens without a scary dialog.

| Mode | Stable identity | Gatekeeper | Produced by |
|---|---|---|---|
| **Ad-hoc** (`CODE_SIGN_IDENTITY=-`) | ❌ macOS identifies it by the hash of the exact binary, so every build is a brand-new app | ❌ blocked | CI with no `SIGNING_P12` secret |
| **Apple Development** (free Apple ID) | ✅ pinned to the team | ❌ one-time **Open Anyway** | local builds, `make dist`, CI with an Apple Development cert |
| **Developer ID** (paid Developer Program) | ✅ pinned to the team | ✅ notarized + stapled | CI with a Developer ID cert |

Local builds and `make dist` sign with the `Apple Development` certificate for team `K6D58UX7NG` (`project.yml`).
`make dist` and CI then re-sign the outer bundle with `scripts/pin-designated-requirement.sh`, which pins the
[designated requirement](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
to the **team** (`leaf[subject.OU] = K6D58UX7NG`) instead of to the individual certificate, which is codesign's
default for development certs. That way a renewed cert, or a CI build signed with a different cert from the same
team, still counts as the same app and users keep their permissions. (The script's header explains why this
cannot be a build phase.) `scripts/verify-bundle.sh` then asserts it — and the seal, and the nested framework —
and prints the requirement and the Gatekeeper verdict; `make dist` and CI both call it, so the two release gates
cannot drift apart.

### Opening a non-notarized build

macOS blocks it on first launch → **System Settings → Privacy & Security → Open Anyway** (right-click → Open no
longer bypasses this on macOS 15+). Alternatively `xattr -dr com.apple.quarantine Dicta.app`. This is a one-time
step per Mac — updates open normally.

**Ad-hoc CI builds need more**, because they have no stable identity:

1. Drag Dicta out of the DMG (or unzip it), then remove the quarantine flag or Gatekeeper will refuse to open it:
   `xattr -dr com.apple.quarantine /Applications/Dicta.app`.
2. Re-grant **Accessibility** (and Microphone if prompted) after *every* update. If the toggle is already on but
   the hotkey doesn't work, remove Dicta from the Accessibility list and add it back.
3. If you previously ran a differently-signed Dicta (e.g. a local Xcode build), macOS may ask whether the new one
   may use the `sarvam-api-key` Keychain item — click **Always Allow**, or just paste the key again in Settings.

## Distribution

```sh
make dist       # Release build → verify signature → dist/Dicta-<version>.zip
make dmg        # the above, then dist/Dicta-<version>.dmg — what a new user downloads
```

`scripts/make-dmg.sh` builds a volume named `Dicta` holding `Dicta.app` and a symlink to `/Applications`, signed
with the same identity as the app, then mounts and re-verifies it before handing it over. It is deliberately plain
(no background art or icon layout — see the script's header for why). The DMG is only about the install *gesture*:
it does not change Gatekeeper, so an Apple Development build inside one still needs the same
[one-time detour](#opening-a-non-notarized-build).

## CI

`.github/workflows/build.yml` runs on every push to `main`, on `v*` tags, and manually via *Run workflow*: `macos-26` Apple Silicon runner → XcodeGen → Release build (arm64, stripped) → `Dicta-<version>-<sha>.zip` uploaded as a workflow artifact (30-day retention).

### Releasing

**Merging a PR that bumps `MARKETING_VERSION` in `project.yml` is the whole release.** When a push to `main` carries a version that has no `v<version>` tag yet, CI treats that run as a release: it builds and signs, generates and verifies the Sparkle appcast, packages the DMG, tags the commit `v<version>`, and publishes a GitHub Release with `Dicta-<version>.dmg`, `Dicta-<version>.zip` and `appcast.xml` attached (notes auto-generated from the PRs since the last release). Installed copies pick it up from `releases/latest/download/appcast.xml`. Nothing has to be run locally, and the version bump can come from anyone's PR.

The two archives have different jobs: the **DMG** is the download for a new user, the **zip** is what Sparkle serves to installed copies. The appcast must keep pointing at the zip — `generate_appcast` scans a whole directory and accepts `.dmg`, so CI builds the image outside `dist/` and fails the run if one turns up there.

Because merging an outside contributor's PR can publish a signed release under your identity, read the diff to `project.yml` and `.github/` before merging one — `SUPublicEDKey`, `DEVELOPMENT_TEAM` and the workflow itself decide what gets signed and what installed copies will trust.

Two escape hatches: `make release VERSION=x.y.z` does the bump-commit-push from a local checkout, and pushing a `v*` tag at an already-released commit re-runs the publish for it. Don't do both at once — a commit and its tag pushed together start two runs that race to create the same release. To re-publish a version, delete the existing release *and* its tag first.

### Signing secrets

Which [signing mode](#signing) CI uses is decided by the certificate in the `SIGNING_P12` secret:

| Secrets set | Mode |
|---|---|
| none | ad-hoc |
| `SIGNING_P12` = **Apple Development** cert, `SIGNING_P12_PASSWORD`, `APPLE_TEAM_ID` | Apple Development, team-pinned requirement |
| the same with a **Developer ID Application** cert, plus `APPLE_ID`, `APPLE_APP_PASSWORD` | Developer ID + notarized + stapled |

Ad-hoc runs suffix their artifacts `-adhoc` and attach an unsigned `.dmg`; no appcast is published for them, since
Sparkle refuses an update whose signing identity differs from the running app.

To set up the free path (same identity as your local builds):

1. Keychain Access → *My Certificates* → right-click **Apple Development: … (team K6D58UX7NG)** → *Export* → `.p12` with a password. (It must be the cert for the same team as `project.yml`, otherwise local and CI builds are different apps to TCC.)
2. `base64 -i cert.p12 | pbcopy` → repository secret `SIGNING_P12`; the export password → `SIGNING_P12_PASSWORD`; `K6D58UX7NG` → `APPLE_TEAM_ID`.
3. Push. The *Import signing certificate* step logs which identity it found; *Verify bundle* fails the run if the designated requirement isn't pinned to the team.

For the paid path, export a *Developer ID Application* cert instead and add an Apple ID + [app-specific password](https://support.apple.com/102654) for `notarytool`. The workflow signs with `--timestamp`, notarizes, staples and `spctl`-assesses both the app and the DMG — the image needs its own ticket, because stapling the app inside does not staple the image.

## Roadmap

- [ ] Double-tap the hotkey to toggle hands-free (the popover already has a manual record button)
- [ ] Long utterances (> 30 s) via Sarvam's batch speech-to-text API
- [ ] AI cleanup (filler words, punctuation, tone per app) — Sarvam chat completion or on-device `FoundationModels`
- [ ] Per-app context (detect frontmost app → formatting style, e.g. code vs. email)
- [ ] Accessibility-API insertion path (no clipboard touch) where supported
- [ ] Streaming transcription over Sarvam's WebSocket API for live preview
- [ ] Custom vocabulary / snippets
- [ ] History window with search
- [ ] Custom key combos (not just single modifiers) and mouse-button triggers
- [ ] Homebrew cask
