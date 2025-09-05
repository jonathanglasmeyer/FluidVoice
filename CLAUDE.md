# FluidVoice — Developer & AI Guidelines

This document provides comprehensive technical instructions for developers and AI assistants working with the FluidVoice codebase. For user-facing information, installation, and usage instructions, see **[README.md](README.md)**.

**Document Purpose**: Complete development guide covering architecture, build system, testing, and deployment.

## ⚠️ CRITICAL: Debug & Log Management

### macOS Console Logging
**NEVER run FluidVoice in foreground in chat** - it blocks the conversation.

**Correct Debug Workflow:**
1. **Build and start in background**: 
   ```bash
   ./build-dev.sh && FluidVoice-dev.app/Contents/MacOS/FluidVoice &
   ```
   Use `run_in_background: true` parameter in Bash tool, NOT `&` ampersand
2. **Stream logs via terminal**: `/usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info` (also background)
3. **Kill when done**: `pkill -f FluidVoice 2>/dev/null || true`

**⚠️ NEVER use raw executable**: `.build-dev/debug/FluidVoice` bypasses app bundle structure, breaking:
- Bundle ID detection (no logging subsystem)
- Resource loading (symlinked Resources/)
- Code signing validation  
- macOS app behavior

**NOTE**: Claude Bash tool handles backgrounding differently than terminal - use `run_in_background` parameter.

**⚠️ CRITICAL: Use Full Path for Log Commands**
The shell built-in `log` command conflicts with macOS Console utility. Always use `/usr/bin/log`:

**Correct log commands:**
- **Recent logs**: `/usr/bin/log show --last 1m --predicate 'subsystem == "com.fluidvoice.app"'`
- **Stream logs**: `/usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info`
- **Specific process**: `/usr/bin/log stream --predicate 'process == "FluidVoice"' --info`
- **Compact format**: `/usr/bin/log show --last 30s --predicate 'subsystem == "com.fluidvoice.app"' --style compact`

**⚠️ CRITICAL: --info Flag Required for Application Logs**
FluidVoice logs at **Info level**, which is standard for structured application logging:
- **Without --info**: Only Error/Fault logs shown (empty for normal app operation)
- **With --info**: Shows Info, Debug, Error, Fault logs (complete app logging)
- **Development logging**: ALWAYS use `--info` flag to see application startup, DataManager, and operation logs

**Log Level Behavior:**
- `log stream --predicate 'subsystem == "com.fluidvoice.app"'` → **Empty output** (filters out Info logs)
- `log stream --predicate 'subsystem == "com.fluidvoice.app"' --info` → **Full application logs**
- `log stream --predicate 'subsystem == "com.fluidvoice.app"' --style compact` → **Empty output** (compact also filters Info)

**Never use**: `log` (conflicts with shell built-in, causes "too many arguments" errors)

**Never use Console.app** - terminal commands are faster and more precise.

## ⚠️ CRITICAL: Interactive Testing Boundaries

**AI assistants DO NOT perform interactive app validation** - user handles all interactive testing.

**AI Assistant Scope:**
- ✅ **Code analysis and implementation** - Can read, analyze, and modify code
- ✅ **Build system validation** - Can run builds and verify compilation
- ✅ **Static verification** - Can check settings, configurations, and code paths
- ✅ **Log monitoring** - Can stream and analyze application logs
- ✅ **Implementation status** - Can verify features are coded and integrated

**User Responsibility:**
- 🎯 **Interactive testing** - User validates hotkeys, UI interactions, end-to-end workflows
- 🎯 **Visual verification** - User confirms UI appearance and behavior
- 🎯 **Audio/speech testing** - User validates microphone input and transcription
- 🎯 **Permission dialogs** - User handles macOS permission prompts and accessibility setup
- 🎯 **Real-world validation** - User tests actual speech-to-text and text insertion

**AI assistants should:**
- Prepare the environment (build, launch, configure)
- Set up logging and monitoring
- Verify implementation completeness
- Hand off to user for interactive validation

**AI assistants should NOT:**
- Attempt to simulate user interactions (hotkey presses, speech input)
- Try to validate UI appearance or user experience
- Test actual microphone input or speech recognition
- Validate accessibility permissions or system dialogs

## ⚠️ CRITICAL: Permission Reset Policy

