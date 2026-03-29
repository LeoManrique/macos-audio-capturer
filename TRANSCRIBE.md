# Transcribe Audio

Requires [WhisperKit CLI](https://github.com/argmaxinc/WhisperKit):

```bash
brew install whisperkit-cli
```

## Usage

```bash
whisperkit-cli transcribe --model large-v3_turbo --language es --audio-path output/your-file.m4a
```

Save to file:

```bash
whisperkit-cli transcribe --model large-v3_turbo --language es --audio-path output/your-file.m4a > transcript.txt
```

## Strip silence (faster transcription)

Whisper processes fixed 30-second chunks regardless of content. Remove silent segments first to speed things up:

```bash
ffmpeg -i output/your-file.m4a -af silenceremove=stop_periods=-1:stop_duration=0.5:stop_threshold=-40dB output/trimmed.m4a
```
