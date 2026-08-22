import XCTest
@testable import Dicta

final class MultipartFormTests: XCTestCase {
    func testBodyLayoutMatchesRFC7578() {
        var form = MultipartForm()
        form.addFile(name: "file", filename: "audio.wav", mimeType: "audio/wav", data: Data("RIFF".utf8))
        form.addField(name: "model", value: "saaras:v4")
        let body = String(decoding: form.finalize(), as: UTF8.self)
        let b = form.boundary

        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=\(b)")
        XCTAssertTrue(b.hasPrefix("dicta-"))
        XCTAssertEqual(body, """
            --\(b)\r
            Content-Disposition: form-data; name="file"; filename="audio.wav"\r
            Content-Type: audio/wav\r
            \r
            RIFF\r
            --\(b)\r
            Content-Disposition: form-data; name="model"\r
            \r
            saaras:v4\r
            --\(b)--\r

            """)
    }

    func testBoundaryIsUniquePerForm() {
        XCTAssertNotEqual(MultipartForm().boundary, MultipartForm().boundary)
    }

    func testFinalizeDoesNotMutateSoItCanBeCalledTwice() {
        var form = MultipartForm()
        form.addField(name: "a", value: "1")
        XCTAssertEqual(form.finalize(), form.finalize())
    }
}