**NEVER use broad tccutil reset commands without explicit user consent:**
- ❌ `tccutil reset Accessibility` (resets ALL apps)
- ❌ `tccutil reset Microphone` (resets ALL apps)
- ❌ `tccutil reset All` (resets EVERYTHING)

**Only use specific bundle ID resets:**
- ✅ `tccutil reset Accessibility com.fluidvoice.app` (specific to FluidVoice)
- ✅ `tccutil reset Microphone com.fluidvoice.app` (specific to FluidVoice)

**Rationale**: Broad resets destroy user's permission settings for ALL applications, requiring them to re-grant permissions to every app they use.

## Code Signing Configuration

FluidVoice requires proper code signing for permission persistence:

**Build Command**:
```bash
CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25" ./build.sh
```

**Certificate Details**:
- Name: "FluidVoice Code Signing"
- Type: Self-signed root certificate
- Hash: EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25
- Bundle ID: com.fluidvoice.app (verified working)

**Never use `swift build` - always use `./build.sh` with CODE_SIGN_IDENTITY set.**

## Build Performance Optimization

FluidVoice includes optimized build scripts for faster development:

**Development Builds** (Hybrid: Fast + Bundle):
```bash
# Load build environment with optimizations
source .build-config

# Hybrid development build (5.38s with full app bundle)
./build-dev.sh
# or use alias:
fv-build
```

**Hybrid Build System** - Fast development builds with full app bundle functionality:
- **5.38s builds** (4.7x faster than release) with complete macOS app behavior
- See **[docs/features/done/hybrid-build-system.md](docs/features/done/hybrid-build-system.md)** for technical details

**Build Environment Aliases**:
- `fv-build` - Fast development build
- `fv-release` - Signed release build 
- `fv-test` - Run tests with parallel execution
- `fv-run` - Build and run in development mode
- `fv-clean` - Clean build artifacts

**Environment Configuration** (.env support):
Both build scripts now support `.env` file for configuration:
```bash
# Copy example and customize
cp .env.example .env

# Example .env content:
CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25"
AUDIO_WHISPER_VERSION="1.0.0"
```

Build scripts automatically load `.env` if present, enabling:
- Consistent code signing across all builds
- Version management
- Custom build configurations
- Team development standardization

**Build Optimizations Implemented**:
- Build cache at `~/.swift-build-cache` (preserves incremental builds)
- Separate debug build path (`.build-dev`) to avoid conflicts
- Parallel compilation using all available CPU cores
- Compiler optimizations for release builds
- Package.swift with proper build settings

**Performance Comparison (Apple Silicon, with build cache):**
- **build-dev.sh (hybrid)**: 5.38s (5.29s user, 0.69s system, 111% CPU) → Full app bundle
- **build.sh (release)**: 25.40s (47.61s user, 2.67s system, 197% CPU) → Universal binary + optimizations
- **Speed improvement**: 4.7x faster development builds with full functionality

**What Makes build-dev.sh Fast:**
- **Debug compilation** (`-c debug`) - No compiler optimizations
- **Single architecture** - Native arm64 only (no universal binary)  
- **Efficient bundling** - Symlinked resources instead of copying
- **Separate build paths** - `.build-dev` vs `.build` prevents conflicts
- **Minimal code signing** - Quick signing vs full release signing process

**What Makes build.sh Slower:**
- **Release optimizations** (`-c release`) - Heavy compiler work
- **Universal binary** - Compiles for both x86_64 + arm64
- **Full resource copying** - Complete app bundle assembly
- **Comprehensive code signing** - Production-ready signing process

## Complete Development Setup

### Prerequisites
- **Xcode 15.0** or later (required for SwiftUI + AppKit integration)
- **Swift 5.9** or later (uses modern concurrency features)
- **macOS 14+** target (Sonoma APIs)
- **Apple Silicon** recommended (M1/M2/M3 for optimal WhisperKit performance)

### Development Workflow

**Initial Setup**:
```bash
# Clone and setup
git clone https://github.com/mazdak/FluidVoice.git
cd FluidVoice

# Load optimized build environment
source .build-config

# First build (downloads dependencies)
./build-dev.sh
```

**Daily Development**:
```bash
# Fast development build (23s)
fv-build

# Build and run immediately  
fv-run

# Run tests with coverage
fv-test

# Clean when needed
fv-clean
```

