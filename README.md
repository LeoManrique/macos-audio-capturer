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

## Automatic Transcription

During recording, audio is automatically split into chunks at silence boundaries and transcribed in real-time using [WhisperKit](https://github.com/argmaxinc/WhisperKit) (`large-v3-turbo` model). A single `.txt` transcript file is produced per session, with chunks appended in chronological order.

Requires:

```bash
brew install whisperkit-cli
```

## Manual Transcription

See [TRANSCRIBE.md](TRANSCRIBE.md) for manually transcribing recordings.
