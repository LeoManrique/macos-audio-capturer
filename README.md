# MacOS Audio Capturer

macOS app that records audio from any running application. Built with SwiftUI and CoreAudio's `AudioHardwareCreateProcessTap` API.

## Requirements

- macOS 26+ (requires `CATapDescription.bundleIDs` API)
- Apple Silicon
- Swift 6.2+

## Build & Run

```bash
swift build
.build/debug/AudioCapturer
```

## Usage

1. Select a running app from the dropdown
2. Choose format (M4A or WAV)
3. Click **Start Recording**
4. Click **Stop Recording** when done

Recordings are saved to `./output/`. Double-click to open, right-click for more options.

## Transcription

See [TRANSCRIBE.md](TRANSCRIBE.md) for generating transcripts from recordings using WhisperKit.
