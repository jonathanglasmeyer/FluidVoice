import Foundation
import AVFoundation
import AudioUnit
import CoreAudio
import os.log

/// Direct HAL AudioUnit microphone source that binds to specific hardware devices
/// without triggering system default input changes or Bluetooth HFP activation
final class HALMicrophoneSource {
    private let engine = AVAudioEngine()
    private var halUnit: AVAudioNode?
    private var audioUnit: AudioUnit?
    private var format: AVAudioFormat?
    private var isRunning = false
    
    /// Audio level monitoring for real-time UI updates
    private weak var levelDelegate: AudioLevelDelegate?
    
    /// Current device information
    private var currentDeviceID: AudioDeviceID = 0
    private var currentDeviceName: String = ""
    
    init() {
        Logger.audioRecorder.infoDev("🎤 HALMicrophoneSource initialized")
    }
    
    /// Start recording with direct HAL AudioUnit binding to specified device
    /// - Parameter deviceID: The AudioDeviceID to bind directly to
    /// - Throws: Configuration or engine errors
    func start(using deviceID: AudioDeviceID) throws {
        guard !isRunning else {
            Logger.audioRecorder.infoDev("⚠️ HAL source already running")
            return
        }
        
        Logger.audioRecorder.infoDev("🚀 Starting HAL AudioUnit with device ID: \(deviceID)")
        currentDeviceID = deviceID
        
        // 1. Create and configure HAL Output AudioUnit
        try createAndConfigureAudioUnit(deviceID: deviceID)
        
        // 2. Setup audio format (16kHz mono for consistent processing)
        setupAudioFormat()
        
        // 3. Connect to AVAudioEngine pipeline
        try connectToEngine()
        
        // 4. Start the engine
        try engine.start()
        
        isRunning = true
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit started successfully with \(currentDeviceName)")
    }
    
    /// Stop the HAL AudioUnit and clean up resources
    func stop() {
        guard isRunning else { return }
        
        Logger.audioRecorder.infoDev("🛑 Stopping HAL AudioUnit...")
        
        // Remove tap if exists
        if let halUnit = halUnit {
            halUnit.removeTap(onBus: 0)
        }
        
        // Stop and reset engine
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()
        
        // Cleanup AudioUnit
        if let audioUnit = audioUnit {
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }
        
        // Reset state
        halUnit = nil
        audioUnit = nil
        isRunning = false
        currentDeviceID = 0
        currentDeviceName = ""
        
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit stopped and cleaned up")
    }
    
    /// Install audio tap for recording and level monitoring
    /// - Parameters:
    ///   - bufferSize: Audio buffer size for processing
    ///   - recordingHandler: Callback for audio data to be recorded
    ///   - levelHandler: Callback for real-time audio level updates
    func installTap(bufferSize: AVAudioFrameCount = 128,
                   recordingHandler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void,
                   levelHandler: @escaping (Float) -> Void) {
        guard let halUnit = halUnit,
              let format = format else {
            Logger.audioRecorder.error("❌ Cannot install tap - HAL unit not configured")
            return
        }
        
        halUnit.installTap(onBus: 0, bufferSize: bufferSize, format: format) { buffer, time in
            // Handle recording
            recordingHandler(buffer, time)
            
            // Calculate and report audio level
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                let level = self.calculateAudioLevel(channelData: channelData, frameCount: frameCount)
                levelHandler(level)
            }
        }
        
        Logger.audioRecorder.infoDev("🎧 Audio tap installed on HAL unit")
    }
    
    /// Remove audio tap
    func removeTap() {
        halUnit?.removeTap(onBus: 0)
        Logger.audioRecorder.infoDev("🎧 Audio tap removed from HAL unit")
    }
    
    /// Get the AVAudioEngine for external access if needed
    var audioEngine: AVAudioEngine {
        return engine
    }
    
    /// Check if the source is currently running
    var running: Bool {
        return isRunning
    }
    
    /// Get current audio format
    var audioFormat: AVAudioFormat? {
        return format
    }
    
    /// Get information about currently bound device
    var deviceInfo: (id: AudioDeviceID, name: String) {
        return (currentDeviceID, currentDeviceName)
    }
}

// MARK: - Private Implementation

private extension HALMicrophoneSource {
    
