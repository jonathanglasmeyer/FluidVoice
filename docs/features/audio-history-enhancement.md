# Audio History Enhancement

**Status:** Planned  
**Priority:** Medium  
**Effort:** Large (3-4 days)  
**Category:** User Experience  

## Problem

Currently, the transcription history only shows text results and basic metadata. Users cannot:
- Listen to the original audio to verify transcription accuracy
- Compare transcription quality across different providers/models
- Access performance metrics to understand transcription speed
- Debug transcription issues with problematic audio

## Solution

Enhance the transcription history with audio file preservation and performance metrics display.

## Current State Analysis

**Data Structure (`TranscriptionRecord.swift`)**:
- ✅ Already has basic fields: `text`, `date`, `provider`, `duration`, `modelUsed`
- ✅ Currently stores duration as `TimeInterval?`
- ❌ Missing: Audio file path, performance metrics, audio file management

**Performance System**:
- ✅ Already has `PerformanceMetrics` struct in `SpeechToTextService.swift`
- ✅ Captures: `audioDuration`, `transcriptionTime`, `realTimeFactor`, `wordsPerSecond`, etc.
- ❌ Performance data is only logged, not stored in records

**Audio File Handling**:
- ✅ `AudioRecorder` creates temporary files: `recording_[timestamp].m4a`
- ✅ Files stored in `FileManager.default.temporaryDirectory`
- ❌ Audio files are deleted after transcription (not preserved)

## Implementation Plan

### Phase 1: Data Structure Enhancement

1. **Extend `TranscriptionRecord`**:
   ```swift
   // New fields to add:
   var audioFilePath: String?        // Path to preserved audio file
   var transcriptionTime: TimeInterval?  // Time taken to transcribe
   var realTimeFactor: Double?       // RTF performance metric
   var wordsPerSecond: Double?       // WPS performance metric
   var millisecondsPerWord: Double?  // ms/word performance metric
   ```

2. **Audio File Management System**:
   - **Permanent Storage**: Move audio files from temp to app-specific directory
   - **Location**: `~/Library/Application Support/FluidVoice/Audio/[YYYY-MM]/`
   - **Naming**: `[UUID].m4a` (linked by record ID)
   - **Retention**: User-configurable (30/90/365 days, or unlimited)

### Phase 2: Performance Data Integration

3. **Capture Performance Metrics**:
   - Modify `DataManager.saveTranscriptionRecord()` to accept `PerformanceMetrics`
   - Update all transcription services to pass performance data
   - Store metrics alongside transcription text

4. **Audio File Preservation**:
   - Modify audio workflow to copy temp files to permanent storage
   - Clean up temp files after copying
   - Handle storage space management

### Phase 3: UI Enhancement

5. **History UI Updates**:
   ```swift
   // New UI components:
   - Audio playback button (play/pause/stop)
   - Audio waveform visualization (optional)
   - Performance metrics display:
     * Transcription time: "2.3s"
     * Real-time factor: "RTF: 0.46"
     * Words per second: "16.7 WPS"
     * Speed indicator: "3x faster than real-time"
   ```

6. **Audio Playback Controls**:
   - **AVAudioPlayer** integration for M4A playback
   - **Playback states**: Ready, Playing, Paused, Stopped
   - **Visual feedback**: Progress bar, time display
   - **Keyboard shortcuts**: Spacebar to play/pause

### Phase 4: Storage Management

7. **Storage & Cleanup System**:
   - **Settings panel**: Audio retention policy
   - **Storage usage**: Display total audio file size
   - **Cleanup options**: Manual/automatic deletion of old audio
   - **Export functionality**: Save audio files to user location

## Expected User Experience

**History View Enhancement**:
```
┌─────────────────────────────────────────────────────────┐
│ [Date] [Provider Badge] [Duration] [▶️ Audio] [RTF: 0.46] │
│ "This is the transcription text..."                     │
│ 📊 2.3s transcription • 16.7 WPS • 3x faster than RTF   │
└─────────────────────────────────────────────────────────┘
```

**Audio Playback Integration**:
- Click audio button → Inline player appears
- Progress bar shows current position vs audio length  
- Compare transcription text with actual audio
- Identify transcription accuracy issues

**Performance Insights**:
- Compare different providers/models performance
- Identify slow transcriptions for optimization
- Track performance trends over time

## Technical Implementation Details

**Storage Structure**:
```
~/Library/Application Support/FluidVoice/
├── Audio/
│   ├── 2024-12/
│   │   ├── [uuid1].m4a
│   │   └── [uuid2].m4a
│   └── 2025-01/
│       └── [uuid3].m4a
└── AudioMetadata.plist  # File metadata cache
```

**Database Migration**:
```swift
// SwiftData will handle schema migration automatically
// New optional fields will default to nil for existing records
```

**Performance Integration Points**:
1. `SpeechToTextService.transcribeRaw()` - Already captures metrics
2. `DataManager.saveTranscriptionRecord()` - Needs metrics parameter
3. All provider-specific services - Pass metrics up the chain

## Benefits

- **Quality Assurance**: Compare transcription accuracy with original audio
- **Performance Monitoring**: Track which providers/models perform best
- **Debugging**: Replay problematic audio for troubleshooting
- **User Trust**: Transparency into transcription speed and accuracy
- **Data Analysis**: Long-term performance trends and optimization opportunities

## Considerations

- **Storage Space**: Audio files will consume significant disk space over time
- **Privacy**: Audio files contain sensitive voice data - need secure handling
- **Performance**: Loading many audio files could impact UI responsiveness
- **Cleanup**: Need robust retention policies to prevent unlimited storage growth

## Dependencies

- Existing `TranscriptionRecord` and `DataManager` systems
- Current `PerformanceMetrics` implementation
- `AVAudioPlayer` for playback functionality
- File system permissions for audio storage directory

## Related Features

- History search and filtering
- Settings for audio retention policies
- Export functionality for audio files
- Performance analytics dashboard