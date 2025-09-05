# Microphone Permission Persistence Bug

**Date**: 2025-09-04  
**Priority**: Critical (UX Blocker)  
**Status**: Active Bug  

## Problem Description

### Current Behavior:
- **FluidVoice repeatedly asks** "would like to access the microphone"
- **Permission not persisted** between app sessions
- **User grants permission** → Works for current session
- **Next app launch** → Permission dialog again ❌

### Expected Behavior:
- **Grant permission once** → Remember forever
- **System Settings** shows FluidVoice with microphone enabled
- **No repeated permission dialogs**

## Root Cause Analysis

### 1. **Bundle Identity Issue**
- **Debug builds** use temporary bundle identifiers
- **System doesn't recognize** as "same app" between builds
- **Permission tied to bundle ID** → New build = new permission

### 2. **Entitlements Missing**
```xml
<!-- FluidVoice.entitlements - Missing? -->
<key>com.apple.security.device.microphone</key>
<true/>
```

### 3. **Code Signing Inconsistency**
- **Ad-hoc signing** vs **Developer ID** signing
- **System treats differently** for permission persistence

### 4. **Info.plist Configuration**
```xml
<!-- Current in Info.plist -->
<key>NSMicrophoneUsageDescription</key>
<string>FluidVoice needs access to your microphone to record audio for transcription.</string>
```

## Investigation Steps

### Check Current Bundle ID:
```bash
# What FluidVoice.app actually reports
mdls -name kMDItemCFBundleIdentifier FluidVoice.app
# Should be: com.fluidvoice.app
```

### Check System Permission Status:
```bash
# macOS permission database
sqlite3 /var/db/SystemPolicyConfiguration/ExecPolicy \
  "SELECT * FROM access WHERE service='kTCCServiceMicrophone'"
```

### Check Code Signature:
```bash
codesign -vv -d FluidVoice.app
# Should show consistent signing
```

## Solution Implementation

### 1. **Proper Entitlements File**
Create `FluidVoice.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.microphone</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <false/>
</dict>
</plist>
```

### 2. **Build Script Updates**
Update `build.sh` to include entitlements:
```bash
# Code signing with entitlements
codesign --force --sign "$SIGNING_IDENTITY" \
  --entitlements FluidVoice.entitlements \
  --deep --strict --options=runtime \
  FluidVoice.app
```

### 3. **Permission Check Logic**
```swift
// PermissionManager.swift - Fix permission persistence
class PermissionManager {
    private let microphonePermissionKey = "microphonePermissionGranted"
    
    func checkMicrophonePermission() -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            UserDefaults.standard.set(true, forKey: microphonePermissionKey)
            return true
        case .denied, .restricted:
            UserDefaults.standard.set(false, forKey: microphonePermissionKey) 
            return false
        case .notDetermined:
            // Check if we previously had permission
            if UserDefaults.standard.bool(forKey: microphonePermissionKey) {
                // We had permission before - system might have reset it
                Logger.app.warning("Microphone permission was reset by system")
            }
            return false
        @unknown default:
            return false
        }
    }
    
    func requestMicrophonePermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        UserDefaults.standard.set(granted, forKey: microphonePermissionKey)
        return granted
    }
}
```

### 4. **Debug Permission Persistence**
```swift
// Add logging to understand permission state
extension PermissionManager {
    func debugPermissionStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        
        Logger.app.info("""
        Permission Debug Info:
        - Bundle ID: \(bundleId)
        - App Version: \(appVersion)
        - AVAuthorizationStatus: \(status.rawValue)
        - UserDefaults saved: \(UserDefaults.standard.bool(forKey: microphonePermissionKey))
        """)
    }
}
```

### 5. **User Guidance for Permission Reset**
```swift
// Show helpful dialog when permission is lost
func showPermissionLostDialog() {
    let alert = NSAlert()
    alert.messageText = "Microphone Permission Reset"
    alert.informativeText = """
    macOS has reset FluidVoice's microphone permission. This can happen when:
    
    • The app was updated or reinstalled
    • System privacy settings were reset
    • macOS security policies changed
    
    To fix this:
    1. Click "Open System Settings" 
    2. Enable FluidVoice under "Microphone"
    3. The permission will be remembered going forward
    """
    
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Cancel")
    
    if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
```

## Testing Plan

### 1. **Clean Permission Test**
```bash
# Reset all permissions for FluidVoice
tccutil reset Microphone com.fluidvoice.app
# Launch app → Should ask for permission once
# Restart app → Should NOT ask again
```

### 2. **Bundle Consistency Test**  
```bash
# Build app twice, check bundle IDs match
./build.sh
bundleId1=$(mdls -name kMDItemCFBundleIdentifier FluidVoice.app | cut -d'"' -f2)
rm -rf FluidVoice.app
./build.sh  
bundleId2=$(mdls -name kMDItemCFBundleIdentifier FluidVoice.app | cut -d'"' -f2)
echo "Bundle IDs: $bundleId1 vs $bundleId2"
# Should be identical
```

### 3. **Permission Persistence Test**
1. **Fresh install** → Grant microphone permission
2. **Close app** → Wait 5 minutes
3. **Relaunch app** → Should NOT ask for permission
4. **Record audio** → Should work immediately

## Quick Fixes (Immediate)

### 1. **Check Current Status**
```bash
# What's the actual bundle ID?
plutil -p FluidVoice.app/Contents/Info.plist | grep CFBundleIdentifier
```

### 2. **Manual Permission Grant**
- **System Settings** → Privacy & Security → Microphone
- **Add FluidVoice** manually if not listed
- **Enable permission** explicitly

### 3. **Consistent Signing**
- **Always use same signing identity**
- **Include in build script** for consistency

## Success Criteria

- ✅ **One-time permission request** per fresh install
- ✅ **Permission persists** across app launches  
- ✅ **No repeated permission dialogs**
- ✅ **FluidVoice appears** in System Settings > Microphone
- ✅ **Permission state** correctly detected in app

---

**Impact**: Fixing this eliminates the **#1 user friction point** and makes FluidVoice feel professional instead of broken.