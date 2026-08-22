import XCTest
@testable import Dicta

final class ReleaseNotesSummaryTests: XCTestCase {
    func testStripsTagsAndTakesFirstNonEmptyLine() {
        let html = "<h2>0.1.0</h2><ul><li>Fixed &amp; improved &lt;things&gt;</li><li>Second</li></ul>"
        XCTAssertEqual(ReleaseNotesSummary.firstLine(ofHTML: html), "0.1.0")
    }

    func testDecodesEntitiesAndSkipsBlankLeadingLines() {
        let html = "<p>  </p><p>It&#39;s &quot;done&quot;<br/>more</p>"
        XCTAssertEqual(ReleaseNotesSummary.firstLine(ofHTML: html), "It's \"done\"")
    }

    func testEmptyOrTagOnlyNotesYieldNil() {
        XCTAssertNil(ReleaseNotesSummary.firstLine(ofHTML: ""))
        XCTAssertNil(ReleaseNotesSummary.firstLine(ofHTML: "<p></p><br>"))
    }
}
