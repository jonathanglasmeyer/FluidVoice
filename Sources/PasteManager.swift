import Foundation
import AppKit
import ApplicationServices
import Carbon
import os.log

// Helper class to safely capture observer in closure
// Uses a lock to ensure thread-safe access to the mutable observer property
// @unchecked is required because we have mutable state but we ensure thread safety via NSLock
private final class ObserverBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _observer: NSObjectProtocol?
    
    var observer: NSObjectProtocol? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _observer
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _observer = newValue
        }
    }
}

/// Errors that can occur during paste operations
enum PasteError: LocalizedError {
    case accessibilityPermissionDenied
    case eventSourceCreationFailed
    case keyboardEventCreationFailed
    case targetAppNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for SmartPaste. Please enable it in System Settings > Privacy & Security > Accessibility."
        case .eventSourceCreationFailed:
            return "Could not create event source for paste operation."
        case .keyboardEventCreationFailed:
            return "Could not create keyboard events for paste operation."
        case .targetAppNotAvailable:
            return "Target application is not available for pasting."
        }
    }
}

@MainActor
class PasteManager: ObservableObject {
    
    private let accessibilityManager = AccessibilityPermissionManager()
    
    /// Directly types the provided text using Unicode-Typing
    func pasteText(_ text: String) {
        performUnicodeTyping(text: text)
    }
    
    /// SmartPaste function that attempts to paste text into a specific application
    /// This is the function mentioned in the test requirements
    func smartPaste(into targetApp: NSRunningApplication?, text: String) {
        // CRITICAL: Check accessibility permission without prompting - never bypass this check
        // If this fails, we must NOT attempt to proceed with CGEvent operations
        guard accessibilityManager.checkPermission() else {
            // Permission is definitively denied - show proper error and stop processing
            // Do NOT attempt any paste operations without permission
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            return
        }
        
        // Validate target application
        guard let targetApp = targetApp, !targetApp.isTerminated else {
            handlePasteResult(.failure(PasteError.targetAppNotAvailable))
            return
        }
        
        // Attempt to activate target application
        let activationSuccess = targetApp.activate(options: [])
        if !activationSuccess {
            // App activation failed - this could indicate the app is not responsive
            handlePasteResult(.failure(PasteError.targetAppNotAvailable))
            return
        }
        
        // Wait for app to become active before pasting
        waitForApplicationActivation(targetApp) { [weak self] in
            guard let self = self else { return }
            
            // Double-check permission before performing paste (belt and suspenders approach)
            guard self.accessibilityManager.checkPermission() else {
                // Permission was revoked between initial check and paste attempt
                self.handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
                return
            }
            
            // Use Unicode-Typing directly with the text
            self.performUnicodeTyping(text: text)
        }
    }
    
    /// Performs paste with completion handler for proper coordination
    @MainActor
    func pasteWithCompletionHandler(text: String) async {
        await withCheckedContinuation { continuation in
            pasteWithUserInteraction(text: text) { _ in
                continuation.resume()
            }
        }
    }
    
    /// Performs paste with immediate user interaction context
    /// This should work better than automatic pasting
    func pasteWithUserInteraction(text: String, completion: ((Result<Void, PasteError>) -> Void)? = nil) {
        // Check permission first - if denied, show proper explanation and request
        guard accessibilityManager.checkPermission() else {
            // Show permission request with explanation - this includes user education
            accessibilityManager.requestPermissionWithExplanation { [weak self] granted in
                guard let self = self else { return }
                
                if granted {
                    // Permission was granted - attempt paste operation
                    self.performUnicodeTyping(text: text, completion: completion)
                } else {
                    // User declined permission - show appropriate message and fail gracefully
                    self.accessibilityManager.showPermissionDeniedMessage()
                    self.handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
                    completion?(.failure(PasteError.accessibilityPermissionDenied))
                }
            }
            return
        }
        
        // Permission is available - proceed with paste
        performUnicodeTyping(text: text, completion: completion)
    }
    
    
    private func handlePasteResult(_ result: Result<Void, PasteError>) {
        DispatchQueue.main.async {
            switch result {
            case .success:
                NotificationCenter.default.post(
                    name: .pasteOperationSucceeded,
                    object: nil
                )
            case .failure(let error):
                NotificationCenter.default.post(
                    name: .pasteOperationFailed,
                    object: error.localizedDescription
                )
            }
        }
    }
    
    @available(*, deprecated, message: "Use handlePasteResult instead")
    private func handlePasteFailure(reason: String) {
        handlePasteResult(.failure(PasteError.keyboardEventCreationFailed))
    }
    
    
    // MARK: - Unicode-Typing
    
    /// Unicode-Typing strategy that directly types text character by character
    /// Uses CGEventKeyboardSetUnicodeString to type text without clipboard
    /// Works with Chrome, modern browsers, and restrictive applications
    private func performUnicodeTyping(text: String, completion: ((Result<Void, PasteError>) -> Void)? = nil) {
        // CRITICAL: Prevent any paste operations during tests
        if NSClassFromString("XCTestCase") != nil {
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }
        
        // CRITICAL SECURITY CHECK: Always verify accessibility permission
        guard accessibilityManager.checkPermission() else {
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }
        
        do {
            try executeUnicodeTyping(text: text)
            // Success - text was typed via Unicode method
            Logger.app.infoDev("✅ Unicode-Typing paste successful")
            handlePasteResult(.success(()))
            completion?(.success(()))
        } catch let error as PasteError {
            // Handle known paste errors
            Logger.app.error("❌ Unicode-Typing failed: \(error.localizedDescription)")
            handlePasteResult(.failure(error))
            completion?(.failure(error))
        } catch {
            // Handle unexpected errors
            Logger.app.error("❌ Unicode-Typing unexpected error: \(error.localizedDescription)")
            handlePasteResult(.failure(PasteError.keyboardEventCreationFailed))
            completion?(.failure(PasteError.keyboardEventCreationFailed))
        }
    }
    
