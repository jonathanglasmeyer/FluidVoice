import Foundation
import AVFoundation
import CoreAudio
import OSLog

extension Logger {
    static let audioInspector = Logger(subsystem: "com.fluidvoice.app", category: "AudioInspector")
}

class AudioDeviceInspector {
    static func logSystemAudioDevices() {
        Logger.audioInspector.infoDev("🔍 === AUDIO DEVICE INSPECTION ===")
        
        // Log default input device
        logDefaultInputDevice()
        
        // Log all available input devices
        logAllInputDevices()
        
        Logger.audioInspector.infoDev("🔍 === END AUDIO DEVICE INSPECTION ===")
    }
    
    private static func logDefaultInputDevice() {
        var deviceID: AudioDeviceID = 0
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
            &deviceID
        )
        
        if status == noErr {
            if let deviceName = getDeviceName(deviceID: deviceID) {
                Logger.audioInspector.infoDev("🎤 SYSTEM DEFAULT INPUT: '\(deviceName)' (ID: \(deviceID))")
            } else {
                Logger.audioInspector.infoDev("⚠️ SYSTEM DEFAULT INPUT: ID \(deviceID) but no name found")
            }
        } else {
            Logger.audioInspector.infoDev("❌ Failed to get default input device: \(status)")
        }
    }
    
    private static func logAllInputDevices() {
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
        
        guard status == noErr else {
            Logger.audioInspector.infoDev("❌ Failed to get device list size: \(status)")
            return
        }
        
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
        
        guard status == noErr else {
            Logger.audioInspector.infoDev("❌ Failed to get device list: \(status)")
            return
        }
        
        Logger.audioInspector.infoDev("🔍 Found \(deviceCount) total audio devices")
        
        var inputDeviceCount = 0
        for deviceID in devices {
            if hasInputChannels(deviceID: deviceID) {
                inputDeviceCount += 1
                if let deviceName = getDeviceName(deviceID: deviceID) {
                    let hasVolume = hasVolumeControl(deviceID: deviceID)
                    Logger.audioInspector.infoDev("📥 INPUT DEVICE: '\(deviceName)' (ID: \(deviceID)) [Volume: \(hasVolume ? "YES" : "NO")]")
                } else {
                    Logger.audioInspector.infoDev("📥 INPUT DEVICE: ID \(deviceID) [No name available]")
                }
            }
        }
        
        Logger.audioInspector.infoDev("🔍 Found \(inputDeviceCount) input devices total")
    }
    
    private static func getDeviceName(deviceID: AudioDeviceID) -> String? {
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
    
    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
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
        
        let buffers = UnsafeBufferPointer<AudioBuffer>(
            start: &bufferList.pointee.mBuffers,
            count: Int(bufferList.pointee.mNumberBuffers)
        )
        
        return buffers.contains { $0.mNumberChannels > 0 }
    }
    
    private static func hasVolumeControl(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        return AudioObjectHasProperty(deviceID, &address)
    }
}