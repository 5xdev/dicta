import AVFoundation
import Foundation

/// Cloud transcription via Sarvam AI's REST speech-to-text endpoint.
/// Audio is accumulated as 16 kHz mono 16-bit PCM while the hotkey is held, wrapped as WAV,
/// and uploaded as multipart/form-data on release.
/// One instance per utterance — the controller creates a fresh one for every recording so uploads can overlap.
/// Endpoint reference: https://docs.sarvam.ai/api-reference-docs/speech-to-text/transcribe
final class SarvamTranscriber: TranscriptionEngine {
    private let config: SarvamConfig

    private static let sampleRate: Double = 16_000
    private static let endpoint = URL(string: "https://api.sarvam.ai/speech-to-text")!
    /// REST endpoint is intended for short clips; longer ones should use Sarvam's batch API.
    /// The controller auto-stops recording at this point; `feed` also hard-caps the buffer as a safety net.
    static let maxUtteranceSeconds: TimeInterval = 30
    private static let maxPCMBytes = Int(maxUtteranceSeconds * sampleRate) * MemoryLayout<Int16>.size

    private let lock = NSLock()
    private var pcm = Data()

    /// Shared across utterances so overlapping uploads reuse one connection pool.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    init(config: SarvamConfig) {
        self.config = config
    }

    // MARK: TranscriptionEngine

    var maxUtteranceSeconds: TimeInterval { Self.maxUtteranceSeconds }

    func begin() async throws -> AVAudioFormat {
        guard !config.apiKey.isEmpty else { throw SarvamError.missingAPIKey }
        lock.withLock { pcm.removeAll(keepingCapacity: true) }
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                         sampleRate: Self.sampleRate,
                                         channels: 1,
                                         interleaved: true) else {
            throw TranscriptionError.noAudioFormat
        }
        return format
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.int16ChannelData?[0], buffer.frameLength > 0 else { return }
        let byteCount = Int(buffer.frameLength) * Int(buffer.format.channelCount) * MemoryLayout<Int16>.size
        let chunk = Data(bytes: channel, count: byteCount)
        lock.withLock {
            guard pcm.count < Self.maxPCMBytes else { return }   // past the limit — drop, never grow unbounded
            pcm.append(chunk.prefix(Self.maxPCMBytes - pcm.count))
        }
    }

    func finish() async throws -> String {
        let audio = lock.withLock { pcm }
        guard !audio.isEmpty else { throw SarvamError.noAudio }
        let wav = WAV.encode(pcm16: audio, sampleRate: Int(Self.sampleRate), channels: 1)
        return try await upload(wav)
    }

    // MARK: Networking

    private struct Response: Decodable {
        let transcript: String?        // may be null/absent for silence — treat as empty, not as a bad response
        let language_code: String?
        let request_id: String?
    }

    private struct APIError: Decodable {
        struct Inner: Decodable { let message: String? }
        let error: Inner?
        let message: String?
        let detail: String?
    }

    private func upload(_ wav: Data) async throws -> String {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "api-subscription-key")

        var form = MultipartForm()
        form.addFile(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: wav)
        form.addField(name: "model", value: config.model.rawValue)
        form.addField(name: "language_code", value: config.languageCode)
        form.addField(name: "mode", value: config.mode.rawValue)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalize()

        Log.speech.info("Uploading \(wav.count, privacy: .public) bytes to Sarvam (\(self.config.model.rawValue, privacy: .public), \(self.config.languageCode, privacy: .public), \(self.config.mode.rawValue, privacy: .public))")
        let started = Date()
        let (data, response) = try await Self.session.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        Log.speech.info("Sarvam responded \(status, privacy: .public) in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")

        guard (200..<300).contains(status) else {
            let parsed = try? JSONDecoder().decode(APIError.self, from: data)
            let message = parsed?.error?.message ?? parsed?.message ?? parsed?.detail
                ?? String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw SarvamError.http(status: status, message: message)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            Log.speech.error("Undecodable body: \(String(data: data.prefix(300), encoding: .utf8) ?? "", privacy: .public)")
            throw SarvamError.badResponse
        }
        if let lang = decoded.language_code { Log.speech.info("Detected language: \(lang, privacy: .public)") }
        if let id = decoded.request_id { Log.speech.info("Sarvam request id: \(id, privacy: .public)") }
        return (decoded.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
