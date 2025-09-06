# Parakeet Model Download UI Blocking Bug

**Status**: Open  
**Severity**: High  
**Component**: MLXModelManager, SettingsView  
**Date**: 2025-09-06  

## Summary

When clicking "Download Parakeet v3 Model" button in Settings, the UI shows spinning cursor and blocks for 2-3 seconds during Python environment setup, making the interface unresponsive.

## Symptoms

- ✅ **Download works correctly** - Model downloads successfully (~600MB)
- ✅ **Progress feedback works** - UI shows spinner and progress text
- ❌ **UI blocks with spinning cursor** - 2-3 second freeze during uv setup
- ❌ **User can't interact** - Settings page becomes unresponsive

## Root Cause Analysis

**Primary Issue**: `await MainActor.run { }` calls in `MLXModelManager.downloadParakeetModel()` force the detached background task to execute on the main thread.

**Technical Details**:
1. **Button uses** `Task.detached { }` to run download in background
2. **BUT** `downloadParakeetModel()` contains `await MainActor.run { }` calls for state updates
3. **Result**: Heavy `UvBootstrap.ensureVenv()` work runs on main thread despite detached task

## Current Workaround

- Download still works, just with UI blocking
- Progress feedback appears after initial blocking period
- Model downloads successfully in background after setup

## Attempted Fix

**Code Changes Made**:
- ✅ Changed `Task { }` to `Task.detached { }` in SettingsView button
- ❌ Removed `await MainActor.run { }` calls from `downloadParakeetModel()`
- ❌ Direct `@Published` property updates (should work from any thread)

**Result**: UI blocking persists despite changes

## Files Affected

- `Sources/SettingsView.swift:313-317` - Button action with `Task.detached`  
- `Sources/MLXModelManager.swift:306-379` - Download method with removed MainActor calls

## Next Steps

**Investigate**:
1. Whether `UvBootstrap.ensureVenv()` itself has MainActor dependencies
2. If `@Published` property updates require MainActor despite documentation
3. Alternative approach using separate async queue or operation queue

**Possible Solutions**:
1. Make `UvBootstrap.ensureVenv()` truly thread-safe
2. Use `DispatchQueue.global().async` instead of `Task.detached`
3. Separate progress updates from heavy computation

## Impact

- **User Experience**: Moderate - download works but feels unresponsive
- **Functionality**: Low - core download feature works correctly  
- **Priority**: Medium - affects UX but not core functionality

## Logs

```
2025-09-06 14:43:41.807 I FluidVoice[42761:23a803] [MLXModelManager] Starting Parakeet model download
2025-09-06 14:43:41.815 I FluidVoice[42761:23a912] [MLXModelManager] uv: Syncing project dependencies via uv sync…
2025-09-06 14:43:47.350 I FluidVoice[42761:23a803] [MLXModelManager] Found 1 MLX models, total size: <private>
```

Download completes successfully with ~6 second total time, but UI blocks for first 2-3 seconds.