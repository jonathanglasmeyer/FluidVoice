import SwiftUI
import AppKit
import os.log

/// Simple circular recording indicator that appears at screen bottom center
/// Shows volume-responsive scaling animation during Express Mode recording
class MiniRecordingIndicator: NSObject, ObservableObject {
    private var window: NSWindow?
    @Published var isVisible: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private static let baseSize: CGFloat = 25
    private static let maxScaleMultiplier: CGFloat = 1.8
    private static let windowPadding: CGFloat = 60 // Distance from bottom of screen
    
    override init() {
        super.init()
    }
    
    /// Show the indicator with fade-in animation
    func show() {
        guard !isVisible else { return }
        
        Logger.miniIndicator.infoDev("🎯 Showing mini recording indicator")
        
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow()
            self?.isVisible = true
        }
    }
    
    /// Hide the indicator with fade-out animation
    func hide() {
        guard isVisible else { return }
        
        Logger.miniIndicator.infoDev("🎯 Hiding mini recording indicator")
        
        DispatchQueue.main.async { [weak self] in
            self?.hideWindow()
            self?.isVisible = false
        }
    }
    
    /// Update the volume level for real-time scaling
    func updateAudioLevel(_ level: Float) {
        // Direct update - already on main queue from AudioRecorder
        self.audioLevel = level
    }
    
    private func createAndShowWindow() {
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        
        // Position at bottom center of screen
        let windowSize = NSSize(width: Self.baseSize * Self.maxScaleMultiplier + 20, 
                               height: Self.baseSize * Self.maxScaleMultiplier + 20)
        let windowX = screenFrame.midX - windowSize.width / 2
        let windowY = screenFrame.minY + Self.windowPadding
        let windowFrame = NSRect(x: windowX, y: windowY, width: windowSize.width, height: windowSize.height)
        
        window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        // Configure window behavior
        window?.level = NSWindow.Level.floating
        window?.isOpaque = false
        window?.backgroundColor = NSColor.clear
        window?.hasShadow = false
        window?.ignoresMouseEvents = true
        window?.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        // Create SwiftUI content
        let contentView = MiniIndicatorView(indicator: self)
        window?.contentView = NSHostingView(rootView: contentView)
        
        // Fade in animation
        window?.alphaValue = 0.0
        window?.orderFront(nil)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1.0
        }
        
        Logger.miniIndicator.infoDev("✅ Mini indicator window created at position: \(windowFrame)")
    }
    
    private func hideWindow() {
        guard let window = window else { return }
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
            self.window = nil
        })
    }
    
    deinit {
        window?.orderOut(nil)
        window = nil
    }
}

/// SwiftUI view for the circular volume indicator
struct MiniIndicatorView: View {
    @ObservedObject var indicator: MiniRecordingIndicator
    
    private let baseSize: CGFloat = 25
    private let maxScaleMultiplier: CGFloat = 1.8
    
    var body: some View {
        ZStack {
            // Transparent background
            Color.clear
            
            // Main indicator circle
            Circle()
                .fill(Color.black)
                .frame(width: baseSize, height: baseSize)
                .scaleEffect(calculateScale())
                .opacity(0.8)
                .animation(.easeOut(duration: 0.1), value: indicator.audioLevel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func calculateScale() -> CGFloat {
        let normalizedLevel = max(0.0, min(1.0, CGFloat(indicator.audioLevel)))
        return 1.0 + (normalizedLevel * (maxScaleMultiplier - 1.0))
    }
}

// MARK: - Logger Extension
extension Logger {
    static let miniIndicator = Logger(subsystem: "com.fluidvoice.app", category: "MiniRecordingIndicator")
}