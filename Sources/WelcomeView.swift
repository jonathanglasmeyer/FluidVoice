import SwiftUI
import AppKit
import AVFoundation

enum SetupStep: CaseIterable {
    case welcome
    case permissions
    case modelDownload
    case complete

    var title: String {
        switch self {
        case .welcome: return "Welcome to FluidVoice"
        case .permissions: return "Grant Permissions"
        case .modelDownload: return "Download Parakeet Model"
        case .complete: return "Setup Complete"
        }
    }
}

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    let initialStep: SetupStep
    @State private var currentStep: SetupStep
    @State private var micPermissionGranted = false
    @State private var accessibilityPermissionGranted = false
    @State private var downloadProgress: Double = 0.0
    @State private var downloadStatus = "Preparing download..."
    @State private var isDownloading = false
    @StateObject private var modelManager = MLXModelManager.shared
    @State private var testText = ""
    @State private var currentHotkey = "Right Option"

    init(initialStep: SetupStep = .welcome) {
        self.initialStep = initialStep
        self._currentStep = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            progressSection

            // Clean header
            VStack(spacing: 16) {
                if currentStep == .welcome {
                    // Logo only
                    Group {
                        if let logoPath = Bundle.main.path(forResource: "Assets.xcassets/FluidVoiceLogo.imageset/FluidVoiceIcon", ofType: "png"),
                           let logoImage = NSImage(contentsOfFile: logoPath) {
                            Image(nsImage: logoImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 220, height: 220)
                        } else {
                            Image(systemName: "mic.circle.fill")
                                .font(.system(size: 80))
                                .foregroundColor(.primary)
                        }
                    }
                } else {
                    // Other steps
                    VStack(spacing: 12) {
                        Image(systemName: stepIcon(for: currentStep))
                            .font(.system(size: 64))
                            .foregroundColor(stepIconColor(for: currentStep))
                            .symbolRenderingMode(.hierarchical)

                        Text(currentStep.title)
                            .font(.largeTitle)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.top, 40)
            .padding(.bottom, 2)

            // Step content
            ScrollView {
                VStack(spacing: 24) {
                    switch currentStep {
                    case .welcome:
                        welcomeContent
                    case .permissions:
                        permissionsContent
                    case .modelDownload:
                        modelDownloadContent
                    case .complete:
                        completeContent
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 30)
            }

            Divider()

            // Dynamic action buttons
            actionButtons
                .padding(20)
        }
        .frame(width: 600, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            checkPermissions()
            currentHotkey = UserDefaults.standard.string(forKey: "globalHotkey") ?? "Right Option"
        }
    }

    // MARK: - Progress Section
    private var progressSection: some View {
        HStack(spacing: 16) {
            ForEach(Array(SetupStep.allCases.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 8) {
                    Circle()
                        .fill(stepColor(for: step))
                        .frame(width: 12, height: 12)

                    if index < SetupStep.allCases.count - 1 {
                        Rectangle()
                            .fill(stepColor(for: step).opacity(0.3))
                            .frame(width: 40, height: 2)
                    }
                }
            }
        }
        .padding(.top, 20)
    }

    private func stepColor(for step: SetupStep) -> Color {
        let currentIndex = SetupStep.allCases.firstIndex(of: currentStep) ?? 0
        let stepIndex = SetupStep.allCases.firstIndex(of: step) ?? 0

        if stepIndex < currentIndex {
            return .secondary
        } else if stepIndex == currentIndex {
            return Color(red: 0.3, green: 0.3, blue: 0.3)
        } else {
            return .secondary.opacity(0.3)
        }
    }

    private func stepIcon(for step: SetupStep) -> String {
        switch step {
        case .welcome: return "mic.circle.fill"
        case .permissions: return "lock.shield.fill"
        case .modelDownload: return "arrow.down.circle.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    private func stepIconColor(for step: SetupStep) -> Color {
        switch step {
        case .welcome: return Color(red: 0.3, green: 0.3, blue: 0.3)
        case .permissions: return Color(red: 0.3, green: 0.3, blue: 0.3)
        case .modelDownload: return Color(red: 0.3, green: 0.3, blue: 0.3)
        case .complete: return .green
        }
    }

    // MARK: - Step Content
    private var welcomeContent: some View {
        VStack(spacing: 32) {
            // Simple description
            Text("Ultra-fast, completely private voice transcription on Apple Silicon Macs. No data leaves your device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .lineSpacing(2)

            // Clean feature list
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "lock.shield", text: "100% private - no cloud dependencies")
                FeatureRow(icon: "bolt", text: "Sub-second transcription with NVIDIA Parakeet V3")
                FeatureRow(icon: "globe", text: "25 languages with automatic detection")
            }
        }
    }

    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("FluidVoice needs access to your microphone and accessibility features to function properly.")
                .font(.body)
                .foregroundColor(.secondary)

            VStack(spacing: 16) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required for recording audio",
                    isGranted: micPermissionGranted,
                    action: requestMicrophonePermission
                )

                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility Access",
                    description: "Required for global hotkeys",
                    isGranted: accessibilityPermissionGranted,
                    action: requestAccessibilityPermission
                )
            }
        }
    }

    private var modelDownloadContent: some View {
        VStack(alignment: .center, spacing: 24) {
            Text("Setting up Parakeet for fast, offline transcription. One-time download.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if isDownloading {
                VStack(spacing: 16) {
                    // Show determinate progress bar with percentage
                    ProgressView(value: downloadProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle())

                    Text(downloadStatus)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    private var completeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Press your global hotkey (\(currentHotkey)) to start recording.")
                    .font(.body)
                    .foregroundColor(.secondary)

                Text("You can change the hotkey in Settings (click the menubar icon).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hold to record")
                        .font(.headline)

                    Text("Hold the key down while speaking, release to stop.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Tap to start, tap to stop")
                        .font(.headline)

                    Text("Tap once to start recording, tap again to stop. Perfect for longer recordings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Try it out")
                    .font(.headline)
                    .fontWeight(.semibold)

                TextField("Click here, press your hotkey and speak...", text: $testText)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Action Buttons
    private var actionButtons: some View {
        HStack {
            if currentStep != .welcome {
                Button("Back") {
                    goToPreviousStep()
                }
                .buttonStyle(.bordered)
                .disabled(currentStep == .modelDownload && isDownloading)
            }

            Spacer()

            Button(buttonTitle) {
                handleMainAction()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(buttonDisabled)
            .focusable(false)
        }
    }

    private var buttonTitle: String {
        switch currentStep {
        case .welcome: return "Start Setup"
        case .permissions: return permissionsGranted ? "Continue" : "Grant Permissions"
        case .modelDownload: return isDownloading ? "Downloading..." : "Download Model"
        case .complete: return "Finish"
        }
    }

    private var buttonDisabled: Bool {
        switch currentStep {
        case .welcome: return false
        case .permissions: return false
        case .modelDownload: return isDownloading
        case .complete: return false
        }
    }

    private var permissionsGranted: Bool {
        micPermissionGranted && accessibilityPermissionGranted
    }

    // MARK: - Actions
    private func handleMainAction() {
        switch currentStep {
        case .welcome:
            currentStep = .permissions
        case .permissions:
            if permissionsGranted {
                // Check if model is already downloaded before showing download step
                let repo = MLXModelManager.parakeetRepo
                if modelManager.downloadedModels.contains(repo) {
                    currentStep = .complete
                } else {
                    currentStep = .modelDownload
                }
            } else {
                // Try to grant permissions
                requestPermissions()
            }
        case .modelDownload:
            if !isDownloading {
                startModelDownload()
            }
        case .complete:
            markSetupComplete()
            dismiss()
        }
    }

    private func goToPreviousStep() {
        switch currentStep {
        case .welcome:
            break
        case .permissions:
            currentStep = .welcome
        case .modelDownload:
            currentStep = .permissions
        case .complete:
            currentStep = .modelDownload
        }
    }

    private func checkPermissions() {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            micPermissionGranted = true
        default:
            micPermissionGranted = false
        }

        // Check accessibility permission
        accessibilityPermissionGranted = AXIsProcessTrusted()
    }

    private func requestPermissions() {
        if !micPermissionGranted {
            requestMicrophonePermission()
        }
        if !accessibilityPermissionGranted {
            requestAccessibilityPermission()
        }
    }

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                self.micPermissionGranted = granted
            }
        }
    }

    private func requestAccessibilityPermission() {
        // Open System Preferences to Accessibility
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)

        // Check again after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.accessibilityPermissionGranted = AXIsProcessTrusted()
        }
    }

    private func startModelDownload() {
        let repo = MLXModelManager.parakeetRepo

        isDownloading = true
        downloadProgress = 0.0
        downloadStatus = "Starting download..."

        Task {
            await modelManager.downloadParakeetModel()

            // Wait for download to complete
            while await modelManager.isDownloading[repo] == true {
                // Update local status from manager
                if let status = await modelManager.downloadProgress[repo] {
                    downloadStatus = status
                    print("📊 WelcomeView: Updated status to: \(status)")
                }
                if let percent = await modelManager.downloadPercent[repo] {
                    downloadProgress = percent
                    print("📊 WelcomeView: Updated progress to: \(percent)")
                }
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds (faster polling)
            }

            // One final update after download completes
            if let finalPercent = await modelManager.downloadPercent[repo] {
                downloadProgress = finalPercent
                print("📊 WelcomeView: Final progress: \(finalPercent)")
            }

            // Refresh model list to update availability flag
            await modelManager.refreshModelList()
            let downloadedModels = await modelManager.downloadedModels
            ParakeetService.isModelAvailable = downloadedModels.contains(MLXModelManager.parakeetRepo)
            print("📊 WelcomeView: ParakeetService.isModelAvailable updated to: \(ParakeetService.isModelAvailable)")

            // Preload Parakeet daemon for zero cold start
            if ParakeetService.isModelAvailable {
                do {
                    Logger.app.infoDev("📊 WelcomeView: Starting Parakeet daemon preload...")
                    let pyURL = try await UvBootstrap.ensureVenv(userPython: nil) { msg in
                        Logger.app.infoDev("WelcomeView uv: \(msg)")
                    }
                    try await ParakeetDaemon.shared.start(pythonPath: pyURL.path)
                    Logger.app.infoDev("📊 WelcomeView: Parakeet daemon preloaded successfully")
                } catch {
                    Logger.app.infoDev("⚠️ WelcomeView: Daemon preload failed: \(error.localizedDescription)")
                }
            }

            downloadStatus = "Download complete!"
            downloadProgress = 1.0
            isDownloading = false
            currentStep = .complete
        }
    }

    private func markSetupComplete() {
        // Check if this is first-run setup (not Help menu)
        let isFirstRun = !UserDefaults.standard.bool(forKey: "hasCompletedWelcome")

        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
        UserDefaults.standard.set("2.0", forKey: "lastWelcomeVersion")

        // Only post notification for first-run setup to trigger Settings opening
        if isFirstRun {
            NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 20)

            Text(text)
                .font(.body)
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        SettingsCard {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .foregroundColor(isGranted ? .secondary : .orange)
                    .frame(width: 24)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title2)
                } else {
                    Button("Grant") {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
        }
    }
}

#Preview {
    WelcomeView()
}