**Release Preparation**:
```bash
# Signed release build
fv-release
# or manually:
CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25" ./build.sh
```

### Architecture Overview

FluidVoice uses a **hybrid SwiftUI + AppKit** architecture:

**Core Components**:
- **Menu Bar App**: `NSApplication` with `LSUIElement=true`
- **Global Hotkeys**: HotKey framework for ⌘⇧Space trigger
- **Audio Pipeline**: AVFoundation → CoreML/API → Clipboard
- **UI Layer**: SwiftUI views with AppKit integration
- **Security**: Keychain for API keys, entitlements for microphone

**Audio Processing Pipeline**:
1. **AudioRecorder**: AVAudioEngine recording
2. **AudioProcessor**: PCM conversion, validation
3. **Transcription Services**: WhisperKit/OpenAI/Gemini/Parakeet
4. **PasteManager**: Clipboard + auto-paste functionality

**Local AI Integration**:
- **WhisperKit**: CoreML models (39MB - 2.9GB), Neural Engine acceleration
- **Parakeet-MLX**: Python subprocess, MLX framework, ~600MB model
- **Model Management**: Automatic downloads, caching, version control

## 1. Purpose and Scope

- **Primary Role**: Assist developers by reading existing code, suggesting idiomatic Swift implementations, writing tests, and fixing bugs.
- **Focus Areas**:
  - Adherence to Swift and SwiftUI best practices
  - Memory safety and thread correctness
  - Consistent use of existing libraries and patterns
  - Comprehensive test coverage

## 2. Libraries and Frameworks

FluidVoice relies on:
- **SwiftUI** + **AppKit** for UI and macOS menu bar integration
- **AVFoundation** for audio recording
- **Alamofire** for HTTP requests and model downloads
- **WhisperKit** (CoreML) for local transcription
- **HotKey** for global keyboard shortcuts
- **Combine** / Swift Concurrency for asynchronous logic
- **KeychainAccess** for secure API key storage

When extending functionality, prefer these existing dependencies over introducing new ones.

## 3. Code Style and Best Practices

- **Swift 5.7+** targeting **macOS 14+** (use modern APIs).
- Avoid force unwrapping (`!`); prefer `guard let` and optional chaining.
- Use value types (`struct`/`enum`) by default; reserve `class` for reference semantics or bridging.
- Prevent retain cycles with `[weak self]` or `unowned self` in closures.
- Dispatch UI updates on the main actor or `DispatchQueue.main`.
- Keep functions small (≤ 40 lines) and single-purpose.
- Write concise comments only for non-obvious logic; favor self-documenting code.
- Follow existing naming conventions, file structure, and grouping.

## 4. Testing

- Write **XCTest** unit tests for all new or modified logic.
- Cover edge cases, error paths, and concurrency scenarios.
- Ensure `swift test --parallel --enable-code-coverage` passes without failures.
- Keep tests deterministic and isolate external dependencies with mocks.

## 5. Memory Safety and Concurrency

- Use Swift Concurrency (`async`/`await`) or Combine for asynchronous flows.
- Prevent data races: confine shared state to actors or serial queues.
- Clean up observers, timers, and resources in `deinit` or task cancellation.
- Annotate UI components with `@MainActor` when required.

## 6. Feature Backlog and Documentation

FluidVoice maintains a structured feature backlog:
- **Feature Index**: See `docs/features/README.md` for current feature priorities and status
- **Feature Documentation**: Individual features documented in `docs/features/` directory
- **Priority Focus**: High-priority items address critical UX issues (e.g., "Preparing Large Turbo" blocking)

When implementing features, always check the backlog first to understand context and priorities.

## 7. Dependencies & Technical Stack

