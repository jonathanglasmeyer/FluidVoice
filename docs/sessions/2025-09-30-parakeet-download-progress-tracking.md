# 2025-09-30: Parakeet Download Progress Tracking Implementation

**Date**: 2025-09-30
**Session Type**: Download Progress UX Implementation
**Status**: ⚠️ **CODED** - Needs validation testing

## Session Summary

### Problem Statement
Parakeet model download (2.4GB) showed misleading progress:
- Jumped from 85% → 98% in seconds
- 60-87 seconds of complete silence at 98%
- User had no feedback during verification phase
- Made app appear frozen/broken

### Root Cause Analysis
1. **Initial polling approach** counted only finalized files in cache, missing:
   - `.incomplete` temp files during download
   - Hidden files (started with `.`)
   - Files in system temp locations

2. **HuggingFace download behavior**:
   - Downloads to `.../blobs/<hash>.incomplete`
   - Large file (model.safetensors, 2.3GB) downloads in ~10-15 seconds
   - Post-download verification takes 60-87 seconds (checksumming)
   - File grows: 0 → 1024 → 2238 → 2392 MB (only 3-4 updates due to filesystem buffering)
   - Then stays at 2392 MB during 60-87s verification

3. **Failed Approach: tqdm Monkey-patching**
   - Attempted to patch `huggingface_hub.utils.tqdm` per ChatGPT-5 suggestion
   - Discovered: `tqdm_class` parameter only affects outer "Fetching X files" progress
   - HuggingFace does NOT use tqdm for individual HTTP downloads in v0.35.3
   - Individual files use simple print statements, no progress bars

### Tasks Completed
1. ✅ **Investigated HuggingFace download behavior** - Validated
   - Watched `.incomplete` files grow in real-time
   - Measured timing: 10-15s download + 60-87s verification
   - Confirmed filesystem buffering causes jumpy progress

2. ✅ **Implemented `.incomplete` polling with known file sizes** - Coded, NOT tested
   - Hardcoded exact blob hashes and sizes from completed download
   - Polls every 0.5s for smooth updates
   - Tracks both completed blobs and partial `.incomplete` files
   - Updates on MB changes (not just percent)

3. ✅ **Added verification phase heartbeat** - Coded, NOT tested
   - Detects when stuck at 98% for >10 seconds
   - Shows: "Verifying download (this may take 1-2 minutes)... Xs"
   - Updates every 5 seconds during verification

4. ❌ **Attempted tqdm monkey-patch** - Failed, rolled back
   - Tried patching `huggingface_hub.utils.tqdm`
   - Discovered HF design limitation
   - Rolled back to polling approach

### Git Commits Made
None - changes not yet tested/validated

## Technical Changes

### Files Modified
```
Sources/MLXModelManager.swift | ~120 lines changed (download progress implementation)
```

### Implementation Details

**File**: `Sources/MLXModelManager.swift:137-250`

**Key Changes:**

1. **Known File Sizes (lines 143-152)**:
```python
KNOWN_FILE_SIZES = {
    "05e01c7f396c298cf7d23f61da7b504adeab698f0aaeafd9c82d198625464592": 2508288736,  # model.safetensors
    "eacec2b0a77f336d4a2ca4a25a7047575d3c2b74de47e997f4c205126ed3135e": 360916,      # tokenizer.model
    "4f469c2e92c981861f7ce6bcd940e608401d931e": 244093,      # config.json
    "3fa4c819f33b03e876ce33c0aa34866ed2b5e17a": 101024,      # tokenizer.vocab
    "d2fc51742d86127c241018b728e72b3a336225a1": 46772,       # vocab.txt
    "2775a7563b1df0f1a13291973a3985163b88725f": 1081,        # README.md
    "a6344aac8c09253b3b630fb776ae94478aa0275b": 1519,        # .gitattributes
}
TOTAL_SIZE = sum(KNOWN_FILE_SIZES.values())  # 2,509,054,121 bytes (~2.51 GB)
```

2. **Polling Logic (lines 164-222)**:
```python
def poll_incomplete_files():
    while not stop_polling.is_set():
        downloaded_bytes = 0

        # Sum completed + incomplete files
        for blob_hash, expected_size in KNOWN_FILE_SIZES.items():
            blob_path = blobs_dir / blob_hash
            incomplete_path = blobs_dir / f"{blob_hash}.incomplete"

            if blob_path.exists():
                downloaded_bytes += expected_size
            elif incomplete_path.exists():
                downloaded_bytes += incomplete_path.stat().st_size

        # Calculate and emit progress
        percent = min(int((downloaded_bytes / TOTAL_SIZE) * 100), 98)

        # Heartbeat every 5s even if stuck
        if changed or heartbeat_due:
            if percent >= 98 and elapsed > 10:
                message = f"Verifying download (this may take 1-2 minutes)... {elapsed}s"
            else:
                message = f"Downloading: {percent}% ({mb_downloaded:.0f}/{mb_total:.0f} MB)"
```

