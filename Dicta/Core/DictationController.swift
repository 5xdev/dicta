import AVFoundation
import Combine
import Foundation

/// Orchestrates the push-to-talk loop:
///   hotkey down → start mic + engine → hotkey up → stop mic → upload/finalize → insert text.
/// Everything here runs on the main actor; the audio callback just forwards buffers to the engine.
/// Only one utterance records at a time, but a new one may start while earlier ones are still uploading;
/// transcripts are inserted in speaking order regardless of which upload finishes first.
/// Escape cancels everything at once — the recording, every upload, any error — and hides the overlay.
///
/// Settings live in `Preferences`, TCC state in `PermissionsMonitor` — this object only reads them.
@MainActor
final class DictationController: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case error(String)

        /// Recording takes precedence (the user is mid-utterance), then a transient error, then any upload still running.
        static func resolve(recording: Bool, error: String?, uploadsInFlight: Int) -> State {
            if recording { return .recording }
            if let error { return .error(error) }
            return uploadsInFlight > 0 ? .transcribing : .idle
        }
    }

    /// Builds the engine for one utterance. Sarvam by default; tests and future backends substitute their own.
    typealias EngineFactory = @MainActor (Preferences) -> any TranscriptionEngine

    // MARK: Published state

    /// Derived from `current` / `uploads` / `errorMessage` via `refreshState()`.
    @Published private(set) var state: State = .idle
    @Published private(set) var level: Float = 0
    @Published private(set) var lastTranscript: String?

    // MARK: Dependencies

    let preferences: Preferences
    let permissions: PermissionsMonitor
    private let makeEngine: EngineFactory
    private let recorder = AudioRecorder()
    private let hotkeyMonitor: HotkeyMonitor
    private var cancellables = Set<AnyCancellable>()

    /// Per-utterance recording state. A cancelled session may still be unwinding (e.g. awaiting `engine.begin()`)
    /// after a new one has started, so each run checks its own flags instead of shared controller state.
    @MainActor
    private final class Session {
        private(set) var stopRequested = false
        var cancelled = false
        private var continuation: CheckedContinuation<Void, Never>?

        func requestStop() {
            stopRequested = true
            continuation?.resume()
            continuation = nil
        }

        func waitForStop() async {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                if stopRequested { c.resume() } else { continuation = c }
            }
        }
    }

    // Session bookkeeping (all main-actor).
    /// The utterance currently recording, if any.
    private var current: Session?
    /// Uploads still running, keyed so each can remove itself when done (or all be cancelled at once).
    private var uploads: [UUID: Task<Void, Never>] = [:]
    private var errorMessage: String?
    private var errorGeneration = 0
    /// Completion of the most recently *started* upload; each session awaits its predecessor before inserting,
    /// so overlapping uploads that finish out of order still land in speaking order.
    private var lastCompletion: Task<Void, Never>?

    init(preferences: Preferences,
         permissions: PermissionsMonitor,
         makeEngine: @escaping EngineFactory = { SarvamTranscriber(config: $0.sarvamConfig) }) {
        self.preferences = preferences
        self.permissions = permissions
        self.makeEngine = makeEngine
        hotkeyMonitor = HotkeyMonitor(hotkey: preferences.hotkey)

        hotkeyMonitor.onPress = { [weak self] in self?.beginRecording() }
        hotkeyMonitor.onRelease = { [weak self] in self?.endRecording() }
        hotkeyMonitor.onEscape = { [weak self] in self?.cancel() }
        recorder.onLevel = { [weak self] in self?.level = $0 }
        recorder.onError = { [weak self] error in
            // Capture died mid-utterance (mic went away) — wrap up what we have and tell the user.
            self?.endRecording()
            self?.fail(error)
        }

        // Mirror the two settings the capture side needs. `$x` delivers the current value on subscription,
        // so this also covers the initial state (property observers don't fire during init).
        preferences.$hotkey
            .sink { [weak self] in self?.hotkeyMonitor.hotkey = $0 }
            .store(in: &cancellables)
        preferences.microphone.$deviceUID
            .map { $0.isEmpty ? nil : $0 }
            .sink { [weak self] in self?.recorder.preferredDeviceUID = $0 }
            .store(in: &cancellables)
    }

    // MARK: Lifecycle

    func start() {
        permissions.start()
        // Install the hotkey tap as soon as Accessibility is trusted — right now for a returning user, or
        // whenever the permissions poll sees it granted (no relaunch needed).
        permissions.$accessibilityTrusted
            .filter { $0 }
            .sink { [weak self] _ in self?.installHotkey() }
            .store(in: &cancellables)
    }

    func stop() {
        permissions.stop()
        hotkeyMonitor.stop()
        recorder.stop()
        preferences.flush()
    }

    private func installHotkey() {
        guard !hotkeyMonitor.isRunning else { return }
        do { try hotkeyMonitor.start() } catch { fail(error) }
    }

    // MARK: Push-to-talk

    /// Manual trigger (the popover's record button). Toggles recording.
    func toggle() {
        current != nil ? endRecording() : beginRecording()
    }

    /// Escape: abandon the recording and every pending upload without inserting anything, and clear any error,
    /// so the overlay disappears immediately and a fresh recording can start.
    func cancel() {
        guard current != nil || !uploads.isEmpty || errorMessage != nil else { return }
        Log.app.info("Dictation cancelled")
        if let session = current {
            session.cancelled = true
            session.requestStop()
            recorder.stop()
            current = nil
        }
        uploads.values.forEach { $0.cancel() }    // cancels the URLSession request too
        uploads.removeAll()
        lastCompletion = nil
        errorGeneration += 1                      // disarm any pending error auto-clear
        errorMessage = nil
        refreshState()
    }

    private func beginRecording() {
        guard current == nil else { return }      // uploads in flight are fine — we can record the next one
        guard permissions.micAuthorized else {
            fail(message: "Microphone access is required. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }
        guard preferences.hasAPIKey else {
            fail(SarvamError.missingAPIKey)
            return
        }
        let session = Session()
        current = session
        refreshState()
        Task { await runSession(session) }
    }

    private func endRecording() {
        current?.requestStop()
    }

    private func runSession(_ session: Session) async {
        // One engine instance per utterance, so a new recording can start while this one is still uploading.
        let engine = makeEngine(preferences)

        // ── Record ──────────────────────────────────────────────────────────────────────────────
        let startedAt: Date
        do {
            let format = try await engine.begin()
            if session.cancelled { return }        // cancel() already reset everything
            if session.stopRequested {             // released before the engine was ready — treat as a tap
                finishRecordingPhase(session)
                return
            }
            startedAt = Date()
            try recorder.start(targetFormat: format) { buffer in engine.feed(buffer) }
        } catch {
            if session.cancelled { return }
            finishRecordingPhase(session)
            fail(error)
            return
        }

        // The backend is built for short clips: if the key is still held at its limit,
        // stop on the user's behalf and transcribe what we have rather than growing the buffer forever.
        let maxSeconds = engine.maxUtteranceSeconds
        let limit = Task {
            try? await Task.sleep(for: .seconds(maxSeconds))
            guard !Task.isCancelled else { return }
            Log.speech.warning("Utterance hit the \(maxSeconds, privacy: .public)s limit — stopping automatically")
            session.requestStop()
        }

        // Suspend until the hotkey is released, the limit above fires, or Escape cancels.
        await session.waitForStop()
        limit.cancel()
        // After a cancel the recorder may already belong to a newer session — leave it alone.
        if session.cancelled { return }
        recorder.stop()
        let duration = Date().timeIntervalSince(startedAt)
        finishRecordingPhase(session)

        if duration < 0.25 { return }     // accidental tap — nothing worth transcribing

        // ── Upload + insert ─────────────────────────────────────────────────────────────────────
        let id = UUID()
        let previous = lastCompletion
        let completion = Task { @MainActor [weak self] in
            var text: String?
            var failure: Error?
            do { text = try await engine.finish() } catch { failure = error }
            await previous?.value          // keep insertion in speaking order
            // Cancelled via Escape: drop the result (and the cancellation error) silently.
            guard let self, !Task.isCancelled else { return }
            if let failure {
                self.fail(failure)
            } else if let text, !text.isEmpty {
                Log.speech.info("Transcript (\(duration, format: .fixed(precision: 1))s): \(text, privacy: .private)")
                self.lastTranscript = text
                TextInserter.insert(text)
            }
        }
        uploads[id] = completion
        lastCompletion = completion
        refreshState()
        await completion.value

        uploads[id] = nil                  // already gone if cancel() ran
        refreshState()
    }

    private func finishRecordingPhase(_ session: Session) {
        guard current === session else { return }
        current = nil
        refreshState()
    }

    // MARK: State

    private func refreshState() {
        let new = State.resolve(recording: current != nil, error: errorMessage, uploadsInFlight: uploads.count)
        if state != new { state = new }
    }

    // MARK: Errors

    private func fail(_ error: Error) {
        fail(message: error.localizedDescription)
    }

    private func fail(message: String) {
        Log.app.error("\(message, privacy: .public)")
        errorGeneration += 1
        let generation = errorGeneration
        errorMessage = message
        refreshState()
        Task {
            try? await Task.sleep(for: .seconds(4))
            guard generation == errorGeneration else { return }   // a newer error owns the display now
            errorMessage = nil
            refreshState()
        }
    }
}
