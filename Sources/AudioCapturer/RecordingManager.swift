import Foundation
import Observation

struct RecordedFile: Identifiable {
    let id: String
    let url: URL
    var name: String { url.lastPathComponent }
    let size: Int64
    let date: Date
}

@Observable
@MainActor
final class RecordingManager {
    static let outputDirectory = URL(fileURLWithPath: "/Users/leo/Dev/LeoManrique/Etc/macos-audio-capturer/output")

    var isRecording = false
    var elapsedSeconds = 0
    var statusMessage = "Idle"
    var errorMessage: String?
    var recordedFiles: [RecordedFile] = []

    private var tap: ProcessTap?
    private var aggregate: AggregateDevice?
    private var recorder: AudioRecorder?
    private var timer: Timer?

    func start(bundleID: String, format: AudioFormat) {
        guard !isRecording else { return }

        errorMessage = nil

        do {
            let tap = try ProcessTap(bundleID: bundleID)
            self.tap = tap

            let aggregate = try AggregateDevice(tapUUID: tap.tapUUID)
            self.aggregate = aggregate

            let outputURL = makeOutputURL(bundleID: bundleID, format: format)

            let recorder = try AudioRecorder(
                aggregateDevice: aggregate,
                tapFormat: tap.format,
                outputURL: outputURL,
                format: format
            )
            self.recorder = recorder

            try recorder.start()

            isRecording = true
            elapsedSeconds = 0
            statusMessage = "Recording..."

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.elapsedSeconds += 1
                }
            }
        } catch {
            cleanup()
            errorMessage = error.localizedDescription
            statusMessage = "Error"
        }
    }

    func stop() {
        guard isRecording else { return }

        recorder?.stop()
        aggregate?.destroy()
        tap?.destroy()

        timer?.invalidate()
        timer = nil

        isRecording = false
        statusMessage = "Saved"

        recorder = nil
        aggregate = nil
        tap = nil

        refreshFiles()
    }

    func refreshFiles() {
        let dir = Self.outputDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            recordedFiles = []
            return
        }

        recordedFiles = contents
            .filter { ["wav", "m4a"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> RecordedFile? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
                    return nil
                }
                return RecordedFile(
                    id: url.path,
                    url: url,
                    size: Int64(values.fileSize ?? 0),
                    date: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.date > $1.date }
    }

    private func cleanup() {
        recorder?.stop()
        aggregate?.destroy()
        tap?.destroy()
        timer?.invalidate()
        timer = nil
        recorder = nil
        aggregate = nil
        tap = nil
        isRecording = false
    }

    private func makeOutputURL(bundleID: String, format: AudioFormat) -> URL {
        let dir = Self.outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let appName = bundleID.components(separatedBy: ".").last ?? bundleID
        let filename = "\(appName)-\(timestamp).\(format.rawValue)"
        return dir.appendingPathComponent(filename)
    }
}
