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

    func transcribe(audioURL: URL, transcriptURL: URL) {
        statuses[audioURL] = .pending
        let config = self.config

        // Dispatch to the serial queue so chunks are transcribed in FIFO order.
        // Each block calls waitUntilExit(), so the next block won't start until
        // the previous one finishes.
        serialQueue.async { [weak self] in
            DispatchQueue.main.async { self?.statuses[audioURL] = .running }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: config.whisperPath)
            process.arguments = [
                "transcribe",
                "--model", config.whisperModel,
                "--language", config.language,
                "--audio-path", audioURL.path,
            ]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let msg = "whisperkit-cli exited with status \(process.terminationStatus)"
                    DispatchQueue.main.async { self?.statuses[audioURL] = .failed(msg) }
                    return
                }

                let rawData = stdout.fileHandleForReading.readDataToEndOfFile()
                let trimmed = String(data: rawData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !trimmed.isEmpty else {
                    DispatchQueue.main.async { self?.statuses[audioURL] = .completed(transcriptURL) }
                    return
                }

                // Append to the shared transcript file
                if let existingData = try? Data(contentsOf: transcriptURL),
                   let existing = String(data: existingData, encoding: .utf8),
                   !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    let cleaned = existing.trimmingCharacters(in: .whitespacesAndNewlines)
                    try Data("\(cleaned) \(trimmed)\n".utf8).write(to: transcriptURL)
                } else {
                    try Data("\(trimmed)\n".utf8).write(to: transcriptURL)
                }

                DispatchQueue.main.async { self?.statuses[audioURL] = .completed(transcriptURL) }
            } catch {
                let msg = error.localizedDescription
                DispatchQueue.main.async { self?.statuses[audioURL] = .failed(msg) }
            }
        }
    }
}
