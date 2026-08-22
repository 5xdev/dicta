import XCTest
@testable import Dicta

final class WAVTests: XCTestCase {
    func testCanonical44ByteHeaderFor16kMono() {
        let pcm = Data([0x01, 0x00, 0x02, 0x00, 0xFF, 0x7F])   // three Int16 samples
        let wav = WAV.encode(pcm16: pcm, sampleRate: 16_000, channels: 1)

        XCTAssertEqual(wav.count, 44 + pcm.count)
        XCTAssertEqual(wav.ascii(0..<4), "RIFF")
        XCTAssertEqual(wav.le32(at: 4), UInt32(36 + pcm.count))       // RIFF chunk size
        XCTAssertEqual(wav.ascii(8..<12), "WAVE")
        XCTAssertEqual(wav.ascii(12..<16), "fmt ")
        XCTAssertEqual(wav.le32(at: 16), 16)                          // fmt chunk size
        XCTAssertEqual(wav.le16(at: 20), 1)                           // PCM
        XCTAssertEqual(wav.le16(at: 22), 1)                           // channels
        XCTAssertEqual(wav.le32(at: 24), 16_000)                      // sample rate
        XCTAssertEqual(wav.le32(at: 28), 32_000)                      // byte rate = 16000 * 1 * 2
        XCTAssertEqual(wav.le16(at: 32), 2)                           // block align
        XCTAssertEqual(wav.le16(at: 34), 16)                          // bits per sample
        XCTAssertEqual(wav.ascii(36..<40), "data")
        XCTAssertEqual(wav.le32(at: 40), UInt32(pcm.count))
        XCTAssertEqual(wav.suffix(pcm.count), pcm)                    // payload untouched
    }

    func testStereoScalesByteRateAndBlockAlign() {
        let wav = WAV.encode(pcm16: Data(count: 8), sampleRate: 44_100, channels: 2)
        XCTAssertEqual(wav.le16(at: 22), 2)
        XCTAssertEqual(wav.le32(at: 28), 176_400)
        XCTAssertEqual(wav.le16(at: 32), 4)
    }

    func testEmptyPayloadStillProducesValidHeader() {
        let wav = WAV.encode(pcm16: Data(), sampleRate: 16_000, channels: 1)
        XCTAssertEqual(wav.count, 44)
        XCTAssertEqual(wav.le32(at: 4), 36)
        XCTAssertEqual(wav.le32(at: 40), 0)
    }
}

private extension Data {
    func ascii(_ range: Range<Int>) -> String { String(decoding: self[range], as: UTF8.self) }
    func le16(at offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func le32(at offset: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(self[offset + $1]) << (8 * UInt32($1)) } }
}
