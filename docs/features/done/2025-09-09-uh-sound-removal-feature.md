# Uh Sound Removal Feature

## Problem Statement

Users frequently include filler sounds like "uh", "uhm", "äh", and similar vocal hesitations in their recordings. These filler sounds clutter the transcribed text and reduce readability, especially for professional or formal content. Current post-processing requires manual editing, which breaks the seamless voice-to-text workflow.

## Technical Solution

### Architecture Overview

```
Audio Input → Transcription → Uh Detection → Text Cleanup → Final Output
```

### Implementation Approach

**Phase 1: Pattern-Based Detection**
- Implement regex patterns for common filler sounds in multiple languages
- German: "äh", "ähm", "öh", "ehm"
- English: "uh", "um", "er", "ah"
- Pattern matching with word boundaries to avoid false positives

**Phase 2: Context-Aware Filtering**
- Distinguish between filler sounds and legitimate words
- Example: "uh-oh" should be preserved, standalone "uh" should be removed
- Consider surrounding punctuation and sentence structure

**Phase 3: User Configuration**
- Toggle feature on/off in settings
- Language-specific filter sets
- Sensitivity levels (aggressive, moderate, conservative)

### Technical Components

**FillerSoundProcessor.swift**
```swift
struct FillerSoundProcessor {
    func removeFillerSounds(from text: String, language: TranscriptionLanguage) -> String
    func detectFillerPatterns(in text: String) -> [FillerMatch]
}
```

**Settings Integration**
- Add toggle in SettingsView
- Persist preference in UserDefaults
- Apply during transcription pipeline

### Integration Points

- **TranscriptionService**: Apply filtering after transcription, before clipboard
- **VocabularyCorrector**: Coordinate with existing correction pipeline
- **SettingsView**: Add configuration UI

## Success Criteria

### Functional Requirements
- [ ] Removes common German filler sounds ("äh", "ähm", "öh")
- [ ] Removes common English filler sounds ("uh", "um", "er")
- [ ] Preserves legitimate words that contain filler patterns
- [ ] User can enable/disable feature
- [ ] Language-specific filtering

### Performance Requirements
- [ ] Processing adds < 50ms to transcription pipeline
- [ ] No impact on transcription accuracy for legitimate words
- [ ] Memory usage remains within app limits

### Quality Requirements
- [ ] False positive rate < 2% (legitimate words incorrectly removed)
- [ ] False negative rate < 10% (filler sounds not detected)
- [ ] Handles edge cases (punctuation, capitalization, word boundaries)

## Testing Strategy

### Unit Tests
- Pattern matching accuracy across languages
- Edge case handling (punctuation, capitalization)
- Performance benchmarks for various text lengths
- Configuration state management

### Integration Tests
- End-to-end transcription pipeline with filler removal
- Settings persistence and UI interaction
- Compatibility with VocabularyCorrector

### Manual Testing Scenarios
- Record samples with known filler sounds
- Test multilingual content
- Verify UI toggle functionality
- Test various filler sound densities

## Implementation Priority

**Priority**: Medium-High
**Effort**: Small (2-3 development sessions)
**Impact**: High user satisfaction improvement

This feature addresses a common pain point without requiring complex ML models or external dependencies, fitting well within FluidVoice's privacy-first approach.