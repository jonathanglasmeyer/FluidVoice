# Session Report: Parakeet Download Progress Implementation

**Date:** 2025-09-29
**Session Focus:** Implementing reliable download progress tracking for Parakeet model in Welcome Screen
**Status:** ⚠️ PARTIAL - Multiple approaches attempted, final solution needs validation

---

## Session Summary

### Tasks Worked On

1. ✅ **Welcome Screen Modal Blocking Fix** - COMPLETED & TESTED
   - Removed `runModal` from `WelcomeWindow.showWelcomeDialog()`
   - Changed to non-modal window to prevent UI thread blocking
   - Added notification-based flow for Settings opening after welcome completes
   - **Status:** Working - user confirmed progress updates now appear

2. ⚠️ **Download Progress Tracking** - NEEDS VALIDATION
   - Attempted multiple approaches to get real-time download progress
   - Final solution uses directory size polling (pragmatic fallback)
   - **Status:** Code written but NOT validated with real download

3. ✅ **Hook Configuration Fix** - COMPLETED
   - Fixed `.claude/settings.json` matcher from `"tools:Bash"` to `"Bash"`
   - Fixed hook script to output to stderr instead of stdout
   - **Status:** Validated - hook now correctly blocks `./build-dev.sh`

### Files Modified

#### Core Implementation Files
- **Sources/WelcomeWindow.swift**
  - Removed `runModal` pattern (was blocking Main Thread)
  - Changed return type from `Bool` to `Void`
  - Added `objc_setAssociatedObject` for memory retention
  - Window now non-blocking

- **Sources/WelcomeView.swift**
  - Added first-run detection in `markSetupComplete()`
  - Only posts `.welcomeCompleted` notification on first run (not Help menu)
  - Changed polling from 0.2s to 0.1s for faster updates
  - Removed `MainActor.run` wrapper (direct `await` on Published properties)
  - Progress bar now shows determinate progress when `downloadProgress > 0`

- **Sources/FluidVoiceApp.swift**
  - Updated `showHelp()` to not expect Bool return
  - Updated `showWelcomeAndSettings()` to not expect Bool return
  - Changed `onWelcomeCompleted()` to open Settings after notification

- **Sources/MLXModelManager.swift** ⚠️ CRITICAL - UNTESTED
  - **Multiple iterations attempting different progress tracking approaches:**
    1. Initially: Custom tqdm with JSON output on stdout
    2. Attempt 2: Monkey-patching `huggingface_hub.file_download.tqdm`
    3. Attempt 3: Custom tqdm with `update()` override
    4. **Final (Current):** Directory size polling approach

  - **Current implementation:**
    ```python
    # Polls ~/.cache/huggingface/ directory size every 1 second
    # Calculates progress based on expected 2400MB size
    # Background thread outputs JSON progress to stdout
    ```

  - **Key changes:**
    - `downloadParakeetModel()` made `nonisolated`
    - Removed `await withCheckedContinuation` (was blocking)
    - Added background `Task.detached` for process waiting
    - Faster polling: 0.1s for stdout, 1s for directory polling

#### Configuration Files
- **~/.claude/settings.json**
  - Fixed PreToolUse hook matcher: `"tools:Bash"` → `"Bash"`

- **~/.claude/hooks/block-build-dev.py**
  - All `print()` statements now use `file=sys.stderr`
  - Provides better error messages when blocking

#### Test Files Created
- **test_download.py** - Script to manually test HuggingFace downloads (for debugging)

### Git Commits Made

**None** - No commits were made this session. User requested to continue work until validation.

### Primary Issues Encountered

1. **tqdm Progress Bars Don't Work in Non-TTY Subprocess**
   - Standard tqdm outputs ANSI terminal codes that don't parse reliably
   - Progress bars use `\r` (carriage return) to overwrite lines
   - `readabilityHandler` never triggers because no newlines
   - `availableData` returns partial/incomplete progress bar strings

2. **HuggingFace Hub Uses TWO Separate tqdm Instances**
   - `snapshot_download` accepts `tqdm_class` parameter for **file-count bar only** (1/7, 2/7)
   - Individual file downloads use internal `huggingface_hub.file_download.tqdm` (NOT our custom class)
   - Result: Only see progress when files complete, not during large file downloads (model.safetensors 2.5GB)

3. **Monkey-Patching Didn't Work**
   - Attempted to patch `huggingface_hub.file_download.tqdm`
   - Did not receive progress updates from individual file downloads
   - Cause unclear - possibly timing/import order issue

4. **Cache Detection Issues**
   - Initially polled wrong directory (model-specific vs entire cache)
   - HuggingFace downloads to temp files first, then moves them
   - Final solution polls entire `~/.cache/huggingface/` directory

---

## Technical Changes

