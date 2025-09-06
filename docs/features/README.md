# FluidVoice Feature Backlog

## 🚀 High Priority Features

- **[Parakeet v3 Multilingual Upgrade](parakeet-v3-multilingual-upgrade.md)** 🔥 **HIGH PRIORITY** - Upgrade to 25 European languages with 2-5x German transcription speed improvement
- **[Express Mode: Background Recording](express-mode-background-recording.md)** ⚠️ **IN PROGRESS** - WhisperFlow-like hotkey start/stop, architecture complete but transcription service broken
- **[Custom Vocabulary](custom-vocabulary-feature.md)** - User-customizable vocabulary correction via enhanced LLM prompts
- **[Developer Config File](developer-config-file-feature.md)** - JSON-based configuration with UI sync for developer workflows
- **[Miniwindow Recording Indicator](miniwindow-recording-indicator.md)** - Small floating window with waveform during recording (WhisperFlow-inspired)
- **[Fn Key Hotkey Support](fn-key-feature.md)** - Enable Function key combinations for global shortcuts 
- **[Model Architecture Simplification](model-cleanup-feature.md)** - Remove legacy multi-provider complexity, focus on WhisperKit only

## ✅ Completed Features

- **[Performance Metrics & Language Detection](done/performance-metrics-language-detection.md)** ✅ **DONE** - Comprehensive transcription benchmarks and German language fix
- **[Model Preloading & Streaming UX](done/model-preloading-feature.md)** ✅ **DONE** - PreloadManager system eliminates first-use delays
- **[WhisperKit Preload System](done/whisperkit-preload-system.md)** ✅ **DONE** - App-idle preloading with warmup cycles

## 📋 Feature Status

| Feature | Priority | Status | Impact |
|---------|----------|--------|--------|
| Parakeet v3 Multilingual | High | 📋 **Planned** | Performance Critical - 2-5x German transcription speed + 25 languages |
| Express Mode | High | ⚠️ **In Progress** | UX Innovation - architecture done, transcription broken |
| Custom Vocabulary | Medium | 📋 **Planned** | Quality Improvement - user-specific term accuracy |
| Developer Config File | Medium | 📋 **Planned** | Developer Experience - JSON config with UI sync |
| Performance Metrics & Language Detection | High | ✅ **Completed** | Quality Critical - German transcription + benchmarking |
| Model Preloading | High | ✅ **Completed** | UX Critical - eliminates worst user experience |
| WhisperKit Preload System | High | ✅ **Completed** | Performance - app-idle preloading with warmup |
| Miniwindow Indicator | Medium | Not Started | UX Polish - elegant recording feedback |
| Fn Key Support | High | Planned | Accessibility - more hotkey options |
| Model Cleanup | High | Planning | Technical Debt - simplify codebase |

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