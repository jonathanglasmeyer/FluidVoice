# Parakeet Onboarding Streamlining

**Date**: 2025-09-19
**Status**: 📋 **PLANNED**
**Priority**: 🚀 **HIGH** - Critical for Parakeet-only architecture success
**Goal**: Automatic Parakeet setup during first launch - zero manual configuration

## Problem Statement

**Post Parakeet-Only Architecture**: Users will have no fallback if Parakeet isn't ready. Current onboarding requires:
- Manual Python environment detection
- Manual model download initiation
- Technical troubleshooting if setup fails
- Understanding of MLX/Python concepts

**This creates a setup barrier for the target audience: developers who want it to "just work".**

## Solution: Guided Setup Wizard

### Core Principle: **Zero-Config Experience**
- App launches → Setup wizard appears (if needed)
- User clicks "Setup" → Everything happens automatically
- No technical decisions or manual intervention required
- Clear progress indication and error recovery

## Setup Wizard Flow

### Step 1: Welcome & Privacy Assurance
```swift
struct SetupWelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.blue)

            Text("Welcome to FluidVoice")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Fast, private voice transcription for developers")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "lock.shield")
                    Text("100% private - never leaves your Mac")
                }
                HStack {
                    Image(systemName: "bolt")
                    Text("Sub-second transcription with Apple Silicon")
                }
                HStack {
                    Image(systemName: "globe")
                    Text("25 languages supported automatically")
                }
            }
            .font(.subheadline)

            Button("Get Started") {
                showSetupStep = .systemCheck
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: 500)
    }
}
```

### Step 2: System Requirements Check
```swift
struct SystemCheckView: View {
    @StateObject private var checker = SystemRequirementsChecker()

    var body: some View {
        VStack(spacing: 20) {
            Text("Checking System Compatibility")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 12) {
                RequirementRow(
                    title: "Apple Silicon Mac",
                    status: checker.hasAppleSilicon,
                    description: "Required for MLX acceleration"
                )

                RequirementRow(
                    title: "macOS 14.0+",
                    status: checker.hasCompatibleOS,
                    description: "Required for CoreML and MLX frameworks"
                )

                RequirementRow(
                    title: "Available Storage",
                    status: checker.hasEnoughStorage,
                    description: "1.2GB needed for Parakeet model and Python environment"
                )

                RequirementRow(
                    title: "Internet Connection",
                    status: checker.hasInternet,
                    description: "Required for one-time model download"
                )
            }

            if checker.allRequirementsMet {
                Button("Continue Setup") {
                    showSetupStep = .parakeetInstall
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("Some requirements not met. FluidVoice requires an Apple Silicon Mac with macOS 14.0+")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .onAppear {
            checker.performChecks()
        }
    }
}
```

### Step 3: Automatic Parakeet Installation
```swift
struct ParakeetInstallView: View {
    @StateObject private var installer = ParakeetInstaller()

    var body: some View {
        VStack(spacing: 24) {
            Text("Setting Up Parakeet Transcription")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 16) {
                InstallStepView(
                    title: "Python Environment",
                    status: installer.pythonStatus,
                    description: "Installing optimized Python environment with UV..."
                )

                InstallStepView(
                    title: "MLX Framework",
                    status: installer.mlxStatus,
                    description: "Installing Apple Silicon acceleration framework..."
                )

                InstallStepView(
                    title: "Parakeet Model",
                    status: installer.modelStatus,
                    description: "Downloading parakeet-tdt-0.6b-v3 (600MB)...",
                    progress: installer.downloadProgress
                )

                InstallStepView(
                    title: "First Run Test",
                    status: installer.testStatus,
                    description: "Testing transcription with sample audio..."
                )
            }

            if installer.isComplete {
                VStack(spacing: 12) {
                    Text("✅ Setup Complete!")
                        .font(.headline)
                        .foregroundColor(.green)

                    Text("FluidVoice is ready for fast, private transcription")
                        .foregroundColor(.secondary)

                    Button("Start Using FluidVoice") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if installer.hasFailed {
                VStack(spacing: 12) {
                    Text("Setup Failed")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text(installer.errorMessage)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack {
                        Button("Retry Setup") {
                            installer.retry()
                        }
                        .buttonStyle(.bordered)

                        Button("Get Help") {
                            openSetupTroubleshooting()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear {
            installer.startInstallation()
        }
    }
}
```

## Technical Implementation

