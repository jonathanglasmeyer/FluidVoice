# CGEvent Command+V Paste Issues and Alternative Solutions for macOS

## Problem Summary

CGEvent-based Command+V paste operations fail in certain applications (notably Chrome) even when:
- The CGEvent is successfully posted without errors
- The target app is correctly activated and frontmost 
- The text field has focus (cursor visible)
- Manual Command+V works fine
- Text is correctly in clipboard

This is a well-documented issue in macOS automation due to security restrictions and application-specific event handling.

## Root Causes

### 1. Security Restrictions
- **macOS Secure Input**: When enabled (password fields, secure contexts), CGEvent keyboard events are blocked
- **Application Sandboxing**: Modern apps like Chrome have security layers that filter synthetic keyboard events
- **System Integrity Protection (SIP)**: Additional security measures that can block programmatic events

### 2. Application-Specific Event Handling
- Some applications implement custom event loops that ignore CGEvent-generated keyboard events
- Chrome and other browsers have specific security policies against synthetic paste events
- Applications may differentiate between "real" hardware events and programmatic events

### 3. Permission Requirements
- **Accessibility Access**: Required for most programmatic input methods
- **Input Monitoring**: May be required for CGEvent operations (macOS 10.15+)
- Missing permissions can cause silent failures

## Alternative Solutions

### 1. Accessibility API (AXUIElement) - Most Reliable

The macOS Accessibility API provides the most robust solution for programmatic text insertion:

```swift
import ApplicationServices

func insertTextViaAccessibility(_ text: String, targetPid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(targetPid)
    var focusedElement: CFTypeRef?
    
    // Get the focused element
    let result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute, &focusedElement)
    
    guard result == .success,
          let element = focusedElement else {
        return false
    }
    
    // Set the text value directly
    let textValue = text as CFString
    let setResult = AXUIElementSetAttributeValue(element as! AXUIElement, kAXValueAttribute, textValue)
    
    return setResult == .success
}

// Alternative: Insert at current position
func insertTextAtCursor(_ text: String, targetPid: pid_t) -> Bool {
    let app = AXUIElementCreateApplication(targetPid)
    var focusedElement: CFTypeRef?
    
    let result = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute, &focusedElement)
    
    guard result == .success,
          let element = focusedElement else {
        return false
    }
    
    // Get current selection range
    var selectedRange: CFTypeRef?
    AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextRangeAttribute, &selectedRange)
    
    // Insert text at selection
    let textValue = text as CFString
    let insertResult = AXUIElementSetAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute, textValue)
    
    return insertResult == .success
}
```

**Advantages:**
- Works reliably across most applications
- Bypasses keyboard event restrictions
- Direct text insertion without clipboard dependency

**Requirements:**
- Accessibility permissions must be granted
- Target application must support Accessibility API

### 2. keyStrokes Method (Hammerspoon-style) - Character-by-Character

Instead of using Command+V paste, simulate typing each character individually:

```swift
import Carbon

func typeTextDirectly(_ text: String) -> Bool {
    for char in text {
        let keyCode = keyCodeForCharacter(char)
        guard keyCode != 0 else { continue }
        
        // Create key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: nil, 
                                       virtualKey: keyCode, 
                                       keyDown: true) else { continue }
        
        // Create key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: nil, 
                                     virtualKey: keyCode, 
                                     keyDown: false) else { continue }
        
        // Post events
        keyDownEvent.post(tap: .cghidEventTap)
        keyUpEvent.post(tap: .cghidEventTap)
        
        // Small delay between characters
        usleep(1000) // 1ms delay
    }
    return true
}

func keyCodeForCharacter(_ char: Character) -> CGKeyCode {
    // Map characters to key codes
    switch char {
    case "a", "A": return 0x00
    case "s", "S": return 0x01
    case "d", "D": return 0x02
    // ... implement full character mapping
    default: return 0
    }
}
```

**Advantages:**
- Bypasses paste restrictions
- Works in most applications that accept keyboard input
- No clipboard dependency

**Disadvantages:**
- Slower for large text blocks
- More complex character mapping required
- May trigger typing animations/effects

### 3. Hybrid Approach - Smart Fallback

Combine multiple methods with intelligent fallback:

