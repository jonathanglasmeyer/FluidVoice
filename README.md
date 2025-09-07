# FluidVoice

<p align="center">
  <img src="FluidVoiceIcon.png" width="200" height="200" alt="FluidVoice Icon">
</p>

![Work in Progress](https://img.shields.io/badge/Status-Work%20in%20Progress-orange?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9+-red?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![CoreML](https://img.shields.io/badge/CoreML-✓-blue?style=flat-square)
![MLX](https://img.shields.io/badge/MLX-✓-purple?style=flat-square)

> ⚠️ **Development in progress** - Features and APIs may change frequently.

macOS menu bar app for audio transcription. Press ⌘⇧Space to start recording, press again to stop. Text appears directly in your current application.

## Key Advantages

### **Complete Privacy & Enterprise-Ready**
- **Zero cloud dependencies** - Audio never leaves your device
- **GDPR/SOX compliant** - No data sent to external servers
- **Enterprise security** - Safe for confidential meetings and sensitive content
- **Offline-first design** - Works without internet connection

### **Intelligent Multilingual Support**
- **Automatic language detection** - Switch between languages mid-sentence
- **25+ European languages** with Parakeet v3 (German, French, Spanish, Italian, etc.)
- **No manual language switching** - Just speak, FluidVoice adapts

### **Ultra-Fast Performance**
- **Sub-second transcription**: 0.1-0.3 second response times
- **10x faster** than traditional approaches with optimized model loading
- **Instant response** - Models preloaded and ready
- **Real-time feel** - Near-zero latency for short audio clips

### **Intelligent Vocabulary Correction**
- **150x faster than LLMs**: 3-5ms correction vs 1500-3000ms for cloud AI
- **100% privacy-first**: All processing happens locally, zero network requests
- **Technical vocabulary mastery**: API → API, github → GitHub, typescript → TypeScript
- **JSONC configuration**: Developer-friendly config with inline comments at `~/.config/fluidvoice/vocabulary.jsonc`
- **Live reload**: Edit vocabulary while FluidVoice runs - changes apply instantly

## Features & Development

### Local Transcription
- **WhisperKit**: CoreML acceleration, 6 model sizes (39MB - 2.9GB) - Supports 50+ languages with seamless detection
- **Parakeet v3**: 25 European languages, daemon mode, auto-detection

### Documentation
- **Features**: See [`docs/features/`](docs/features/) for planned features and [`docs/features/done/`](docs/features/done/) for completed implementations
- **Bugs**: See [`docs/bugs/`](docs/bugs/) for known issues and [`docs/bugs/done/`](docs/bugs/done/) for resolved bugs

## Legacy Features (Will Be Removed)
- **Window-based recording**: Recording window interface (disable "Express Mode" in settings)
- **Manual copy/paste workflow**: Use background mode instead
- **Cloud APIs**: OpenAI Whisper, Google Gemini - require API keys, send audio to external servers

## Requirements
- macOS 14.0 (Sonoma) or later

## Installation
```bash
git clone https://github.com/mazdak/FluidVoice.git
cd FluidVoice
./build-dev.sh
cp -r FluidVoice-dev.app /Applications/FluidVoice.app
```

## Troubleshooting

**"Unidentified Developer" Warning**
- Right-click the app and select "Open" instead of double-clicking
- Click "Open" in the security dialog

**Microphone Permission**
- Go to System Settings → Privacy & Security → Microphone
- Ensure FluidVoice is enabled

**Parakeet Setup Issues**
- Click "Download Parakeet v3 Model" in settings
- Check that download completed (~600MB)

## Contributing

See [CLAUDE.md](CLAUDE.md) for development setup and guidelines.

## Acknowledgments

Based on [mazdak/AudioWhisper](https://github.com/mazdak/AudioWhisper). Built with SwiftUI, AppKit, WhisperKit, Parakeet-MLX. MIT License.
