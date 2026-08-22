import XCTest
@testable import Dicta

final class SarvamModelsTests: XCTestCase {
    func testLanguageCodesAreUniqueAndAutoDetectComesFirst() {
        let codes = SarvamLanguage.all.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count)
        XCTAssertEqual(SarvamLanguage.all.first?.code, SarvamLanguage.autoDetect.code)
        XCTAssertEqual(SarvamLanguage.autoDetect.code, "unknown")   // Sarvam's sentinel for auto-detect
    }

    func testModelAndModeRawValuesAreTheWireFormat() {
        XCTAssertEqual(SarvamModel.saarasV4.rawValue, "saaras:v4")
        XCTAssertEqual(SarvamMode.allCases.map(\.rawValue), ["transcribe", "translate", "verbatim", "translit", "codemix"])
    }

    func testHTTPErrorsGetUserFacingMessages() {
        XCTAssertEqual(SarvamError.http(status: 401, message: "x").errorDescription, "Sarvam rejected the API key (401).")
        XCTAssertEqual(SarvamError.http(status: 403, message: "x").errorDescription, "Sarvam rejected the API key (403).")
        XCTAssertEqual(SarvamError.http(status: 429, message: "x").errorDescription, "Sarvam rate limit reached — try again in a moment.")
        XCTAssertEqual(SarvamError.http(status: 500, message: "boom").errorDescription, "Sarvam error 500: boom")
        XCTAssertNotNil(SarvamError.missingAPIKey.errorDescription)
        XCTAssertNotNil(SarvamError.noAudio.errorDescription)
        XCTAssertNotNil(SarvamError.badResponse.errorDescription)
    }
}
