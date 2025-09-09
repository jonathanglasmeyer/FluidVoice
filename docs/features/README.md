# FluidVoice Feature Backlog

## 🚀 High Priority Features
- **[Developer Config File](developer-config-file-feature.md)** - JSON-based configuration with UI sync for developer workflows
- **[Audio Ducking During Recording](audio-ducking-feature.md)** - Automatically reduce background audio (Spotify, etc.) during voice recording
- **[Miniwindow Recording Indicator](miniwindow-recording-indicator.md)** - Small floating window with waveform during recording (WhisperFlow-inspired)
- **[Model Architecture Simplification](model-cleanup-feature.md)** - Simplify to Parakeet-only transcription for speed advantage and privacy-first approach

## ✅ Completed Features

- **[Uh Sound Removal](done/uh-sound-removal-feature.md)** ✅ **DONE** - Automatically remove filler sounds like 'uh', 'äh', 'um' from transcriptions
- **[Fast Vocabulary Correction](done/fast-vocabulary-correction.md)** ✅ **DONE** - Ultra-fast privacy-first vocabulary correction (150x faster than LLMs)
- **[Fn Key Hotkey Support](done/fn-key-feature.md)** ✅ **DONE** - Enable Function key combinations for global shortcuts
- **[Express Mode: Background Recording](done/express-mode-background-recording.md)** ✅ **DONE** - Revolutionary WhisperFlow-style background recording with hotkey start/stop
- **[Parakeet v3 Multilingual Upgrade](done/parakeet-v3-multilingual-upgrade.md)** ✅ **DONE** - 25 European languages with automatic detection and performance boost
- **[Performance Metrics & Language Detection](done/performance-metrics-language-detection.md)** ✅ **DONE** - Comprehensive transcription benchmarks and German language fix
- **[Model Preloading & Streaming UX](done/model-preloading-feature.md)** ✅ **DONE** - PreloadManager system eliminates first-use delays
- **[WhisperKit Preload System](done/whisperkit-preload-system.md)** ✅ **DONE** - App-idle preloading with warmup cycles
- **[Hybrid Build System](done/hybrid-build-system.md)** ✅ **DONE** - 4.7x faster development builds


## 🎯 Feature Guidelines

Features in this backlog follow these principles:
- **User-First**: Address real user pain points identified through usage
- **Technical Excellence**: Maintain Swift/SwiftUI best practices
- **Minimal Scope**: Focus on core voice recording and transcription workflow
- **Test Coverage**: All features require comprehensive XCTest coverage

## 📁 Feature Documentation Structure

Each feature includes:
- **Problem Statement** - What user pain point does this solve?
- **Technical Solution** - Implementation approach and architecture
- **Success Criteria** - How do we measure completion?
- **Testing Strategy** - Unit tests and integration scenarios

### 📝 Documentation Requirements

When adding a new feature:

1. **Create feature documentation** in `docs/features/[feature-name].md`
2. **Update this README** - Add feature to appropriate section (High Priority, Completed, etc.)
3. **Update status table** - Include priority, status, and impact description
4. **Link consistently** - Use relative paths to feature documentation files

This ensures the feature backlog stays current and discoverable for all contributors.