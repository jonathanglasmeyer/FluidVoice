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
        guard hasPermission else {
            Logger.audioRecorder.infoDev("🔧 Skipping engine pre-warming - no microphone permission")
            return
        }
        
        guard !isEnginePrewarmed else {
            Logger.audioRecorder.infoDev("✅ AVAudioEngine already pre-warmed")
            return
        }
        
        Logger.audioRecorder.infoDev("🔧 Pre-warming AVAudioEngine - moving prepare() off main thread...")
        
        // Move the potentially blocking prepare() call to a background thread
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                Logger.audioRecorder.infoDev("🔧 Calling audioEngine.prepare() on background thread...")
                
                do {
                    // Prepare the bare engine on background thread
                    self.audioEngine.prepare()
                    Logger.audioRecorder.infoDev("✅ audioEngine.prepare() completed successfully")
                    
                    DispatchQueue.main.async {
                        self.isEnginePrewarmed = true
                        Logger.audioRecorder.infoDev("✅ AVAudioEngine pre-warmed successfully")
                        continuation.resume()
                    }
                } catch {
                    Logger.audioRecorder.error("❌ audioEngine.prepare() failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
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
            }
        case .denied, .restricted:
            Logger.audioRecorder.infoDev("⚠️ Microphone permission denied/restricted - attempting re-request in case TCC entry was lost")
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
            // Use optimal format for Whisper (16kHz, mono, 16-bit)
            let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
            audioFormat = format
            
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
            
            // Use pre-warmed engine or prepare on-demand
            if !isEnginePrewarmed {
                Logger.audioRecorder.infoDev("⚠️ Engine not pre-warmed, preparing now...")
                audioEngine.prepare()
            } else {
                Logger.audioRecorder.infoDev("✅ Using pre-warmed engine for optimal latency")
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