**Core Dependencies** (Package.swift):
- **[Alamofire 5.10.2+](https://github.com/Alamofire/Alamofire)**: HTTP client for API requests, model downloads
  - Used for: OpenAI/Gemini API calls, Hugging Face model downloads
  - Features: Request/response validation, multipart uploads, certificate pinning
- **[HotKey 0.2.1+](https://github.com/soffes/HotKey)**: Global keyboard shortcuts
  - Used for: ⌘⇧Space global trigger, Space/ESC in recording window
  - macOS Carbon API wrapper with Swift-friendly interface
- **[WhisperKit 0.13.1+](https://github.com/argmaxinc/WhisperKit)**: CoreML Whisper models
  - Used for: Local transcription, 6 model sizes, Neural Engine acceleration
  - Features: Streaming, VAD, custom vocabulary, multilingual

**Swift Package Dependencies** (transitive):
- **Swift Collections**: OrderedSet, OrderedDictionary for model management
- **Swift Transformers**: Tokenization, Hugging Face model loading
- **Swift Argument Parser**: CLI argument parsing for build scripts

**External Integrations**:
- **Parakeet-MLX**: Python package, MLX acceleration, English-only
- **UV**: Python package manager, bundled in app for dependency isolation
- **CoreML**: Apple's ML framework, hardware acceleration
- **AVFoundation**: Audio recording, format conversion, device management

## 8. Advanced Configuration

### Parakeet Python Integration

**Requirements**:
- Python 3.8+ with working MLX installation
- Apple Silicon Mac (MLX requirement)
- ~600MB model download on first use

**Setup Process**:
1. **Python Detection**: `PythonDetector.swift` validates Python path
2. **UV Bootstrap**: `UvBootstrap.swift` manages Python dependencies
3. **Model Download**: Automatic from Hugging Face on first transcription
4. **Process Management**: Swift subprocess execution with proper cleanup

**Configuration Files**:
- `Sources/Resources/pyproject.toml`: Python dependencies
- `Sources/parakeet_transcribe_pcm.py`: Transcription script
- `Sources/Resources/bin/uv`: Bundled Python package manager

### WhisperKit Model Management

**Model Sizes & Performance**:
- **tiny**: 39MB, ~2s transcription, basic quality
- **base**: 74MB, ~3s transcription, good quality  
- **small**: 244MB, ~5s transcription, better quality
- **medium**: 769MB, ~8s transcription, high quality
- **large**: 1.5GB, ~12s transcription, excellent quality
- **large-v3**: 2.9GB, ~15s transcription, best quality

**Storage Locations**:
- Models: `~/Library/Caches/WhisperKit/`
- Cache: `~/.swift-build-cache/` (build artifacts)
- App Resources: `FluidVoice.app/Contents/Resources/`

## 9. Testing & Quality Assurance

**Test Structure**:
```bash
# Run all tests with coverage
swift test --parallel --enable-code-coverage --build-path .build-dev

# Individual test suites
swift test --filter AudioRecorderTests
swift test --filter SpeechToTextServiceTests
swift test --filter ParakeetServiceTests
```

**Test Categories**:
- **Unit Tests**: Core logic, data transformations, utilities
- **Integration Tests**: API calls, model loading, audio processing
- **Mock Tests**: External dependencies, network calls, file system
- **UI Tests**: SwiftUI view rendering, user interactions (limited)

**Critical Test Areas**:
- Audio format validation and conversion
- API key security (never logged or exposed)
- Model download and caching behavior
- Hotkey registration and cleanup
- Memory management for large audio buffers

## 10. Release & Distribution

**Release Build Process**:
1. **Version Bump**: Update `VERSION` file
2. **Build**: `fv-release` (with code signing)
3. **Testing**: Full integration test suite
4. **Notarization**: Apple notarization (optional, requires dev account)
5. **Distribution**: GitHub Releases, direct download

**Code Signing Details**:
- **Identity**: `EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25`
- **Bundle ID**: `com.fluidvoice.app` (registered, working)
- **Entitlements**: Microphone access, network client
- **Hardened Runtime**: Required for distribution

**App Bundle Structure**:
```
FluidVoice.app/
├── Contents/
│   ├── MacOS/FluidVoice              # Main executable
│   ├── Resources/
│   │   ├── AppIcon.icns             # App icon
│   │   ├── parakeet_transcribe_pcm.py
│   │   ├── mlx_semantic_correct.py
│   │   ├── pyproject.toml
│   │   └── bin/uv                   # Bundled Python manager
│   └── Info.plist                   # App metadata
```

## 11. Pull Request Guidelines for AI Outputs

- Provide minimal, focused patches for the requested change.
- Use `./build-dev.sh` for development testing and `fv-test` for running tests.
- Always use the optimized build system instead of plain `swift build`.
- Do not introduce unrelated changes or fix pre-existing warnings.
- Include a brief rationale and testing steps in the PR description.
- Reference relevant sections of this document for context.

## 12. Performance Benchmarks

**Build Performance** (16-core Apple Silicon):
- **Development Build**: ~23 seconds (debug, incremental)
- **Clean Development Build**: ~45 seconds (debug, fresh)
- **Release Build**: ~60 seconds (optimized, universal binary)
- **Test Suite**: ~15 seconds (parallel execution)

**Runtime Performance**:
- **App Launch**: <2 seconds (menu bar app)
- **Recording Start**: <500ms (hotkey to window)
- **WhisperKit Transcription**: 2-15s (model dependent)
- **API Transcription**: 3-8s (network dependent)
- **Memory Usage**: ~50MB baseline, ~200MB during transcription

---

## 📋 Development Session Status Reports

### Purpose & Context Preservation

Development sessions are tracked via comprehensive status reports stored in `docs/reports/` to maintain context across development sessions when the context window becomes full. These reports serve as detailed checkpoints for AI assistants to restore complete understanding of:

- **Technical progress**: What was implemented, tested, and debugged
- **Architecture decisions**: Why specific approaches were chosen 
- **Current blockers**: Exactly what issues remain and debugging evidence
- **Next priorities**: Clear actionable steps for continuing work

### Status Report Guidelines

**When to Write Status Reports:**
1. **End of major debugging session** - Capture resolution details and lessons learned
2. **Before context window fills** - Preserve critical state before conversation reset  
3. **After significant architecture changes** - Document design decisions and implementation details
4. **When hitting complex blockers** - Detailed analysis to avoid re-investigation

**Required Sections:**
```markdown
# FluidVoice Development Status - Session [N]

**Date:** YYYY-MM-DD
**Session:** [Brief descriptive title]

## 🎯 Main Accomplishment: [Key Achievement]
### ✅ Successfully Implemented
### 🚨 Current Issue: [Primary Blocker]
### 📁 File Changes This Session  
### 🎯 Next Session Priorities
### 🏆 Impact Assessment
```

**Content Requirements:**
- **Exhaustive Technical Details**: Include specific error messages, log excerpts, and debugging steps
- **Code Changes**: List all modified files with key changes explained
- **Architecture Context**: Explain design decisions and why alternatives were rejected
- **Debugging Evidence**: Include command outputs, test results, and verification steps
- **Clear Next Steps**: Specific, actionable priorities with estimated effort

**Auto-Increment System:**
When creating new status reports, use the next available session number:
```bash
# Auto-determine next session number
NEXT_SESSION=$(ls docs/reports/*session-*.md | grep -o 'session-[0-9]*' | sed 's/session-//' | sort -n | tail -1)
NEXT_SESSION=$((NEXT_SESSION + 1))
# Create new report with format:
docs/reports/YYYY-MM-DD-session-$(printf "%02d" $NEXT_SESSION)-[descriptive-title].md
```

**Historical Context:**
- **Session 01**: SmartPaste Unicode-Typing implementation and app startup debugging
- **Session 02**: Unicode-Typing system with app targeting improvements  
- **Session 03**: Complete background-only mode architecture implementation
- **Session 04**: Bundle ID fixes, comprehensive rebranding, hotkey resolution
- **Session 05**: Logger system debugging and Bundle ID issue resolution

### Writing Status Reports

**Context Restoration Focus:**
Write as if the next AI assistant has **zero context** about the project. Include:
- **System state**: What's currently working vs broken
- **Dependencies**: Required tools, models, API keys, permissions
- **Debug workflow**: Exact commands to reproduce current state
- **Technical stack**: Frameworks, libraries, and integration points
- **User workflow**: How the application is supposed to work end-to-end

**Quality Checklist:**
- [ ] Can another AI assistant understand the current state without additional context?
- [ ] Are all error messages and debugging steps documented?
- [ ] Are the next steps specific and actionable?
- [ ] Is the impact and risk assessment realistic?
- [ ] Are all file changes and technical decisions explained?

---

## Quick Navigation

- **[README.md](README.md)** - User installation, setup, and usage
- **[CLAUDE.md](CLAUDE.md)** - This document: Complete developer guide
- **`.build-config`** - Build environment setup
- **`build-dev.sh`** - Fast development builds
- **`build.sh`** - Production release builds

*This file contains technical implementation details for developers and AI assistants. For end-user documentation, see README.md.*