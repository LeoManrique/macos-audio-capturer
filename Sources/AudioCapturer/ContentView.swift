import SwiftUI

struct ContentView: View {
    @State private var appsProvider = RunningAppsProvider()
    @State private var manager = RecordingManager()
    @State private var selectedBundleID: String = ""
    @State private var selectedFormat: AudioFormat = .m4a

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
                        manager.start(bundleID: selectedBundleID, format: selectedFormat)
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
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundStyle(file.name.hasSuffix(".m4a") ? .purple : .blue)
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
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        NSWorkspace.shared.open(file.url)
                    }
                    .contextMenu {
                        Button("Open") {
                            NSWorkspace.shared.open(file.url)
                        }
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
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
        .frame(width: 380)
        .fixedSize(horizontal: true, vertical: false)
        .onAppear {
            manager.refreshFiles()
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
