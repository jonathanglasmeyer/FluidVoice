import Foundation
import AVFoundation
import Combine
import os.log

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false
    
    private var captureSession: AVCaptureSession?
    private var audioInput: AVCaptureDeviceInput?
    private var audioOutput: AVCaptureAudioFileOutput?
    private var recordingURL: URL?
    private var levelUpdateTimer: Timer?
    private let volumeManager = MicrophoneVolumeManager.shared
    private let deviceManager = AudioDeviceManager.shared
    
    // Pre-warmed session for instant recording start
    private var prewarmedSession: AVCaptureSession?
    private var prewarmedInput: AVCaptureDeviceInput?
    private var prewarmedOutput: AVCaptureAudioFileOutput?
    private var lastSelectedDeviceID: String = ""
    
    override init() {
        super.init()
        setupRecorder()
        checkMicrophonePermission()
        logSelectedMicrophone()
        
        // Pre-warm session in background after short delay
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            await prepareSessionInBackground()
        }
    }
    
    private func setupRecorder() {
        // AVAudioSession is not needed on macOS
    }
    
    @MainActor
    private func prepareSessionInBackground() async {
        guard hasPermission else {
            Logger.audioRecorder.infoDev("🔧 Skipping session pre-warming - no microphone permission")
            return
        }
        
        Logger.audioRecorder.infoDev("🔧 Pre-warming capture session in background...")
        
        do {
            let selectedDevice = try await getSelectedDevice()
            let deviceID = selectedDevice.uniqueID
            
            // Only create new session if device changed
            if deviceID != lastSelectedDeviceID || prewarmedSession == nil {
                Logger.audioRecorder.infoDev("🔄 Device changed or first time - creating pre-warmed session")
                
                // Clean up old session
                prewarmedSession?.stopRunning()
                prewarmedSession = nil
                prewarmedInput = nil
                prewarmedOutput = nil
                
                // Create new pre-warmed session with parallel setup
                let session = AVCaptureSession()
                session.beginConfiguration()
                
                // Create input and output in parallel
                async let inputTask: AVCaptureDeviceInput = {
                    return try AVCaptureDeviceInput(device: selectedDevice)
                }()
                async let outputTask: AVCaptureAudioFileOutput = {
                    return AVCaptureAudioFileOutput()
                }()
                
                let (audioInput, audioOutput) = try await (inputTask, outputTask)
                
                guard session.canAddInput(audioInput) && session.canAddOutput(audioOutput) else {
                    Logger.audioRecorder.error("❌ Cannot add input/output to pre-warmed session")
                    return
                }
                
                session.addInput(audioInput)
                session.addOutput(audioOutput)
                session.commitConfiguration()
                
                // Start session in background (this is the expensive 50ms operation)
                session.startRunning()
                
                // Store pre-warmed components
                self.prewarmedSession = session
                self.prewarmedInput = audioInput
                self.prewarmedOutput = audioOutput
                self.lastSelectedDeviceID = deviceID
                
                Logger.audioRecorder.infoDev("✅ Pre-warmed session created and started for device: '\(selectedDevice.localizedName)'")
            } else {
                Logger.audioRecorder.infoDev("✅ Pre-warmed session already ready for current device")
            }
        } catch {
            Logger.audioRecorder.error("❌ Failed to pre-warm session: \(error.localizedDescription)")
        }
    }
    
    private func getSelectedDevice() async throws -> AVCaptureDevice {
        let selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophone") ?? ""
        
        if selectedMicrophoneID.isEmpty {
            // Use AudioDeviceManager's intelligent selection
            let selectedDeviceID = try deviceManager.getSelectedInputDevice()
            let deviceName = deviceManager.getDeviceName(deviceID: selectedDeviceID) ?? "Unknown"
            
            // Find corresponding AVCaptureDevice
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            
            if let device = discoverySession.devices.first(where: { device in
                device.localizedName == deviceName || device.localizedName.contains(deviceName) || deviceName.contains(device.localizedName)
            }) {
                return device
            } else {
                guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
                    throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No default audio device"])
                }
                return defaultDevice
            }
        } else {
            // User selected specific device
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            
            if let device = discoverySession.devices.first(where: { $0.uniqueID == selectedMicrophoneID }) {
                return device
            } else {
                guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
                    throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "No default audio device"])
                }
                return defaultDevice
            }
        }
    }
    
    private func logSelectedMicrophone() {
        let selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophone") ?? ""
        
        if selectedMicrophoneID.isEmpty {
            Logger.audioRecorder.infoDev("🎯 No specific microphone selected - will use intelligent default")
        } else {
            // Try to get the device name for better logging
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            
            if let device = discoverySession.devices.first(where: { $0.uniqueID == selectedMicrophoneID }) {
                Logger.audioRecorder.infoDev("🎯 User has selected microphone: '\(device.localizedName)' (ID: \(selectedMicrophoneID))")
            } else {
                Logger.audioRecorder.infoDev("🎯 User has selected microphone ID: '\(selectedMicrophoneID)' (device not currently available)")
            }
        }
    }
    
    func checkMicrophonePermission() {
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.audioRecorder.infoDev("🔍 checkMicrophonePermission: \(permissionStatus) (rawValue: \(permissionStatus.rawValue))")
        
        switch permissionStatus {
        case .authorized:
            DispatchQueue.main.async {
                self.hasPermission = true
            }
        case .denied, .restricted:
            Logger.audioRecorder.infoDev("⚠️ Microphone permission denied/restricted - attempting re-request in case TCC entry was lost")
            // Try to request permission again - could be due to TCC reset or missing entry
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Logger.audioRecorder.infoDev("🔍 Re-permission request result: \(granted)")
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                }
            }
        case .notDetermined:
            Logger.audioRecorder.infoDev("🔄 Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Logger.audioRecorder.infoDev("🔍 Permission request result: \(granted)")
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                }
            }
        @unknown default:
            Logger.audioRecorder.infoDev("⚠️ Unknown permission status: \(permissionStatus)")
            DispatchQueue.main.async {
                self.hasPermission = false
            }
        }
    }
    
    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
            }
        }
    }
    
    func startRecording() -> Bool {
        // Check permission first
        guard hasPermission else {
            Logger.audioRecorder.error("❌ startRecording failed: No microphone permission")
            return false
        }
        
        // Prevent re-entrancy - if already recording, return false
        guard captureSession == nil else {
            Logger.audioRecorder.error("❌ startRecording failed: Capture session already exists (not cleaned up)")
            // Force cleanup and try again
            forceCleanup()
            return false
        }
        
        // Try to use pre-warmed session first (FAST PATH)
        if let prewarmedSession = self.prewarmedSession,
           let prewarmedInput = self.prewarmedInput,
           let prewarmedOutput = self.prewarmedOutput {
            
            Logger.audioRecorder.infoDev("🚀 Using pre-warmed session for instant recording start")
            
            let tempPath = FileManager.default.temporaryDirectory
            let audioFilename = tempPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
            recordingURL = audioFilename
            
            // Move pre-warmed session to active session
            self.captureSession = prewarmedSession
            self.audioInput = prewarmedInput
            self.audioOutput = prewarmedOutput
            
            // Clear pre-warmed references
            self.prewarmedSession = nil
            self.prewarmedInput = nil
            self.prewarmedOutput = nil
            
            Logger.audioRecorder.infoDev("🎬 Starting recording to file: \(audioFilename.lastPathComponent)")
            
            // Start recording and volume boost in parallel
            prewarmedOutput.startRecording(to: audioFilename, outputFileType: .m4a, recordingDelegate: self)
            
            // Boost microphone volume if enabled (parallel - no await)
            if UserDefaults.standard.autoBoostMicrophoneVolume {
                Task {
                    await volumeManager.boostMicrophoneVolume()
                }
            }
            
            // Update recording state
            if Thread.isMainThread {
                self.isRecording = true
                self.startLevelMonitoring()
            } else {
                DispatchQueue.main.sync {
                    self.isRecording = true
                    self.startLevelMonitoring()
                }
            }
            
            Logger.audioRecorder.infoDev("✅ Pre-warmed recording started instantly!")
            
            // Pre-warm next session in background
            Task {
                await prepareSessionInBackground()
            }
            
            return true
        }
        
        // Fallback to old slow path if pre-warming failed
        Logger.audioRecorder.infoDev("⚠️ Pre-warmed session not available - using slow path")
        
        // Boost microphone volume if enabled
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.boostMicrophoneVolume()
            }
        }
        
        let tempPath = FileManager.default.temporaryDirectory
        let audioFilename = tempPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        
        recordingURL = audioFilename
        
        // Get the selected input device
        let selectedDevice: AVCaptureDevice
        let selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophone") ?? ""
        
        if selectedMicrophoneID.isEmpty {
            // Use system default - get intelligently selected device
            Logger.audioRecorder.infoDev("🎤 Using system default (intelligent selection)")
            
            // Get all available devices
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            
            // Use AudioDeviceManager's intelligent selection logic
            let selectedDeviceID: AudioDeviceID
            do {
                selectedDeviceID = try deviceManager.getSelectedInputDevice()
            } catch {
                Logger.audioRecorder.error("Failed to get selected input device: \(error.localizedDescription)")
                return false
            }
            
            let deviceName = deviceManager.getDeviceName(deviceID: selectedDeviceID) ?? "Unknown"
            Logger.audioRecorder.infoDev("🎤 AudioDeviceManager selected: '\(deviceName)' (ID: \(selectedDeviceID))")
            
            // Find corresponding AVCaptureDevice by matching names
            let matchingDevice = discoverySession.devices.first { device in
                device.localizedName == deviceName || device.localizedName.contains(deviceName) || deviceName.contains(device.localizedName)
            }
            
            if let device = matchingDevice {
                selectedDevice = device
                Logger.audioRecorder.infoDev("✅ Found matching AVCaptureDevice: '\(device.localizedName)'")
            } else {
                // Fallback to default device
                guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
                    Logger.audioRecorder.error("No default audio input device available")
                    return false
                }
                selectedDevice = defaultDevice
                Logger.audioRecorder.infoDev("⚠️ Using AVCaptureDevice default: '\(defaultDevice.localizedName)'")
            }
        } else {
            // User selected specific device
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            
            if let device = discoverySession.devices.first(where: { $0.uniqueID == selectedMicrophoneID }) {
                selectedDevice = device
                Logger.audioRecorder.infoDev("🎯 Using user-selected device: '\(device.localizedName)'")
            } else {
                Logger.audioRecorder.error("Selected microphone device not found: '\(selectedMicrophoneID)' - falling back to default")
                
                guard let defaultDevice = AVCaptureDevice.default(for: .audio) else {
                    Logger.audioRecorder.error("No default audio input device available")
                    return false
                }
                selectedDevice = defaultDevice
                Logger.audioRecorder.infoDev("⚠️ Falling back to default device: '\(defaultDevice.localizedName)'")
            }
        }
        
        Logger.audioRecorder.infoDev("🎤 Recording with device: '\(selectedDevice.localizedName)' (ID: \(selectedDevice.uniqueID))")
        Logger.audioRecorder.infoDev("🔍 Device validated and ready for recording")
        
        do {
            Logger.audioRecorder.infoDev("🔧 Creating capture session...")
            // Create capture session
            let session = AVCaptureSession()
            session.beginConfiguration()
            
            Logger.audioRecorder.infoDev("🔧 Creating audio input...")
            // Add audio input
            let audioInput = try AVCaptureDeviceInput(device: selectedDevice)
            Logger.audioRecorder.infoDev("✅ Audio input created successfully")
            
            guard session.canAddInput(audioInput) else {
                Logger.audioRecorder.error("❌ Cannot add audio input to capture session")
                return false
            }
            session.addInput(audioInput)
            Logger.audioRecorder.infoDev("✅ Audio input added to session")
            
            Logger.audioRecorder.infoDev("🔧 Creating audio file output...")
            // Add audio file output
            let audioOutput = AVCaptureAudioFileOutput()
            guard session.canAddOutput(audioOutput) else {
                Logger.audioRecorder.error("❌ Cannot add audio output to capture session")
                return false
            }
            session.addOutput(audioOutput)
            Logger.audioRecorder.infoDev("✅ Audio output added to session")
            
            session.commitConfiguration()
            Logger.audioRecorder.infoDev("✅ Session configuration committed")
            
            // Store references
            self.captureSession = session
            self.audioInput = audioInput
            self.audioOutput = audioOutput
            
            Logger.audioRecorder.infoDev("▶️ Starting capture session first...")
            // CRITICAL: Start capture session BEFORE starting recording
            session.startRunning()
            Logger.audioRecorder.infoDev("✅ Capture session started")
            
            Logger.audioRecorder.infoDev("🎬 Starting recording to file: \(audioFilename.lastPathComponent)")
            Logger.audioRecorder.infoDev("🔍 File path: \(audioFilename.path)")
            
            // Check if we can write to the temp directory
            let tempDir = audioFilename.deletingLastPathComponent()
            if !FileManager.default.isWritableFile(atPath: tempDir.path) {
                Logger.audioRecorder.error("❌ Cannot write to temp directory: \(tempDir.path)")
                return false
            }
            Logger.audioRecorder.infoDev("✅ Temp directory is writable")
            
            // Start recording to file (session must be running first!)
            audioOutput.startRecording(to: audioFilename, outputFileType: .m4a, recordingDelegate: self)
            Logger.audioRecorder.infoDev("✅ startRecording() call completed")
            
            // Update @Published properties on main thread
            Logger.audioRecorder.infoDev("🔄 Updating recording state...")
            if Thread.isMainThread {
                self.isRecording = true
                self.startLevelMonitoring()
            } else {
                DispatchQueue.main.sync {
                    self.isRecording = true
                    self.startLevelMonitoring()
                }
            }
            Logger.audioRecorder.infoDev("✅ Recording state updated - recording is now active")
            return true
        } catch {
            Logger.audioRecorder.error("❌ Failed to start recording: \(error.localizedDescription)")
            Logger.audioRecorder.error("❌ Error details: \(error)")
            
            // Cleanup on failure
            forceCleanup()
            
            // Recheck permissions if recording failed
            checkMicrophonePermission()
            return false
        }
    }
    
    
    func stopRecording() -> URL? {
        audioOutput?.stopRecording()
        captureSession?.stopRunning()
        
        // Cleanup references
        captureSession = nil
        audioInput = nil
        audioOutput = nil
        
        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        // Update @Published properties on main thread
        if Thread.isMainThread {
            self.isRecording = false
            self.stopLevelMonitoring()
        } else {
            DispatchQueue.main.sync {
                self.isRecording = false
                self.stopLevelMonitoring()
            }
        }
        
        return recordingURL
    }
    
    func cleanupRecording() {
        guard let url = recordingURL else { return }
        
        // Restore microphone volume if it was boosted (in case of cancellation/cleanup)
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.audioRecorder.error("Failed to cleanup recording file: \(error.localizedDescription)")
        }
        
        recordingURL = nil
    }
    
    func cancelRecording() {
        // Stop recording and cleanup without returning URL
        audioOutput?.stopRecording()
        captureSession?.stopRunning()
        
        // Cleanup references
        captureSession = nil
        audioInput = nil
        audioOutput = nil
        
        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        // Update @Published properties on main thread
        if Thread.isMainThread {
            self.isRecording = false
            self.stopLevelMonitoring()
        } else {
            DispatchQueue.main.sync {
                self.isRecording = false
                self.stopLevelMonitoring()
            }
        }
        
        // Clean up the recording file
        cleanupRecording()
    }
    
    private func forceCleanup() {
        Logger.audioRecorder.infoDev("🧹 Force cleanup of capture session")
        
        // Stop any active recording
        audioOutput?.stopRecording()
        captureSession?.stopRunning()
        
        // Clear all references
        captureSession = nil
        audioInput = nil
        audioOutput = nil
        
        // Don't touch pre-warmed session - it should stay ready
        
        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        // Update state on main thread
        if Thread.isMainThread {
            self.isRecording = false
            self.stopLevelMonitoring()
        } else {
            DispatchQueue.main.sync {
                self.isRecording = false
                self.stopLevelMonitoring()
            }
        }
        
        // Clean up any orphaned recording file
        cleanupRecording()
    }
    
    deinit {
        // Clean up pre-warmed session on deallocation
        prewarmedSession?.stopRunning()
        prewarmedSession = nil
        prewarmedInput = nil
        prewarmedOutput = nil
    }
    
    private func startLevelMonitoring() {
        // For AVCaptureSession, we'll simulate audio levels since we don't have direct metering
        // In a production app, you might want to add an AVCaptureAudioDataOutput to get actual levels
        levelUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, self.isRecording else { return }
            
            // Simulate audio level (in a real implementation, you'd get this from audio data)
            let simulatedLevel = Float.random(in: 0.3...0.8)
            
            // Update on main thread if needed
            if Thread.isMainThread {
                self.audioLevel = simulatedLevel
            } else {
                DispatchQueue.main.async {
                    self.audioLevel = simulatedLevel
                }
            }
        }
    }
    
    private func stopLevelMonitoring() {
        levelUpdateTimer?.invalidate()
        levelUpdateTimer = nil
        audioLevel = 0.0
    }
    
    private func normalizeLevel(_ level: Float) -> Float {
        // Convert dB to linear scale (0.0 to 1.0)
        let minDb: Float = -60.0
        let maxDb: Float = 0.0
        
        let clampedLevel = max(minDb, min(maxDb, level))
        return (clampedLevel - minDb) / (maxDb - minDb)
    }
}

extension AudioRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            Logger.audioRecorder.error("Recording finished with error: \(error.localizedDescription)")
        } else {
            Logger.audioRecorder.infoDev("✅ Recording finished successfully to: \(outputFileURL.path)")
        }
    }
}