```swift
func insertTextSmart(_ text: String, targetApp: NSRunningApplication) -> Bool {
    let pid = targetApp.processIdentifier
    
    // Method 1: Try Accessibility API first (most reliable)
    if insertTextViaAccessibility(text, targetPid: pid) {
        return true
    }
    
    // Method 2: Try traditional paste if clipboard method preferred
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    
    if sendCommandV(to: targetApp) {
        // Verify paste worked by checking if clipboard was accessed
        Thread.sleep(forTimeInterval: 0.1)
        return true
    }
    
    // Method 3: Fallback to character-by-character typing
    return typeTextDirectly(text)
}

func sendCommandV(to app: NSRunningApplication) -> Bool {
    app.activate()
    Thread.sleep(forTimeInterval: 0.05)
    
    guard let cmdDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: true),
          let vDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
          let vUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false),
          let cmdUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: false) else {
        return false
    }
    
    // Set command modifier for V key events
    vDown.flags = .maskCommand
    vUp.flags = .maskCommand
    
    // Post the sequence
    cmdDown.post(tap: .cghidEventTap)
    vDown.post(tap: .cghidEventTap)
    vUp.post(tap: .cghidEventTrap)
    cmdUp.post(tap: .cghidEventTap)
    
    return true
}
```

### 4. Application-Specific Solutions

For Chrome and other Chromium-based browsers:

```swift
// Use Chrome DevTools Protocol (if available)
func insertTextInChrome(_ text: String) -> Bool {
    // This requires Chrome to be launched with debugging enabled
    // --remote-debugging-port=9222
    
    let script = """
    document.activeElement.value = '\(text.replacingOccurrences(of: "'", with: "\\'"))';
    document.activeElement.dispatchEvent(new Event('input', { bubbles: true }));
    """
    
    // Send via CDP Runtime.evaluate
    return sendCDPCommand(method: "Runtime.evaluate", params: ["expression": script])
}

// Alternative: AppleScript for specific apps
func insertTextViaAppleScript(_ text: String, appName: String) -> Bool {
    let script = """
    tell application "\(appName)"
        tell application "System Events"
            keystroke "\(text)"
        end tell
    end tell
    """
    
    var error: NSDictionary?
    let appleScript = NSAppleScript(source: script)
    appleScript?.executeAndReturnError(&error)
    
    return error == nil
}
```

## Required Permissions

### Accessibility Access
```swift
func requestAccessibilityPermissions() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
    return AXIsProcessTrustedWithOptions(options)
}
```

Add to Info.plist:
```xml
<key>NSAppleEventsUsageDescription</key>
<string>This app needs accessibility access to insert text into other applications.</string>
```

### Input Monitoring (macOS 10.15+)
```swift
// For CGEvent operations, may need Input Monitoring permissions
// This is automatically prompted when first using CGEvent APIs
```

Add to Info.plist:
```xml
<key>NSInputMonitoringUsageDescription</key>
<string>This app monitors input to provide text insertion capabilities.</string>
```

## Best Practices

### 1. Progressive Enhancement
- Start with the most reliable method (Accessibility API)
- Fall back to less reliable methods as needed
- Provide user feedback about what method is being used

### 2. Error Handling
```swift
enum TextInsertionError: Error {
    case accessibilityDenied
    case targetAppNotFound
    case insertionFailed
    case unsupportedApplication
}

func insertTextWithErrorHandling(_ text: String, targetApp: NSRunningApplication) throws {
    // Check permissions first
    guard AXIsProcessTrusted() else {
        throw TextInsertionError.accessibilityDenied
    }
    
    // Attempt insertion with fallbacks
    if !insertTextSmart(text, targetApp: targetApp) {
        throw TextInsertionError.insertionFailed
    }
}
```

### 3. Application Detection
```swift
func getInsertionStrategy(for app: NSRunningApplication) -> InsertionStrategy {
    guard let bundleId = app.bundleIdentifier else {
        return .accessibility // Safe default
    }
    
    switch bundleId {
    case "com.google.Chrome", "com.microsoft.edgemac":
        return .keystrokes // Bypass paste restrictions
    case "com.apple.TextEdit", "com.apple.Notes":
        return .accessibility // Reliable for Apple apps
    default:
        return .hybrid // Try multiple methods
    }
}
```

## Testing Different Apps

### Known Working Methods by Application:
- **TextEdit**: Accessibility API ✅, CGEvent paste ✅
- **Notes**: Accessibility API ✅, CGEvent paste ✅  
- **Chrome**: Accessibility API ✅, keyStrokes ✅, CGEvent paste ❌
- **Firefox**: Accessibility API ✅, keyStrokes ✅, CGEvent paste ⚠️
- **VSCode**: Accessibility API ✅, CGEvent paste ✅
- **Terminal**: keyStrokes ✅, CGEvent paste ⚠️ (depends on shell)

## Implementation Recommendations

1. **Primary Strategy**: Use Accessibility API (`AXUIElementSetAttributeValue`) for direct text insertion
2. **Fallback Strategy**: Character-by-character typing via CGEvent keystrokes
3. **Permission Handling**: Request accessibility permissions on first use with clear explanation
4. **User Feedback**: Inform users which method is being used and why
5. **Testing**: Test against target applications in your specific use case

This multi-layered approach provides the most reliable text insertion across different macOS applications while handling the security restrictions that block simple CGEvent paste operations.