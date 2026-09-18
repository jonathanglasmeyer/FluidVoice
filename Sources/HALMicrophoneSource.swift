import Foundation
import AVFoundation
import AudioUnit
import CoreAudio
import os.log

/// True HAL AudioUnit direct input that completely bypasses AVAudioEngine.inputNode
/// and system default device behavior - no Bluetooth HFP activation
final class HALMicrophoneSource {
    fileprivate var audioUnit: AudioUnit?
    private var isRunning = false
    private var isPrewarmed = false
    
    /// Audio format for processing (detected from device)
    private var sampleRate: Double = 48000  // Default, will be detected
    private let channels: UInt32 = 1
    private var nativeSampleRate: Double = 48000
    
    /// Current device information
    private var currentDeviceID: AudioDeviceID = 0
    private var currentDeviceName: String = ""
    private var prewarmDeviceID: AudioDeviceID = 0
    
    /// Recording callbacks (pre-allocated during prewarming)
    private var recordingHandler: ((UnsafePointer<Float>, Int) -> Void)?
    private var levelHandler: ((Float) -> Void)?
    private var activeRecordingHandler: ((UnsafePointer<Float>, Int) -> Void)?
    private var activeLevelHandler: ((Float) -> Void)?
    
    /// Audio buffer for processing
    private var audioBuffer: [Float] = []
    private let bufferSize = 512

    /// Render health of the current/last run. Written on the render thread while running,
    /// read only after AudioOutputUnitStop (which is synchronous), so no lock needed.
    fileprivate var renderErrorCount = 0
    fileprivate var lastRenderError: OSStatus = noErr
    fileprivate var capturedFrames = 0

    /// Set when the pre-warmed AudioUnit may be stale (wake, device list change) while recording
    private var invalidatePending = false

    init() {
        Logger.audioRecorder.infoDev("🎤 HALMicrophoneSource initialized (direct HAL AudioUnit)")
    }
    
    /// Pre-create and pre-configure HAL AudioUnit for instant recording start
    func prewarm(using deviceID: AudioDeviceID,
                recordingHandler: @escaping (UnsafePointer<Float>, Int) -> Void,
                levelHandler: @escaping (Float) -> Void) async {
        guard !isPrewarmed else {
            Logger.audioRecorder.infoDev("✅ HAL AudioUnit already pre-warmed")
            return
        }
        
        Logger.audioRecorder.infoDev("🔧 Pre-warming HAL AudioUnit with device ID: \(deviceID)...")
        prewarmDeviceID = deviceID
        
        // Pre-set the callback handlers to avoid allocation during start
        self.recordingHandler = recordingHandler
        self.levelHandler = levelHandler
        
        do {
            // Detect device native sample rate first
            nativeSampleRate = detectNativeSampleRate(deviceID: deviceID)
            sampleRate = nativeSampleRate
            Logger.audioRecorder.infoDev("🔍 Detected native sample rate: \(nativeSampleRate)Hz for device \(deviceID)")
            guard nativeSampleRate > 0 else {
                throw HALError.invalidSampleRate(deviceID)
            }

            // Create and configure HAL AudioUnit with native sample rate
            try createHALAudioUnit(deviceID: deviceID)
            guard let audioUnit = audioUnit else {
                throw HALError.componentNotFound
            }

            // Initialize the AudioUnit for prewarming (but don't start it)
            let initResult = AudioUnitInitialize(audioUnit)
            guard initResult == noErr else {
                throw HALError.initializationFailed(initResult)
            }
            
            isPrewarmed = true
            Logger.audioRecorder.infoDev("🚀 HAL AudioUnit pre-warmed and initialized successfully with \(getDeviceName(deviceID) ?? "Unknown Device") at \(nativeSampleRate)Hz")
        } catch {
            Logger.audioRecorder.errorDev("⚠️ HAL AudioUnit pre-warming failed: \(error.localizedDescription)")
        }
    }
    
