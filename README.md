# FluidVoice

<p align="center">
  <img src="FluidVoiceIcon.png" width="200" height="200" alt="FluidVoice Icon">
</p>

![Swift](https://img.shields.io/badge/Swift-5.9+-red?style=flat-square&logo=swift)
![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![CoreML](https://img.shields.io/badge/CoreML-✓-blue?style=flat-square)
![MLX](https://img.shields.io/badge/MLX-✓-purple?style=flat-square)

macOS menu bar app for audio transcription that works system-wide in any application.

**Two recording modes:**
- **Toggle Mode**: Press your shortcut (Right Option or your favorite modifier like `Fn`) to start, press again to stop
- **Hold to Speak**: Hold your shortcut key, speak, release to transcribe

Text appears instantly in your current application—no copy/paste needed.

**Status:** Core features are functional. Planned enhancements tracked in [`docs/features/`](docs/features/).

## Key Advantages

### **Complete Privacy**
- **100% offline** - Audio never leaves your device
- **No data collection** - Zero telemetry, zero tracking
- **Open source** - Verify for yourself what the code does

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
- **Ultra-fast pattern matching**: 3-5ms correction (vs 1500-3000ms for LLM-based approaches)
- **Privacy-first processing**: All vocabulary correction happens locally, zero network requests
- **Default presets**: Includes common technical terms - "api" → "API", "github" → "GitHub", "typescript" → "TypeScript"
- **Domain adaptable**: Easily customize for any field - legal, medical, scientific, or business terminology
- **JSONC configuration**: Developer-friendly config with inline comments at `~/.config/fluidvoice/vocabulary.jsonc`
- **Live reload**: Edit vocabulary while FluidVoice runs - changes apply instantly

## Features & Development

### Local Transcription
- **[Parakeet v3 Multilingual](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)**: NVIDIA's 600M parameter model optimized for speed and accuracy
  - 25 European languages with automatic detection
  - Daemon mode for zero cold-start latency
  - Sub-second transcription on Apple Silicon
  - Runs entirely offline via MLX

### Documentation
- **Features**: See [`docs/features/`](docs/features/) for planned features and [`docs/features/done/`](docs/features/done/) for completed implementations
- **Bugs**: See [`docs/bugs/`](docs/bugs/) for known issues and [`docs/bugs/done/`](docs/bugs/done/) for resolved bugs

## Alternative Products

Looking for other voice transcription tools? Check out [ALTERNATIVES.md](ALTERNATIVES.md) for a detailed comparison of 8 competing products including VoiceInk, Spokenly, SuperWhisper, and more.

## Requirements
- macOS 14.0 (Sonoma) or later

## Installation

### Build from Source
1. Install Xcode Command Line Tools: `xcode-select --install`
2. Clone repository:
   ```bash
   git clone https://github.com/mazdak/FluidVoice.git
   cd FluidVoice
   ```
3. **Setup code signing** (required for microphone access):
   - Follow the guide: [docs/setup-code-signing.md](docs/setup-code-signing.md)
   - Takes ~5 minutes, completely free, no Apple account needed
4. Build: `./build.sh`
5. Run: Open `FluidVoice.app`

**Why code signing?** macOS requires signed apps for microphone permissions. Self-signed certificates work perfectly and cost nothing.

## Development Workflow

**Using just commands:**
```bash
just                # List all available commands
just dev            # Build and run development version
just release        # Build release version and install to /Applications
just test           # Run tests
just logs           # Stream app logs
just kill           # Kill running app processes
```

## Troubleshooting

**"Unidentified Developer" Warning**
- Right-click the app and select "Open" instead of double-clicking
- Click "Open" in the security dialog

**Microphone Permission Issues**
- Go to System Settings → Privacy & Security → Microphone
- Ensure FluidVoice is enabled
- If permissions don't work after rebuilding, reset them:
  ```bash
  tccutil reset Microphone com.fluidvoice.app
  ```
- Then restart the app and grant permission again

**Parakeet Setup Issues**
- Click "Download Parakeet v3 Model" in settings
- Check that download completed (~600MB)

## Contributing

See [CLAUDE.md](CLAUDE.md) for development setup and guidelines.

## Acknowledgments

Based on [mazdak/AudioWhisper](https://github.com/mazdak/AudioWhisper). Built with SwiftUI, AppKit, MLX, and [Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3). MIT License.
