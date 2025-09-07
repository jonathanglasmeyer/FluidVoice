# Session Report: Fn Key Implementation

**Date:** 2025-09-07  
**Session:** 02  
**Title:** Fn Key Hotkey Support Implementation  
**Duration:** ~2 hours

## Main Accomplishment

✅ **Successfully implemented Fn key as hotkey option** with direct NSEvent monitoring, providing zero-latency push-to-talk functionality.

## Current Status

**✅ Completed:**
- Fn key detection via NSEvent global monitor (keyCode 63)
- Clean push-to-talk implementation (press=start, release=stop)
- Fixed dual handler conflict (disabled normal hotkey when Fn active)
- HotKeyRecorderView now captures Fn key presses correctly
- InputMonitoringPermission utility class for future permission handling

**⚠️ Current Issue:**
- macOS Microphone Permission architecture blocks recording when foreground app lacks mic permission
- This breaks the core use case (dictating into any app while different apps are in focus)

## Technical Implementation

### Files Modified:
- `Sources/HotKeyManager.swift` - Extended with Fn key monitoring
- `Sources/SettingsView.swift` - Added Fn key detection to recorder
- `Sources/InputMonitoringPermission.swift` - New utility class (unused currently)

### Key Technical Details:
```swift
// Fn key detection in NSEvent monitor
fnKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { event in
    if event.keyCode == 63 {
        self?.handleFnKeyEvent(event)
    }
}

// Push-to-talk logic
if fnPressed && fnKeyState == .idle {
    onHotKeyPressed() // Start recording
} else if !fnPressed && fnKeyState != .idle {
    onHotKeyPressed() // Stop recording  
}
```

### System State:
- **App Bundle:** FluidVoice-dev.app (development build)
- **Debug Workflow:** `./build-dev.sh && FluidVoice-dev.app/Contents/MacOS/FluidVoice`
- **Logging:** `/usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info`
- **Current Hotkey:** "Fn" (set via Change Hotkey UI)

## Critical Blocker

**Microphone Permission Architecture Issue:**
- FluidVoice has microphone permission ✅
- But when foreground app (e.g., Ghostty terminal) lacks mic permission ❌
- macOS blocks **all** microphone access system-wide for that focus context
- This breaks the fundamental use case of background dictation

**Error Pattern:**
```
❌ No microphone permission - background recording not possible
```

## Next Priorities

1. **CRITICAL:** Investigate macOS microphone permission bypass for background apps
   - Research AVAudioSession categories for background recording
   - Explore NSApplication background modes
   - Consider alternative audio capture methods

2. **Commit current work** - Fn key implementation is solid despite permission issue

3. **User experience:** Add graceful handling/messaging for permission conflicts

## Architecture Dependencies

- **Audio Stack:** AVFoundation → recording blocked by system permissions
- **Event System:** NSEvent global monitors → working correctly
- **Build System:** Swift Package Manager → no issues
- **Code Signing:** Development identity → working

## Notes for Future AI Context

The Fn key implementation itself is **technically sound and working**. The core issue is macOS's microphone permission model where foreground app permissions affect background app capabilities. This is likely a fundamental limitation that may require:

1. Different audio session configuration
2. User education about app permissions  
3. Alternative recording approaches
4. System-level workarounds

The dual-mode complexity was removed in favor of simple push-to-talk (press=start, release=stop) which provides the best user experience.