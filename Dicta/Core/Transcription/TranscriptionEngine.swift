import AVFoundation

enum TranscriptionError: LocalizedError {
    case noAudioFormat

    var errorDescription: String? {
        switch self {
        case .noAudioFormat: return "Couldn't create the audio format the speech engine needs."
        }
    }
}

/// One utterance = begin() → feed(buffer)* → finish(). Sarvam's REST API today (`SarvamTranscriber`);
/// on-device or streaming backends can adopt this later. `DictationController` gets its engine from an injected
/// factory, so a new backend is a one-line change in `AppDelegate` (or a fake in tests).
protocol TranscriptionEngine: AnyObject {
    /// Longest utterance the backend accepts. The controller stops recording on the user's behalf at this point.
    var maxUtteranceSeconds: TimeInterval { get }

    /// Prepare for a new utterance. Returns the audio format the engine wants buffers in.
    func begin() async throws -> AVAudioFormat

    /// Push audio. Called from the audio render thread — must be non-blocking.
    func feed(_ buffer: AVAudioPCMBuffer)

    /// Signal end-of-audio and wait for the final transcript.
    func finish() async throws -> String
}