### ParakeetInstaller Service
```swift
@MainActor
class ParakeetInstaller: ObservableObject {
    @Published var pythonStatus: InstallStatus = .pending
    @Published var mlxStatus: InstallStatus = .pending
    @Published var modelStatus: InstallStatus = .pending
    @Published var testStatus: InstallStatus = .pending
    @Published var downloadProgress: Double = 0.0
    @Published var errorMessage: String = ""

    private let uvBootstrap = UvBootstrap()
    private let modelManager = MLXModelManager.shared

    func startInstallation() async {
        do {
            // Step 1: Python Environment
            pythonStatus = .inProgress
            try await setupPythonEnvironment()
            pythonStatus = .completed

            // Step 2: MLX Framework
            mlxStatus = .inProgress
            try await installMLXDependencies()
            mlxStatus = .completed

            // Step 3: Parakeet Model Download
            modelStatus = .inProgress
            try await downloadParakeetModel()
            modelStatus = .completed

            // Step 4: Test Run
            testStatus = .inProgress
            try await performTestTranscription()
            testStatus = .completed

        } catch {
            handleInstallationError(error)
        }
    }

    private func setupPythonEnvironment() async throws {
        // Use existing UvBootstrap but with progress reporting
        try await uvBootstrap.ensureUvInstalled()
        try await uvBootstrap.createVirtualEnvironment()
    }

    private func downloadParakeetModel() async throws {
        // Download with progress tracking
        let modelURL = "https://huggingface.co/mlx-community/parakeet-tdt-0.6b-v3"

        let progressStream = AsyncThrowingStream<Double, Error> { continuation in
            Task {
                do {
                    try await modelManager.downloadModel(
                        from: modelURL,
                        progressHandler: { progress in
                            continuation.yield(progress)
                        }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        for try await progress in progressStream {
            downloadProgress = progress
        }
    }

    private func performTestTranscription() async throws {
        // Test with bundled sample audio (1 second "Hello")
        let testAudioURL = Bundle.main.url(forResource: "test-sample", withExtension: "wav")!
        let parakeetService = ParakeetService()

        let result = try await parakeetService.transcribe(audioURL: testAudioURL)

        guard result.text.lowercased().contains("hello") else {
            throw SetupError.transcriptionTestFailed
        }
    }
}

enum InstallStatus {
    case pending, inProgress, completed, failed
}

enum SetupError: LocalizedError {
    case pythonSetupFailed
    case mlxInstallFailed
    case modelDownloadFailed
    case transcriptionTestFailed

    var errorDescription: String? {
        switch self {
        case .pythonSetupFailed:
            return "Failed to set up Python environment. Please ensure you have administrator privileges."
        case .mlxInstallFailed:
            return "Failed to install MLX framework. This may indicate an incompatible system."
        case .modelDownloadFailed:
            return "Failed to download Parakeet model. Please check your internet connection."
        case .transcriptionTestFailed:
            return "Transcription test failed. The setup may be incomplete."
        }
    }
}
```

### Integration with App Launch
```swift
// FluidVoiceApp.swift
struct FluidVoiceApp: App {
    @StateObject private var setupState = SetupState()

    var body: some Scene {
        WindowGroup {
            if setupState.needsSetup {
                SetupWizardView(setupState: setupState)
            } else {
                ContentView()
            }
        }
        .onAppear {
            setupState.checkSetupStatus()
        }
    }
}

@MainActor
class SetupState: ObservableObject {
    @Published var needsSetup: Bool = false

    func checkSetupStatus() {
        // Check if Parakeet is properly installed and working
        needsSetup = !ParakeetService.isAvailable()
    }
}
```

## User Experience Flow

### Happy Path (95% of users)
1. **Launch FluidVoice** → Setup wizard appears
2. **Click "Get Started"** → System check passes
3. **Click "Continue Setup"** → Automatic installation begins
4. **Wait 2-3 minutes** → Progress bars show download/install
5. **"Setup Complete!"** → Click "Start Using FluidVoice"
6. **Ready to record** → Press hotkey, works immediately

### Error Recovery Path
- **No internet**: Clear message, retry button
- **Insufficient storage**: Suggest cleanup, show storage needed
- **Intel Mac**: Explain Apple Silicon requirement, suggest alternatives
- **Download failure**: Retry mechanism, fallback servers
- **Test failure**: Diagnostic information, manual setup guide

## Post-Setup Features

### Settings Integration
```swift
// SettingsView.swift - Add troubleshooting section
Section("Parakeet Setup") {
    HStack {
        Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
        Text("Parakeet installed and working")
        Spacer()
        Button("Re-run Setup") {
            showSetupWizard = true
        }
        .buttonStyle(.bordered)
    }

    Button("Download Additional Models") {
        showModelDownloader = true
    }

    Button("Test Transcription") {
        performTranscriptionTest()
    }
}
```

### Diagnostic Tools
```swift
struct DiagnosticView: View {
    @StateObject private var diagnostics = DiagnosticsRunner()

    var body: some View {
        VStack {
            Text("FluidVoice Diagnostics")
                .font(.title2)

            List(diagnostics.results, id: \.name) { result in
                DiagnosticRow(result: result)
            }

            Button("Run Diagnostics") {
                diagnostics.runAll()
            }

            Button("Export Report") {
                exportDiagnosticReport()
            }
        }
    }
}
```

## Implementation Timeline

### Phase 1: Core Setup Service (Day 1)
- Create ParakeetInstaller class
- Implement progress tracking for downloads
- Add system requirements checking
- Create error handling and recovery

### Phase 2: Setup UI Components (Day 2)
- Build SetupWizardView with steps
- Create progress indicators and status displays
- Implement error messaging and retry flows
- Add completion celebration

### Phase 3: App Integration (Day 3)
- Integrate setup check into app launch
- Create SetupState management
- Add settings panel for re-running setup
- Handle setup bypass for development

### Phase 4: Testing & Polish (Day 4)
- Test all error scenarios (no internet, insufficient space, etc.)
- Verify progress tracking accuracy
- Test on clean systems without Python/MLX
- Optimize download performance

### Phase 5: Diagnostics & Support (Day 5)
- Create diagnostic tools for troubleshooting
- Add setup logs for debugging
- Create help documentation
- Test complete onboarding flow

## Success Criteria

### Technical
- ✅ 95%+ first-time setup success rate
- ✅ Complete setup in under 3 minutes on good internet
- ✅ Clear error recovery for all failure modes
- ✅ No manual configuration required

### User Experience
- ✅ Users understand what's happening during setup
- ✅ Setup feels professional and polished
- ✅ Clear progress indication throughout process
- ✅ Successful setup leads directly to working transcription

### Business Impact
- ✅ Eliminates setup barrier for new users
- ✅ Reduces support requests about installation
- ✅ Improves first-time user experience
- ✅ Supports Parakeet-only architecture strategy

---

**Outcome**: FluidVoice becomes a **"download and go"** experience. Users get from download to working transcription in under 5 minutes with zero technical configuration.

**Marketing**: *"The fastest way to get started with private voice transcription - no setup required."*