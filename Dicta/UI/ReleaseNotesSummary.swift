import Foundation
import Sparkle

enum ReleaseNotesSummary {
    /// First non-empty line of an HTML release-notes blob as plain text, for the one-line popover card.
    static func firstLine(ofHTML html: String) -> String? {
        let text = html
            .replacingOccurrences(of: "<br\\s*/?>|</p>|</li>|</h[1-6]>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        return text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }
}

extension SUAppcastItem {
    /// First line of the release notes as plain text (tags stripped). Nil when the appcast item has no `<description>`.
    var releaseNotesSummary: String? {
        itemDescription.flatMap(ReleaseNotesSummary.firstLine(ofHTML:))
    }
}
