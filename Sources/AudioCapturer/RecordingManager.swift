import Foundation
import Observation
import os

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
    static let outputDirectory = URL(
        fileURLWithPath: "./output")

    var isRecording = false
    var elapsedSeconds = 0
    var statusMessage = "Idle"
    var errorMessage: String?
    var recordedFiles: [RecordedFile] = []
    var currentChunkIndex = 0

    let chunkingConfig = ChunkingConfig()
    let transcriptionConfig = TranscriptionConfig()
    let transcriber = ChunkTranscriber()

    private var tap: ProcessTap?
    private var aggregate: AggregateDevice?
    private var recorder: AudioRecorder?
    private var silenceDetector: SilenceDetector?
    private var timer: Timer?
    private var chunkMonitor: ChunkMonitor?
    private var currentChunkURL: URL?
    private var currentBundleID = ""
    private var currentFormat: AudioFormat = .m4a
    private var sessionTimestamp = ""

    /// Thread-safe chunk elapsed time, read by the background timer and written by the main-thread timer.
    @ObservationIgnored
    private let _chunkElapsed = OSAllocatedUnfairLock(initialState: TimeInterval(0))

    /// Set to true by the background timer when rotation is needed, consumed by the main-thread timer.
    @ObservationIgnored
    private let _shouldRotate = OSAllocatedUnfairLock(initialState: false)

    func start(bundleID: String, format: AudioFormat) {
        guard !isRecording else { return }

        errorMessage = nil
        currentBundleID = bundleID
        currentFormat = format

        do {
            let tap = try ProcessTap(bundleID: bundleID)
            self.tap = tap

            let aggregate = try AggregateDevice(tapUUID: tap.tapUUID)
            self.aggregate = aggregate

            let detector = SilenceDetector(threshold: chunkingConfig.silenceThreshold)
            self.silenceDetector = detector

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            sessionTimestamp = formatter.string(from: Date())

            currentChunkIndex = 1
            let outputURL = makeOutputURL(
                bundleID: bundleID, format: format, chunkIndex: currentChunkIndex)
            currentChunkURL = outputURL

            let recorder = try AudioRecorder(
                aggregateDevice: aggregate,
                tapFormat: tap.format,
                outputURL: outputURL,
                format: format,
                silenceDetector: detector
            )
            self.recorder = recorder

            try recorder.start()

            // Create empty transcript file so it's visible immediately
            let txtURL = transcriptURL()
            FileManager.default.createFile(atPath: txtURL.path, contents: nil)

            refreshFiles()

            isRecording = true
            elapsedSeconds = 0
            _chunkElapsed.withLock { $0 = 0 }
            statusMessage = "Recording..."

            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsedSeconds += 1
                    self._chunkElapsed.withLock { $0 += 1 }

                    // Check if the background silence detector flagged a rotation
                    let needsRotation = self._shouldRotate.withLock { val -> Bool in
                        let v = val; val = false; return v
                    }
                    if needsRotation {
                        self.rotateChunk()
                    }
                }
            }

            chunkMonitor = ChunkMonitor(
                detector: detector,
                config: chunkingConfig,
                chunkElapsed: _chunkElapsed,
                shouldRotate: _shouldRotate
            )
        } catch {
            cleanup()
            errorMessage = error.localizedDescription
            statusMessage = "Error"
        }
    }

    func stop() {
        guard isRecording else { return }

        chunkMonitor?.cancel()
        chunkMonitor = nil

        recorder?.stop()
        aggregate?.destroy()
        tap?.destroy()

        timer?.invalidate()
        timer = nil

        isRecording = false
        statusMessage = "Saved"

        // Transcribe the final chunk
        if let url = currentChunkURL {
            transcriber.transcribe(audioURL: url, transcriptURL: transcriptURL())
        }

        recorder = nil
        aggregate = nil
        tap = nil
        silenceDetector = nil
        currentChunkURL = nil

        refreshFiles()
    }

    func refreshFiles() {
        let dir = Self.outputDirectory
        guard
            let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )
        else {
            recordedFiles = []
            return
        }

        recordedFiles =
            contents
            .filter { ["wav", "m4a", "txt"].contains($0.pathExtension.lowercased()) }
            .compactMap { url -> RecordedFile? in
                guard
                    let values = try? url.resourceValues(forKeys: [
                        .fileSizeKey, .contentModificationDateKey,
                    ])
                else {
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

    // MARK: - Chunking

    private func rotateChunk() {
        guard isRecording, let recorder else { return }

        let completedURL = currentChunkURL
        currentChunkIndex += 1
        let newURL = makeOutputURL(
            bundleID: currentBundleID, format: currentFormat, chunkIndex: currentChunkIndex)

        do {
            try recorder.rotateFile(newURL: newURL, format: currentFormat)
            currentChunkURL = newURL
            silenceDetector?.reset()
            _chunkElapsed.withLock { $0 = 0 }
            statusMessage = "Recording... (chunk \(currentChunkIndex))"

            if let url = completedURL {
                transcriber.transcribe(audioURL: url, transcriptURL: transcriptURL())
            }

            refreshFiles()
        } catch {
            errorMessage = "Chunk rotation failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func cleanup() {
        recorder?.stop()
        aggregate?.destroy()
        tap?.destroy()
        chunkMonitor?.cancel()
        chunkMonitor = nil
        timer?.invalidate()
        timer = nil
        recorder = nil
        aggregate = nil
        tap = nil
        silenceDetector = nil
        currentChunkURL = nil
        isRecording = false
    }

    private func makeOutputURL(bundleID: String, format: AudioFormat, chunkIndex: Int) -> URL {
        let dir = Self.outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let appName = bundleID.components(separatedBy: ".").last ?? bundleID
        let filename =
            "\(appName)-\(sessionTimestamp)-chunk\(String(format: "%03d", chunkIndex)).\(format.rawValue)"
        return dir.appendingPathComponent(filename)
    }

    /// Single transcript file for the entire session (no chunk suffix).
    private func transcriptURL() -> URL {
        let appName = currentBundleID.components(separatedBy: ".").last ?? currentBundleID
        return Self.outputDirectory.appendingPathComponent("\(appName)-\(sessionTimestamp).txt")
    }
}
