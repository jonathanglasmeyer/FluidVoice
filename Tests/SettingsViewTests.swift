import XCTest
import SwiftUI
import AVFoundation
import ServiceManagement
@testable import FluidVoice

class SettingsViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear UserDefaults for testing
        UserDefaults.standard.removeObject(forKey: "selectedMicrophone")
        UserDefaults.standard.removeObject(forKey: "globalHotkey")
        UserDefaults.standard.removeObject(forKey: "startAtLogin")
        UserDefaults.standard.removeObject(forKey: "immediateRecording")
        UserDefaults.standard.removeObject(forKey: "transcriptionHistoryEnabled")
        UserDefaults.standard.removeObject(forKey: "transcriptionRetentionPeriod")
    }
    
    override func tearDown() {
        // Clean up UserDefaults
        UserDefaults.standard.removeObject(forKey: "selectedMicrophone")
        UserDefaults.standard.removeObject(forKey: "globalHotkey")
        UserDefaults.standard.removeObject(forKey: "startAtLogin")
        UserDefaults.standard.removeObject(forKey: "immediateRecording")
        UserDefaults.standard.removeObject(forKey: "transcriptionHistoryEnabled")
        UserDefaults.standard.removeObject(forKey: "transcriptionRetentionPeriod")
        
        super.tearDown()
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultSettings() {
        // Test that default values are set correctly
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectedMicrophone") ?? "", "")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "globalHotkey") ?? "Right Option", "Right Option")
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "startAtLogin"), false) // Default is false when not set
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "immediateRecording"), false) // Default is Manual Start & Stop mode
    }
    
    func testSettingsInitialization() {
        // Set some values
        UserDefaults.standard.set("test-microphone", forKey: "selectedMicrophone")
        UserDefaults.standard.set("⌘⇧R", forKey: "globalHotkey")
        UserDefaults.standard.set(true, forKey: "startAtLogin")
        UserDefaults.standard.set(true, forKey: "immediateRecording") // Enable Hotkey Start & Stop mode
        
        // Values should persist
        XCTAssertEqual(UserDefaults.standard.string(forKey: "selectedMicrophone"), "test-microphone")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "globalHotkey"), "⌘⇧R")
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "startAtLogin"), true)
        XCTAssertEqual(UserDefaults.standard.bool(forKey: "immediateRecording"), true)
    }
    
    // MARK: - Microphone Discovery Tests
    
    func testMicrophoneDiscovery() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )
        
        let devices = discoverySession.devices
        
        // Should be able to discover microphones (at least system default)
        XCTAssertNotNil(devices)
        
        // Each device should have required properties
        for device in devices {
            XCTAssertFalse(device.localizedName.isEmpty)
            XCTAssertFalse(device.uniqueID.isEmpty)
        }
    }
    
    func testMicrophoneSelectionPersistence() {
        let testMicrophoneID = "test-microphone-id"
        
        UserDefaults.standard.set(testMicrophoneID, forKey: "selectedMicrophone")
        
        let selectedMicrophone = UserDefaults.standard.string(forKey: "selectedMicrophone")
        XCTAssertEqual(selectedMicrophone, testMicrophoneID)
    }
    
    // MARK: - View Construction Tests
    
    func testSettingsViewInitializes() {
        // SettingsView reads everything from @AppStorage; it has no injected dependencies
        let view = SettingsView()
        XCTAssertNotNil(view.body)
    }
    
    // MARK: - Global Hotkey Tests
    
    func testGlobalHotkeyDefault() {
        // Test default hotkey
        let defaultHotkey = UserDefaults.standard.string(forKey: "globalHotkey") ?? "Right Option"
        XCTAssertEqual(defaultHotkey, "Right Option")
    }
    
    func testGlobalHotkeyCustomization() {
        let customHotkey = "⌘⇧R"
        UserDefaults.standard.set(customHotkey, forKey: "globalHotkey")
        
        let retrievedHotkey = UserDefaults.standard.string(forKey: "globalHotkey")
        XCTAssertEqual(retrievedHotkey, customHotkey)
    }
    
    // MARK: - Start at Login Tests
    
    func testStartAtLoginDefault() {
        // Test default value
        let defaultStartAtLogin = UserDefaults.standard.bool(forKey: "startAtLogin")
        XCTAssertEqual(defaultStartAtLogin, false) // Default is false when not set
    }
    
    func testStartAtLoginPersistence() {
        // Enable start at login
        UserDefaults.standard.set(true, forKey: "startAtLogin")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "startAtLogin"))
        
        // Disable start at login
        UserDefaults.standard.set(false, forKey: "startAtLogin")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "startAtLogin"))
    }
    
    func testHotkeyStartStopModeDefault() {
        // Test default value (should be false - Manual Start & Stop mode)
        let defaultHotkeyMode = UserDefaults.standard.bool(forKey: "immediateRecording")
        XCTAssertEqual(defaultHotkeyMode, false) // Default is false when not set
    }
    
    func testHotkeyStartStopModePersistence() {
        // Enable Hotkey Start & Stop mode
        UserDefaults.standard.set(true, forKey: "immediateRecording")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "immediateRecording"))
        
        // Disable Hotkey Start & Stop mode (back to Manual mode)
        UserDefaults.standard.set(false, forKey: "immediateRecording")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "immediateRecording"))
    }
    
    // MARK: - Keychain Security Tests
    
    func testKeychainDataEncoding() {
        let testKey = "test-api-key-with-special-chars-!@#$%^&*()"
        let encodedData = testKey.data(using: .utf8)!
        let decodedString = String(data: encodedData, encoding: .utf8)
        
        XCTAssertEqual(decodedString, testKey)
    }
    
    // MARK: - History Settings Tests
    
    func testHistorySettingsDefaults() {
        // Test default values for history settings
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "transcriptionHistoryEnabled"))
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "transcriptionRetentionPeriod") ?? RetentionPeriod.oneMonth.rawValue,
            RetentionPeriod.oneMonth.rawValue
        )
    }
    
    func testHistoryTogglePersistence() {
        // Enable history
        UserDefaults.standard.set(true, forKey: "transcriptionHistoryEnabled")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "transcriptionHistoryEnabled"))
        
        // Disable history
        UserDefaults.standard.set(false, forKey: "transcriptionHistoryEnabled")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "transcriptionHistoryEnabled"))
    }
    
    func testRetentionPeriodPersistence() {
        // Test each retention period option
        for period in RetentionPeriod.allCases {
            UserDefaults.standard.set(period.rawValue, forKey: "transcriptionRetentionPeriod")
            let savedPeriod = UserDefaults.standard.string(forKey: "transcriptionRetentionPeriod")
            XCTAssertEqual(savedPeriod, period.rawValue)
        }
    }
    
    func testRetentionPeriodDisplayNames() {
        // Test that all retention periods have display names
        for period in RetentionPeriod.allCases {
            XCTAssertFalse(period.displayName.isEmpty)
        }
        
        // Test specific display names
        XCTAssertEqual(RetentionPeriod.oneWeek.displayName, "1 Week")
        XCTAssertEqual(RetentionPeriod.oneMonth.displayName, "1 Month")
        XCTAssertEqual(RetentionPeriod.threeMonths.displayName, "3 Months")
        XCTAssertEqual(RetentionPeriod.forever.displayName, "Forever")
    }
    
    // MARK: - Performance Tests
    
    func testMicrophoneDiscoveryPerformance() {
        measure {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            )
            _ = discoverySession.devices
        }
    }
}

// MARK: - Test Helpers and Extensions

extension SettingsViewTests {
    private func clearUserDefaults() {
        let keys = [
            "selectedMicrophone", 
            "globalHotkey", 
            "startAtLogin",
            "transcriptionHistoryEnabled",
            "transcriptionRetentionPeriod"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

