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
        
        if let cachedDeviceID = selectedDeviceID {
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
            let blacklistedNames = ["Background Music", "Soundflower", "Loopback", "SoundSource"]
            if blacklistedNames.contains(where: { systemDefaultName.contains($0) }) {
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
                let blacklistedNames = ["Background Music", "Soundflower", "Loopback", "SoundSource"]
                if blacklistedNames.contains(where: { deviceName.contains($0) }) {
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
    
    private func isValidInputDevice(deviceID: AudioDeviceID) -> Bool {
        return hasInputChannels(deviceID: deviceID)
    }
    
    func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var cfString: CFString?
        var size = UInt32(MemoryLayout<CFString>.size)
        
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &cfString
        )
        
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