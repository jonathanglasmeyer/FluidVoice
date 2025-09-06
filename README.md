# FluidVoice 🎙️

![Work in Progress](https://img.shields.io/badge/Status-Work%20in%20Progress-orange?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9+-red?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![CoreML](https://img.shields.io/badge/CoreML-✓-blue?style=flat-square)
![MLX](https://img.shields.io/badge/MLX-✓-purple?style=flat-square)

> ⚠️ **Heavy development in progress** - Features and APIs may change frequently.

macOS menu bar app for audio transcription. Press ⌘⇧Space to start recording, press again to stop. Text appears directly in your current application.

<p align="center">
  <img src="FluidVoiceIcon.png" width="128" height="128" alt="FluidVoice Icon">
</p>

## Features

### Local Transcription
- **WhisperKit**: CoreML acceleration, 6 model sizes (39MB - 2.9GB)
- **Parakeet v3**: 25 European languages, daemon mode, auto-detection

### Technical Features
- Model preloading eliminates startup delays
- Daemon architecture for fast response times

## Legacy Features (Will Be Removed)
- **Window-based recording**: Recording window interface (disable "Express Mode" in settings)
- **Manual copy/paste workflow**: Use background mode instead
- **Cloud APIs**: OpenAI Whisper, Google Gemini (use local transcription instead)

## Requirements 📋
- macOS 14.0 (Sonoma) or later
- Swift 5.9+ (for building from source)

## Installation 🛠️
### Option 1: Download Pre-built App
TBD

### Option 2: Build from Source
```bash
git clone https://github.com/mazdak/FluidVoice.git
cd FluidVoice
source .build-config && fv-build
cp -r FluidVoice-dev.app /Applications/FluidVoice.app
```

## Setup 🔧

### Local Transcription (Recommended)

**WhisperKit**
- No API key required
- Audio stays on your device
- CoreML hardware acceleration with Neural Engine
- 6 model sizes available (39MB to 2.9GB)
- Models download automatically on first use

**Parakeet v3**
- No API key required
- 25 European languages with automatic detection
- MLX framework optimized for Apple Silicon
- Daemon mode for fast response times
- ~600MB model downloads on setup
- Setup via "Download Parakeet v3 Model" in settings

### Legacy Cloud APIs
- OpenAI Whisper and Google Gemini are still available but will be removed
- Requires API keys and sends audio to external servers
- Use local transcription for better privacy and performance

## Usage 🎯

1. Press ⌘⇧Space to start recording (background, no window)
2. Press ⌘⇧Space again to stop and transcribe
3. Text appears directly in current application

The app lives in your menu bar - click the microphone icon for settings.

### Legacy Window Mode
If you disable "Express Mode" in settings, FluidVoice will use the old window-based interface. This mode will be removed in future versions.



## Privacy & Security 🔒

- **Local Processing**: Audio stays on your device with WhisperKit and Parakeet
- **No Network Requests**: All transcription happens locally
- **No Tracking**: No usage data or analytics collected
- **Microphone Permission**: You'll be prompted once on first use
- **Open Source**: Full source code available for auditing

## Keyboard Shortcuts ⌨️

| Action | Shortcut |
|--------|----------|
| Start Recording | ⌘⇧Space |
| Stop Recording & Transcribe | ⌘⇧Space |
| Open Settings | Click menu bar icon |

## Troubleshooting 🔧

**"Unidentified Developer" Warning**
- Right-click the app and select "Open" instead of double-clicking
- Click "Open" in the security dialog

**Microphone Permission**
- Go to System Settings → Privacy & Security → Microphone
- Ensure FluidVoice is enabled

**Parakeet Setup Issues**
- Click "Download Parakeet v3 Model" in settings
- Check that download completed (~600MB)
- Use "Test" button to validate setup

## Contributing

Contributions welcome! See [CLAUDE.md](CLAUDE.md) for development setup and guidelines.

## Acknowledgments

Based on [mazdak/AudioWhisper](https://github.com/mazdak/AudioWhisper).

Built with SwiftUI, AppKit, WhisperKit, Parakeet-MLX, Alamofire, HotKey, KeychainAccess. MIT License.

---

Made with ❤️ for the macOS community. If you find this useful, please consider starring the repository!
