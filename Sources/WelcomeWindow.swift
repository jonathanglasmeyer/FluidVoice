import AppKit
import SwiftUI

class WelcomeWindow {
    static func showWelcomeDialog(initialStep: SetupStep = .welcome) {
        // Show the new SwiftUI welcome window
        let welcomeView = WelcomeView(initialStep: initialStep)
        let hostingController = NSHostingController(rootView: welcomeView)
        
        // Get the active screen dimensions for proper centering
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
        let screenFrame = activeScreen?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let windowWidth: CGFloat = 600
        let windowHeight: CGFloat = 650
        
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: windowWidth,
                height: windowHeight
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "Welcome to FluidVoice"
        window.isReleasedWhenClosed = false

        // Center the window on the active screen
        if let screen = activeScreen {
            let centerX = screen.frame.origin.x + (screen.frame.width - windowWidth) / 2
            let centerY = screen.frame.origin.y + (screen.frame.height - windowHeight) / 2
            window.setFrame(NSRect(x: centerX, y: centerY, width: windowWidth, height: windowHeight), display: true)
        } else {
            window.center()
        }
        
        // Add window delegate to handle close button properly
        let delegate = WelcomeWindowDelegate()
        window.delegate = delegate
        
        // Ensure proper focus and activation
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // Force focus after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKey()
        }

        // Keep window reference to prevent deallocation
        objc_setAssociatedObject(NSApp, "welcomeWindow", window, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(NSApp, "welcomeDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    }
}

class WelcomeWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Clean up associated objects when window closes
        objc_setAssociatedObject(NSApp, "welcomeWindow", nil, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(NSApp, "welcomeDelegate", nil, .OBJC_ASSOCIATION_RETAIN)
    }
}