### Dependencies
- No new dependencies added
- Relies on existing: `huggingface_hub`, `tqdm` (Python via uv)

### Configuration Changes
1. **Hook System Fixed:**
   - `~/.claude/settings.json`: Matcher corrected
   - `~/.claude/hooks/block-build-dev.py`: stderr output

### Code Architecture Changes

1. **Welcome Flow - Non-Modal Pattern:**
   ```
   OLD: showWelcomeDialog() → runModal() → BLOCKS → returns Bool
   NEW: showWelcomeDialog() → non-modal window → returns Void
        → User completes → posts .welcomeCompleted notification
        → AppDelegate.onWelcomeCompleted() → opens Settings
   ```

2. **Download Progress - Polling Pattern:**
   ```
   Python Script:
   - Main thread: Calls snapshot_download() (blocking)
   - Background thread: Polls cache directory size every 1s
     → Calculates progress vs expected 2400MB
     → Outputs JSON to stdout

   Swift:
   - Polls stdout every 0.1s
   - Parses JSON progress updates
   - Updates @Published properties

   WelcomeView:
   - Polls MLXModelManager properties every 0.1s
   - Updates ProgressView with downloadProgress
   ```

### Services/Environment
- No services started/stopped
- No environment changes
- Uses existing uv venv at `~/Library/Application Support/FluidVoice/python_project/`

---

## Outstanding Issues & Blockers

### Critical - Needs Validation

1. **⚠️ Download Progress NOT TESTED WITH REAL DOWNLOAD**
   - Current approach: Directory size polling
   - **Problem:** User reports downloads complete in 2-3 seconds (cached?)
   - **Need:** Delete ALL caches and test with fresh 2.5GB download
   - **Validation command:**
     ```bash
     rm -rf ~/.cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v3
     # Then trigger download via app
     ```

2. **Expected Size Might Be Wrong**
   - Current: `EXPECTED_SIZE_MB = 2400`
   - Actual size uncertain - needs validation during real download
   - Logs show: `~1216MB/600MB` (clearly wrong, cache was present)

3. **Progress Bar Might Not Update Smoothly**
   - Polling interval: 1 second (directory scan is expensive)
   - During fast downloads, might jump from 0% → 20% → 100%
   - No intermediate updates during the 1s windows

### Known Limitations

1. **Progress Is Approximate**
   - Based on directory size, not actual download progress
   - Other cached models in `~/.cache/huggingface/` affect the calculation
   - Initial cache size stored, but if user has other models, math is off

2. **No File-Level Granularity**
   - Can't distinguish between "7 files" progress vs individual file progress
   - User won't see "Downloading model.safetensors: 45%" - only overall %

3. **Stderr Parsing Abandoned**
   - tqdm outputs to stderr with terminal codes
   - Too fragile to parse reliably
   - Final solution ignores stderr entirely (only logs for debugging)

---

## Continuation Points

### Immediate Next Actions (Priority Order)

1. **🔴 CRITICAL: Validate Download Progress with Real Download**
   ```bash
   # 1. Delete model completely
   rm -rf ~/.cache/huggingface/hub/models--mlx-community--parakeet-tdt-0.6b-v3

   # 2. Verify empty
   ls ~/.cache/huggingface/hub/ | grep parakeet  # Should be empty

   # 3. Rebuild app
   cd ~/Projects/FluidVoice && ./build-dev.sh

   # 4. Run app from Finder (not terminal - TCC issues)
   open FluidVoice-dev.app

   # 5. Trigger welcome screen, start download
   # 6. Watch logs for progress updates
   /usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info | grep -E "(Progress|percent|Downloading)"
   ```

2. **If Progress Still Broken:**
   - Consider simpler fallback: Indeterminate spinner with status text only
   - Or: Show file count progress only (1/7, 2/7) - at least something updates
   - Document limitation: "Downloading model (~600MB)" without percentage

3. **If Progress Works:**
   - Test edge cases:
     - Cancel download mid-way
     - Resume interrupted download
     - Network issues/timeouts
   - Adjust `EXPECTED_SIZE_MB` if needed based on actual size
   - Consider adjusting polling interval (1s might be too slow for fast networks)

4. **Commit Changes:**
   ```bash
   git add -A
   git commit -m "Fix welcome screen modal blocking and implement download progress

   - Remove runModal from WelcomeWindow (was blocking UI thread)
   - Add notification-based flow for Settings opening
   - Implement directory-polling for download progress tracking
   - Fix hook configuration (matcher and stderr output)

   Note: Download progress uses pragmatic directory size polling
   instead of tqdm parsing (tqdm doesn't work in non-TTY subprocess)"
   ```

### Research Items (If Current Approach Fails)

1. **Alternative Progress Tracking Approaches:**
   - Use `requests` library directly instead of `huggingface_hub`
   - Download files individually with progress callbacks
   - Use `urllib3` with progress hooks
   - Write custom download logic that reports progress reliably

