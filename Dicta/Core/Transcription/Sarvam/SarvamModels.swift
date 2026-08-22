import Foundation

// The Sarvam speech-to-text vocabulary: what the Settings window offers and what `SarvamTranscriber` sends.
// Endpoint reference: https://docs.sarvam.ai/api-reference-docs/speech-to-text/transcribe

enum SarvamModel: String, CaseIterable, Identifiable {
    case saarasV4 = "saaras:v4"
    case saarasV3 = "saaras:v3"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .saarasV4: return "Saaras v4 (latest)"
        case .saarasV3: return "Saaras v3"
        }
    }
}

enum SarvamMode: String, CaseIterable, Identifiable {
    case transcribe, translate, verbatim, translit, codemix
    var id: String { rawValue }
    var title: String {
        switch self {
        case .transcribe: return "Transcribe"
        case .translate: return "Translate to English"
        case .verbatim: return "Verbatim (keep fillers)"
        case .translit: return "Transliterate"
        case .codemix: return "Code-mixed"
        }
    }
}

struct SarvamLanguage: Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let autoDetect = SarvamLanguage(code: "unknown", name: "Auto-detect")
    static let all: [SarvamLanguage] = [
        autoDetect,
        .init(code: "en-IN", name: "English"),
        .init(code: "hi-IN", name: "Hindi"),
        .init(code: "bn-IN", name: "Bengali"),
        .init(code: "gu-IN", name: "Gujarati"),
        .init(code: "kn-IN", name: "Kannada"),
        .init(code: "ml-IN", name: "Malayalam"),
        .init(code: "mr-IN", name: "Marathi"),
        .init(code: "od-IN", name: "Odia"),
        .init(code: "pa-IN", name: "Punjabi"),
        .init(code: "ta-IN", name: "Tamil"),
        .init(code: "te-IN", name: "Telugu"),
        .init(code: "as-IN", name: "Assamese"),
        .init(code: "ur-IN", name: "Urdu"),
        .init(code: "ne-IN", name: "Nepali"),
        .init(code: "kok-IN", name: "Konkani"),
        .init(code: "ks-IN", name: "Kashmiri"),
        .init(code: "sd-IN", name: "Sindhi"),
        .init(code: "sa-IN", name: "Sanskrit"),
        .init(code: "sat-IN", name: "Santali"),
        .init(code: "mni-IN", name: "Manipuri"),
        .init(code: "brx-IN", name: "Bodo"),
        .init(code: "mai-IN", name: "Maithili"),
        .init(code: "doi-IN", name: "Dogri"),
    ]
}

/// Everything one upload needs. Defaults for "no saved setting yet" live in `Preferences.init`, not here,
/// so there is one place that decides them.
struct SarvamConfig {
    var apiKey: String
    var model: SarvamModel
    var languageCode: String
    var mode: SarvamMode
}

enum SarvamError: LocalizedError {
    case missingAPIKey
    case noAudio
    case http(status: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add your Sarvam AI API key in Settings."
        case .noAudio: return "No audio was captured."
        case .http(let status, let message):
            switch status {
            case 401, 403: return "Sarvam rejected the API key (\(status))."
            case 429: return "Sarvam rate limit reached — try again in a moment."
            default: return "Sarvam error \(status): \(message)"
            }
        case .badResponse: return "Unexpected response from Sarvam."
        }
    }
}
