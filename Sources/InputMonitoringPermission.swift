import Foundation
import AppKit

class InputMonitoringPermission {
    
    static func checkPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let trusted = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false
            ] as CFDictionary)
            return trusted
        } else {
            return true
        }
    }
    
    static func requestPermission() -> Bool {
        if #available(macOS 10.15, *) {
            let trusted = AXIsProcessTrustedWithOptions([
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary)
            return trusted
        } else {
            return true
        }
    }
    
    static func openSystemPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }
}