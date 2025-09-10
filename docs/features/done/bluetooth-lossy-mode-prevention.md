# Bluetooth Lossy Mode Prevention

## Summary
Prevents macOS from switching Bluetooth headphones to lossy HFP mode during FluidVoice recording by temporarily changing system default input device.

## Problem
When using Bluetooth headphones (e.g., Bose) for music playback and FluidVoice for recording:
- User selects "MacBook Pro Microphone" in FluidVoice settings
- Recording starts → macOS activates Bluetooth HFP mode (lossy ~64kbps audio)
- Music quality drops dramatically during and after recording
- Even after recording stops, headphones remain in lossy mode

## Root Cause
- macOS prioritizes Bluetooth devices when ANY audio input session starts
- `AVAudioEngine.inputNode` queries system default input device
- If Bluetooth headphones are system default, macOS activates HFP mode
- Application-level device selection happens too late in the process

## Solution
**Temporary System Default Switching:**
1. **Before Recording**: Save current system default input device
2. **Switch Default**: Set system default to FluidVoice's selected device (Built-in Mic)
3. **Record**: AVAudioEngine uses correct device, no Bluetooth activation
4. **After Recording**: Restore original default (unless it was Bluetooth)

## Implementation

### Core Components
- `setSystemDefaultInputDevice()` - Temporarily switches system default
- `restoreSystemDefaultInputDevice()` - Smart restoration logic
- `isBluetoothDevice()` - Detects Bluetooth devices by transport type

### Key APIs Used
```swift
// CoreAudio Hardware Abstraction Layer
kAudioHardwarePropertyDefaultInputDevice
kAudioDevicePropertyTransportType
AudioObjectGetPropertyData()
AudioObjectSetPropertyData()
```

### Smart Restoration Logic
```swift
// Only restore non-Bluetooth devices
if isBluetoothDevice(originalDevice) {
    // Keep Built-in Mic as default to prevent lossy mode
    // User can manually change in System Settings if needed
} else {
    // Safe to restore original device
    setDefaultInputDevice(originalDevice)
}
```

## Results
- ✅ **No Bluetooth activation** during recording
- ✅ **Music stays high quality** (A2DP mode preserved)
- ✅ **Correct microphone used** (Built-in Mic as selected)
- ✅ **No user intervention** required
- ✅ **Smart restoration** prevents post-recording lossy mode

## User Experience
1. User has Bluetooth headphones connected for music
2. FluidVoice recording starts → **no audio quality drop**
3. Recording completes → **music remains high quality**
4. System preserves optimal audio configuration

## Technical Details

### Files Modified
- `Sources/AudioRecorder.swift` - Core implementation
- Added CoreAudio import for HAL APIs
- Integrated with existing recording workflow

### Integration Points
- `startRecording()` - System default switching before AVAudioEngine start
- `stopRecording()` - Smart restoration after recording completion
- Error handling for API failures with graceful fallback

### Performance Impact
- Minimal: ~1ms overhead for device switching
- No impact on recording latency or quality
- Logging provides full visibility into device operations

## Edge Cases Handled
- **API Failures**: Graceful fallback to current behavior
- **Missing Devices**: Validation before switching
- **Multiple Bluetooth Devices**: Transport type detection
- **System Changes**: Robust error handling

## Status
✅ **Completed** - Integrated in production build with selective switching logic
🎯 **Result**: Bluetooth lossy mode eliminated during FluidVoice recording

## Implementation Evolution

### Fixed Implementation Issue (v2)

**FIXED**: Updated implementation now uses selective switching logic.

### Previous Problem (v1)
Initial implementation **always** switched system default input device, even when unnecessary:

```swift
// v1 (overly aggressive):
savedDefaultInputDevice = try getCurrentDefaultInputDevice()  // Always save
try setDefaultInputDevice(selectedDeviceID)                   // Always switch

// v2 (selective - IMPLEMENTED):
let currentDefault = try getCurrentDefaultInputDevice()
if isBluetoothDevice(currentDefault) {
    // Only switch when current default is Bluetooth
    savedDefaultInputDevice = currentDefault
    try setDefaultInputDevice(selectedDeviceID)
} else {
    // No system-level switch needed - use AudioUnit property only
    try setSelectedInputDevice()
}
```

### Previous Impact (v1)
- **Unnecessary system changes** when current default is harmless (USB mic, built-in mic, etc.)
- **User system settings disrupted** even when Bluetooth workaround not needed
- **Overly invasive** behavior for non-Bluetooth scenarios

### Fixed Logic (v2)
System default switching now **only** occurs when:
1. Current system default input device is Bluetooth
2. FluidVoice needs to use a different device

For non-Bluetooth system defaults, explicit AudioUnit device setting is used instead.

### Current Behavior (v2)
- ✅ **Current Default: Bluetooth, FluidVoice: Built-in** → System switch (prevents HFP)
- ✅ **Current Default: USB Mic, FluidVoice: USB Mic** → AudioUnit only (no system changes)
- ✅ **Current Default: Built-in, FluidVoice: External** → AudioUnit only (no system changes)

## Future Considerations
- Optional user preference for restoration behavior
- Support for multiple simultaneous Bluetooth devices
- Integration with audio device change notifications