import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import os.log

extension Logger {
    static let audioDeviceManager = Logger(subsystem: "com.fluidvoice.app", category: "AudioDeviceManager")
}

class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()
    
    private var selectedDeviceID: AudioDeviceID?
    private var deviceSelectionLock = NSLock()
    
    private init() {}
    
    /// Get the intelligently selected input device ID
    func getSelectedInputDevice() throws -> AudioDeviceID {
        deviceSelectionLock.lock()
        defer { deviceSelectionLock.unlock() }
        
        // 🚀 ALWAYS evaluate the priority list first (hot-plug support)
        let priority = MicrophonePriority.load()

        if !priority.isEmpty {
            if let entry = MicrophonePriority.firstAvailable(in: priority, isAvailable: { usableDeviceID(forUID: $0) != nil }),
               let preferredDeviceID = usableDeviceID(forUID: entry.uid) {
                if preferredDeviceID != selectedDeviceID {
                    Logger.audioDeviceManager.infoDev("🎯 Priority microphone: '\(entry.name)' (ID: \(preferredDeviceID), rank \((priority.firstIndex(of: entry) ?? 0) + 1)/\(priority.count))")
                    selectedDeviceID = preferredDeviceID
                }
                return preferredDeviceID
            }
            // Nothing from the list available: fall back to the built-in mic
            Logger.audioDeviceManager.infoDev("⚠️ No microphone from priority list available, falling back")
            if let builtInID = findBuiltInInputDevice() {
                Logger.audioDeviceManager.infoDev("🎤 Fallback to built-in input: \(getDeviceName(deviceID: builtInID) ?? "Unknown") (ID: \(builtInID))")
                selectedDeviceID = builtInID
                return builtInID
            }
            selectedDeviceID = nil
        }
        // No user preference OR preference unavailable, select best available
        else if let cachedDeviceID = selectedDeviceID {
            if isValidInputDevice(deviceID: cachedDeviceID) {
                Logger.audioDeviceManager.infoDev("🎤 Using cached input device: \(self.getDeviceName(deviceID: cachedDeviceID) ?? "Unknown") (ID: \(cachedDeviceID))")
                return cachedDeviceID
            } else {
                Logger.audioDeviceManager.infoDev("⚠️ Cached device no longer valid, reselecting...")
                selectedDeviceID = nil
            }
        }
        
        let deviceID = try selectBestInputDevice()
        selectedDeviceID = deviceID
        return deviceID
    }
    
    /// Force reselection of input device
    func refreshDeviceSelection() throws -> AudioDeviceID {
        deviceSelectionLock.lock()
        selectedDeviceID = nil
        deviceSelectionLock.unlock()
        return try getSelectedInputDevice()
    }
    
    /// Get all available audio devices for UI display
    func getAllAvailableDevices() -> [AVCaptureDevice] {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        Logger.audioDeviceManager.infoDev("🔄 Refreshed audio device list: found \(discoverySession.devices.count) devices")
        return discoverySession.devices
    }
    
    private func selectBestInputDevice() throws -> AudioDeviceID {
        // This function is now only called as final fallback when user preference unavailable
        Logger.audioDeviceManager.infoDev("🔍 Selecting best available input device (fallback mode)")
        
        // Get system default device
        var systemDefaultID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &systemDefaultID
        )
        
        guard status == noErr else {
            throw AudioDeviceError.deviceNotFound
        }
        
        if let systemDefaultName = getDeviceName(deviceID: systemDefaultID) {
            Logger.audioDeviceManager.infoDev("🎤 System default input: '\(systemDefaultName)' (ID: \(systemDefaultID))")
            
            // Check if system default is blacklisted
            if Self.blacklistedNames.contains(where: { systemDefaultName.contains($0) }) || !isValidInputDevice(deviceID: systemDefaultID) {
                Logger.audioDeviceManager.infoDev("⚠️ System default '\(systemDefaultName)' is virtual/blacklisted - finding better device")
                
                if let betterDeviceID = findBetterInputDevice() {
                    let betterName = getDeviceName(deviceID: betterDeviceID) ?? "Unknown"
                    Logger.audioDeviceManager.infoDev("✅ Selected better input device: '\(betterName)' (ID: \(betterDeviceID))")
                    return betterDeviceID
                } else {
                    Logger.audioDeviceManager.infoDev("⚠️ No better device found, using system default: '\(systemDefaultName)'")
                }
            } else {
                Logger.audioDeviceManager.infoDev("✅ System default input device is suitable: '\(systemDefaultName)'")
            }
        }
        
        return systemDefaultID
    }
    
    private func findBetterInputDevice() -> AudioDeviceID? {
        // Get all audio devices
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        
        guard status == noErr else { return nil }
        
        let deviceCount = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
        
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        )
        
        guard status == noErr else { return nil }
        
        // Look for built-in or USB microphones, prioritizing built-in
        var builtInDevice: AudioDeviceID?
        var usbDevice: AudioDeviceID?
        
        for deviceID in devices {
            guard hasInputChannels(deviceID: deviceID) else { continue }
            
            if let deviceName = getDeviceName(deviceID: deviceID) {
                Logger.audioDeviceManager.infoDev("🔍 Evaluating input device: '\(deviceName)' (ID: \(deviceID))")
                
                // Skip blacklisted devices
                if Self.blacklistedNames.contains(where: { deviceName.contains($0) }) {
                    Logger.audioDeviceManager.infoDev("⚠️ Skipping blacklisted device: '\(deviceName)'")
                    continue
                }
                
                // Prioritize built-in microphones
                if deviceName.lowercased().contains("built-in") || 
                   deviceName.lowercased().contains("macbook") ||
                   deviceName.lowercased().contains("imac") {
                    Logger.audioDeviceManager.infoDev("✅ Found built-in device: '\(deviceName)'")
                    builtInDevice = deviceID
                }
                // Fallback to USB devices
                else if deviceName.lowercased().contains("usb") {
                    Logger.audioDeviceManager.infoDev("📱 Found USB device: '\(deviceName)'")
                    usbDevice = deviceID
                }
            }
        }
        
        return builtInDevice ?? usbDevice
    }
    
    /// CoreAudio device for a UID (== AVCaptureDevice.uniqueID), if present and able to record
    func usableDeviceID(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPtr,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown, isValidInputDevice(deviceID: deviceID) else {
            return nil
        }
        return deviceID
    }
    
    /// Loopback/virtual inputs that carry no microphone signal (not offered in the priority list)
    static func isVirtualDevice(name: String) -> Bool {
        return blacklistedNames.contains(where: { name.contains($0) })
    }
    
    /// Virtual/loopback devices: they have input channels but carry no microphone signal
    private static let blacklistedNames = ["Background Music", "Soundflower", "Loopback", "SoundSource", "BlackHole", "Microsoft Teams Audio", "ZoomAudioDevice"]
    
    private func isValidInputDevice(deviceID: AudioDeviceID) -> Bool {
        return hasInputChannels(deviceID: deviceID) && (nominalSampleRate(deviceID: deviceID) ?? 0) > 0
    }
    
    private func findBuiltInInputDevice() -> AudioDeviceID? {
        return allDeviceIDs().first { deviceID in
            transportType(deviceID: deviceID) == kAudioDeviceTransportTypeBuiltIn && isValidInputDevice(deviceID: deviceID)
        }
    }
    
    private func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }
    
    private func transportType(deviceID: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    
    /// 0 for aggregate devices whose sub-device is disconnected
    private func nominalSampleRate(deviceID: AudioDeviceID) -> Float64? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    
    func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var cfString: CFString?
        var size = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafeMutablePointer(to: &cfString) { cfStringPtr in
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                cfStringPtr
            )
        }
        
        if status == noErr, let cfString = cfString {
            return cfString as String
        }
        return nil
    }
    
    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &size
        )
        
        guard status == noErr, size > 0 else { return false }
        
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        
        let getStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            bufferList
        )
        
        guard getStatus == noErr else { return false }
        
        let buffers = withUnsafePointer(to: &bufferList.pointee.mBuffers) { buffersPointer in
            UnsafeBufferPointer<AudioBuffer>(
                start: buffersPointer,
                count: Int(bufferList.pointee.mNumberBuffers)
            )
        }
        
        return buffers.contains { $0.mNumberChannels > 0 }
    }
}

enum AudioDeviceError: LocalizedError {
    case deviceNotFound
    case deviceNotValid
    
    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Audio input device not found"
        case .deviceNotValid:
            return "Audio input device is not valid"
        }
    }
}