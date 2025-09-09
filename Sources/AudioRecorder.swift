import Foundation
import AVFoundation
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
    
    // Unified AVAudioEngine for both recording and level monitoring
    private var audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var audioFormat: AVAudioFormat?
    
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
        
        // Pre-warm AVAudioEngine for optimal latency (background thread, safe implementation)
        Task {
            await prewarmAudioEngine()
        }
    }
    
    private func setupRecorder() {
        // AVAudioSession is not needed on macOS
    }
    
    private func prewarmAudioEngine() async {
        Logger.audioRecorder.infoDev("🔧 Starting AVAudioEngine pre-warming process...")
        
        // Check if already pre-warmed on main actor
        let alreadyPrewarmed = await MainActor.run { isEnginePrewarmed }
        guard !alreadyPrewarmed else {
            Logger.audioRecorder.infoDev("✅ AVAudioEngine already pre-warmed")
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
                Logger.audioRecorder.infoDev("🔧 Skipping engine pre-warming - no microphone permission after \(maxWaitTime)s")
                return
            }
        }
        
        Logger.audioRecorder.infoDev("🔧 Permission confirmed - pre-warming AVAudioEngine configuration...")
        
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
        
        // IMPORTANT: Do NOT call audioEngine.prepare() without configured nodes!
        // This would crash with "inputNode != nullptr || outputNode != nullptr"
        // Instead, mark as ready for fast configuration during startRecording()
        
        DispatchQueue.main.async { [weak self] in
            self?.isEnginePrewarmed = true
            Logger.audioRecorder.infoDev("🚀 AVAudioEngine pre-warmed successfully - format and device cached!")
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
        
        guard !audioEngine.isRunning else {
            Logger.audioRecorder.error("❌ startRecording failed: Engine already running")
            return false
        }
        
        Logger.audioRecorder.infoDev("🚀 Starting unified AVAudioEngine recording + level monitoring")
        
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
            
            // Create audio file for recording
            audioFile = try AVAudioFile(forWriting: audioFilename, settings: format.settings)
            
            let inputNode = audioEngine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            // Install tap for BOTH recording AND level monitoring
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
                guard let self = self, self.isRecording else { return }
                
                // 1. Convert and write to file for recording
                do {
                    // Convert from input format (e.g., 44.1kHz stereo) to our target format (16kHz mono)
                    guard let converter = AVAudioConverter(from: inputFormat, to: format) else {
                        Logger.audioRecorder.error("❌ Could not create audio format converter")
                        return
                    }
                    
                    // Calculate output buffer size based on sample rate conversion
                    let ratio = format.sampleRate / inputFormat.sampleRate
                    let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                    
                    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCount) else {
                        Logger.audioRecorder.error("❌ Could not create output buffer")
                        return
                    }
                    
                    var error: NSError?
                    let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                        outStatus.pointee = AVAudioConverterInputStatus.haveData
                        return buffer
                    }
                    
                    if status == .error {
                        Logger.audioRecorder.error("❌ Audio conversion failed: \(error?.localizedDescription ?? "unknown error")")
                        return
                    }
                    
                    // Write the converted buffer to file
                    try self.audioFile?.write(from: outputBuffer)
                } catch {
                    Logger.audioRecorder.error("❌ Failed to write audio buffer: \(error.localizedDescription)")
                }
                
                // 2. Calculate real-time audio levels
                guard let channelData = buffer.floatChannelData?[0] else { return }
                let frameCount = Int(buffer.frameLength)
                
                // Calculate RMS using vDSP
                var rms: Float = 0.0
                vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
                
                // Convert to normalized level (0.0-1.0)
                let db = 20 * log10(max(rms, 0.000001)) // Avoid log(0)
                let normalizedLevel = max(0.0, min(1.0, (db + 60) / 60)) // -60dB to 0dB range
                
                // Throttle UI updates to 60fps
                let now = CACurrentMediaTime()
                if now - self.lastLevelUpdateTime >= self.levelUpdateInterval {
                    DispatchQueue.main.async {
                        self.audioLevel = normalizedLevel
                        // MiniIndicator will be updated via Combine publisher
                    }
                    self.lastLevelUpdateTime = now
                }
            }
            
            // Prepare engine (necessary step after installTap)
            let startTime = CACurrentMediaTime()
            audioEngine.prepare()
            let prepareTime = (CACurrentMediaTime() - startTime) * 1000
            
            if isEnginePrewarmed {
                Logger.audioRecorder.infoDev("✅ Engine prepared with pre-warmed config in \(String(format: "%.1f", prepareTime))ms")
            } else {
                Logger.audioRecorder.infoDev("⚠️ Engine prepared on-demand in \(String(format: "%.1f", prepareTime))ms")
            }
            
            try audioEngine.start()
            
            DispatchQueue.main.async {
                self.isRecording = true
            }
            
            Logger.audioRecorder.infoDev("✅ Unified AVAudioEngine recording started: \(audioFilename.lastPathComponent)")
            
            return true
            
        } catch {
            Logger.audioRecorder.error("❌ Failed to start AVAudioEngine recording: \(error.localizedDescription)")
            return false
        }
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        Logger.audioRecorder.infoDev("🛑 Stopping AVAudioEngine recording...")
        
        // Stop engine and remove tap
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        
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
        
        Logger.audioRecorder.infoDev("✅ Recording stopped successfully")
        return recordingURL
    }
    
    private func forceCleanup() {
        Logger.audioRecorder.infoDev("🧹 Force cleanup - stopping everything")
        
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
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
    
    deinit {
        forceCleanup()
    }
}