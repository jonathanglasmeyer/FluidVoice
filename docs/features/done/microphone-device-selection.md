# Microphone Device Selection

## Status
🔴 **NOT IMPLEMENTED** - UI exists but is non-functional

## Problem
FluidVoice has a microphone device selection dropdown in Settings, but it doesn't actually work. AudioRecorder always uses the system default input device, completely ignoring the user's selection.

This creates a confusing UX where users can select different microphones but the selection has no effect on recording.

## Current Implementation
- SettingsView shows microphone picker with `@AppStorage("selectedMicrophone")`
- AudioRecorder uses `AVAudioRecorder` which can only use system default device
- Selection is saved to UserDefaults but never read by recording logic
- AudioDeviceManager provides intelligent device selection but ignores user choice

## Technical Issue
`AVAudioRecorder` (current implementation) can only record from the system's default input device. To support custom device selection, AudioRecorder must be rebuilt using `AVCaptureSession`.

## Proposed Solution

### Architecture Change
Replace `AVAudioRecorder` with `AVCaptureSession` in AudioRecorder.swift:

```swift
class AudioRecorder {
    private var captureSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var audioInput: AVCaptureDeviceInput?
}
```

### User Experience
1. **System Default**: When user selects "System Default", use intelligent device selection (current AudioDeviceManager logic)
2. **Specific Device**: When user selects a specific microphone, use that device directly
3. **Fallback**: If selected device becomes unavailable, fall back to system default with user notification

### Settings Integration
```swift
func getSelectedInputDevice() -> AVCaptureDevice? {
    let selectedID = UserDefaults.standard.string(forKey: "selectedMicrophone")
    
    if selectedID?.isEmpty != false {
        // System Default - use intelligent selection
        return findBestInputDevice()
    } else {
        // User selected specific device
        return AVCaptureDevice(uniqueID: selectedID!)
    }
}
```

### Logging & Debugging
- Log selected device on recording start
- Show device name in logs for debugging
- Warning when selected device not available

## Implementation Tasks
1. Replace `AVAudioRecorder` with `AVCaptureSession` in AudioRecorder
2. Implement device selection logic that respects UserDefaults
3. Add fallback handling for disconnected devices
4. Update audio level monitoring for new architecture
5. Test with multiple device types (built-in, USB, Bluetooth)

## Testing Scenarios
- Built-in MacBook microphone
- USB microphones (Blue Yeti, etc.)
- Bluetooth headsets (AirPods, etc.)  
- Device disconnect/reconnect during recording
- System default change while app is running

## Expected Outcome
Users can select any available microphone device and FluidVoice will actually use it for recording, matching the behavior of professional audio applications like Microsoft Teams, Wispr Flow, etc.