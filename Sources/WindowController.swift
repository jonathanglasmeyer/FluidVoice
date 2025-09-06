import Foundation
import AppKit
import SwiftUI
import SwiftData

/// Manages window display and focus restoration for FluidVoice
/// 
/// This class handles showing/hiding the recording window and restoring focus
/// to the previous application. All window operations now support optional
/// completion handlers for better coordination and testing.
class WindowController {
    private var previousApp: NSRunningApplication?
    private let isTestEnvironment: Bool
    
    // Thread-safe static property to share target app with ContentView
    private static let storedTargetAppQueue = DispatchQueue(label: "com.fluidvoice.storedTargetApp", attributes: .concurrent)
    private static var _storedTargetApp: NSRunningApplication?
    
    static var storedTargetApp: NSRunningApplication? {
        get {
            return storedTargetAppQueue.sync {
                return _storedTargetApp
            }
        }
        set {
            storedTargetAppQueue.async(flags: .barrier) {
                _storedTargetApp = newValue
            }
        }
    }
    
    init() {
        isTestEnvironment = NSClassFromString("XCTestCase") != nil
    }
    
    
    /// Helper method to perform window operations with delays and completion handlers
    private func performWindowOperation(after delay: TimeInterval, operation: @escaping () -> Void) {
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: operation)
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
    
    
    func restoreFocusToPreviousApp(completion: (() -> Void)? = nil) {
        guard let prevApp = previousApp else {
            completion?()
            return
        }
        
        // Small delay to ensure window is hidden first
        performWindowOperation(after: 0.1) { [weak self] in
            prevApp.activate(options: [])
            self?.previousApp = nil
            completion?()
        }
    }
    
    private weak var settingsWindow: NSWindow?
    private var settingsWindowDelegate: SettingsWindowDelegate?
    
    @MainActor func openSettings() {
        // Skip actual window operations in test environment
        if isTestEnvironment {
            return
        }
        
        // No recording window to hide anymore
        
        // Check if settings window already exists
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            // Bring existing window to front and focus
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
        } else {
            // Create new settings window (SwiftUI Settings scene can have focus issues)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = LocalizedStrings.Settings.title
            // Use normal window level so it doesn't float above other apps
            window.level = .normal
            
            // Ensure window doesn't cause app to quit when closed
            window.isReleasedWhenClosed = false
            
            // Create SettingsView with proper ModelContainer
            let settingsView = SettingsView()
                .modelContainer(DataManager.shared.sharedModelContainer ?? createFallbackModelContainer())
            
            window.contentView = NSHostingView(rootView: settingsView)
            window.center()
            
            // Set up delegate to handle window lifecycle
            settingsWindowDelegate = SettingsWindowDelegate { [weak self] in
                self?.settingsWindow = nil
                self?.settingsWindowDelegate = nil
            }
            window.delegate = settingsWindowDelegate
            
            // Store weak reference
            settingsWindow = window
            
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    /// Creates a fallback container if DataManager initialization fails
    private func createFallbackModelContainer() -> ModelContainer {
        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create fallback ModelContainer: \(error)")
        }
    }
}

/// Window delegate that handles the settings window lifecycle
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