3. **Verification Detection (lines 195-211)**:
```python
# Track when we hit 98%
if percent >= 98 and hit_98_time[0] is None:
    hit_98_time[0] = now

# Special message during 98% verification phase
if percent >= 98 and hit_98_time[0] is not None:
    elapsed = int(now - hit_98_time[0])
    if elapsed > 10:
        message = f"Verifying download (this may take 1-2 minutes)... {elapsed}s"
```

### Dependencies/Configuration
- **No new dependencies added**
- **HuggingFace Hub**: v0.35.3 (already present)
- **Build system**: Code compiles successfully

### What Was NOT Changed
- No Swift-side progress handling changes
- No UI changes
- No model download trigger changes
- Only Python progress reporting logic modified

## Expected Behavior (NOT YET VALIDATED)

### Download Phase (10-15 seconds)
```
0% (0/2393 MB)
42% (1025/2393 MB)    ← Filesystem buffer flush
93% (2238/2393 MB)    ← Filesystem buffer flush
98% (2392/2393 MB)    ← Filesystem buffer flush
```

**Why only 3-4 updates:**
- Filesystem buffers file writes
- `stat().st_size` only updates when buffers flush
- Still better than before (was stuck at 85%)

### Verification Phase (60-87 seconds)
```
98% - Verifying download (this may take 1-2 minutes)... 15s
98% - Verifying download (this may take 1-2 minutes)... 20s
98% - Verifying download (this may take 1-2 minutes)... 25s
...
98% - Verifying download (this may take 1-2 minutes)... 85s
99% - Verifying model files...
100% - Download complete!
```

**Every 5 seconds:** Heartbeat message with elapsed time counter

## Detailed Technical Notes

### HuggingFace Download Phases

**Phase 1: HTTP Download (10-15s)**
```
~/.cache/huggingface/models--mlx-community--parakeet-tdt-0.6b-v3/blobs/
└── 05e01c7f...592.incomplete  (grows from 0 → 2,508,288,736 bytes)
```

**Phase 2: Verification (60-87s)**
```
File stays at 2,508,288,736 bytes (no growth)
HuggingFace checksums, verifies integrity
```

**Phase 3: Finalization (<1s)**
```
.incomplete → blobs/05e01c7f...592 (rename/move)
Create symlink: snapshots/.../model.safetensors → ../../blobs/05e01c7f...592
```

### Why tqdm Patching Failed

**From HuggingFace Docs:**
> "The `tqdm_class` is not passed to individual file downloads"

**Evidence from logs:**
```
[TQDM INIT] desc=Fetching 7 files, is_bytes=False, unit=None
```

Only the outer "Fetching 7 files" progress uses tqdm. Individual file downloads use plain print statements with no progress bars. This is a design limitation in HuggingFace Hub v0.35.3 (and likely all versions).

### Filesystem Buffering Impact

**Real-time watch of `.incomplete` file:**
```
16:28:11 - 0 MB
16:28:14 - 1024 MB   ← 1 second, 1GB written
16:28:15 - 2238 MB   ← 1 second, 1.2GB written
16:28:21 - 2392 MB   ← 6 seconds, 154MB written
16:28:22-32 - 2392 MB (stuck during verification)
```

Despite continuous HTTP download, `stat().st_size` only updates when OS flushes buffers. This is unavoidable without lower-level file monitoring (inotify/fsevents).

### Alternative Approaches Considered

1. **HTTP Progress Hooks** ❌
   - Would require patching urllib3 or requests internals
   - Too fragile, breaks with HF updates

2. **File System Events (inotify/fsevents)** ❌
   - Would need native Swift/C code
   - Still subject to filesystem buffering
   - Over-engineered for this use case

3. **Accept Limitations, Improve UX** ✅ **CHOSEN**
   - Honest about what's happening
   - Shows progress where measurable
   - Clear messages during verification
   - User knows app is working

## Current State

### Build Status
✅ **Compiles successfully** - No errors, no warnings

### Testing Status
❌ **NOT TESTED** - Code written but not validated:
1. Polling thread behavior
2. Progress updates during download
3. Heartbeat messages during verification
4. Edge cases (network interruption, resume)

### Known Limitations
1. **Jumpy Progress (3-4 updates)**: Unavoidable due to filesystem buffering
2. **Verification Silent**: No way to track HF's internal checksumming
3. **Model-Specific**: Hardcoded hashes only work for parakeet-tdt-0.6b-v3
4. **Resume Behavior**: Untested if download resumes from incomplete

