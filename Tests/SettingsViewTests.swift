import XCTest
import SwiftUI
import AVFoundation
import ServiceManagement
@testable import FluidVoice

class SettingsViewTests: XCTestCase {
    // Isolated per test: parallel test processes share UserDefaults.standard and race on these keys
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsViewTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // Clear UserDefaults for testing
        defaults.removeObject(forKey: "selectedMicrophone")
        defaults.removeObject(forKey: "globalHotkey")
        defaults.removeObject(forKey: "startAtLogin")
        defaults.removeObject(forKey: "immediateRecording")
        defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        defaults.removeObject(forKey: "transcriptionRetentionPeriod")
    }
    
    override func tearDown() {
        // Clean up UserDefaults
        defaults.removeObject(forKey: "selectedMicrophone")
        defaults.removeObject(forKey: "globalHotkey")
        defaults.removeObject(forKey: "startAtLogin")
        defaults.removeObject(forKey: "immediateRecording")
        defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        defaults.removeObject(forKey: "transcriptionRetentionPeriod")
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        
        super.tearDown()
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultSettings() {
        // Test that default values are set correctly
        XCTAssertEqual(defaults.string(forKey: "selectedMicrophone") ?? "", "")
        XCTAssertEqual(defaults.string(forKey: "globalHotkey") ?? "Right Option", "Right Option")
        XCTAssertEqual(defaults.bool(forKey: "startAtLogin"), false) // Default is false when not set
        XCTAssertEqual(defaults.bool(forKey: "immediateRecording"), false) // Default is Manual Start & Stop mode
    }
    
    func testSettingsInitialization() {
        // Set some values
        defaults.set("test-microphone", forKey: "selectedMicrophone")
        defaults.set("⌘⇧R", forKey: "globalHotkey")
        defaults.set(true, forKey: "startAtLogin")
        defaults.set(true, forKey: "immediateRecording") // Enable Hotkey Start & Stop mode
        
        // Values should persist
        XCTAssertEqual(defaults.string(forKey: "selectedMicrophone"), "test-microphone")
        XCTAssertEqual(defaults.string(forKey: "globalHotkey"), "⌘⇧R")
        XCTAssertEqual(defaults.bool(forKey: "startAtLogin"), true)
        XCTAssertEqual(defaults.bool(forKey: "immediateRecording"), true)
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
        
        defaults.set(testMicrophoneID, forKey: "selectedMicrophone")
        
        let selectedMicrophone = defaults.string(forKey: "selectedMicrophone")
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
        let defaultHotkey = defaults.string(forKey: "globalHotkey") ?? "Right Option"
        XCTAssertEqual(defaultHotkey, "Right Option")
    }
    
    func testGlobalHotkeyCustomization() {
        let customHotkey = "⌘⇧R"
        defaults.set(customHotkey, forKey: "globalHotkey")
        
        let retrievedHotkey = defaults.string(forKey: "globalHotkey")
        XCTAssertEqual(retrievedHotkey, customHotkey)
    }
    
    // MARK: - Start at Login Tests
    
    func testStartAtLoginDefault() {
        // Test default value
        let defaultStartAtLogin = defaults.bool(forKey: "startAtLogin")
        XCTAssertEqual(defaultStartAtLogin, false) // Default is false when not set
    }
    
    func testStartAtLoginPersistence() {
        // Enable start at login
        defaults.set(true, forKey: "startAtLogin")
        XCTAssertTrue(defaults.bool(forKey: "startAtLogin"))
        
        // Disable start at login
        defaults.set(false, forKey: "startAtLogin")
        XCTAssertFalse(defaults.bool(forKey: "startAtLogin"))
    }
    
    func testHotkeyStartStopModeDefault() {
        // Test default value (should be false - Manual Start & Stop mode)
        let defaultHotkeyMode = defaults.bool(forKey: "immediateRecording")
        XCTAssertEqual(defaultHotkeyMode, false) // Default is false when not set
    }
    
    func testHotkeyStartStopModePersistence() {
        // Enable Hotkey Start & Stop mode
        defaults.set(true, forKey: "immediateRecording")
        XCTAssertTrue(defaults.bool(forKey: "immediateRecording"))
        
        // Disable Hotkey Start & Stop mode (back to Manual mode)
        defaults.set(false, forKey: "immediateRecording")
        XCTAssertFalse(defaults.bool(forKey: "immediateRecording"))
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
        XCTAssertFalse(defaults.bool(forKey: "transcriptionHistoryEnabled"))
        XCTAssertEqual(
            defaults.string(forKey: "transcriptionRetentionPeriod") ?? RetentionPeriod.oneMonth.rawValue,
            RetentionPeriod.oneMonth.rawValue
        )
    }
    
    func testHistoryTogglePersistence() {
        // Enable history
        defaults.set(true, forKey: "transcriptionHistoryEnabled")
        XCTAssertTrue(defaults.bool(forKey: "transcriptionHistoryEnabled"))
        
        // Disable history
        defaults.set(false, forKey: "transcriptionHistoryEnabled")
        XCTAssertFalse(defaults.bool(forKey: "transcriptionHistoryEnabled"))
    }
    
    func testRetentionPeriodPersistence() {
        // Test each retention period option
        for period in RetentionPeriod.allCases {
            defaults.set(period.rawValue, forKey: "transcriptionRetentionPeriod")
            let savedPeriod = defaults.string(forKey: "transcriptionRetentionPeriod")
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
            defaults.removeObject(forKey: key)
        }
    }
}