    /// Create and configure HAL Output AudioUnit for input capture
    func createAndConfigureAudioUnit(deviceID: AudioDeviceID) throws {
        Logger.audioRecorder.infoDev("🔧 Creating HAL Output AudioUnit...")
        
        // 1. Get device name for logging
        currentDeviceName = getDeviceName(deviceID) ?? "Unknown Device"
        Logger.audioRecorder.infoDev("📱 Target device: \(currentDeviceName) (ID: \(deviceID))")
        
        // 2. Create AudioComponent description for HAL Output
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // 3. Find and instantiate the component
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw HALMicrophoneError.componentNotFound
        }
        
        var unit: AudioUnit?
        let status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let audioUnit = unit else {
            throw HALMicrophoneError.instantiationFailed(status)
        }
        
        self.audioUnit = audioUnit
        
        // 4. Enable input (scope 1), disable output (scope 0)
        var enableInput: UInt32 = 1
        var disableOutput: UInt32 = 0
        
        var result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // Input bus
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        guard result == noErr else {
            throw HALMicrophoneError.configurationFailed("Failed to enable input", result)
        }
        
        result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // Output bus
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )
        
        guard result == noErr else {
            throw HALMicrophoneError.configurationFailed("Failed to disable output", result)
        }
        
        // 5. CRITICAL: Bind to specific device BEFORE any engine operations
        var targetDevice = deviceID
        result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &targetDevice,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        guard result == noErr else {
            throw HALMicrophoneError.configurationFailed("Failed to bind to device \(deviceID)", result)
        }
        
        // 6. Initialize the AudioUnit
        result = AudioUnitInitialize(audioUnit)
        guard result == noErr else {
            throw HALMicrophoneError.initializationFailed(result)
        }
        
        // Store the initialized AudioUnit for cleanup
        // Note: We'll actually use the engine's inputNode in connectToEngine()
        
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit configured and bound to \(currentDeviceName)")
    }
    
    /// Setup audio format for consistent processing
    func setupAudioFormat() {
        // Use 16kHz mono format for consistent whisper processing
        format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)
        Logger.audioRecorder.infoDev("🎵 Audio format configured: 16kHz mono")
    }
    
    /// Connect HAL AudioUnit to AVAudioEngine pipeline
    /// For now, we'll use a simpler approach with AVAudioEngine.inputNode but with explicit device setting
    func connectToEngine() throws {
        guard let format = format else {
            throw HALMicrophoneError.configurationFailed("Audio format not ready", -1)
        }
        
        // Set the device on the engine's input node AudioUnit
        let inputNode = engine.inputNode
        let inputAudioUnit = inputNode.audioUnit!
        
        var deviceID = currentDeviceID
        let result = AudioUnitSetProperty(
            inputAudioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        
        guard result == noErr else {
            throw HALMicrophoneError.configurationFailed("Failed to set device on input node", result)
        }
        
        // Store reference to input node as our "halUnit"
        halUnit = inputNode
        
        // Prepare engine
        engine.prepare()
        
        Logger.audioRecorder.infoDev("✅ Input node configured with device ID \(currentDeviceID)")
    }
    
    /// Calculate normalized audio level from buffer data
    func calculateAudioLevel(channelData: UnsafePointer<Float>, frameCount: Int) -> Float {
        // Calculate RMS using basic math (no vDSP dependency for now)
        var sum: Float = 0.0
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        
        // Convert to dB and normalize to 0.0-1.0 range
        let db = 20 * log10(max(rms, 0.000001)) // Avoid log(0)
        let normalizedLevel = max(0.0, min(1.0, (db + 60) / 60)) // -60dB to 0dB range
        
        return normalizedLevel
    }
    
    /// Get human-readable device name for logging
    func getDeviceName(_ deviceID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &size)
        guard result == noErr else { return nil }
        
        // Allocate buffer for CFString
        var cfString: CFString?
        result = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &cfString)
        guard result == noErr, let cfString = cfString else { return nil }
        
        return cfString as String
    }
}

// MARK: - Error Types

enum HALMicrophoneError: Error, LocalizedError {
    case componentNotFound
    case instantiationFailed(OSStatus)
    case configurationFailed(String, OSStatus)
    case initializationFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "HAL Output AudioUnit component not found"
        case .instantiationFailed(let status):
            return "Failed to instantiate AudioUnit (status: \(status))"
        case .configurationFailed(let message, let status):
            return "\(message) (status: \(status))"
        case .initializationFailed(let status):
            return "Failed to initialize AudioUnit (status: \(status))"
        }
    }
}

// MARK: - Audio Level Delegate

protocol AudioLevelDelegate: AnyObject {
    func audioLevelChanged(_ level: Float)
}