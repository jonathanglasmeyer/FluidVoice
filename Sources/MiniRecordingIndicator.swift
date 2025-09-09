import SwiftUI
import AppKit
import os.log

/// Simple circular recording indicator that appears at screen bottom center
/// Shows volume-responsive scaling animation during Express Mode recording
class MiniRecordingIndicator: NSObject, ObservableObject {
    private var window: NSWindow?
    @Published var isVisible: Bool = false
    @Published var audioLevel: Float = 0.0
    
    private static let containerWidth: CGFloat = 200
    private static let containerHeight: CGFloat = 100
    private static let windowPadding: CGFloat = 80 // Distance from bottom of screen
    
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
        
        // Position at bottom center of screen - window exactly matches container size
        let windowSize = NSSize(width: Self.containerWidth, 
                               height: Self.containerHeight)
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
        window?.hasShadow = false  // We'll draw our own round shadow
        window?.ignoresMouseEvents = true
        window?.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        // Container with roundness + shadow (layer-based) - NOT the effect view
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        // Round, soft shadow
        container.layer?.shadowOpacity = 0.35
        container.layer?.shadowRadius = 18
        container.layer?.shadowOffset = CGSize(width: 0, height: -2)
        container.layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: windowSize),
                                            cornerWidth: 16, cornerHeight: 16, transform: nil)
        
        window?.contentView = container
        
        // NSVisualEffectView WITHOUT any layer properties - fills container
        let effectView = NSVisualEffectView(frame: container.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .popover  // Good balance of clarity and blur
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        // CRITICAL: No wantsLayer, no cornerRadius/masksToBounds on effectView!
        container.addSubview(effectView)
        
        // SwiftUI content on top (without background)
        let contentView = MiniIndicatorView(indicator: self)
            .padding(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
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

/// SwiftUI view for the glassmorphism waveform indicator  
struct MiniIndicatorView: View {
    @ObservedObject var indicator: MiniRecordingIndicator
    
    private let barCount = 5
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 4
    private let maxBarHeight: CGFloat = 30
    private let minBarHeight: CGFloat = 6
    
    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth/2)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.9), Color.white.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: barWidth, height: calculateBarHeight(for: index))
            }
        }
    }
    
    private func calculateBarHeight(for index: Int) -> CGFloat {
        // Static pattern for now - no animation
        let pattern: [CGFloat] = [0.6, 0.8, 1.0, 0.8, 0.6]
        let multiplier = pattern[index]
        return minBarHeight + (maxBarHeight - minBarHeight) * multiplier
    }
}

// MARK: - Logger Extension
extension Logger {
    static let miniIndicator = Logger(subsystem: "com.fluidvoice.app", category: "MiniRecordingIndicator")
}