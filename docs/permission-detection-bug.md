# Permission Detection Bug - Accessibility

**Date**: 2025-09-04  
**Priority**: Critical (UX/Trust Issue)  
**Status**: Active Bug

## Problem Description

### Current Broken Flow:
1. **User enables FluidVoice** in System Settings > Accessibility ✅
2. **macOS shows FluidVoice** as enabled in settings ✅  
3. **FluidVoice app** still shows "Permission denied" ❌
4. **App doesn't detect** the granted permission ❌
5. **SmartPaste doesn't work** despite permission being granted ❌

### User Impact:
- **"This app is broken"** - permission clearly granted but app doesn't work
- **Trust issues** - app ignores system settings
- **Abandonment** - users give up after following instructions correctly

## Root Cause Investigation

### 1. **Permission Check Implementation**
```swift
// AccessibilityPermissionManager.swift - Current implementation
func checkPermission() -> Bool {
    return AXIsProcessTrustedWithOptions(nil)
}
```

**Potential Issues:**
- **Bundle identity mismatch** between running app and system registration
- **Caching of permission status** - app checks once and caches wrong result
- **Timing issue** - system hasn't fully propagated permission change
- **Process identity confusion** - different process than registered

### 2. **Bundle Identity Verification**
```bash
# What system sees vs what app reports
ps aux | grep FluidVoice
# vs
plutil -p FluidVoice.app/Contents/Info.plist | grep CFBundleIdentifier
```

### 3. **System Permission Database**
```bash
# Check what system actually has registered
sqlite3 /var/db/SystemPolicyConfiguration/ExecPolicy \
  "SELECT * FROM access WHERE service='kTCCServiceAccessibility'"
```

## Debug Implementation

### 1. **Enhanced Permission Checker**
```swift
// AccessibilityPermissionManager.swift - Debug version
class AccessibilityPermissionManager {
    func checkPermission() -> Bool {
        let permission = AXIsProcessTrustedWithOptions(nil)
        debugPermissionStatus(granted: permission)
        return permission
    }
    
    private func debugPermissionStatus(granted: Bool) {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let executablePath = Bundle.main.executablePath ?? "unknown"
        let processName = ProcessInfo.processInfo.processName
        
        Logger.app.info("""
        Accessibility Permission Debug:
        - Granted: \(granted)
        - Bundle ID: \(bundleId)
        - Executable: \(executablePath)  
        - Process Name: \(processName)
        - PID: \(ProcessInfo.processInfo.processIdentifier)
        """)
        
        // Also check with prompt to see if that changes anything
        let withPrompt = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): false
        ] as CFDictionary)
        
        if granted != withPrompt {
            Logger.app.warning("Permission status differs: nil=\(granted), noprompt=\(withPrompt)")
        }
    }
    
    // Force refresh permission status
    func refreshPermissionStatus() -> Bool {
        // Clear any internal caches
        let permission = AXIsProcessTrustedWithOptions([
            kAXTrustedCheckOptionPrompt.takeRetainedValue(): false
        ] as CFDictionary)
        
        debugPermissionStatus(granted: permission)
        return permission
    }
}
```

### 2. **Real-time Permission Monitoring**
```swift
// Monitor for permission changes
class PermissionMonitor {
    private var timer: Timer?
    
    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let current = AccessibilityPermissionManager().checkPermission()
            if current != self.lastKnownStatus {
                Logger.app.info("Accessibility permission changed: \(self.lastKnownStatus) -> \(current)")
                self.lastKnownStatus = current
                NotificationCenter.default.post(name: .accessibilityPermissionChanged, object: current)
            }
        }
    }
    
    private var lastKnownStatus = false
}
```

### 3. **Manual Permission Verification Dialog**
```swift
// Show debug info to user
func showPermissionDebugDialog() {
    let alert = NSAlert()
    alert.messageText = "Permission Detection Debug"
    
    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
    let appDetection = AXIsProcessTrustedWithOptions(nil)
    
    alert.informativeText = """
    Debug Information:
    
    App Bundle ID: \(bundleId)
    App Detection: \(appDetection ? "✅ GRANTED" : "❌ DENIED")
    
    Please verify in System Settings:
    1. Open System Settings > Privacy & Security > Accessibility  
    2. Look for "FluidVoice" in the list
    3. Ensure the toggle is ON
    4. If app still doesn't detect, try toggling OFF and ON again
    
    Bundle ID should match: com.fluidvoice.app
    """
    
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Refresh Detection")
    alert.addButton(withTitle: "Close")
    
    let response = alert.runModal()
    
    switch response {
    case .alertFirstButtonReturn:
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    case .alertSecondButtonReturn:
        let refreshed = AccessibilityPermissionManager().refreshPermissionStatus()
        showSimpleAlert(title: "Refreshed", message: "Permission status: \(refreshed ? "GRANTED" : "DENIED")")
    default:
        break
    }
}
```

