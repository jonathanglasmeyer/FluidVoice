# Audio Level Metering for Mini Recording Indicator

**Priority**: High  
**Status**: ✅ COMPLETED  
**Estimated Effort**: 1-2 days  
**Target Release**: v1.2.1  
**Completed**: 2025-09-10  

## Overview

Connect real-time audio levels from the microphone to the Mini Recording Indicator's vertical bars, creating a dynamic waveform visualization during recording. The UI framework exists but currently shows static bars for testing.

## Current State vs. Desired State

**Current Implementation:**
- MiniRecordingIndicator window with glass effect ✅
- 5 vertical bars with static heights (hardcoded pattern)
- `audioLevel` property and `updateAudioLevel()` method ready but unused
- AudioRecorder captures audio but doesn't measure levels

**Desired Implementation:**
- Real-time audio level measurement from microphone input
- Dynamic bar heights responding to voice volume
- Smooth rolling waveform effect across the 5 bars
- Natural, responsive animation during speech

## Technical Solution

### Audio Level Measurement

**In AudioRecorder.swift:**
```swift
// Add audio tap to measure levels during recording
private func setupAudioLevelMeasurement() {
    // Install tap on input node to measure audio levels
    audioEngine.inputNode.installTap(
        onBus: 0,
        bufferSize: 512,
        format: inputFormat
    ) { [weak self] buffer, _ in
        self?.measureAudioLevel(from: buffer)
    }
}

private func measureAudioLevel(from buffer: AVAudioPCMBuffer) {
    guard let channelData = buffer.floatChannelData else { return }
    
    let channelCount = Int(buffer.format.channelCount)
    let frameLength = Int(buffer.frameLength)
    
    // Calculate RMS (Root Mean Square) for volume level
    var sum: Float = 0
    for channel in 0..<channelCount {
        for frame in 0..<frameLength {
            let sample = channelData[channel][frame]
            sum += sample * sample
        }
    }
    
    let rms = sqrt(sum / Float(channelCount * frameLength))
    let decibels = 20 * log10(rms)
    
    // Normalize to 0.0-1.0 range (-60dB to 0dB)
    let normalizedLevel = max(0, min(1, (decibels + 60) / 60))
    
    // Update indicator on main thread
    DispatchQueue.main.async { [weak self] in
        self?.miniIndicator?.updateAudioLevel(normalizedLevel)
    }
}
```

### Rolling Waveform Buffer

**In MiniRecordingIndicator.swift:**
```swift
class MiniRecordingIndicator: NSObject, ObservableObject {
    // Circular buffer for rolling waveform effect
    @Published private var audioLevelBuffer: [Float] = Array(repeating: 0.0, count: 5)
    private var bufferUpdateTimer: Timer?
    
    func updateAudioLevel(_ level: Float) {
        // Smooth the input level to reduce jitter
        let smoothedLevel = (audioLevel * 0.7) + (level * 0.3)
        audioLevel = smoothedLevel
        
        // Update buffer for rolling effect (shift left, add new)
        audioLevelBuffer.removeLast()
        audioLevelBuffer.insert(smoothedLevel, at: 0)
    }
    
    func show() {
        // ... existing code ...
        
        // Start buffer animation timer (60fps)
        bufferUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }
    
    func hide() {
        bufferUpdateTimer?.invalidate()
        bufferUpdateTimer = nil
        // ... existing code ...
    }
}
```

### Dynamic Bar Heights

**In MiniIndicatorView:**
```swift
struct MiniIndicatorView: View {
    @ObservedObject var indicator: MiniRecordingIndicator
    
    private func calculateBarHeight(for index: Int) -> CGFloat {
        // Get level from buffer (with bounds checking)
        let level = indicator.audioLevelBuffer[safe: index] ?? 0.0
        
        // Apply easing curve for more natural response
        let easedLevel = easeInOutQuad(level)
        
        // Add subtle idle animation when no audio
        let idleOffset = sin(Date().timeIntervalSince1970 * 2 + Double(index)) * 2
        let baseHeight = minBarHeight + (level < 0.1 ? idleOffset : 0)
        
        // Calculate final height
        return baseHeight + (maxBarHeight - minBarHeight) * easedLevel
    }
    
    private func easeInOutQuad(_ t: Float) -> CGFloat {
        let t = CGFloat(t)
        return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }
}
```

## Implementation Steps

### Phase 1: Audio Level Measurement (4 hours)
1. Add audio tap to AudioRecorder's `startRecording()` method
2. Implement RMS-based level calculation
3. Test decibel normalization ranges with actual speech
4. Verify thread safety for UI updates

### Phase 2: Buffer Management (3 hours)
1. Implement circular buffer in MiniRecordingIndicator
2. Add smoothing algorithm to reduce jitter
3. Create timer-based update mechanism
4. Test buffer shifting performance

### Phase 3: Visual Polish (3 hours)
1. Apply easing curves for natural movement
2. Add idle animation for visual interest
3. Fine-tune min/max heights for optimal visibility
4. Test with various voice volumes and speaking patterns

### Phase 4: Integration & Testing (2 hours)
1. Connect AudioRecorder to MiniRecordingIndicator
2. Ensure proper cleanup on recording stop
3. Test with Express Mode recording flow
4. Verify CPU usage remains low (<5%)

## Success Criteria

- **Responsiveness**: Bars react within 50ms of audio input
- **Smoothness**: 60fps animation without stuttering
- **Accuracy**: Visual levels match perceived volume
- **Performance**: <5% CPU usage during recording
- **Reliability**: No memory leaks or retained references

## Testing Strategy

### Unit Tests
- Audio level calculation accuracy
- Buffer rotation logic
- Normalization ranges

### Integration Tests
- AudioRecorder → MiniIndicator data flow
- Timer lifecycle management
- Memory cleanup on stop

### Manual Testing
- Various speaking volumes (whisper to loud)
- Background noise handling
- Different microphone types
- Quick start/stop cycles

## Performance Considerations

- **Audio Tap**: Use small buffer size (512 samples) for low latency
- **Threading**: Measure levels on audio thread, update UI on main
- **Smoothing**: Balance between responsiveness and jitter reduction
- **Timer**: Consider CADisplayLink for smoother animations

## Files to Modify

- `Sources/AudioRecorder.swift` - Add level measurement tap
- `Sources/MiniRecordingIndicator.swift` - Implement buffer and animation
- `Sources/ContentView.swift` - Wire up connection (may already exist)

## Future Enhancements

- Frequency-based visualization (spectrum analyzer)
- Peak hold indicators
- Stereo level display for stereo mics
- Configurable sensitivity/range
- Color coding for volume ranges (green/yellow/red)