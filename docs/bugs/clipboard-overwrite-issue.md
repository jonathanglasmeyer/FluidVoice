# Bug Report: Clipboard Content Overwritten During Transcription

**Date:** 2025-09-06  
**Severity:** High - User Experience Impact  
**Component:** Clipboard Management / PasteManager  

## Issue Description

FluidVoice overwrites the user's clipboard content during transcription processing, causing loss of previously copied data that users may need to paste elsewhere.

## Expected Behavior

- User's existing clipboard content should be preserved
- Transcription result should only be placed in clipboard if user explicitly chooses clipboard mode
- No unintended clipboard modifications during processing

## Actual Behavior

- Transcription automatically overwrites clipboard content
- User loses previously copied data (text, images, files)
- Clipboard state changes without user consent

## Impact

- **Data Loss**: Users lose important clipboard content they intended to use
- **Workflow Disruption**: Breaks user's copy-paste workflow in other applications
- **User Trust**: Unexpected behavior reduces confidence in the application
- **Productivity Loss**: Users must re-copy lost clipboard content

## User Scenarios Affected

1. **Multi-step workflow**: User copies data, starts transcription, loses copied data
2. **Research tasks**: User copies reference material, transcription overwrites it
3. **Document editing**: User copies formatting/content, transcription interferes
4. **Image/file operations**: User copies non-text content, gets overwritten by text

## Potential Root Causes

1. **Aggressive Clipboard Management**: PasteManager always writes to clipboard
2. **Missing User Preference**: No option to disable clipboard auto-write  
3. **State Management**: Not preserving/restoring original clipboard content
4. **Mode Confusion**: Auto-paste vs clipboard-only modes not properly distinguished

## Investigation Areas

- `Sources/PasteManager.swift` - Clipboard write behavior
- Transcription completion handlers - When clipboard gets modified
- User preference system - Clipboard behavior settings
- Express Mode vs Manual Mode - Different clipboard strategies

## Reproduction Steps

1. Copy some text/content to clipboard
2. Trigger FluidVoice transcription (⌘⇧Space)  
3. Complete transcription
4. Attempt to paste original content - observe it's gone

## Related Files

- `Sources/PasteManager.swift` - Clipboard operations
- `Sources/SpeechToTextService.swift` - Transcription completion
- Settings/preferences - User control options

## Potential Solutions

1. **Clipboard Preservation**: Save original clipboard, restore if transcription cancelled
2. **User Control**: Add preference to disable automatic clipboard writing  
3. **Mode Distinction**: Only write to clipboard in explicit clipboard mode
4. **Smart Detection**: Ask user if they want to overwrite non-empty clipboard

## Priority

High - This affects core user workflow and causes data loss, which significantly impacts user experience and trust in the application.