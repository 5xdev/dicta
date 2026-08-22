import Foundation

enum WAV {
    /// Wrap raw little-endian 16-bit PCM in a canonical 44-byte RIFF/WAVE header.
    static func encode(pcm16: Data, sampleRate: Int, channels: Int) -> Data {
        let bitsPerSample = 16
        let byteRate = sampleRate * channels * bitsPerSample / 8
        let blockAlign = channels * bitsPerSample / 8
        var header = Data(capacity: 44)
        header.append("RIFF")
        header.appendLE(UInt32(36 + pcm16.count))
        header.append("WAVE")
        header.append("fmt ")
        header.appendLE(UInt32(16))                 // PCM fmt chunk size
        header.appendLE(UInt16(1))                  // audio format: PCM
        header.appendLE(UInt16(channels))
        header.appendLE(UInt32(sampleRate))
        header.appendLE(UInt32(byteRate))
        header.appendLE(UInt16(blockAlign))
        header.appendLE(UInt16(bitsPerSample))
        header.append("data")
        header.appendLE(UInt32(pcm16.count))
        return header + pcm16
    }
}