    /// Start recording with direct HAL AudioUnit - optimized for speed
    func start(using deviceID: AudioDeviceID, 
               recordingHandler: @escaping (UnsafePointer<Float>, Int) -> Void,
               levelHandler: @escaping (Float) -> Void) throws {
        guard !isRunning else {
            Logger.audioRecorder.infoDev("⚠️ HAL source already running")
            return
        }
        
        currentDeviceID = deviceID
        currentDeviceName = getDeviceName(deviceID) ?? "Unknown Device"

        // AUHAL does no sample rate conversion on the input side: a client format that doesn't
        // match the device's nominal rate makes every AudioUnitRender fail with -10863 (silence).
        // The rate can change under a pre-warmed unit (other apps, wake, device switch).
        let deviceRate = detectNativeSampleRate(deviceID: deviceID)
        guard deviceRate > 0 else {
            throw HALError.invalidSampleRate(deviceID)
        }

        let canReusePrewarmed = isPrewarmed && audioUnit != nil && prewarmDeviceID == deviceID
            && deviceRate == nativeSampleRate && renderErrorCount == 0
        if isPrewarmed && !canReusePrewarmed {
            Logger.audioRecorder.infoDev("🔄 Rebuilding HAL AudioUnit (device \(prewarmDeviceID)→\(deviceID), rate \(nativeSampleRate)→\(deviceRate)Hz, prior render errors: \(renderErrorCount))")
        }

        renderErrorCount = 0
        lastRenderError = noErr
        capturedFrames = 0

        if canReusePrewarmed, let audioUnit = audioUnit {
            // OPTIMIZED PATH: Just activate the pre-configured AudioUnit
            Logger.audioRecorder.infoDev("🚀 Starting pre-warmed HAL AudioUnit with device ID: \(deviceID)")
            
            // Set active handlers (these should match pre-warmed ones)
            activeRecordingHandler = recordingHandler
            activeLevelHandler = levelHandler
            
            // Ultra-fast start: just start the AudioUnit
            let startResult = AudioOutputUnitStart(audioUnit)
            guard startResult == noErr else {
                throw HALError.startFailed(startResult)
            }
            
            isRunning = true
            Logger.audioRecorder.infoDev("✅ Pre-warmed HAL AudioUnit started with \(currentDeviceName)")
        } else {
            // FALLBACK PATH: create new AudioUnit (device changed or not pre-warmed)
            Logger.audioRecorder.infoDev("🚀 Creating new HAL AudioUnit with device ID: \(deviceID) (not pre-warmed or device changed)")
            
            // Clean up any existing AudioUnit
            if audioUnit != nil {
                dispose()
            }
            
            // Set handlers for new AudioUnit
            self.recordingHandler = recordingHandler
            self.levelHandler = levelHandler
            activeRecordingHandler = recordingHandler
            activeLevelHandler = levelHandler
            
            // Create and configure new HAL AudioUnit at the device's current rate
            nativeSampleRate = deviceRate
            sampleRate = deviceRate
            try createHALAudioUnit(deviceID: deviceID)
            guard let newUnit = audioUnit else {
                throw HALError.componentNotFound
            }

            let initResult = AudioUnitInitialize(newUnit)
            guard initResult == noErr else {
                dispose()
                throw HALError.initializationFailed(initResult)
            }

            let startResult = AudioOutputUnitStart(newUnit)
            guard startResult == noErr else {
                dispose()
                throw HALError.startFailed(startResult)
            }
            
            isRunning = true
            
            // 🚀 OPTIMIZATION: Update pre-warm state for next recording
            isPrewarmed = true
            prewarmDeviceID = deviceID
            Logger.audioRecorder.infoDev("🔧 Updated pre-warm state to new device: \(currentDeviceName)")
            
            Logger.audioRecorder.infoDev("✅ New HAL AudioUnit started with \(currentDeviceName)")
        }
    }
    
    /// Stop the HAL AudioUnit (but keep it pre-warmed if possible)
    func stop() {
        guard isRunning else { return }
        
        Logger.audioRecorder.infoDev("🛑 Stopping HAL AudioUnit...")
        
        if let audioUnit = audioUnit {
            AudioOutputUnitStop(audioUnit)
            
            // Keep AudioUnit pre-warmed (don't uninitialize/dispose)
            if isPrewarmed {
                Logger.audioRecorder.infoDev("🔧 Keeping HAL AudioUnit pre-warmed for next recording")
            }
        }
        
        isRunning = false
        activeRecordingHandler = nil
        activeLevelHandler = nil

        if renderErrorCount > 0 {
            Logger.audioRecorder.errorDev("❌ \(renderErrorCount) AudioUnitRender failures this recording (last: \(lastRenderError)), captured frames: \(capturedFrames) - unit will be rebuilt on next start")
        }

        if invalidatePending {
            invalidatePending = false
            dispose()
            return
        }

        Logger.audioRecorder.infoDev("✅ HAL AudioUnit stopped (pre-warmed state preserved)")
    }

