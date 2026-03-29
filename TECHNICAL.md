# Technical Details

## Architecture

```
AudioCapturerApp.swift    → @main SwiftUI entry point
ContentView.swift         → UI: app picker, format picker, start/stop, file list
RecordingManager.swift    → Orchestrates the recording pipeline
RunningAppsProvider.swift → Lists running GUI apps via NSWorkspace
ProcessTap.swift          → Creates CoreAudio process tap
AggregateDevice.swift     → Wraps tap + output device into aggregate device
AudioRecorder.swift       → IOProc callback + ExtAudioFile writing
CoreAudioHelpers.swift    → AudioObjectID property reading utilities
```

## Recording Pipeline

```
ProcessTap → AggregateDevice → IOProc callback → ExtAudioFile
```

1. **ProcessTap** — Creates a `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` with `.bundleIDs` set to the target app. This captures audio from all processes matching the bundle ID (important for multi-process apps like Chrome). Audio remains unmuted during capture.

2. **AggregateDevice** — Combines the tap with the default system output device via `AudioHardwareCreateAggregateDevice`. The tap UUID links them, and `kAudioAggregateDeviceTapAutoStartKey` auto-starts the tap.

3. **AudioRecorder** — Registers an IOProc on the aggregate device via `AudioDeviceCreateIOProcIDWithBlock`. The callback receives `AudioBufferList` data and writes it to disk using `ExtAudioFileWrite`. The dispatch queue is retained as a property to prevent deallocation.

4. **File output** — WAV writes raw PCM (48kHz, stereo, Float32). M4A uses AAC compression (~125kbps, ~15x smaller).

## Key Decisions

- **`stereoGlobalTapButExcludeProcesses` + `bundleIDs`** instead of `stereoMixdownOfProcesses`: The mixdown initializer requires AudioObjectIDs and doesn't work with multi-process apps. The global tap with `bundleIDs` filter handles this correctly.
- **`ExtAudioFile`** instead of `AVAudioFile`: ExtAudioFile explicitly finalizes the file on `dispose()`, preventing corrupt headers if the process is interrupted.
- **`readTapFormat` uses `AudioObjectGetPropertyDataSize` first**: Direct `readProperty` with a fixed size fails for tap format on some macOS versions.
- **AppDelegate for activation**: SPM-built SwiftUI apps need `NSApplication.setActivationPolicy(.regular)` to show windows.
