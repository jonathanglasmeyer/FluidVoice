# Fn Key Capture on macOS - Research Report

**Date**: 2025-09-04  
**Status**: Research Complete  
**Priority**: High (Must-have feature for competitive parity)

## Problem Statement

FluidVoice currently uses the HotKey library which doesn't support the Fn key as a hotkey trigger. Competitor apps like Whisper Flow support Fn key, making it a critical feature gap.

## Current Implementation

### HotKeyManager.swift Analysis
- **Library**: `soffes/HotKey` (Carbon-based)
- **Supported Keys**: F1-F19, Command, Shift, Option, Control
- **Missing**: Fn key support (Hardware-level modifier)
- **Limitation**: Carbon APIs don't expose Fn key events

```swift
// Current approach - limited to standard modifier keys
hotKey = HotKey(key: .space, modifiers: [.command, .shift])
```

## Research Findings

### Method 1: NSEvent Global Monitor (Recommended)

**Advantages:**
- Native macOS API
- Works system-wide  
- Reliable Fn key detection
- Moderate complexity

**Implementation:**
```swift
private var fnKeyMonitor: Any?

func setupFnKeyMonitoring() {
    fnKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
        if event.keyCode == 63 { // Fn key keyCode
            if event.modifierFlags.contains(.function) {
                self.onHotKeyPressed() // Trigger recording
            }
        }
    }
}
```

**Requirements:**
- **Input Monitoring Permission** (macOS 10.15+)
- User grants access in System Preferences > Security & Privacy > Input Monitoring

### Method 2: CGEventTap (Most Powerful)

**Advantages:**
- Lowest-level event interception
- Can modify/block events
- System-wide coverage

**Disadvantages:**
- More complex implementation
- Requires Accessibility permission
- Potential performance impact

### Method 3: IOKit HID Interface (Overkill)

**Evaluation**: Too complex for this use case. Direct hardware access not needed.

## Technical Specifications

### Fn Key Details
- **KeyCode**: 63 (hardware scancode)
- **Modifier Flag**: `NSEvent.ModifierFlags.function`
- **Behavior**: Special hardware modifier, doesn't generate standard key events
- **Detection**: Must monitor `flagsChanged` events specifically

### Permission Requirements

1. **Input Monitoring Permission**
   ```swift
   // Check permission status
   let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
   let accessibilityEnabled = AXIsProcessTrustedWithOptions(options)
   ```

2. **User Consent Flow**
   - App requests permission on first Fn key setup
   - System shows permission dialog
   - User must manually enable in System Preferences
   - App requires restart after permission grant

## Implementation Approach

### Phase 1: Extend HotKeyManager
```swift
class HotKeyManager {
    private var hotKey: HotKey?           // Existing HotKey library
    private var fnKeyMonitor: Any?        // New NSEvent monitor
    private var currentHotkeyType: HotkeyType = .standard
    
    enum HotkeyType {
        case standard    // Uses HotKey library
        case fnKey      // Uses NSEvent monitor
    }
}
```

### Phase 2: Settings Integration
- Add "Fn" option to hotkey selection
- Handle permission requests gracefully
- Provide clear user guidance for permission setup

### Phase 3: Permission Handling
- Detect permission status
- Show explanatory dialogs
- Guide user through System Preferences setup

## Competitive Analysis

### Whisper Flow
- **Supports**: Fn key triggering
- **User Experience**: Seamless setup, clear permission requests
- **Implementation**: Likely uses NSEvent or CGEventTap approach

### FluidVoice Gap
- **Current**: No Fn key support
- **Impact**: Major feature disadvantage
- **User Feedback**: "mh ok also `Fn` kann sie schon mal nich als hotkey?"

## Risks and Considerations

### Technical Risks
1. **Permission Complexity**: User must understand and grant Input Monitoring
2. **System Compatibility**: Different behavior across macOS versions
3. **Performance Impact**: Global event monitoring overhead

### UX Risks
1. **Permission Friction**: Additional setup steps for users
2. **System Trust**: Users must trust app with global keyboard access
3. **Permission Failure**: App degradation if permission denied

## Next Steps

1. **Proof of Concept**: Implement NSEvent monitor in development branch
2. **Permission Flow**: Design user-friendly permission request flow
3. **Settings Integration**: Add Fn key option to hotkey selection
4. **Testing**: Validate across different Mac hardware and macOS versions
5. **Documentation**: Update user documentation with permission requirements

## Implementation Timeline

- **Day 1**: NSEvent monitor implementation
- **Day 2**: Settings UI integration  
- **Day 3**: Permission handling and UX flow
- **Day 4**: Testing and refinement

## References

- [NSEvent Documentation](https://developer.apple.com/documentation/appkit/nsevent)
- [Input Monitoring Permission Guide](https://developer.apple.com/documentation/security/requesting_permission_for_media_capture_on_macos)
- [CGEvent Documentation](https://developer.apple.com/documentation/coregraphics/cgevent)

---

**Conclusion**: Fn key support is technically feasible using NSEvent global monitoring. The main complexity is permission handling, but this is standard for professional macOS productivity apps. Implementation should prioritize user experience and clear permission guidance.