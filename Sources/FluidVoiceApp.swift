import SwiftUI
import SwiftData
import AppKit
import HotKey
import ServiceManagement
import os.log

@main
struct FluidVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // This is a menu bar app, so we just need to define menu commands
        // All windows are created programmatically
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .onAppear {
                    // Hide the empty window immediately
                    NSApplication.shared.windows.first?.orderOut(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(LocalizedStrings.Menu.settings) {
                    appDelegate.openSettings()
                }
                // Remove keyboard shortcut hint for menu bar app
            }
            CommandGroup(replacing: .windowArrangement) {
                Button(LocalizedStrings.Menu.closeWindow) {
                    NSApplication.shared.keyWindow?.orderOut(nil)
                }
                // No keyboard shortcut hints
            }
        }
    }
    
    /// Creates a fallback container if DataManager initialization fails
    private func createFallbackContainer() -> ModelContainer {
        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create fallback ModelContainer: \(error)")
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private var keyboardEventHandler: KeyboardEventHandler?
    private var windowController = WindowController()
    private weak var recordingWindow: NSWindow?
    private var recordingWindowDelegate: RecordingWindowDelegate?
    private var audioRecorder: AudioRecorder?
    private var recordingAnimationTimer: DispatchSourceTimer?
    // SmartPasteTestWindow removed for debugging
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 FluidVoice starting up...") // STARTUP DEBUG
        print("🔍 Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")") // DEBUG BUNDLE ID
        Logger.app.infoDev("🚀 FluidVoice starting up...")
        Logger.app.infoDev("📋 Session Marker: =================================")
        
        // Skip UI initialization in test environment
        let isTestEnvironment = NSClassFromString("XCTestCase") != nil
        if isTestEnvironment {
            print("❌ Test environment detected - skipping UI initialization") // STARTUP DEBUG
            Logger.app.infoDev("Test environment detected - skipping UI initialization")
            return
        }
        
        print("🖥️ UI initialization started") // STARTUP DEBUG  
        Logger.app.infoDev("🖥️ UI initialization started")
        
        // Initialize DataManager first
        do {
            try DataManager.shared.initialize()
            Logger.app.infoDev("DataManager initialized successfully")
        } catch {
            Logger.app.errorDev("Failed to initialize DataManager: \(error.localizedDescription)")
            // App continues with in-memory fallback
        }
        
        // Start background model preloading for instant transcription
        PreloadManager.shared.startIdlePreload()
        
        // Initialize MLX model cache at startup (async, non-blocking)
        Task {
            await MLXModelManager.shared.refreshModelList()
            
            // Set cached flags for instant transcription checks
            let downloadedModels = await MLXModelManager.shared.downloadedModels
            ParakeetService.isModelAvailable = downloadedModels.contains(MLXModelManager.parakeetRepo)
            
            Logger.app.infoDev("MLX model cache initialized at startup - Parakeet available: \(ParakeetService.isModelAvailable)")
            
            // Early daemon initialization for zero cold start (if daemon mode enabled)
            let daemonModeEnabled = UserDefaults.standard.bool(forKey: "parakeetDaemonMode")
            if ParakeetService.isModelAvailable && daemonModeEnabled {
                do {
                    Logger.app.infoDev("🚀 Starting Parakeet daemon preload...")
                    let pyURL = try await UvBootstrap.ensureVenv(userPython: nil)
                    try await ParakeetDaemon.shared.start(pythonPath: pyURL.path)
                    Logger.app.infoDev("✅ Parakeet daemon preloaded at startup - zero cold start ready")
                } catch {
                    Logger.app.infoDev("⚠️ Daemon preload failed (will fallback to lazy loading): \(error.localizedDescription)")
                }
            }
        }
        
        // Setup app configuration
        AppSetupHelper.setupApp()
        
        // Initialize audio recorder
        audioRecorder = AudioRecorder()
        
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = AppSetupHelper.createMenuBarIcon()
            button.action = #selector(toggleRecordWindow)
            button.target = self
        }
        
        // Create menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: LocalizedStrings.Menu.record, action: #selector(toggleRecordWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: LocalizedStrings.Menu.history, action: #selector(showHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: LocalizedStrings.Menu.settings, action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Help", action: #selector(showHelp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: LocalizedStrings.Menu.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        statusItem?.menu = menu
        
        // Set up global hotkey and keyboard monitoring
        print("🔥 Setting up HotKeyManager...") // HOTKEY DEBUG
        hotKeyManager = HotKeyManager { [weak self] in
            self?.handleHotkey()
        }
        print("✅ HotKeyManager initialized") // HOTKEY DEBUG
        keyboardEventHandler = KeyboardEventHandler()
        
        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        
        // Setup additional notification observers
        setupNotificationObservers()

        // Check for first run and show settings if needed
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if AppSetupHelper.checkFirstRun() {
                self.showWelcomeAndSettings()
            }
        }
        
        // Session start marker for easy log identification
        Logger.app.infoDev("")
        Logger.app.infoDev("")
        Logger.app.infoDev("================================================================================")
        Logger.app.infoDev("🚀 FLUIDVOICE SESSION STARTED 🚀")
        Logger.app.infoDev("================================================================================")
        Logger.app.infoDev("")
        Logger.app.infoDev("")
    }
    
    private func setupNotificationObservers() {
        // Listen for settings requests from error dialogs
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettings),
            name: .openSettingsRequested,
            object: nil
        )
        
        // Listen for welcome completion
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onWelcomeCompleted),
            name: .welcomeCompleted,
            object: nil
        )
        
        // Listen for focus restoration requests
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreFocusToPreviousApp),
            name: .restoreFocusToPreviousApp,
            object: nil
        )
        
        // Listen for recording stopped notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onRecordingStopped),
            name: .recordingStopped,
            object: nil
        )
    }
    
    private func handleHotkey() {
        print("🎹 Hotkey pressed! Starting handleHotkey()") // Direct stderr output
        Logger.app.infoDev("🎹 Hotkey pressed! Starting handleHotkey()")
        let immediateRecording = UserDefaults.standard.bool(forKey: "immediateRecording")
        print("⚙️ immediateRecording = \(immediateRecording)") // Direct stderr output
        Logger.app.infoDev("⚙️ immediateRecording = \(immediateRecording)")
        
        if immediateRecording {
            // Mode 2: Hotkey Start & Stop
            guard let recorder = audioRecorder else {
                Logger.app.errorDev("❌ AudioRecorder not available for immediate recording")
                // Fallback to showing window if recorder not available
                toggleRecordWindow()
                return
            }
            
            Logger.app.infoDev("✅ AudioRecorder is available: \(recorder)")
            
            if recorder.isRecording {
                // Stop recording and process in background - no window needed!
                updateMenuBarIcon(isRecording: false)
                
                // Stop recording and get the audio file
                if let audioURL = recorder.stopRecording() {
                    Logger.app.infoDev("🔄 Starting background transcription...")
                    
                    // Trigger background transcription
                    startBackgroundTranscription(audioURL: audioURL)
                } else {
                    Logger.app.errorDev("❌ Failed to stop recording - no audio URL")
                }
            } else {
                Logger.app.infoDev("🎙️ Attempting to start recording...")
                
                // Check permission first
                if !recorder.hasPermission {
                    Logger.app.errorDev("❌ No microphone permission - showing window for permission UI")
                    toggleRecordWindow()
                    return
                }
                
                Logger.app.infoDev("✅ Microphone permission granted")
                
                // Try to start recording
                if recorder.startRecording() {
                    Logger.app.infoDev("✅ Recording started successfully!")
                    // Success - recording started in background
                    updateMenuBarIcon(isRecording: true)

                    // Play recording start sound if enabled
                    SoundManager().playRecordingStartSound()
                } else {
                    Logger.app.errorDev("❌ Recording failed to start - showing window with error")
                    // Failed - show window with error
                    toggleRecordWindow()
                    // Notify ContentView to show error
                    NotificationCenter.default.post(
                        name: .recordingStartFailed,
                        object: nil
                    )
                }
            }
        } else {
            // Mode 1: Manual Start & Stop (original behavior)
            toggleRecordWindow()
        }
    }
    
    private func updateMenuBarIcon(isRecording: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            
            if isRecording {
                self.startRecordingAnimation()
            } else {
                self.stopRecordingAnimation()
                // Use normal microphone icon
                button.image = AppSetupHelper.createMenuBarIcon()
            }
        }
    }
    
    private func startRecordingAnimation() {
        guard let button = statusItem?.button else { return }
        
        // Stop any existing animation
        stopRecordingAnimation()
        
        // Use the same adaptive sizing as the normal icon
        let iconSize = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        
        // Create red version: red circle outline with red microphone
        let redImage = NSImage(systemSymbolName: "microphone.circle", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        redImage?.isTemplate = false
        let redOutlineImage = redImage?.tinted(with: .systemRed)
        
        // Create black version: use template image so it follows system appearance
        let blackImage = NSImage(systemSymbolName: "microphone.circle", accessibilityDescription: "Recording")?.withSymbolConfiguration(config)
        blackImage?.isTemplate = true  // Template images automatically adapt to menu bar appearance
        
        // Start with red state
        button.image = redOutlineImage
        
        var isRedState = true // Start as red since we just set red image
        
        // Create DispatchSourceTimer on background queue for efficiency
        let queue = DispatchQueue(label: "com.fluidvoice.animation", qos: .background)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        
        // Schedule timer to start immediately and repeat every 0.5 seconds
        timer.schedule(deadline: .now(), repeating: 0.5)
        
        timer.setEventHandler { [weak button] in
            guard let button = button else { return }
            
            // Toggle the state
            isRedState.toggle()
            
            // Update UI on main thread
            DispatchQueue.main.async {
                button.image = isRedState ? redOutlineImage : blackImage
            }
        }
        
        recordingAnimationTimer = timer
        timer.resume()
    }
    
    private func stopRecordingAnimation() {
        recordingAnimationTimer?.cancel()
        recordingAnimationTimer = nil
    }
    
    @objc func toggleRecordWindow() {
        // Create recording window on-demand if it doesn't exist
        if recordingWindow == nil {
            createRecordingWindow()
        }
        windowController.toggleRecordWindow(recordingWindow)
    }
    
    private func createRecordingWindow() {
        // Ensure audioRecorder is available
        guard let recorder = audioRecorder else {
            Logger.app.errorDev("Cannot create recording window: AudioRecorder not initialized")
            return
        }
        
        // Create the recording window programmatically
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window properties
        window.title = "FluidVoice Recording"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .modalPanel
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenPrimary, .fullScreenAuxiliary]
        window.hasShadow = true
        window.isOpaque = false
        
        // Create ContentView and set it as content
        let contentView = ContentView(audioRecorder: recorder)
            .frame(width: 280, height: 160)
            .fixedSize()
            .background(VisualEffectView())
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .modelContainer(DataManager.shared.sharedModelContainer ?? createFallbackModelContainer())
        
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        
        // Hide standard window buttons
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Set up delegate to handle window lifecycle
        recordingWindowDelegate = RecordingWindowDelegate { [weak self] in
            self?.onRecordingWindowClosed()
        }
        window.delegate = recordingWindowDelegate
        
        recordingWindow = window
    }
    
    /// Called when the recording window is closing
    private func onRecordingWindowClosed() {
        // Clean up references
        recordingWindow = nil
        recordingWindowDelegate = nil
        Logger.app.infoDev("Recording window closed and references cleaned up")
    }
    
    /// Creates a fallback container if DataManager initialization fails
    private func createFallbackModelContainer() -> ModelContainer {
        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create fallback ModelContainer: \(error)")
        }
    }
    
    @objc private func restoreFocusToPreviousApp() {
        windowController.restoreFocusToPreviousApp()
    }
    
    @objc private func onRecordingStopped() {
        // Stop the red flashing animation when recording stops (entering processing phase)
        updateMenuBarIcon(isRecording: false)
    }
    
    @objc func openSettings() {
        windowController.openSettings()
    }
    
    
    @objc func onWelcomeCompleted() {
        // Nothing needed - the recording window exists and will be shown by hotkey
    }
    
    
    @MainActor @objc func showHistory() {
        Logger.app.infoDev("History menu item selected")
        HistoryWindowManager.shared.showHistoryWindow()
    }
    
    @objc func showHelp() {
        // Show the welcome dialog as help
        let shouldOpenSettings = WelcomeWindow.showWelcomeDialog()
        
        if shouldOpenSettings {
            openSettings()
        }
    }
    
    @objc private func screenConfigurationChanged() {
        // Reset the cached icon size when screen configuration changes
        AppSetupHelper.resetIconSizeCache()
        
        // Update the menu bar icon with the new size
        if let button = statusItem?.button {
            button.image = AppSetupHelper.createMenuBarIcon()
        }
    }
    
    func hasAPIKey(service: String, account: String) -> Bool {
        return KeychainService.shared.getQuietly(service: service, account: account) != nil
    }
    
    func showWelcomeAndSettings() {
        let shouldOpenSettings = WelcomeWindow.showWelcomeDialog()
        
        if shouldOpenSettings {
            openSettings()
        }
    }
    
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false // Keep app running in menu bar
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources
        recordingAnimationTimer?.cancel()
        recordingAnimationTimer = nil
        
        // Clean up window references
        recordingWindow = nil
        recordingWindowDelegate = nil
        
        // Gracefully shutdown Parakeet daemon
        Task {
            await ParakeetDaemon.shared.stop()
        }
        
        // Cleanup is handled by the deinitializers of the helper classes
        AppSetupHelper.cleanupOldTemporaryFiles()
    }
    
    // MARK: - Debug Configuration
    
    /// Returns debug audio URL if debug mode is enabled and file exists
    private func getDebugAudioURL() -> URL? {
        // Check if debug mode is enabled via UserDefaults
        let debugEnabled = UserDefaults.standard.bool(forKey: "enableDebugAudioMode")
        guard debugEnabled else { return nil }
        
        // Get debug audio path from UserDefaults, fall back to hardcoded path
        let debugAudioPath = UserDefaults.standard.string(forKey: "debugAudioFilePath") 
            ?? "/Users/jonathan.glasmeyer/Downloads/12770092-94b0-4c06-bf19-07346d0e6c6b.wav"
        
        let debugURL = URL(fileURLWithPath: debugAudioPath)
        
        // Only use debug audio if file actually exists
        guard FileManager.default.fileExists(atPath: debugAudioPath) else {
            Logger.app.infoDev("🧪 DEBUG: Debug audio file not found at \(debugAudioPath)")
            return nil
        }
        
        return debugURL
    }
    
    // MARK: - Background Transcription
    
    /// Handles transcription in background without showing any windows
    /// This is the core of the background-only recording mode
    private func startBackgroundTranscription(audioURL: URL) {
        Task {
            do {
                // 🧪 TEST MODE: Use debug audio file if enabled
                let finalAudioURL = getDebugAudioURL() ?? audioURL
                
                Logger.app.infoDev("🎤 Starting transcription for audio file: \(finalAudioURL.lastPathComponent)")
                if finalAudioURL != audioURL {
                    Logger.app.infoDev("🧪 DEBUG: Using test audio file for silent testing")
                    Logger.app.infoDev("🧪 DEBUG: Test file path is \(finalAudioURL.path)")
                }
                
                // Get user's transcription settings (same logic as ContentView)
                let transcriptionProviderString = UserDefaults.standard.string(forKey: "transcriptionProvider") ?? "local"
                let selectedModelString = UserDefaults.standard.string(forKey: "selectedWhisperModel") ?? "large-v3-turbo"
                
                guard let transcriptionProvider = TranscriptionProvider(rawValue: transcriptionProviderString) else {
                    Logger.app.errorDev("❌ Invalid transcription provider: \(transcriptionProviderString)")
                    return
                }
                
                Logger.app.infoDev("🔧 Using transcription provider: \(transcriptionProvider.displayName)")
                
                // Create services directly for background transcription
                let speechToTextService = SpeechToTextService()
                
                // Use same transcription logic as ContentView
                let transcribedText: String
                if transcriptionProvider == .local {
                    guard let selectedWhisperModel = WhisperModel(rawValue: selectedModelString) else {
                        Logger.app.errorDev("❌ Invalid whisper model: \(selectedModelString)")
                        return
                    }
                    Logger.app.infoDev("🤖 Using WhisperKit model: \(selectedWhisperModel.displayName)")
                    transcribedText = try await speechToTextService.transcribe(audioURL: finalAudioURL, provider: transcriptionProvider, model: selectedWhisperModel)
                } else {
                    transcribedText = try await speechToTextService.transcribe(audioURL: finalAudioURL, provider: transcriptionProvider)
                }
                
                Logger.app.infoDev("✅ Transcription completed: \(transcribedText.prefix(50))...")
                Logger.app.infoDev("🧪 DEBUG: Full transcription is [\(transcribedText)]")
                
                // Auto-paste transcribed text
                Logger.app.infoDev("🔄 Auto-pasting transcribed text...")
                await MainActor.run {
                    let pasteManager = PasteManager()
                    pasteManager.pasteText(transcribedText)
                }
                
                // TODO: Save to history later
                // Logger.app.infoDev("📊 Transcription saved to clipboard")
                
                Logger.app.info("✅ Transcription completed successfully")
                
            } catch {
                Logger.app.errorDev("❌ Background transcription failed: \(error.localizedDescription)")
                
                // Even on error, show some feedback to user via menu bar or notification
                await MainActor.run {
                    // Could show a brief notification here if needed
                }
            }
        }
    }
    
}

// Custom window class that can become key and handle keyboard input
class ChromelessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override var acceptsFirstResponder: Bool { true }
}

// Visual effect view for background blur
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let effectView = NSVisualEffectView()
        effectView.state = .active
        effectView.material = .hudWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        return effectView
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Window delegate that handles the recording window lifecycle
private class RecordingWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