## Continuation Points

### 🔴 IMMEDIATE: Validation Testing (Priority 1)

**Test 1: Fresh Download**
```bash
just reset-deps  # Clear cache
./build-dev.sh   # Build with new code
# Start app, trigger Parakeet download
# Watch logs: /usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info
```

**Expected:**
- 3-4 progress updates: 0% → ~42% → ~93% → 98%
- Heartbeat every 5s at 98%: "Verifying download... 15s", "...20s", etc.
- Total time: ~90 seconds (15s download + 75s verification)

**Test 2: Resume Behavior**
```bash
# Start download, kill app mid-download (at ~50%)
# Restart app, trigger download again
# Should resume from 50%, not restart from 0%
```

**Test 3: Network Interruption**
```bash
# Disconnect network during download
# Should show error, not hang forever
```

### 🟡 MEDIUM: Code Improvements (Priority 2)

1. **Dynamic File Size Discovery**
   - Current: Hardcoded hashes for parakeet-tdt-0.6b-v3
   - Better: Query `HfApi.model_info(..., files_metadata=True)` before download
   - Benefit: Works for any model, not just Parakeet

2. **Error Handling**
   - Add timeout for polling thread
   - Handle missing/corrupted `.incomplete` files
   - Graceful degradation if cache_dir doesn't exist

3. **Progress Smoothing**
   - Optional: Interpolate between filesystem flushes
   - Estimated download speed (e.g., 50 MB/s) for smoother bar
   - Trade-off: Less accurate but smoother UX

### 🟢 LOW: Future Enhancements (Priority 3)

1. **Download Speed Display**
   - Calculate MB/s from polling deltas
   - Show: "Downloading: 42% (1025/2393 MB) - 120 MB/s"

2. **ETA Calculation**
   - Based on current speed, estimate time remaining
   - Show: "Downloading: 42% - ~15s remaining"

3. **Multi-Model Support**
   - Generalize to work with any HuggingFace model
   - Configuration-driven file size expectations

## Outstanding Questions

1. **Does resume work correctly?**
   - HF should resume incomplete downloads automatically
   - Need to test: Does our polling correctly show resumed progress?

2. **What happens on slow connections?**
   - Current code assumes ~10-15s download
   - On slow networks, might see more updates (longer download = more buffer flushes)

3. **Is 60-87s verification normal for all users?**
   - Could depend on disk speed (SSD vs HDD)
   - MacBook Pro M1/M2 observed 60-87s
   - Older Macs might take longer?

## Risk Assessment

### Low Risk ✅
- Build compiles without errors
- No changes to existing functionality (only adds progress)
- Polling happens in background thread (non-blocking)

### Medium Risk 🟡
- Untested in production (fresh install, resume, network issues)
- Hardcoded file sizes might break if model updates
- Filesystem polling might behave differently on other systems

### High Risk 🔴
- None identified

## Lessons Learned

1. **ChatGPT suggestions aren't always valid**
   - tqdm monkey-patch seemed plausible but didn't work
   - Always verify against actual library behavior/docs

2. **HuggingFace progress tracking is limited by design**
   - No per-file HTTP progress callbacks
   - `tqdm_class` only affects outer progress
   - Polling is the most reliable approach

3. **Filesystem buffering is unavoidable**
   - `stat().st_size` lags behind actual writes
   - Can't get smooth byte-by-byte progress without kernel hooks
   - Better to embrace limitations and set expectations

4. **Verification phase is significant**
   - 60-87s is longer than download itself (10-15s)
   - Users need feedback during this phase
   - Heartbeat with timer is good compromise

## Commands for Next Session

**Validation:**
```bash
# Clean slate test
just reset-deps && ./build-dev.sh

# Watch logs in separate terminal
/usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info | grep MLXModelManager

# Start app and trigger download
```

**Debug if issues:**
```bash
# Watch .incomplete files in real-time
while true; do
  echo "$(date '+%H:%M:%S') - $(fd -e incomplete . ~/.cache/huggingface/models--mlx-community--parakeet-tdt-0.6b-v3/blobs/ -x bash -c 'stat -f "{}: %z bytes" {}' 2>/dev/null || echo 'No incomplete files')"
  sleep 0.5
done
```

## Recommended Files for Next Session

**For Testing:**
- `docs/features/done/parakeet-local-mlx-model-feature.md` - Parakeet download spec
- `Sources/MLXModelManager.swift:113-250` - Download progress implementation

**For Improvements:**
- Research: `HfApi.model_info(..., files_metadata=True)` for dynamic file sizes
- Consider: Move hardcoded sizes to config file or fetch at runtime

---

**Session End State**: Code implemented, builds successfully, awaiting validation testing before commit.