2. **Context7 Research:**
   - Search for "huggingface_hub progress callback subprocess"
   - Look for official examples of progress tracking in non-TTY environments
   - Check if newer versions of `huggingface_hub` have better APIs

3. **Simplification Options:**
   - Accept limitation: Show indeterminate progress
   - Show file-count only (1/7, 2/7, etc.)
   - Add estimated time instead of percentage ("~2 minutes remaining")

---

## Important Context for Next Session

### Current State of Codebase

1. **Welcome Flow:**
   - ✅ Non-modal window works
   - ✅ Settings opens after first-run welcome completes
   - ✅ Help menu doesn't trigger Settings (correct behavior)

2. **Download Progress:**
   - ⚠️ Code written but NOT validated
   - ⚠️ Might work, might need adjustments
   - ⚠️ Expected size (2400MB) might be wrong

3. **Hook System:**
   - ✅ Correctly blocks `./build-dev.sh`
   - ✅ Shows helpful error messages

### Debug Logging

The code has extensive logging for debugging:

```swift
// In WelcomeView.swift - remove after validation
print("📊 WelcomeView: Updated status to: \(status)")
print("📊 WelcomeView: Updated progress to: \(percent)")

// In MLXModelManager.swift
self.logger.infoDev("📊 tqdm line: \(trimmed)")
self.logger.infoDev("✅ Parsed download progress: \(percent)%")
```

**Remember to remove these print statements** after validation!

### Test Scenarios Needed

1. **First-Run Experience:**
   - [ ] Clean install (no cached model)
   - [ ] Welcome screen appears
   - [ ] Download progress shows updates
   - [ ] Settings opens after completion

2. **Help Menu:**
   - [ ] Help → Welcome screen appears
   - [ ] Settings does NOT open after close
   - [ ] Model already cached (instant completion)

3. **Download Interruption:**
   - [ ] Start download
   - [ ] Force quit app mid-download
   - [ ] Restart app
   - [ ] Should resume download (huggingface_hub feature)

---

## Files That Need Attention

### Need Testing
- `Sources/MLXModelManager.swift` - Download progress logic entirely untested
- `Sources/WelcomeView.swift` - Polling loop tested but edge cases unknown
- `Sources/WelcomeWindow.swift` - Memory retention pattern untested

### Cleanup Needed
- Remove debug `print()` statements from `WelcomeView.swift`
- Remove verbose logging from `MLXModelManager.swift` after validation
- Consider removing `test_download.py` (or move to `Scripts/`)

### Related Documentation
- `docs/bugs/parakeet-download-ui-blocking.md` - Original bug report
- `docs/features/done/2025-09-06-parakeet-v3-multilingual-upgrade.md` - Parakeet integration

---

## Session Timeline (Key Moments)

1. **Session Start:** User complained welcome screen progress bar hung at 14%
2. **Root Cause Found:** `runModal` was blocking Main Thread, preventing @Published updates
3. **Fix #1:** Removed modal pattern → non-modal window
4. **Problem #2:** Progress still didn't update (only showed file-count: 1/7, 2/7)
5. **Research:** Discovered `huggingface_hub` uses two separate tqdm instances
6. **Attempt #1:** Custom tqdm class with JSON output (only caught file-count)
7. **Attempt #2:** Monkey-patch internal tqdm (didn't work)
8. **Attempt #3:** Parse stderr for tqdm progress bars (too fragile)
9. **Final Solution:** Pragmatic fallback - poll directory size
10. **Current State:** Code written, needs validation with real download

---

## Recommendations for Next Developer

1. **Start by validating the current approach:**
   - It's simple and should work even if not perfect
   - Might be "good enough" for v1

2. **If progress is jerky/insufficient:**
   - Consider indeterminate spinner as acceptable fallback
   - Document as known limitation
   - Plan future improvement with better progress API

3. **Don't spend more time on tqdm parsing:**
   - We tried multiple approaches, none worked reliably
   - The subprocess + non-TTY environment is too hostile
   - Directory polling is pragmatic, simple, debuggable

4. **Focus on user experience:**
   - SOMETHING updating is better than appearing frozen
   - Even if progress jumps (0% → 30% → 70% → 100%), that's okay
   - Status text helps: "Downloading Parakeet v3 model (~600MB)"

---

## Related Files for Context

- **Bug Report:** `docs/bugs/parakeet-download-ui-blocking.md`
- **Feature:** `docs/features/done/2025-09-06-parakeet-v3-multilingual-upgrade.md`
- **Related Session:** `docs/sessions/2025-09-19-parakeet-only-completion-and-warning-fixes.md`

---

**Session End:** 2025-09-29 23:20 CET
**Next Session Should:** Validate download progress with real download, commit if working