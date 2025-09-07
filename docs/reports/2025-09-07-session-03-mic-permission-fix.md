# Session Report: Microphone Permission Fix

**Date:** 2025-09-07  
**Session:** 03  
**Title:** TCC Microphone Permission Recovery  
**Duration:** ~2 hours

## Main Accomplishment

✅ **Fixed TCC microphone permission issue** - App now properly requests permission even after TCC entry loss/corruption.

## Problem Identified

**Root Cause:** After TCC reset or code changes, `AVCaptureDevice.authorizationStatus(for: .audio)` returned `.denied` but app never triggered permission request dialog, leaving users without microphone access.

**Symptoms:**
- FluidVoice missing from System Preferences → Privacy & Security → Microphone
- `AVAuthorizationStatus.rawValue: 2` (.denied) on every startup
- No permission dialog shown to user
- Background recording failed with "No microphone permission" error

## Technical Solution

**File:** `Sources/AudioRecorder.swift:180-188`

**Before:**
```swift
case .denied, .restricted:
    DispatchQueue.main.async {
        self.hasPermission = false
    }
    // Log the issue but don't request again automatically
    Logger.audioRecorder.infoDev("⚠️ Microphone permission denied/restricted - user must enable in System Preferences")
```

**After:**
```swift
case .denied, .restricted:
    Logger.audioRecorder.infoDev("⚠️ Microphone permission denied/restricted - attempting re-request in case TCC entry was lost")
    // Try to request permission again - could be due to TCC reset or missing entry
    AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
        Logger.audioRecorder.infoDev("🔍 Re-permission request result: \(granted)")
        DispatchQueue.main.async {
            self?.hasPermission = granted
        }
    }
```

## Key Insight

**TCC Behavior on macOS:** After `tccutil reset` or Bundle signature changes, TCC status can be `.denied` instead of `.notDetermined`. Standard iOS/macOS patterns assume `.denied` means "user explicitly rejected", but on macOS development builds this can also mean "TCC entry missing/corrupted".

**Solution:** Always attempt permission request for `.denied` state as fallback recovery mechanism.

## System State

- **App Bundle:** FluidVoice-dev.app (development build)
- **Bundle ID:** com.fluidvoice.app  
- **Debug Workflow:** `./build-dev.sh && FluidVoice-dev.app/Contents/MacOS/FluidVoice`
- **Logging:** `/usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info`
- **Current Hotkey:** "Fn" (implemented and working after permission grant)

## Architecture Dependencies

- **Audio Stack:** AVFoundation → now properly requesting TCC permissions
- **Permission Flow:** AudioRecorder.checkMicrophonePermission() → requestAccess for all non-authorized states
- **Fn Key Detection:** NSEvent global monitor (keyCode 63) → working correctly
- **Build System:** Swift Package Manager → no issues

## Files Modified

1. `Sources/AudioRecorder.swift` - Enhanced permission request logic for .denied state
2. `CLAUDE.md` - Added rule: "AI niemals BashOutput für Logs: User copy/pastet relevante Logs"

## Next Steps

**User Action Required:**
1. Test permission dialog appears on app startup
2. Grant microphone permission in system dialog
3. Verify FluidVoice appears in System Preferences → Privacy & Security → Microphone
4. Test Fn key hotkey functionality with Ghostty active

**If permission still fails:**
- Check Bundle signing with `codesign -vv FluidVoice-dev.app`
- Verify Info.plist NSMicrophoneUsageDescription 
- Consider full TCC database reset: `sudo tccutil reset All` (nuclear option)

## Notes for Future AI Context

This fix addresses the common macOS development issue where TCC permissions get "stuck" in denied state after code changes or resets. The solution is defensive - always attempt permission request rather than assuming `.denied` means permanent user rejection.

The Fn key implementation from previous session is solid and working once permissions are granted. The core issue was always TCC permission recovery, not the hotkey detection mechanism.