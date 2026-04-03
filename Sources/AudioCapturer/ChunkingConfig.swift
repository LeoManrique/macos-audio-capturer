import Foundation

struct ChunkingConfig {
    /// Seconds of recording before silence detection activates for each chunk
    var chunkMinDuration: TimeInterval = 5

    /// RMS energy below this value counts as silence (linear scale, 0–1)
    var silenceThreshold: Float = 0.005

    /// Continuous silence required to trigger a chunk cut (milliseconds)
    var silenceDuration: Int = 300

    /// Force a chunk cut after this many seconds regardless of silence
    var hardCeilingDuration: TimeInterval = 300

    /// How often to poll the silence detector once active (seconds)
    var pollInterval: TimeInterval = 0.1
}

enum TranscriptionLanguage: String, CaseIterable {
    case en, es, fr, de, it, pt, ja, ko, zh, ru, ar, hi, nl, pl, sv, tr

    var displayName: String {
        switch self {
        case .en: "English"
        case .es: "Spanish"
        case .fr: "French"
        case .de: "German"
        case .it: "Italian"
        case .pt: "Portuguese"
        case .ja: "Japanese"
        case .ko: "Korean"
        case .zh: "Chinese"
        case .ru: "Russian"
        case .ar: "Arabic"
        case .hi: "Hindi"
        case .nl: "Dutch"
        case .pl: "Polish"
        case .sv: "Swedish"
        case .tr: "Turkish"
        }
    }
}

struct TranscriptionConfig {
    var whisperModel: String = "large-v3_turbo"
    var language: TranscriptionLanguage = .es
    var whisperPath: String = "/opt/homebrew/bin/whisperkit-cli"
}
