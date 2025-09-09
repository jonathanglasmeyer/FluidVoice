import SwiftUI
import AppKit
import os.log

/// Simple circular recording indicator that appears at screen bottom center
/// Shows volume-responsive scaling animation during Express Mode recording
class MiniRecordingIndicator: NSObject, ObservableObject {
    private var window: NSWindow?
    private var frameObserverToken: Any?
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
        
        // Position at bottom center of screen - pixel-snapped for crisp rendering
        let windowSize = NSSize(width: Self.containerWidth, 
                               height: Self.containerHeight)
        let windowX = round(screenFrame.midX - windowSize.width / 2)
        let windowY = round(screenFrame.minY + Self.windowPadding)
        let windowFrame = NSRect(x: windowX, y: windowY, 
                                width: round(windowSize.width), height: round(windowSize.height))
        
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
        window?.hasShadow = true
        window?.ignoresMouseEvents = true
        window?.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        
        guard let content = window?.contentView else { return }
        
        // Helper function for creating rounded mask
        func makeMask(_ size: CGSize) -> NSImage {
            let img = NSImage(size: size)
            img.lockFocus()
            NSColor.white.setFill()
            NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 16, yRadius: 16).fill()
            img.unlockFocus()
            return img
        }
        
        // VEV directly in contentView - no clipping container above it
        let effectView = NSVisualEffectView(frame: content.bounds)
        effectView.autoresizingMask = [.width, .height]
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.isEmphasized = false
        // No appearance setting - inherits from window naturally
        effectView.material = .popover  // unified material for both Light and Dark
        
        // Rounded corners via maskImage - no masksToBounds in parents
        effectView.maskImage = makeMask(content.bounds.size)
        content.addSubview(effectView, positioned: .below, relativeTo: nil)
        
        // SwiftUI content with GlassChrome styling
        let contentView = MiniIndicatorView(indicator: self)
            .glassChrome()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        
        content.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: content.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        
        // Round window shadow via superview
        content.superview?.wantsLayer = true
        content.superview?.layer?.cornerRadius = 16
        content.superview?.layer?.masksToBounds = false
        
        // Mask updates on frame/scale changes
        content.postsFrameChangedNotifications = true
        frameObserverToken = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification,
                                              object: content, queue: .main) { _ in
            effectView.maskImage = makeMask(content.bounds.size)
        }
        
        // Fade in animation
        window?.alphaValue = 0.0
        window?.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window?.animator().alphaValue = 1.0
        }
        
        Logger.miniIndicator.infoDev("✅ Mini indicator window created with simplified glass architecture at: \(windowFrame)")
    }
    
    private func hideWindow() {
        guard let window = window else { return }
        
        // Clean up frame observer
        if let token = frameObserverToken {
            NotificationCenter.default.removeObserver(token)
            frameObserverToken = nil
        }
        
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
        if let token = frameObserverToken {
            NotificationCenter.default.removeObserver(token)
            frameObserverToken = nil
        }
        window?.orderOut(nil)
        window = nil
    }
}

/// SwiftUI view for the glassmorphism waveform indicator  
struct MiniIndicatorView: View {
    @ObservedObject var indicator: MiniRecordingIndicator
    @Environment(\.colorScheme) private var colorScheme
    
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
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.95), Color.white.opacity(0.75)]
                                : [Color.black.opacity(0.75), Color.black.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
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

// MARK: - Refined Glass Chrome with Narrow Edge Gloss
struct GlassChrome: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }
    private let r: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(16)

            // minimal tinting (enhanced for reduced transparency)
            .background(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(dark ? Color.black.opacity(0.12) : 
                         (NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 
                          Color.black.opacity(0.08) : Color.black.opacity(0.02)))
            )

            // very narrow top gloss (8-10 pt)
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(dark ? 0.11 : 0.17),
                                .clear
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(height: 9)         // narrower zone
                    .blur(radius: 0.4)
            }

            // crisp inner bottom edge
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(Color.black.opacity(dark ? 0.22 : 0.12), lineWidth: 1)
                    .blur(radius: 0.6)
                    .offset(y: 0.6)
                    .mask(
                        LinearGradient(colors: [.clear, .black],
                                       startPoint: .center, endPoint: .bottom)
                        .mask(RoundedRectangle(cornerRadius: r, style: .continuous))
                    )
            }

            // fine hairline around
            .overlay(
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(Color.white.opacity(dark ? 0.10 : 0.14), lineWidth: 1)
            )
            .compositingGroup()
            .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}

extension View {
    func glassChrome() -> some View { modifier(GlassChrome()) }
}

// MARK: - Logger Extension
extension Logger {
    static let miniIndicator = Logger(subsystem: "com.fluidvoice.app", category: "MiniRecordingIndicator")
}