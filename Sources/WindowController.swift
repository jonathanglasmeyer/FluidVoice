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
    
    // Thread-safe static property to share target app with other components
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
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 650),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = LocalizedStrings.Settings.title
            // Use normal window level so it doesn't float above other apps
            window.level = .normal

            // Configure window for glass effect
            window.isOpaque = false
            window.backgroundColor = NSColor.clear
            window.hasShadow = true

            // Ensure window doesn't cause app to quit when closed
            window.isReleasedWhenClosed = false
            
            // Setup glass effect background
            guard let content = window.contentView else { return }

            // Add NSVisualEffectView for glass effect - only for sidebar area (left 250px)
            let sidebarWidth: CGFloat = 250
            let effectView = NSVisualEffectView(frame: NSRect(
                x: 0,
                y: 0,
                width: sidebarWidth,
                height: content.bounds.height
            ))
            effectView.autoresizingMask = [.height]  // Only resize height, keep width fixed
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.isEmphasized = false
            effectView.material = .sidebar  // Use sidebar material for settings
            content.addSubview(effectView, positioned: .below, relativeTo: nil)

            // Restore SettingsView for Parakeet-only architecture
            let settingsView = SettingsView()
                .frame(width: 700, height: 650)
                .modelContainer(DataManager.shared.sharedModelContainer ?? createFallbackModelContainer())

            let hostingView = NSHostingView(rootView: settingsView)
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            // Make hosting view transparent to allow glass effect through
            if let layer = hostingView.layer {
                layer.backgroundColor = NSColor.clear.cgColor
            }

            content.addSubview(hostingView)

            // Layout constraints for hosting view
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: content.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])

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
