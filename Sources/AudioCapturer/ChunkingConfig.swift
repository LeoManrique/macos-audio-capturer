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

struct TranscriptionConfig {
    var whisperModel: String = "large-v3_turbo"
    var language: String = "es"
    var whisperPath: String = "/opt/homebrew/bin/whisperkit-cli"
}
