# Miniwindow Recording Indicator with Waveform

**Priority**: Medium  
**Status**: Not Started  
**Estimated Effort**: 3-4 days  
**Target Release**: v1.3.0  

## Overview

Add a small, elegant recording indicator window that appears during voice recording sessions, featuring a subtle real-time audio waveform visualization similar to WhisperFlow's interface.

## Current State vs. Desired State

**Current Recording UX:**
- Large modal recording window (RecordingView)
- Blocks other applications during recording
- No visual feedback of audio levels
- User cannot see other apps while recording

**Desired Recording UX:**
- Small, non-intrusive miniwindow overlay
- Always-on-top during recording
- Real-time waveform showing audio input levels
- Allows interaction with other applications
- Elegant, minimal design inspired by WhisperFlow

## Technical Requirements

### Window Management
- **Window Type**: `NSPanel` with `NSWindow.Level.floating` (always on top)
- **Size**: ~200x80 pixels (compact, unobtrusive)
- **Position**: Center-top of screen or user-configurable
- **Behavior**: Draggable, non-resizable, auto-hide when not recording
- **Integration**: Replace current RecordingView modal with miniwindow option

### Waveform Visualization
- **Real-time Audio Analysis**: 
  - Integrate with existing `AudioRecorder` AVAudioEngine
  - Sample audio levels at 60fps for smooth animation
  - Use `AVAudioPCMBuffer` analysis for amplitude detection
- **Visual Design**:
  - Subtle waveform bars (10-15 bars across window width)
  - Smooth amplitude-based height animation
  - Color: Accent color with opacity gradient
  - Background: Semi-transparent dark overlay
- **Performance**: Efficient Core Animation, minimal CPU impact

### User Controls
- **Recording Controls**: Stop button, pause/resume (if supported)
- **Visual States**: Recording (animated waveform), processing (spinner), error (red indicator)
- **Keyboard Shortcuts**: Space (stop), Escape (cancel) - same as current
- **Settings**: Toggle between miniwindow vs. full recording view

## Implementation Plan

### Phase 1: Basic Miniwindow (1-2 days)
1. **Create `MiniRecordingWindow.swift`**:
   - `NSPanel` subclass with floating level
   - Basic recording controls (stop/cancel buttons)
   - Integration with existing `AudioRecorder`
   - Replace modal RecordingView usage in hotkey flow

2. **Window Management**:
   - Auto-positioning and draggable behavior
   - Proper cleanup when recording ends
   - Handle multiple display setups

### Phase 2: Waveform Integration (2 days)  
1. **Audio Analysis Extension**:
   - Extend `AudioRecorder` with real-time level monitoring
   - Create `AudioLevelAnalyzer` for amplitude calculation
   - Ensure thread safety for UI updates

2. **Waveform View**:
   - SwiftUI `WaveformVisualizerView` with Core Animation
   - Real-time data binding with `@State` level arrays
   - Smooth animation transitions and amplitude scaling

### Phase 3: Polish & Settings (1 day)
1. **Settings Integration**:
   - Add miniwindow preference in `SettingsView`
   - User choice: miniwindow vs. full recording view
   - Position persistence across app launches

2. **Visual Refinements**:
   - macOS-native styling (vibrancy effects)
   - Proper dark/light mode support
   - Accessibility features (VoiceOver support)

## User Experience Flow

1. **Recording Trigger**: User presses ⌘⇧Space
2. **Miniwindow Appears**: Small window materializes at screen center-top
3. **Live Waveform**: Audio levels visualized in real-time as user speaks
4. **Background Usage**: User can interact with other apps while recording
5. **Recording Complete**: Window shows processing state, then disappears
6. **Result**: Transcribed text pasted automatically (existing behavior)

## Design References

**WhisperFlow Inspiration**:
- Compact floating window design
- Subtle waveform visualization
- Non-blocking recording experience
- Elegant, minimal aesthetic

**macOS System Consistency**:
- Follow HIG for floating panels
- Use system accent colors
- Support vibrancy and translucency
- Proper focus and accessibility behavior

## Technical Considerations

### Performance
- **Audio Processing**: Reuse existing `AudioRecorder` AVAudioEngine
- **Waveform Rendering**: Use `CADisplayLink` for smooth 60fps updates
- **Memory**: Efficient circular buffer for waveform history
- **CPU Impact**: Target <5% CPU usage during recording

### Compatibility
- **macOS Versions**: Support macOS 14+ (current target)
- **Display Setups**: Handle multiple monitors and screen configurations
- **Accessibility**: VoiceOver descriptions for recording states
- **Settings Migration**: Preserve user preferences across updates

### Integration Points
- **AudioRecorder**: Extend for real-time level monitoring
- **WindowManager**: Coordinate with existing window management
- **SettingsView**: Add miniwindow preference toggle
- **RecordingView**: Maintain as fallback option

## Success Metrics

- **User Adoption**: >80% of users prefer miniwindow after trying both options
- **Performance**: Recording UX remains responsive with <100ms UI lag
- **Usability**: Users can effectively multitask during recording sessions
- **System Impact**: Minimal CPU/battery usage during recording

## Future Enhancements

- **Customization**: User-configurable window size and position
- **Advanced Waveform**: Frequency analysis, noise level indication  
- **Quick Actions**: Inline transcription preview, correction shortcuts
- **Multiple Windows**: Support for concurrent recording sessions
- **Themes**: Custom color schemes and visual styles

## Files to Create/Modify

**New Files**:
- `Sources/MiniRecordingWindow.swift`
- `Sources/WaveformVisualizerView.swift`
- `Sources/AudioLevelAnalyzer.swift`

**Modified Files**:
- `Sources/AudioRecorder.swift` (real-time level monitoring)
- `Sources/WindowManager.swift` (miniwindow coordination)
- `Sources/SettingsView.swift` (miniwindow preference)
- `Sources/ContentView.swift` (recording flow integration)

## Risk Assessment

**Low Risk**:
- Building on existing AudioRecorder infrastructure
- Well-defined SwiftUI/AppKit integration patterns
- Clear user experience requirements

**Considerations**:
- Audio processing overhead during recording
- Window management complexity with existing modal system
- User preference migration and settings consistency