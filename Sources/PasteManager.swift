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
    
    /// Attempts to paste text to the currently active application
    /// Uses Unicode-Typing
    func pasteToActiveApp() {
        // Use Unicode-Typing
        performUnicodeTyping()
    }
    
    /// Directly types the provided text using Unicode-Typing
    func pasteText(_ text: String) {
        // Copy text to clipboard first for Unicode-Typing to work
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Use Unicode-Typing
        performUnicodeTyping()
    }
    
    /// SmartPaste function that attempts to paste text into a specific application
    /// This is the function mentioned in the test requirements
    func smartPaste(into targetApp: NSRunningApplication?, text: String) {
        // First copy text to clipboard as fallback - this ensures users always have access to the text
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        
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
            
            self.performCGEventPaste()
        }
    }
    
    /// Performs paste with completion handler for proper coordination
    @MainActor
    func pasteWithCompletionHandler() async {
        await withCheckedContinuation { continuation in
            pasteWithUserInteraction { _ in
                continuation.resume()
            }
        }
    }
    
    /// Performs paste with immediate user interaction context
    /// This should work better than automatic pasting
    func pasteWithUserInteraction(completion: ((Result<Void, PasteError>) -> Void)? = nil) {
        // Check permission first - if denied, show proper explanation and request
        guard accessibilityManager.checkPermission() else {
            // Show permission request with explanation - this includes user education
            accessibilityManager.requestPermissionWithExplanation { [weak self] granted in
                guard let self = self else { return }
                
                if granted {
                    // Permission was granted - attempt paste operation
                    self.performCGEventPaste(completion: completion)
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
        performCGEventPaste(completion: completion)
    }
    
    // MARK: - CGEvent Paste
    
    private func performCGEventPaste(completion: ((Result<Void, PasteError>) -> Void)? = nil) {
        // CRITICAL: Prevent any paste operations during tests
        if NSClassFromString("XCTestCase") != nil {
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }
        
        // CRITICAL SECURITY CHECK: Always verify accessibility permission before any CGEvent operations
        // This method should NEVER execute without proper permission - no exceptions
        guard accessibilityManager.checkPermission() else {
            // Permission is not granted - STOP IMMEDIATELY and report error
            // We must never attempt CGEvent operations without permission
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }
        
        // Permission is verified - proceed with paste operation
        do {
            try simulateCmdVPaste()
            // CGEvent paste completed successfully
            Logger.app.infoDev("✅ CGEvent Command+V paste successful")
            handlePasteResult(.success(()))
            completion?(.success(()))
        } catch let error as PasteError {
            // CGEvent failed - try Unicode-Typing fallback
            Logger.app.infoDev("⚠️ CGEvent paste failed, attempting Unicode-Typing fallback: \(error.localizedDescription)")
            performUnicodeTypingFallback(originalError: error, completion: completion)
        } catch {
            // Handle unexpected errors - also try Unicode-Typing fallback
            Logger.app.infoDev("⚠️ CGEvent paste unexpected error, attempting Unicode-Typing fallback: \(error.localizedDescription)")
            performUnicodeTypingFallback(originalError: PasteError.keyboardEventCreationFailed, completion: completion)
        }
    }
    
    // Removed - using AccessibilityPermissionManager instead
    
    private func simulateCmdVPaste() throws {
        // CRITICAL: Prevent any paste operations during tests
        if NSClassFromString("XCTestCase") != nil {
            throw PasteError.accessibilityPermissionDenied
        }
        
        // Final permission check before creating any CGEvents
        // This is our last line of defense against unauthorized paste operations
        guard accessibilityManager.checkPermission() else {
            throw PasteError.accessibilityPermissionDenied
        }
        
        // Create event source with proper session state
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }
        
        // Configure event source to suppress local events during paste operation
        // This prevents interference from local keyboard input
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        
        // Create ⌘V key events for paste operation
        let cmdFlag = CGEventFlags([.maskCommand])
        let vKeyCode = CGKeyCode(kVK_ANSI_V) // V key code
        
        // Create both key down and key up events for complete key press simulation
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw PasteError.keyboardEventCreationFailed
        }
        
        // Apply Command modifier flag to both events
        keyVDown.flags = cmdFlag
        keyVUp.flags = cmdFlag
        
        // Post the key events to the system
        // This simulates pressing and releasing ⌘V
        keyVDown.post(tap: .cgSessionEventTap)
        keyVUp.post(tap: .cgSessionEventTap)
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
    
    /// Fallback handler that attempts Unicode-Typing when CGEvent fails
    /// This provides the hybrid approach: CGEvent first, Unicode-Typing as backup
    private func performUnicodeTypingFallback(originalError: PasteError, completion: ((Result<Void, PasteError>) -> Void)? = nil) {
        Logger.app.infoDev("🔄 Starting Unicode-Typing fallback after CGEvent failure")
        
        // Try Unicode-Typing fallback
        performUnicodeTyping { result in
            switch result {
            case .success:
                Logger.app.infoDev("✅ Unicode-Typing fallback successful - hybrid paste completed")
                // Don't call handlePasteResult again, performUnicodeTyping already did
            case .failure(let fallbackError):
                Logger.app.error("❌ Unicode-Typing fallback also failed: \(fallbackError.localizedDescription)")
                Logger.app.error("❌ Both CGEvent and Unicode-Typing failed - paste operation failed")
                // Report the original CGEvent error, not the fallback error
                self.handlePasteResult(.failure(originalError))
                completion?(.failure(originalError))
            }
        }
    }
    
    // MARK: - Unicode-Typing Fallback
    
    /// Unicode-Typing fallback strategy for apps that block CGEvent Command+V
    /// Uses CGEventKeyboardSetUnicodeString to type text character by character
    /// Works with Chrome, modern browsers, and restrictive applications
    private func performUnicodeTyping(completion: ((Result<Void, PasteError>) -> Void)? = nil) {
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
            try executeUnicodeTyping()
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
    
    private func executeUnicodeTyping() throws {
        // Get text from clipboard
        guard let textToType = NSPasteboard.general.string(forType: .string), !textToType.isEmpty else {
            Logger.app.infoDev("📋 No text in clipboard for Unicode-Typing")
            return // Empty clipboard is not an error
        }
        
        // Logger.app.infoDev("🔤 Starting Unicode-Typing for \(textToType.count) characters")
        
        // Simple approach: just type to whatever app is currently active
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            // Logger.app.infoDev("🎯 Typing to currently active app: \(frontmostApp.localizedName ?? "Unknown") (PID: \(frontmostApp.processIdentifier))")
        } else {
            Logger.app.warning("⚠️ No active app found - proceeding anyway")
        }
        
        // Create event source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }
        
        // Split text into manageable chunks (100 characters)
        let chunks = textToType.chunked(into: 100)
        // Logger.app.infoDev("📦 Processing \(chunks.count) text chunks")
        
        // Process each chunk
        for (index, chunk) in chunks.enumerated() {
            try processUnicodeChunk(chunk, chunkIndex: index, source: source)
            
            // Small delay between chunks to prevent overwhelming the target app
            if chunks.count > 1 && index < chunks.count - 1 {
                usleep(10_000) // 10ms delay between chunks
            }
        }
        
        // Logger.app.infoDev("✅ Unicode-Typing completed successfully")
    }
    
    private func processUnicodeChunk(_ chunk: String, chunkIndex: Int, source: CGEventSource) throws {
        // Convert string to UTF-16 UniChar array
        let unicodeChars = chunk.utf16.map { UniChar($0) }
        
        // Create Unicode keyboard event
        guard let unicodeEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
            throw PasteError.keyboardEventCreationFailed
        }
        
        // Set the Unicode string for this chunk
        unicodeEvent.keyboardSetUnicodeString(stringLength: unicodeChars.count, unicodeString: unicodeChars)
        
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
            // Logger.app.infoDev("📤 Posted Unicode chunk \(chunkIndex + 1)")
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
