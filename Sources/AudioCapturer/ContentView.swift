import SwiftUI

struct ContentView: View {
    @State private var appsProvider = RunningAppsProvider()
    @State private var manager = RecordingManager()
    @State private var selectedBundleID: String = ""
    @State private var selectedFormat: AudioFormat = .m4a
    @State private var selectedLanguage: TranscriptionLanguage = .es

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Audio Capturer")
                .font(.title2)
                .fontWeight(.semibold)

            // App picker
            LabeledContent("Application") {
                Picker("", selection: $selectedBundleID) {
                    Text("Select an app...").tag("")
                    ForEach(appsProvider.apps) { app in
                        HStack(spacing: 6) {
                            Image(nsImage: app.icon)
                            Text(app.name)
                        }
                        .tag(app.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            // Format picker
            LabeledContent("Format") {
                Picker("", selection: $selectedFormat) {
                    Text("M4A").tag(AudioFormat.m4a)
                    Text("WAV").tag(AudioFormat.wav)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Language picker
            LabeledContent("Language") {
                Picker("", selection: $selectedLanguage) {
                    ForEach(TranscriptionLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider()

            // Start / Stop button
            HStack {
                if manager.isRecording {
                    Button {
                        manager.stop()
                    } label: {
                        Label("Stop Recording", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        manager.start(bundleID: selectedBundleID, format: selectedFormat, language: selectedLanguage)
                    } label: {
                        Label("Start Recording", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBundleID.isEmpty)
                }
            }

            // Status
            HStack(spacing: 8) {
                if manager.isRecording {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative)
                    Text(formatTime(manager.elapsedSeconds))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if manager.currentChunkIndex > 0 {
                        Text("Chunk \(manager.currentChunkIndex)")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                    }
                }

                Text(manager.statusMessage)
                    .foregroundStyle(manager.errorMessage != nil ? .red : .secondary)
            }
            .font(.callout)

            if let error = manager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Recordings list
            if !manager.recordedFiles.isEmpty {
                Divider()

                Text("Recordings")
                    .font(.headline)

                List(manager.recordedFiles) { file in
                    let isTxt = file.name.hasSuffix(".txt")
                    HStack {
                        Image(systemName: isTxt ? "doc.text" : "waveform")
                            .foregroundStyle(
                                isTxt ? .green : file.name.hasSuffix(".m4a") ? .purple : .blue
                            )
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(formatFileSize(file.size))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        if !isTxt {
                            transcriptionBadge(for: file.url)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        if isTxt {
                            openInZed(file.url)
                        } else {
                            NSWorkspace.shared.open(file.url)
                        }
                    }
                    .contextMenu {
                        Button("Open") {
                            NSWorkspace.shared.open(file.url)
                        }
                        if let txtURL = transcriptURL(for: file.url),
                           FileManager.default.fileExists(atPath: txtURL.path) {
                            Button("Show Transcript") {
                                let process = Process()
                                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                                process.arguments = ["zed-preview", txtURL.path]
                                try? process.run()
                            }
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(
                                file.url.path, inFileViewerRootedAtPath: "")
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            try? FileManager.default.removeItem(at: file.url)
                            manager.refreshFiles()
                        }
                    }
                }
                .frame(height: 180)
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .padding(24)
        .frame(width: 400)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            manager.refreshFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.refreshFiles()
        }
    }

    @ViewBuilder
    private func transcriptionBadge(for url: URL) -> some View {
        switch manager.transcriber.statuses[url] {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .running:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case nil:
            EmptyView()
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func transcriptURL(for audioURL: URL) -> URL? {
        let name = audioURL.deletingPathExtension().lastPathComponent
        // Strip "-chunkXXX" suffix to get the session name
        guard let range = name.range(of: #"-chunk\d+$"#, options: .regularExpression) else {
            return nil
        }
        let sessionName = String(name[name.startIndex..<range.lowerBound])
        return audioURL.deletingLastPathComponent().appendingPathComponent("\(sessionName).txt")
    }

    private func openInZed(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["zed-preview", url.path]
        try? process.run()
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
