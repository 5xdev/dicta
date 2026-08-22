import AVFoundation

enum AudioError: LocalizedError {
    case noInputDevice
    var errorDescription: String? { "No microphone input is available." }
}

/// Captures microphone audio and delivers PCM buffers in the caller's requested format.
/// Also publishes a normalized input level (0…1) for the UI meter.
///
/// Two capture paths, same contract:
///  • **System default** — `AVAudioEngine` tap. Survives input-device changes mid-capture (AirPods connecting,
///    a USB mic unplugged): the engine is rebuilt on the new default device and `onBuffer` keeps receiving audio.
///  • **Pinned microphone** (`preferredDeviceUID`) — `AVCaptureSession` on that exact device, with
///    `AVCaptureAudioDataOutput` resampling to the target format. (AVAudioEngine's input node can't be re-pointed
///    at a non-default device on recent macOS — it keeps the default device's format and delivers nothing.)
///    If the pinned mic isn't present when capture starts, or goes away mid-utterance, we fall back to the
///    system default rather than failing.
final class AudioRecorder: NSObject {
    private var isRunning = false

    /// CoreAudio UID of the microphone to capture from. `nil` follows the system default input.
    /// Takes effect on the next `start()`; changing it mid-recording does not interrupt the current utterance.
    var preferredDeviceUID: String?

    // Captured at `start` so capture can be rebuilt with the same contract after a device change.
    private var targetFormat: AVAudioFormat?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    // Engine path (system default).
    private var engine: AVAudioEngine?
    // Capture-session path (pinned device).
    private var session: AVCaptureSession?
    private var sessionConverter: AVAudioConverter?
    private let sessionQueue = DispatchQueue(label: "com.honeyyadav.dicta.capture")

    private var observers: [NSObjectProtocol] = []

    /// Called on the main thread with a 0…1 loudness value.
    var onLevel: ((Float) -> Void)?
    /// Called on the main thread if capture dies mid-recording and can't be restarted (e.g. the only mic went away).
    var onError: ((Error) -> Void)?

    /// Start capture. `onBuffer` is invoked on a capture thread — keep it cheap.
    func start(targetFormat: AVAudioFormat, onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard !isRunning else { return }
        self.targetFormat = targetFormat
        self.onBuffer = onBuffer
        try startCapture()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        tearDownCapture()
        onBuffer = nil
        targetFormat = nil
        isRunning = false
        DispatchQueue.main.async { [weak self] in self?.onLevel?(0) }
        Log.audio.info("Recording stopped")
    }

    // MARK: - Capture lifecycle

    private func startCapture() throws {
        if let uid = preferredDeviceUID {
            if let device = AVCaptureDevice(uniqueID: uid) {
                try startSession(on: device)
                return
            }
            Log.audio.notice("Preferred microphone \(uid, privacy: .public) not connected — using the system default")
        }
        try startEngine()
    }

    private func tearDownCapture() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()

        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        session?.stopRunning()
        session = nil
        sessionConverter = nil
    }

    /// Something about the active device changed underneath us. Rebuild on whatever is available now —
    /// the pinned mic if it's still there, otherwise the system default — so the utterance continues.
    private func handleConfigurationChange(_ reason: String) {
        guard isRunning else { return }
        Log.audio.notice("\(reason, privacy: .public) — restarting capture")
        tearDownCapture()
        do {
            try startCapture()
        } catch {
            Log.audio.error("Couldn't restart capture: \(error.localizedDescription, privacy: .public)")
            stop()
            onError?(error)
        }
    }

    // MARK: - Engine path (system default input)

    private func startEngine() throws {
        guard let onBuffer, let targetFormat else { return }
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw AudioError.noInputDevice }

        let converter = (targetFormat == inputFormat) ? nil : AVAudioConverter(from: inputFormat, to: targetFormat)

        // Everything the render thread needs is captured here — it never reads mutable state off `self`.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.publishLevel(of: buffer)
            if let converter {
                if let converted = Self.convert(buffer, using: converter, to: targetFormat) { onBuffer(converted) }
            } else {
                onBuffer(buffer)
            }
        }

        // When the input hardware's format changes (device switch), the engine stops itself and posts this.
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange("Audio configuration changed")
        })

        engine.prepare()
        try engine.start()
        self.engine = engine
        Log.audio.info("Recording started on system default: \(inputFormat.sampleRate, privacy: .public) Hz → \(targetFormat.sampleRate, privacy: .public) Hz")
    }

    // MARK: - Capture-session path (pinned input device)

    private func startSession(on device: AVCaptureDevice) throws {
        guard let targetFormat else { return }
        let session = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw AudioError.noInputDevice }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        // On macOS the data output can resample/convert for us; ask for the target format directly so the
        // delegate usually gets buffers it can hand straight to `onBuffer` (a converter covers any mismatch).
        output.audioSettings = targetFormat.settings
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        guard session.canAddOutput(output) else { throw AudioError.noInputDevice }
        session.addOutput(output)

        // The pinned mic was unplugged / turned off, or the session died for another reason: fall back.
        observers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange("\(device.localizedName) disconnected")
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main
        ) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
            self?.handleConfigurationChange("Capture session error: \(error?.localizedDescription ?? "unknown")")
        })

        session.startRunning()
        guard session.isRunning else { throw AudioError.noInputDevice }
        self.session = session
        Log.audio.info("Recording started on \(device.localizedName, privacy: .public)")
    }

    // MARK: - Helpers

    private static func convert(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if status == .error {
            Log.audio.error("Conversion failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return nil
        }
        return out.frameLength > 0 ? out : nil
    }

    private func publishLevel(of buffer: AVAudioPCMBuffer) {
        guard let onLevel else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        let stride = buffer.stride
        var sum: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for i in 0..<n { let v = channel[i * stride]; sum += v * v }
        } else if let channel = buffer.int16ChannelData?[0] {
            for i in 0..<n { let v = Float(channel[i * stride]) / 32768; sum += v * v }
        } else {
            return
        }
        let rms = (sum / Float(n)).squareRoot()
        let db = 20 * log10(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 50) / 50)) // map −50 dB…0 dB → 0…1
        DispatchQueue.main.async { onLevel(normalized) }
    }
}

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Runs on `sessionQueue` (serial). `onBuffer`/`targetFormat` are only mutated while no session is running.
        guard let onBuffer, let targetFormat,
              let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0 else { return }

        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        pcm.frameLength = AVAudioFrameCount(frames)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: pcm.mutableAudioBufferList
        )
        guard status == noErr else {
            Log.audio.error("Couldn't copy capture buffer: OSStatus \(status, privacy: .public)")
            return
        }

        publishLevel(of: pcm)

        guard targetFormat != format else {
            onBuffer(pcm)
            return
        }
        // The data output didn't (or couldn't) honor our requested format — convert like the engine path does.
        if sessionConverter?.inputFormat != format {
            sessionConverter = AVAudioConverter(from: format, to: targetFormat)
        }
        guard let converter = sessionConverter else { return }
        if let converted = Self.convert(pcm, using: converter, to: targetFormat) { onBuffer(converted) }
    }
}
