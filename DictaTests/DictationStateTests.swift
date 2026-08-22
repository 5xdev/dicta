import XCTest
@testable import Dicta

@MainActor
final class DictationStateTests: XCTestCase {
    typealias State = DictationController.State

    func testRecordingWinsOverEverything() {
        XCTAssertEqual(State.resolve(recording: true, error: "x", uploadsInFlight: 3), .recording)
    }

    func testErrorWinsOverUploads() {
        XCTAssertEqual(State.resolve(recording: false, error: "x", uploadsInFlight: 3), .error("x"))
    }

    func testUploadsInFlightMeansTranscribing() {
        XCTAssertEqual(State.resolve(recording: false, error: nil, uploadsInFlight: 1), .transcribing)
    }

    func testNothingGoingOnIsIdle() {
        XCTAssertEqual(State.resolve(recording: false, error: nil, uploadsInFlight: 0), .idle)
    }
}
