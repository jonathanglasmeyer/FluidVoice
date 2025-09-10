import Foundation
import AVFoundation
import AudioUnit
import CoreAudio
import os.log

/// True HAL AudioUnit direct input that completely bypasses AVAudioEngine.inputNode
/// and system default device behavior - no Bluetooth HFP activation
final class HALMicrophoneSourceV2 {
    fileprivate var audioUnit: AudioUnit?
    private var isRunning = false
    
    /// Audio format for processing
    private let sampleRate: Double = 16000
    private let channels: UInt32 = 1
    
    /// Current device information
    private var currentDeviceID: AudioDeviceID = 0
    private var currentDeviceName: String = ""
    
    /// Recording callbacks
    private var recordingHandler: ((UnsafePointer<Float>, Int) -> Void)?
    private var levelHandler: ((Float) -> Void)?
    
    /// Audio buffer for processing
    private var audioBuffer: [Float] = []
    private let bufferSize = 512
    
    init() {
        Logger.audioRecorder.infoDev("🎤 HALMicrophoneSourceV2 initialized (true HAL-only)")
    }
    
    /// Start recording with direct HAL AudioUnit - no AVAudioEngine involvement
    func start(using deviceID: AudioDeviceID, 
               recordingHandler: @escaping (UnsafePointer<Float>, Int) -> Void,
               levelHandler: @escaping (Float) -> Void) throws {
        guard !isRunning else {
            Logger.audioRecorder.infoDev("⚠️ HAL source already running")
            return
        }
        
        Logger.audioRecorder.infoDev("🚀 Starting true HAL AudioUnit with device ID: \(deviceID)")
        currentDeviceID = deviceID
        currentDeviceName = getDeviceName(deviceID) ?? "Unknown Device"
        
        self.recordingHandler = recordingHandler
        self.levelHandler = levelHandler
        
        // Create and configure pure HAL AudioUnit
        try createHALAudioUnit(deviceID: deviceID)
        
        // Start the AudioUnit
        AudioUnitInitialize(audioUnit!)
        
        let startResult = AudioOutputUnitStart(audioUnit!)
        guard startResult == noErr else {
            throw HALError.startFailed(startResult)
        }
        
        isRunning = true
        Logger.audioRecorder.infoDev("✅ True HAL AudioUnit started with \(currentDeviceName)")
    }
    
    /// Stop the HAL AudioUnit
    func stop() {
        guard isRunning else { return }
        
        Logger.audioRecorder.infoDev("🛑 Stopping true HAL AudioUnit...")
        
        if let audioUnit = audioUnit {
            AudioOutputUnitStop(audioUnit)
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }
        
        audioUnit = nil
        isRunning = false
        currentDeviceID = 0
        currentDeviceName = ""
        recordingHandler = nil
        levelHandler = nil
        
        Logger.audioRecorder.infoDev("✅ True HAL AudioUnit stopped and cleaned up")
    }
    
    /// Check if the source is currently running
    var running: Bool {
        return isRunning
    }
    
    /// Get information about currently bound device
    var deviceInfo: (id: AudioDeviceID, name: String) {
        return (currentDeviceID, currentDeviceName)
    }
}

// MARK: - Private Implementation

private extension HALMicrophoneSourceV2 {
    
    /// Create pure HAL AudioUnit for input capture - no AVAudioEngine
    func createHALAudioUnit(deviceID: AudioDeviceID) throws {
        Logger.audioRecorder.infoDev("🔧 Creating pure HAL AudioUnit (no AVAudioEngine)...")
        
        // 1. Create AudioComponent description for HAL Output
        var componentDescription = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        // 2. Find and instantiate the component
        guard let component = AudioComponentFindNext(nil, &componentDescription) else {
            throw HALError.componentNotFound
        }
        
        var unit: AudioUnit?
        let status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let audioUnit = unit else {
            throw HALError.instantiationFailed(status)
        }
        
        self.audioUnit = audioUnit
        
        // 3. Enable input (scope 1), disable output (scope 0)
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
            throw HALError.configurationFailed("Failed to enable input", result)
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
            throw HALError.configurationFailed("Failed to disable output", result)
        }
        
        // 4. CRITICAL: Bind to specific device BEFORE any other operations
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
            throw HALError.configurationFailed("Failed to bind to device \(deviceID)", result)
        }
        
        // 5. Set up audio format (16kHz mono)
        var streamFormat = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        result = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1, // Input bus output
            &streamFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )
        
        guard result == noErr else {
            throw HALError.configurationFailed("Failed to set stream format", result)
        }
        
        // 6. Set up input callback for audio data
        var inputCallbackStruct = AURenderCallbackStruct(
            inputProc: audioInputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        
        result = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &inputCallbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )
        
        guard result == noErr else {
            throw HALError.configurationFailed("Failed to set input callback", result)
        }
        
        Logger.audioRecorder.infoDev("✅ Pure HAL AudioUnit configured and bound to \(currentDeviceName)")
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
    
    /// Process audio input data from HAL AudioUnit
    func processAudioInput(_ audioBuffer: UnsafePointer<Float>, frameCount: Int) {
        // Call recording handler
        recordingHandler?(audioBuffer, frameCount)
        
        // Calculate and report audio level
        let level = calculateAudioLevel(channelData: audioBuffer, frameCount: frameCount)
        levelHandler?(level)
    }
    
    /// Calculate normalized audio level from buffer data
    func calculateAudioLevel(channelData: UnsafePointer<Float>, frameCount: Int) -> Float {
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
}

// MARK: - Audio Callback

/// C callback function for audio input
private func audioInputCallback(
    inRefCon: UnsafeMutableRawPointer,
    ioActionFlags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    inTimeStamp: UnsafePointer<AudioTimeStamp>,
    inBusNumber: UInt32,
    inNumberFrames: UInt32,
    ioData: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    
    let source = Unmanaged<HALMicrophoneSourceV2>.fromOpaque(inRefCon).takeUnretainedValue()
    
    // Allocate buffer for audio data
    var bufferList = AudioBufferList(
        mNumberBuffers: 1,
        mBuffers: AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: inNumberFrames * 4, // 4 bytes per float
            mData: nil
        )
    )
    
    // Get audio data from the AudioUnit
    let status = AudioUnitRender(
        source.audioUnit!,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        &bufferList
    )
    
    guard status == noErr else {
        Logger.audioRecorder.error("❌ AudioUnitRender failed: \(status)")
        return status
    }
    
    // Process the audio data
    if let audioData = bufferList.mBuffers.mData {
        let floatPointer = audioData.bindMemory(to: Float.self, capacity: Int(inNumberFrames))
        source.processAudioInput(floatPointer, frameCount: Int(inNumberFrames))
    }
    
    return noErr
}

// MARK: - Error Types

enum HALError: Error, LocalizedError {
    case componentNotFound
    case instantiationFailed(OSStatus)
    case configurationFailed(String, OSStatus)
    case startFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .componentNotFound:
            return "HAL Output AudioUnit component not found"
        case .instantiationFailed(let status):
            return "Failed to instantiate AudioUnit (status: \(status))"
        case .configurationFailed(let message, let status):
            return "\(message) (status: \(status))"
        case .startFailed(let status):
            return "Failed to start AudioUnit (status: \(status))"
        }
    }
}