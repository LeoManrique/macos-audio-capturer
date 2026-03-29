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
    private let queue = DispatchQueue(label: "com.audiocapturer.transcription", qos: .utility)

    init(config: TranscriptionConfig = TranscriptionConfig()) {
        self.config = config
    }

    func transcribe(audioURL: URL, transcriptURL: URL) {
        statuses[audioURL] = .pending
        let config = self.config

        Task { @MainActor in
            self.statuses[audioURL] = .running

            enum Outcome { case success(URL), failure(String) }

            let outcome: Outcome = await withCheckedContinuation { continuation in
                queue.async {
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
                            continuation.resume(
                                returning: .failure(
                                    "whisperkit-cli exited with status \(process.terminationStatus)"
                                ))
                            return
                        }

                        let data = stdout.fileHandleForReading.readDataToEndOfFile()

                        // Append to the shared transcript file with a space separator
                        if let existingSize = try? FileManager.default.attributesOfItem(atPath: transcriptURL.path)[.size] as? Int,
                           existingSize > 0 {
                            let handle = try FileHandle(forWritingTo: transcriptURL)
                            handle.seekToEndOfFile()
                            handle.write(Data(" ".utf8))
                            handle.write(data)
                            handle.closeFile()
                        } else {
                            try data.write(to: transcriptURL)
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
