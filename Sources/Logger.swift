import Foundation
import os.log

// Use os.Logger directly - no shadowing/polyfilling
public typealias Logger = os.Logger

// MARK: - Dev-Only Extensions for Public Logging
extension Logger {
    @inlinable
    func infoDev(_ message: String) {
        #if DEBUG
        self.info("\(message, privacy: .public)")
        #else
        self.info("\(message, privacy: .private)")
        #endif
    }
    
    @inlinable
    func errorDev(_ message: String) {
        #if DEBUG
        self.error("\(message, privacy: .public)")
        #else
        self.error("\(message, privacy: .private)")
        #endif
    }
    
    @inlinable
    func warningDev(_ message: String) {
        #if DEBUG
        self.warning("\(message, privacy: .public)")
        #else
        self.warning("\(message, privacy: .private)")
        #endif
    }
    
    @inlinable
    func debugDev(_ message: String) {
        #if DEBUG
        self.debug("\(message, privacy: .public)")
        #else
        self.debug("\(message, privacy: .private)")
        #endif
    }
}

// Centralized logging for FluidVoice
extension Logger {
    private static var subsystem = "com.fluidvoice.app"
    
    static let modelManager = Logger(subsystem: subsystem, category: "ModelManager")
    static let audioRecorder = Logger(subsystem: subsystem, category: "AudioRecorder")
    static let microphoneVolume = Logger(subsystem: subsystem, category: "MicrophoneVolume")
    static let speechToText = Logger(subsystem: subsystem, category: "SpeechToText")
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    static let app = Logger(subsystem: subsystem, category: "App")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let dataManager = Logger(subsystem: subsystem, category: "DataManager")
}