    /// Drop the pre-warmed AudioUnit so the next start rebuilds it against the current device state.
    /// Deferred until stop() if a recording is running.
    func invalidate(reason: String) {
        guard audioUnit != nil else { return }
        if isRunning {
            Logger.audioRecorder.infoDev("🔄 HAL AudioUnit invalidation deferred until stop (\(reason))")
            invalidatePending = true
        } else {
            Logger.audioRecorder.infoDev("🔄 Invalidating pre-warmed HAL AudioUnit (\(reason))")
            dispose()
        }
    }

    /// Frames delivered by the device during the last run (0 = no signal at all)
    var lastCapturedFrames: Int {
        return capturedFrames
    }
    
    /// Completely dispose of the HAL AudioUnit (called on deinit)
    func dispose() {
        Logger.audioRecorder.infoDev("🧹 Disposing HAL AudioUnit...")
        
        if let audioUnit = audioUnit {
            if isRunning {
                AudioOutputUnitStop(audioUnit)
            }
            AudioUnitUninitialize(audioUnit)
            AudioComponentInstanceDispose(audioUnit)
        }
        
        audioUnit = nil
        isRunning = false
        isPrewarmed = false
        currentDeviceID = 0
        currentDeviceName = ""
        prewarmDeviceID = 0
        recordingHandler = nil
        levelHandler = nil
        
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit disposed completely")
    }
    
    /// Check if the source is currently running
    var running: Bool {
        return isRunning
    }
    
    /// Get information about currently bound device
    var deviceInfo: (id: AudioDeviceID, name: String) {
        return (currentDeviceID, currentDeviceName)
    }
    
    /// Check if HAL AudioUnit is pre-warmed
    var prewarmed: Bool {
        return isPrewarmed
    }
    
    /// Get the native audio format being used
    var nativeAudioFormat: AVAudioFormat? {
        return AVAudioFormat(standardFormatWithSampleRate: nativeSampleRate, channels: channels)
    }
    
    deinit {
        dispose()
    }
}

// MARK: - Private Implementation

private extension HALMicrophoneSource {
    
    /// Create pure HAL AudioUnit for input capture - no AVAudioEngine
    func createHALAudioUnit(deviceID: AudioDeviceID) throws {
        Logger.audioRecorder.infoDev("🔧 Creating HAL AudioUnit for device \(deviceID)...")
        
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
        
        Logger.audioRecorder.infoDev("✅ HAL AudioUnit configured and bound to \(getDeviceName(deviceID) ?? "Unknown Device")")
    }
    
    /// Detect the native sample rate of an audio device
    func detectNativeSampleRate(deviceID: AudioDeviceID) -> Double {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var sampleRate: Float64 = 48000.0  // Default fallback
        var size = UInt32(MemoryLayout<Float64>.size)
        
        let result = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &sampleRate)
        
        if result == noErr {
            Logger.audioRecorder.infoDev("🎵 Device \(deviceID) native sample rate: \(sampleRate)Hz")
            return sampleRate
        } else {
            Logger.audioRecorder.infoDev("⚠️ Could not detect sample rate for device \(deviceID), using 48kHz default")
            return 48000.0
        }
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
        // Call active recording handler (optimized - no optional chaining)
        if let handler = activeRecordingHandler {
            handler(audioBuffer, frameCount)
        }
        
        // Calculate and report audio level (optimized - no optional chaining)
        if let handler = activeLevelHandler {
            let level = calculateAudioLevel(channelData: audioBuffer, frameCount: frameCount)
            handler(level)
        }
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
    
    let source = Unmanaged<HALMicrophoneSource>.fromOpaque(inRefCon).takeUnretainedValue()
    
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
        // Count instead of logging per callback (was hundreds of lines per recording); stop() reports
        source.renderErrorCount += 1
        source.lastRenderError = status
        return status
    }

    source.capturedFrames += Int(inNumberFrames)

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
    case initializationFailed(OSStatus)
    case startFailed(OSStatus)
    case invalidSampleRate(AudioDeviceID)

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
        case .startFailed(let status):
            return "Failed to start AudioUnit (status: \(status))"
        case .invalidSampleRate(let deviceID):
            return "Device \(deviceID) reports no valid sample rate (disconnected aggregate/sub-device?)"
        }
    }
}