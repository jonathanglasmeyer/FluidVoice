# Bug Report: Model Double Loading Despite Prefetch

**Date:** 2025-09-05
**Severity:** Minor Performance Issue
**Component:** Model Management / WhisperKit Integration

## Issue Description

The transcription system loads the model again during transcription even when the model has already been prefetched successfully.

## Expected Behavior

- Model should be prefetched once during app startup or first use
- Subsequent transcription requests should use the already-loaded model
- No additional loading time should occur for transcription

## Actual Behavior

- Model gets prefetched correctly
- During transcription, model loading occurs again
- This causes unnecessary delay before transcription starts

## Impact

- **Performance**: Extra loading time before each transcription
- **User Experience**: Longer wait times despite prefetch optimization
- **Resource Usage**: Redundant model loading operations

## Potential Root Causes

1. **Model Instance Management**: WhisperKit instance not being properly reused
2. **State Management**: Model loading state not being tracked correctly
3. **Threading Issues**: Race condition between prefetch and transcription
4. **Memory Management**: Model being released and requiring reload

## Investigation Areas

- `Sources/SpeechToTextService.swift` - WhisperKit integration
- `Sources/MLXModelManager.swift` - Model lifecycle management
- Model loading state tracking
- WhisperKit instance reuse patterns

## Reproduction Steps

1. Launch FluidVoice
2. Observe model prefetch in logs
3. Trigger transcription with hotkey
4. Observe model loading again in logs/UI

## Related Files

- Model management logic
- WhisperKit service implementation
- Transcription pipeline