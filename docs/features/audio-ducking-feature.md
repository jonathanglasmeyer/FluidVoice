# Audio Ducking During Recording

## Problem Statement

When recording voice input, background audio from music apps (Spotify, Apple Music, YouTube) can interfere with transcription accuracy. Users currently need to manually pause or lower volume of other applications before recording, creating friction in the voice workflow.

## Technical Solution

### Core Implementation
- **AudioDuckingManager** class following existing `MicrophoneVolumeManager` pattern
- Integration with Core Audio APIs for system-wide audio control
- Optional feature controlled by UserDefaults (like `autoBoostMicrophoneVolume`)

### Technical Approach
1. **Core Audio Integration**
   - Use `AudioHardwarePropertyListenerProc` for system audio events
   - `AudioObjectSetPropertyData` for audio device volume control
   - Target system output devices and running audio applications

2. **Application-Level Ducking**
   - Identify active audio apps via `NSRunningApplication`
   - Control volume via AppleScript for known apps (Spotify, Music, YouTube)
   - Fallback to system-wide output volume reduction

3. **Integration Points**
   - Hook into `AudioRecorder.startRecording()` - duck audio before recording starts
   - Hook into `AudioRecorder.stopRecording()` - restore audio levels
   - Follow same error handling pattern as microphone volume boost

### Architecture
```swift
class AudioDuckingManager: ObservableObject {
    static let shared = AudioDuckingManager()
    
    func duckSystemAudio() async
    func restoreSystemAudio() async
    
    private var originalLevels: [String: Float] = [:]
    private let duckingLevel: Float = 0.3 // 30% of original
}
```

## Success Criteria

- [ ] System audio (Spotify, Music, etc.) automatically reduces to 30% during recording
- [ ] Audio levels fully restore after recording completion
- [ ] Feature works with cancellation/cleanup scenarios
- [ ] User preference toggle in settings
- [ ] No audio artifacts or glitches during ducking/restoration
- [ ] Performance impact < 50ms on recording start/stop

## Testing Strategy

### Unit Tests
- AudioDuckingManager initialization and state management
- Volume level calculation and restoration logic
- Error handling for permission failures

### Integration Tests
- End-to-end recording workflow with audio ducking enabled/disabled
- Multiple audio app scenarios (Spotify + YouTube simultaneously)
- Recording cancellation with proper audio restoration

### Manual Testing Requirements
- Test with various audio applications (Spotify, Apple Music, YouTube, VLC)
- Verify system-wide volume ducking as fallback
- Test audio permission scenarios and error handling
- Validate UserDefaults toggle functionality

## Implementation Notes

### Dependencies
- Core Audio framework (already imported)
- NSRunningApplication for app detection
- AppleScript bridging for app-specific control

### User Experience
- Feature should be discoverable in settings alongside microphone volume boost
- Clear naming: "Reduce background audio during recording"
- Should work transparently without user intervention once enabled

### Technical Considerations
- Respect system audio permissions
- Handle edge cases: app crashes during recording, multiple FluidVoice instances
- Graceful degradation if Core Audio APIs fail
- Minimal performance overhead on recording workflow

## Related Features

- Builds upon existing `MicrophoneVolumeManager` architecture
- Complements auto-boost microphone volume feature
- Could integrate with future miniwindow recording indicator