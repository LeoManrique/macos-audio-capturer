# Technical Details

## Architecture

```
AudioCapturerApp.swift    → @main SwiftUI entry point
ContentView.swift         → UI: app picker, format picker, start/stop, file list
RecordingManager.swift    → Orchestrates recording, chunking, and transcription
RunningAppsProvider.swift → Lists running GUI apps via NSWorkspace
ProcessTap.swift          → Creates CoreAudio process tap
AggregateDevice.swift     → Wraps tap + output device into aggregate device
AudioRecorder.swift       → IOProc callback + ExtAudioFile writing
CoreAudioHelpers.swift    → AudioObjectID property reading utilities
SilenceDetector.swift     → Real-time RMS energy analysis on audio buffers
ChunkMonitor.swift        → Background polling to trigger chunk rotation
ChunkTranscriber.swift    → Serial whisperkit-cli process execution
ChunkingConfig.swift      → Tunable parameters for chunking and transcription
```

## Recording Pipeline

```
ProcessTap → AggregateDevice → IOProc callback → ExtAudioFile
```

1. **ProcessTap** — Creates a `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` with `.bundleIDs` set to the target app. This captures audio from all processes matching the bundle ID (important for multi-process apps like Chrome). Audio remains unmuted during capture.

2. **AggregateDevice** — Combines the tap with the default system output device via `AudioHardwareCreateAggregateDevice`. The tap UUID links them, and `kAudioAggregateDeviceTapAutoStartKey` auto-starts the tap.

3. **AudioRecorder** — Registers an IOProc on the aggregate device via `AudioDeviceCreateIOProcIDWithBlock`. The callback receives `AudioBufferList` data and writes it to disk using `ExtAudioFileWrite`. The dispatch queue is retained as a property to prevent deallocation.

4. **File output** — WAV writes raw PCM (48kHz, stereo, Float32). M4A uses AAC compression (~125kbps, ~15x smaller).

## Chunking & Transcription Pipeline

```
AudioRecorder → SilenceDetector → ChunkMonitor → RecordingManager.rotateChunk() → ChunkTranscriber
```

1. **SilenceDetector** — Runs on the real-time audio thread. Calculates RMS energy per buffer and tracks how long silence has lasted. Uses `Mutex` and `mach_absolute_time()` for thread-safe, precise timing.

2. **ChunkMonitor** — Polls the silence detector on a utility `DispatchSourceTimer`. Signals rotation when either: silence exceeds threshold after minimum chunk duration (default 5s), or the hard ceiling is reached (default 5 min). Communicates via `OSAllocatedUnfairLock` flags — no MainActor blocking.

3. **RecordingManager.rotateChunk()** — Called on the main thread when the monitor flags rotation. Stops the current ExtAudioFile, creates a new one, resets the silence detector, and enqueues the completed chunk for transcription.

4. **ChunkTranscriber** — Spawns `whisperkit-cli` processes on a **serial dispatch queue**, guaranteeing chronological transcript order regardless of chunk duration. Each chunk's output is appended to a single `.txt` file per session.

## Key Decisions

- **`stereoGlobalTapButExcludeProcesses` + `bundleIDs`** instead of `stereoMixdownOfProcesses`: The mixdown initializer requires AudioObjectIDs and doesn't work with multi-process apps. The global tap with `bundleIDs` filter handles this correctly.
- **`ExtAudioFile`** instead of `AVAudioFile`: ExtAudioFile explicitly finalizes the file on `dispose()`, preventing corrupt headers if the process is interrupted.
- **`readTapFormat` uses `AudioObjectGetPropertyDataSize` first**: Direct `readProperty` with a fixed size fails for tap format on some macOS versions.
- **AppDelegate for activation**: SPM-built SwiftUI apps need `NSApplication.setActivationPolicy(.regular)` to show windows.
- **Serial transcription queue**: Chunks are transcribed in strict FIFO order to prevent shorter chunks from being appended to the transcript before longer ones that preceded them.
- **Silence-based chunk boundaries**: Splitting at silence avoids cutting words mid-sentence, producing cleaner transcripts than fixed-duration chunks.