## Common Fixes

### 1. **App Restart After Permission Grant**
```swift
// Show restart suggestion
func suggestAppRestart() {
    let alert = NSAlert()
    alert.messageText = "Permission Granted - Restart Recommended"
    alert.informativeText = """
    Accessibility permission has been granted, but the app may need to restart to detect it properly.
    
    This is a known macOS behavior where permission changes aren't immediately visible to running apps.
    """
    
    alert.addButton(withTitle: "Restart FluidVoice")
    alert.addButton(withTitle: "Continue")
    
    if alert.runModal() == .alertFirstButtonReturn {
        restartApp()
    }
}

private func restartApp() {
    let path = Bundle.main.bundlePath
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), 
                                     configuration: NSWorkspace.OpenConfiguration()) { _, _ in
        NSApp.terminate(nil)
    }
}
```

### 2. **Toggle Permission Workaround**
```swift
// Suggest the "toggle off/on" fix
func showToggleWorkaround() {
    let alert = NSAlert()
    alert.messageText = "Permission Detection Issue"
    alert.informativeText = """
    FluidVoice appears to be enabled in Accessibility settings, but the app cannot detect it.
    
    Common fix:
    1. Open System Settings > Privacy & Security > Accessibility
    2. Find "FluidVoice" in the list
    3. Toggle it OFF, then back ON
    4. Return to FluidVoice - permission should now be detected
    
    This refreshes the system's permission state.
    """
    
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Try Again")
    
    if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
```

### 3. **Bundle Identity Fix**
```swift
// Verify bundle identity matches system expectations
func verifyBundleIdentity() {
    let currentBundleId = Bundle.main.bundleIdentifier
    let expectedBundleId = "com.fluidvoice.app"
    
    if currentBundleId != expectedBundleId {
        Logger.app.error("Bundle ID mismatch: got '\(currentBundleId ?? "nil")', expected '\(expectedBundleId)'")
        
        let alert = NSAlert()
        alert.messageText = "App Identity Issue"
        alert.informativeText = """
        The app's bundle identifier doesn't match what's expected for permission tracking.
        
        Expected: \(expectedBundleId)
        Current: \(currentBundleId ?? "nil")
        
        This can cause permission detection failures.
        """
        alert.runModal()
    }
}
```

## Testing Protocol

### 1. **Clean Permission Test**
```bash
# Remove all FluidVoice permissions
tccutil reset All com.fluidvoice.app

# Launch app
open FluidVoice.app

# Grant accessibility permission
# Test detection immediately
# Test detection after app restart
```

### 2. **Permission State Verification**
```bash
# Check system permission database
sqlite3 /var/db/SystemPolicyConfiguration/ExecPolicy \
  "SELECT * FROM access WHERE service='kTCCServiceAccessibility' AND client='com.fluidvoice.app'"

# Should return a row with allowed=1
```

### 3. **Bundle Consistency Test**
```bash
# What system sees
ps aux | grep FluidVoice | head -1 | awk '{print $11}'

# What Info.plist says  
plutil -p FluidVoice.app/Contents/Info.plist | grep CFBundleIdentifier

# Should match exactly
```

## Immediate Workarounds

### 1. **Add "Refresh Permission" Button**
- In Settings UI
- Calls refreshPermissionStatus()
- Shows current detection status

### 2. **Show Permission Debug Info**  
- Display bundle ID to user
- Show detection status vs system status
- Help user troubleshoot

### 3. **Suggest Manual Fixes**
- Toggle permission off/on in System Settings
- Restart app after granting permission
- Verify bundle ID matches in System Settings

## Success Criteria

- ✅ **Permission granted in System Settings** = **App detects immediately**
- ✅ **No restart required** after granting permission  
- ✅ **No toggle off/on workaround** needed
- ✅ **Debug info available** for troubleshooting
- ✅ **Clear user guidance** when detection fails

---

**Impact**: This is a **trust-breaking bug**. Users follow instructions correctly but app still doesn't work, making FluidVoice appear fundamentally broken.