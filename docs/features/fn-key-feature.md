# Feature Specification: Fn Key Hotkey Support

**Feature ID**: FV-001  
**Priority**: High  
**Status**: Planned  
**Assignee**: TBD  
**Estimated Effort**: 3-4 days  

## Overview

Add support for the Fn key as a hotkey trigger option in FluidVoice, achieving feature parity with competitor applications like Whisper Flow.

## User Story

**As a** FluidVoice user  
**I want** to use the Fn key as my recording hotkey  
**So that** I can trigger recordings with a single, easily accessible key without modifier combinations

## Background

Users expect modern transcription apps to support the Fn key as a hotkey option. This is especially important for:
- **Single-handed operation**: No modifier key combinations needed
- **Muscle memory**: Users accustomed to other apps using Fn key
- **Accessibility**: Simpler key press for users with mobility constraints
- **Competitive parity**: Whisper Flow and other apps support this feature

## Requirements

### Functional Requirements

#### FR-1: Fn Key Detection
- **Description**: System shall detect Fn key press and release events system-wide
- **Implementation**: NSEvent global monitor with keyCode 63 detection
- **Acceptance Criteria**:
  - Fn key press triggers recording start/stop (based on recording mode)
  - Detection works when FluidVoice is not the active application
  - No interference with system Fn key functions (brightness, volume, etc.)

#### FR-2: Settings Integration
- **Description**: Users can select "Fn" as their global hotkey option
- **Implementation**: Extend HotKeyManager and SettingsView
- **Acceptance Criteria**:
  - "Fn" appears in hotkey selection dropdown/picker
  - Selecting Fn disables standard HotKey library hotkey
  - Settings persist across app restarts
  - Clear UI indication when Fn key is active hotkey

#### FR-3: Permission Management
- **Description**: Handle Input Monitoring permission gracefully
- **Implementation**: Permission detection, request flow, and user guidance
- **Acceptance Criteria**:
  - App detects Input Monitoring permission status
  - Clear explanation of why permission is needed
  - Graceful fallback if permission denied
  - Helpful guidance for granting permission in System Preferences

### Non-Functional Requirements

#### NFR-1: Performance
- **Requirement**: Fn key monitoring shall not noticeably impact system performance
- **Acceptance Criteria**: 
  - CPU usage increase < 1% during monitoring
  - No measurable impact on key input latency
  - Memory usage increase < 5MB

#### NFR-2: Reliability  
- **Requirement**: Fn key detection shall be reliable across different Mac hardware
- **Acceptance Criteria**:
  - Works on MacBook Pro, MacBook Air, iMac keyboards
  - Consistent behavior across macOS versions (14.0+)
  - Handles system sleep/wake cycles correctly

#### NFR-3: Security
- **Requirement**: Input monitoring shall be implemented securely
- **Acceptance Criteria**:
  - Only monitors Fn key events (keyCode 63)
  - No logging or storage of other keyboard inputs
  - Immediate cleanup when feature disabled

## User Experience Design

### Settings Flow

1. **Hotkey Selection**
   ```
   Global Hotkey: [Dropdown]
   Options: ⌘⇧Space, ⌘Space, ⌥Space, F13, F14, F15, Fn
   ```

2. **Fn Key Selection**
   ```
   ⚠️  Fn Key Selection requires Input Monitoring permission
   
   FluidVoice needs permission to monitor keyboard input 
   system-wide to detect the Fn key.
   
   [Grant Permission] [Cancel]
   ```

3. **Permission Granted**
   ```
   ✅ Fn key hotkey is now active
   Press Fn to start/stop recording
   ```

4. **Permission Denied**
   ```
   ❌ Fn key requires Input Monitoring permission
   
   To use Fn key as hotkey:
   1. Open System Preferences > Security & Privacy
   2. Click "Input Monitoring" 
   3. Enable FluidVoice
   4. Restart FluidVoice
   
   [Open System Preferences] [Use Different Hotkey]
   ```