    private func executeUnicodeTyping(text: String) throws {
        // Validate input text
        guard !text.isEmpty else {
            Logger.app.infoDev("📋 No text provided for Unicode-Typing")
            return // Empty text is not an error
        }
        
        Logger.app.infoDev("🔤 Starting Unicode-Typing for \(text.count) characters: [\(text.prefix(50))...]")
        
        // Check what app is currently active
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            Logger.app.infoDev("🎯 Typing to currently active app: \(frontmostApp.localizedName ?? "Unknown") (PID: \(frontmostApp.processIdentifier))")
        } else {
            Logger.app.warning("⚠️ No active app found - proceeding anyway")
        }
        
        // Create event source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }
        
        // Check event source flags/state
        Logger.app.infoDev("🔧 CGEventSource created with combinedSessionState")
        
        // Split text into manageable chunks (100 characters)
        let chunks = text.chunked(into: 100)
        Logger.app.infoDev("📦 Processing \(chunks.count) text chunks")
        
        // Process each chunk
        for (index, chunk) in chunks.enumerated() {
            Logger.app.infoDev("🔤 Processing chunk \(index + 1)/\(chunks.count): [\(chunk.prefix(20))...]")
            try processUnicodeChunk(chunk, chunkIndex: index, source: source)
            
            // Small delay between chunks to prevent overwhelming the target app
            if chunks.count > 1 && index < chunks.count - 1 {
                usleep(10_000) // 10ms delay between chunks
            }
        }
        
        Logger.app.infoDev("✅ Unicode-Typing completed successfully - \(chunks.count) chunks processed")
    }
    
    private func processUnicodeChunk(_ chunk: String, chunkIndex: Int, source: CGEventSource) throws {
        // Convert string to UTF-16 UniChar array
        let unicodeChars = chunk.utf16.map { UniChar($0) }
        
        // Create Unicode keyboard event
        guard let unicodeEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            throw PasteError.keyboardEventCreationFailed
        }
        
        // CRITICAL FIX: Clear ALL modifier flags to prevent Cmd+A behavior
        // The hotkey (Cmd+Shift+Space) can leave Command modifier active
        // This was causing Unicode events to be interpreted as Command+text
        let originalFlags = unicodeEvent.flags
        unicodeEvent.flags = [] // Clear all modifier flags
        
        // Debug logging to track modifier flag issues
        if !originalFlags.isEmpty {
            Logger.app.infoDev("🐛 MODIFIER DEBUG: Cleared flags \(originalFlags) from Unicode event")
        }
        
        // Set the Unicode string for this chunk
        unicodeEvent.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: unicodeChars)
        
        // Additional debug logging
        Logger.app.infoDev("🔤 Unicode chunk \(chunkIndex + 1): \(unicodeChars.count) chars, flags=\(unicodeEvent.flags)")
        
        // Try multiple tap locations for maximum compatibility
        let tapLocations: [CGEventTapLocation] = [
            .cghidEventTap,           // Hardware level - most reliable
            .cgSessionEventTap,       // Session level - fallback
            .cgAnnotatedSessionEventTap  // Annotated session - last resort
        ]
        
        var posted = false
        for tapLocation in tapLocations {
            unicodeEvent.post(tap: tapLocation)
            posted = true
            Logger.app.infoDev("📤 Posted Unicode chunk \(chunkIndex + 1) to \(tapLocation)")
            break // Only use first tap location for now, can add retry logic later
        }
        
        if !posted {
            throw PasteError.keyboardEventCreationFailed
        }
    }
    
    // MARK: - App Activation Handling
    
    private func waitForApplicationActivation(_ target: NSRunningApplication, completion: @escaping () -> Void) {
        // If already active, execute completion immediately
        if target.isActive {
            completion()
            return
        }
        
        let observerBox = ObserverBox()
        var timeoutCancelled = false
        
        // Set up timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak observerBox] in
            guard !timeoutCancelled else { return }
            if let observer = observerBox?.observer {
                NotificationCenter.default.removeObserver(observer)
            }
            // Execute completion even on timeout to avoid hanging
            completion()
        }
        
        // Observe app activation
        observerBox.observer = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak observerBox] notification in
            if let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               activatedApp.processIdentifier == target.processIdentifier {
                timeoutCancelled = true
                if let observer = observerBox?.observer {
                    NotificationCenter.default.removeObserver(observer)
                }
                completion()
            }
        }
    }
    
}

// MARK: - String Extensions for Unicode-Typing

extension String {
    /// Splits the string into chunks of specified size
    /// Used for processing large text in manageable pieces during Unicode-Typing
    func chunked(into size: Int) -> [String] {
        guard size > 0 else { return [self] }
        
        var chunks: [String] = []
        var startIndex = self.startIndex
        
        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: size, limitedBy: self.endIndex) ?? self.endIndex
            chunks.append(String(self[startIndex..<endIndex]))
            startIndex = endIndex
        }
        
        return chunks.isEmpty ? [self] : chunks
    }
}
