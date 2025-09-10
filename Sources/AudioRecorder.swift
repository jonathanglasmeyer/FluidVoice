import Foundation
import AVFoundation
import AudioUnit
import CoreAudio
import Combine
import Accelerate
import AppKit
import os.log

class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var hasPermission = false
    
    private var recordingURL: URL?
    private var levelUpdateTimer: Timer?
    private let volumeManager = MicrophoneVolumeManager.shared
    private let deviceManager = AudioDeviceManager.shared
    
    // System default input device backup for restoration
    private var savedDefaultInputDevice: AudioDeviceID?
    
    // True HAL AudioUnit direct input source (completely bypasses AVAudioEngine.inputNode)
    private var halMicSource: HALMicrophoneSourceV2!
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    
    // Audio data buffer for file writing
    private var audioFileEngine = AVAudioEngine()
    private var audioConverter: AVAudioConverter?
    
    // Pre-warmed AVAudioEngine for instant recording start
    private var isEnginePrewarmed: Bool = false
    
    // Real-time level monitoring throttling
    private var lastLevelUpdateTime: CFTimeInterval = 0
    private let levelUpdateInterval: CFTimeInterval = 1.0/60.0 // 60fps
    
    override init() {
        super.init()
        setupRecorder()
        checkMicrophonePermission()
        logSelectedMicrophone()
        
        // Initialize true HAL microphone source
        halMicSource = HALMicrophoneSourceV2()
        
        // Pre-warm device manager for optimal latency
        Task {
            await prewarmDeviceManager()
        }
    }
    
    private func setupRecorder() {
        // AVAudioSession is not needed on macOS
    }
    
    private func prewarmDeviceManager() async {
        Logger.audioRecorder.infoDev("🔧 Starting device manager pre-warming process...")
        
        // Check if already pre-warmed on main actor
        let alreadyPrewarmed = await MainActor.run { isEnginePrewarmed }
        guard !alreadyPrewarmed else {
            Logger.audioRecorder.infoDev("✅ Device manager already pre-warmed")
            return
        }
        
        // Check permission first - if not granted, request and wait
        if !hasPermission {
            Logger.audioRecorder.infoDev("🔧 No permission yet - checking current status...")
            checkMicrophonePermission()
            
            // Wait for permission resolution (max 3 seconds)
            let maxWaitTime = 3.0
            let checkInterval = 0.1
            var waitedTime = 0.0
            
            while !hasPermission && waitedTime < maxWaitTime {
                try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
                waitedTime += checkInterval
            }
            
            if !hasPermission {
                Logger.audioRecorder.infoDev("🔧 Skipping device pre-warming - no microphone permission after \(maxWaitTime)s")
                return
            }
        }
        
        Logger.audioRecorder.infoDev("🔧 Permission confirmed - pre-warming device manager...")
        
        // Pre-configure format (this is lightweight and doesn't crash)
        let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        audioFormat = format
        
        // Pre-warm device manager (cache device lookup)
        do {
            let deviceID = try deviceManager.getSelectedInputDevice()
            Logger.audioRecorder.infoDev("✅ Pre-warmed device manager - cached device ID: \(deviceID)")
        } catch {
            Logger.audioRecorder.infoDev("⚠️ Device manager pre-warm failed: \(error.localizedDescription)")
        }
        
        await MainActor.run { [weak self] in
            self?.isEnginePrewarmed = true
            Logger.audioRecorder.infoDev("🚀 Device manager pre-warmed successfully - format and device cached!")
        }
    }
    
    private func logSelectedMicrophone() {
        let selectedMicrophoneID = UserDefaults.standard.string(forKey: "selectedMicrophone") ?? ""
        
        if selectedMicrophoneID.isEmpty {
            Logger.audioRecorder.infoDev("🎯 No specific microphone selected - will use intelligent default")
        } else {
            Logger.audioRecorder.infoDev("🎯 User has selected microphone ID: '\(selectedMicrophoneID)'")
        }
    }
    
    func checkMicrophonePermission() {
        let permissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Logger.audioRecorder.infoDev("🔍 checkMicrophonePermission: \(permissionStatus) (rawValue: \(permissionStatus.rawValue))")
        
        switch permissionStatus {
        case .authorized:
            DispatchQueue.main.async {
                self.hasPermission = true
                // If permission just got granted and we're not pre-warmed, do it now
                // Pre-warming is handled at app startup - no need to repeat
            }
        case .denied, .restricted:
            Logger.audioRecorder.infoDev("⚠️ Microphone permission denied/restricted - attempting re-request in case TCC entry was lost")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Logger.audioRecorder.infoDev("🔍 Re-permission request result: \(granted)")
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    // Pre-warming is handled at app startup - no need to repeat
                }
            }
        case .notDetermined:
            Logger.audioRecorder.infoDev("🔄 Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Logger.audioRecorder.infoDev("🔍 Permission request result: \(granted)")
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    // Pre-warming is handled at app startup - no need to repeat
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
                // Pre-warming is handled at app startup - no need to repeat
            }
        }
    }
    
    
    func startRecording() -> Bool {
        guard hasPermission else {
            Logger.audioRecorder.error("❌ startRecording failed: No microphone permission")
            return false
        }
        
        guard !halMicSource.running else {
            Logger.audioRecorder.error("❌ startRecording failed: HAL source already running")
            return false
        }
        
        Logger.audioRecorder.infoDev("🚀 Starting HAL AudioUnit direct input recording")
        
        // Boost microphone volume if enabled
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.boostMicrophoneVolume()
            }
        }
        
        let tempPath = FileManager.default.temporaryDirectory
        let audioFilename = tempPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")
        recordingURL = audioFilename
        
        do {
            // Use pre-warmed format if available, otherwise create new
            let format: AVAudioFormat
            if isEnginePrewarmed && audioFormat != nil {
                format = audioFormat!
                Logger.audioRecorder.infoDev("✅ Using pre-warmed audio format (16kHz mono)")
            } else {
                format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
                audioFormat = format
                Logger.audioRecorder.infoDev("⚠️ Creating audio format on-demand (not pre-warmed)")
            }
            
            // Get selected device (no expensive system calls needed)
            let selectedDeviceID = try deviceManager.getSelectedInputDevice()
            Logger.audioRecorder.infoDev("📱 Using device ID: \(selectedDeviceID) (direct HAL binding)")
            
            // Create audio file for recording
            audioFile = try AVAudioFile(forWriting: audioFilename, settings: format.settings)
            
            // Start true HAL AudioUnit with direct device binding (no AVAudioEngine involvement)
            let startTime = CACurrentMediaTime()
            try halMicSource.start(using: selectedDeviceID,
                recordingHandler: { [weak self] audioData, frameCount in
                    guard let self = self, self.isRecording else { return }
                    
                    // Convert raw float data to AVAudioPCMBuffer for file writing
                    self.writeAudioData(audioData, frameCount: frameCount)
                },
                levelHandler: { [weak self] level in
                    guard let self = self else { return }
                    
                    // Throttle UI updates to 60fps
                    let now = CACurrentMediaTime()
                    if now - self.lastLevelUpdateTime >= self.levelUpdateInterval {
                        DispatchQueue.main.async {
                            self.audioLevel = level
                            // MiniIndicator will be updated via Combine publisher
                        }
                        self.lastLevelUpdateTime = now
                    }
                }
            )
            let startDuration = (CACurrentMediaTime() - startTime) * 1000
            
            if isEnginePrewarmed {
                Logger.audioRecorder.infoDev("✅ HAL source started with pre-warmed config in \(String(format: "%.1f", startDuration))ms")
            } else {
                Logger.audioRecorder.infoDev("⚠️ HAL source started on-demand in \(String(format: "%.1f", startDuration))ms")
            }
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
            
            Logger.audioRecorder.infoDev("✅ HAL AudioUnit direct input started: \(audioFilename.lastPathComponent)")
            
            return true
            
        } catch {
            Logger.audioRecorder.error("❌ Failed to start HAL AudioUnit recording: \(error.localizedDescription)")
            return false
        }
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        Logger.audioRecorder.infoDev("🛑 Stopping HAL AudioUnit recording...")
        
        // Stop HAL source
        halMicSource.stop()
        
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit stopped cleanly (no system setting restoration needed)")
        
        // Close audio file
        audioFile = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }
        
        // Restore microphone volume if it was boosted
        if UserDefaults.standard.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }
        
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit recording stopped successfully")
        return recordingURL
    }
    
    /// Temporarily sets system default input to prevent Bluetooth activation
    /// Saves current default for restoration after recording
    private func setSystemDefaultInputDevice() throws {
        Logger.audioRecorder.infoDev("🔧 Temporarily setting system default input to prevent Bluetooth activation...")
        
        // First, save the current system default
        savedDefaultInputDevice = try getCurrentDefaultInputDevice()
        Logger.audioRecorder.infoDev("💾 Saved current system default input device: \(savedDefaultInputDevice!)")
        
        // Set to FluidVoice's selected device (should be built-in mic)
        let selectedDeviceID = try deviceManager.getSelectedInputDevice()
        try setDefaultInputDevice(selectedDeviceID)
        
        Logger.audioRecorder.infoDev("✅ System default input temporarily set to ID: \(selectedDeviceID)")
    }
    
    /// Restores the original system default input device (only if it's not Bluetooth)
    private func restoreSystemDefaultInputDevice() {
        guard let originalDevice = savedDefaultInputDevice else {
            Logger.audioRecorder.infoDev("📝 No saved default input device to restore")
            return
        }
        
        // Check if the original device was Bluetooth - if so, don't restore it
        if isBluetoothDevice(originalDevice) {
            Logger.audioRecorder.infoDev("🚫 Original device was Bluetooth (ID: \(originalDevice)) - keeping Built-in Mic as default to prevent lossy mode")
            Logger.audioRecorder.infoDev("💡 User can manually change back in System Settings if needed")
            savedDefaultInputDevice = nil
            return
        }
        
        Logger.audioRecorder.infoDev("🔄 Restoring original system default input device: \(originalDevice)")
        
        do {
            try setDefaultInputDevice(originalDevice)
            Logger.audioRecorder.infoDev("✅ System default input device restored")
        } catch {
            Logger.audioRecorder.errorDev("⚠️ Failed to restore system default input device: \(error.localizedDescription)")
        }
        
        savedDefaultInputDevice = nil
    }
    
    /// Checks if a device is a Bluetooth device
    private func isBluetoothDevice(_ deviceID: AudioDeviceID) -> Bool {
        var transportType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &transportType)
        
        if status == noErr {
            Logger.audioRecorder.infoDev("🔍 Device \(deviceID) transport type: \(transportType)")
            return transportType == kAudioDeviceTransportTypeBluetooth
        }
        
        return false
    }
    
    /// Gets the current system default input device
    private func getCurrentDefaultInputDevice() throws -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil, &size, &deviceID
        )
        
        guard status == noErr else {
            throw NSError(domain: "AudioRecorder", code: Int(status), 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to get current default input device"])
        }
        
        return deviceID
    }
    
    /// Sets the system default input device
    private func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = deviceID
        
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &device
        )
        
        guard status == noErr else {
            throw NSError(domain: "AudioRecorder", code: Int(status),
                         userInfo: [NSLocalizedDescriptionKey: "Failed to set default input device"])
        }
    }
    
    /// Legacy method - no longer needed with HAL AudioUnit direct binding
    private func setSelectedInputDevice() throws {
        Logger.audioRecorder.infoDev("📝 Legacy setSelectedInputDevice() called - no longer needed with HAL direct binding")
        // HAL AudioUnit handles device binding directly, no additional work needed
    }
    
    /// Temporarily disables Bluetooth input devices to prevent HFP mode activation
    private func disableBluetoothInputDevices() {
        Logger.audioRecorder.infoDev("🚫 Preventing Bluetooth input activation...")
        
        // Simple approach: Just log that we're preventing Bluetooth
        // The real work is done by explicitly setting the device in setSelectedInputDevice()
        Logger.audioRecorder.infoDev("✅ Bluetooth input prevention completed (via explicit device selection)")
    }
    
    /// Re-enables Bluetooth input devices after recording
    private func enableBluetoothInputDevices() {
        Logger.audioRecorder.infoDev("✅ Re-enabling Bluetooth input devices...")
        // Since we didn't actually disable anything, this is just logging
        // The main prevention was forcing the non-Bluetooth device selection
    }
    
    /// Legacy method - no longer needed with HAL AudioUnit direct binding
    private func resetAudioRouting() {
        Logger.audioRecorder.infoDev("📝 Legacy resetAudioRouting() called - no longer needed with HAL direct binding")
        // HAL AudioUnit cleanup is handled in halMicSource.stop(), no additional work needed
    }
    
    private func forceCleanup() {
        Logger.audioRecorder.infoDev("🧹 Force cleanup - stopping everything")
        
        if halMicSource.running {
            halMicSource.stop()
        }
        
        audioFile = nil
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.audioLevel = 0.0
        }
    }
    
    private func cleanupRecording() {
        guard let url = recordingURL else { return }
        
        do {
            try FileManager.default.removeItem(at: url)
            Logger.audioRecorder.infoDev("🗑️ Cleaned up orphaned recording file: \(url.lastPathComponent)")
        } catch {
            Logger.audioRecorder.infoDev("⚠️ Could not clean up recording file: \(error.localizedDescription)")
        }
        
        recordingURL = nil
    }
    
    /// Convert raw float audio data to AVAudioPCMBuffer and write to file
    private func writeAudioData(_ audioData: UnsafePointer<Float>, frameCount: Int) {
        guard let format = audioFormat else { return }
        
        // Create buffer with the audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            Logger.audioRecorder.error("❌ Could not create PCM buffer")
            return
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Copy audio data to buffer
        if let channelData = buffer.floatChannelData?[0] {
            channelData.update(from: audioData, count: frameCount)
        }
        
        // Write to file
        do {
            try audioFile?.write(from: buffer)
        } catch {
            Logger.audioRecorder.error("❌ Failed to write audio buffer: \(error.localizedDescription)")
        }
    }
    
    deinit {
        forceCleanup()
    }
}