### Error States

#### Permission Revoked
```
⚠️  Input Monitoring permission was revoked
Fn key hotkey is no longer available.

[Restore Permission] [Choose Different Hotkey]
```

#### System Compatibility
```
❌ Fn key detection not supported on this system
Please choose a different hotkey option.

[Select Alternative Hotkey]
```

## Technical Implementation

### Architecture Changes

```swift
// HotKeyManager.swift - Extended
class HotKeyManager {
    private var hotKey: HotKey?                    // Existing
    private var fnKeyMonitor: Any?                 // New
    private var currentHotkeyType: HotkeyType      // New
    
    enum HotkeyType {
        case standard(key: Key, modifiers: NSEvent.ModifierFlags)
        case fnKey
    }
    
    func setupHotkey(type: HotkeyType) { /* Implementation */ }
    func requestInputMonitoringPermission() { /* Implementation */ }
}
```

### Settings Integration

```swift
// SettingsView.swift - Extended
struct SettingsView {
    @State private var selectedHotkey: String = "⌘⇧Space"
    @State private var showingFnPermissionAlert = false
    
    private let hotkeyOptions = [
        "⌘⇧Space", "⌘Space", "⌥Space", 
        "F13", "F14", "F15", "Fn"
    ]
}
```

### Permission Utilities

```swift
// New: InputMonitoringPermission.swift
class InputMonitoringPermission {
    static func checkPermission() -> Bool
    static func requestPermission() -> Bool
    static func openSystemPreferences()
}
```

## Testing Strategy

### Unit Tests
- HotKeyManager Fn key setup
- Permission status detection
- Settings persistence
- Error state handling

### Integration Tests  
- End-to-end hotkey functionality
- Permission flow testing
- Settings UI integration
- Recording trigger validation

### Manual Testing
- Different Mac hardware (MacBook Pro, Air, iMac)
- macOS version compatibility (14.0, 14.1, 14.2+)  
- Permission grant/revoke scenarios
- System sleep/wake behavior

## Risks and Mitigation

### Risk 1: Permission Complexity
- **Impact**: Users may not grant Input Monitoring permission
- **Mitigation**: Clear explanations, helpful guidance, fallback options
- **Monitoring**: Track permission grant rates in analytics

### Risk 2: Hardware Compatibility
- **Impact**: Fn key behavior may vary across Mac models
- **Mitigation**: Extensive testing on different hardware
- **Monitoring**: User feedback collection for compatibility issues

### Risk 3: System Updates
- **Impact**: macOS updates may change Fn key behavior
- **Mitigation**: Version-specific testing, graceful fallbacks
- **Monitoring**: Monitor for system update impact reports

## Success Metrics

### Adoption Metrics
- **Target**: 40% of users enable Fn key hotkey within 30 days
- **Measurement**: Settings analytics

### Reliability Metrics  
- **Target**: <1% Fn key detection failures
- **Measurement**: Error logging and user reports

### User Satisfaction
- **Target**: Positive feedback on Fn key functionality
- **Measurement**: User reviews and support tickets

## Future Enhancements

### Phase 2 Features
- **Fn + Key Combinations**: Support Fn+F1, Fn+F2, etc.
- **Custom Fn Actions**: Multiple actions triggered by Fn key
- **Advanced Settings**: Fn key behavior customization

### Integration Opportunities
- **Touch Bar Support**: Fn key behavior on Touch Bar Macs
- **External Keyboards**: Support for third-party keyboard Fn keys
- **Accessibility**: Enhanced accessibility features with Fn key

---

**Acceptance Criteria Summary:**
- ✅ Fn key detected system-wide
- ✅ Settings UI includes Fn key option  
- ✅ Permission handling implemented
- ✅ Works across different Mac hardware
- ✅ Performance impact minimal
- ✅ Comprehensive error handling
- ✅ User guidance for setup process