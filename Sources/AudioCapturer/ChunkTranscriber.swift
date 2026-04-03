import Foundation
import Observation

enum TranscriptionStatus: Equatable {
    case pending
    case running
    case completed(URL)
    case failed(String)
}

@Observable
@MainActor
final class ChunkTranscriber {
    var statuses: [URL: TranscriptionStatus] = [:]

    private let config: TranscriptionConfig
    private let serialQueue = DispatchQueue(label: "com.audiocapturer.transcription", qos: .utility)

    init(config: TranscriptionConfig = TranscriptionConfig()) {
        self.config = config
    }

    func transcribe(audioURL: URL, transcriptURL: URL, language: TranscriptionLanguage? = nil) {
        statuses[audioURL] = .pending

        var effectiveConfig = config
        if let language { effectiveConfig.language = language }
        let config = effectiveConfig

        Task { @MainActor in
            self.statuses[audioURL] = .running

            enum Outcome { case success(URL), failure(String) }

            let outcome: Outcome = await withCheckedContinuation { continuation in
                serialQueue.async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: config.whisperPath)
                    process.arguments = [
                        "transcribe",
                        "--model", config.whisperModel,
                        "--language", config.language.rawValue,
                        "--audio-path", audioURL.path,
                    ]

                    let stdout = Pipe()
                    process.standardOutput = stdout
                    process.standardError = Pipe()

                    do {
                        try process.run()
                        process.waitUntilExit()

                        guard process.terminationStatus == 0 else {
                            continuation.resume(
                                returning: .failure(
                                    "whisperkit-cli exited with status \(process.terminationStatus)"
                                ))
                            return
                        }

                        let rawData = stdout.fileHandleForReading.readDataToEndOfFile()
                        let trimmed = String(data: rawData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                        guard !trimmed.isEmpty else {
                            continuation.resume(returning: .success(transcriptURL))
                            return
                        }

                        // Append to the shared transcript file with a space separator
                        if let existingData = try? Data(contentsOf: transcriptURL),
                           let existing = String(data: existingData, encoding: .utf8),
                           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        {
                            let cleaned = existing.trimmingCharacters(in: .whitespacesAndNewlines)
                            try Data("\(cleaned) \(trimmed)\n".utf8).write(to: transcriptURL)
                        } else {
                            try Data("\(trimmed)\n".utf8).write(to: transcriptURL)
                        }

                        continuation.resume(returning: .success(transcriptURL))
                    } catch {
                        continuation.resume(returning: .failure(error.localizedDescription))
                    }
                }
            }

            switch outcome {
            case .success(let url):
                self.statuses[audioURL] = .completed(url)
            case .failure(let message):
                self.statuses[audioURL] = .failed(message)
            }
        }
    }
}
