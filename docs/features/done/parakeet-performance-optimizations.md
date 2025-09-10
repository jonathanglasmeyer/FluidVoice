# Parakeet Performance Optimizations

**Status**: 🚧 **PLANNED** - Multiple optimization opportunities identified  
**Priority**: Medium - Performance improvements for power users  
**Complexity**: Medium to High - Requires architecture changes

## Overview

Comprehensive performance optimization roadmap for Parakeet transcription pipeline. Current baseline: **1.9s audio → 0.88s transcription (RTF=0.46)**. Target: **Sub-300ms transcription time** for short audio clips.

## Completed Optimizations ✅

### 1. MLX Model Cache Initialization (DONE)
**Status**: ✅ **COMPLETED**  
**Performance Gain**: 25ms reduction per transcription  
**Implementation**: Move expensive filesystem scan to app startup  

**Details**:
- Eliminated redundant `MLXModelManager.refreshModelList()` calls during transcription
- Added cached `ParakeetService.isModelAvailable` boolean flag
- Zero-cost runtime model availability checks

### 2. Python Subprocess Reuse (COMPLETED)
**Status**: ✅ **COMPLETED**  
**Performance Gain**: 250-500ms reduction per transcription  
**Implementation**: Long-running Python daemon with IPC protocol

**Technical Implementation**:
```swift
// ParakeetDaemon.swift - Swift process manager
- JSON-based IPC over stdin/stdout
- Automatic daemon restart on failure
- Graceful shutdown handling

// parakeet_daemon.py - Python daemon process  
- Model loaded once at startup (~500ms)
- Responds to transcription requests via JSON
- Keeps MLX model warm in memory
```

**Performance Results**:
```bash
# Before (subprocess per request):
📊 PERF (parakeet): Audio=1.9s, Time=0.88s, RTF=0.46, WPS=5.7

# After (daemon first call):
📊 PERF (parakeet-daemon): Audio=1.6s, Time=0.63s, RTF=0.39, WPS=7.9

# After (daemon warm):
📊 PERF (parakeet-daemon): Audio=1.5s, Time=0.16s, RTF=0.11, WPS=32.0
```

**Configuration**:
```bash
# Daemon mode is now enabled by default for optimal performance
# No configuration needed - always uses high-performance daemon mode
```

### 3. Early Daemon Initialization (COMPLETED)
**Status**: ✅ **COMPLETED**  
**Performance Gain**: Eliminates cold start delay entirely  
**Implementation**: Daemon preloading during app startup

**Technical Implementation**:
```swift
// FluidVoiceApp.swift - App startup integration
Task {
    // After MLX model cache init...
    if ParakeetService.isModelAvailable && UserDefaults.standard.bool(forKey: "parakeetDaemonMode") {
        let pyURL = try await UvBootstrap.ensureVenv(userPython: nil)
        try await ParakeetDaemon.shared.start(pythonPath: pyURL.path)
        Logger.app.infoDev("✅ Parakeet daemon preloaded at startup")
    }
}
```

**Performance Results**:
```bash
# First transcription (no cold start):
📊 PERF (parakeet-preloaded): Audio=1.2s, Time=0.23s, RTF=0.19, WPS=13.1

# Subsequent transcriptions (ultra-optimized):
📊 PERF (parakeet-preloaded): Audio=1.7s, Time=0.09s, RTF=0.05, WPS=54.7
```

**Benefits**:
- **Zero Cold Start**: First transcription is immediately fast (0.23s vs 0.63s)
- **Consistent Performance**: All transcriptions benefit from warm daemon
- **User Experience**: No waiting time on first hotkey press
- **Always Active**: Daemon mode is now enabled by default for all users

**Trade-offs**:
- **App Startup**: +500ms startup time for daemon initialization
- **Memory Footprint**: +600MB permanent RAM usage (model always loaded)
- **Background Process**: Python daemon runs continuously

**Overall Performance Improvement**: **10x faster** than original implementation

## Remaining Optimization Opportunities 🚧

### 4. PCM Pre-processing Cache (Medium Impact)
**Status**: 🚧 **PLANNED**  
**Estimated Gain**: 50-100ms reduction (for repeated audio)  
**Complexity**: Medium  

**Current Problem**:
```swift
// Every transcription: m4a → PCM conversion via AudioProcessor
let pcmDataURL = try await processAudioToRawPCM(audioFileURL: audioURL)
```

**Proposed Solution**:
```swift
// Cache PCM files based on audio content hash:
1. Calculate SHA256 of input audio file
2. Check if PCM cache exists: ~/.cache/fluidvoice/pcm/{hash}.raw
3. If exists: Use cached PCM, skip conversion
4. If not: Convert and cache for future use
5. LRU eviction when cache size exceeds limit (500MB?)
```

**Implementation Plan**:
1. Add `PCMCache` manager class
2. Integrate SHA256 hashing for audio files  
3. Add cache size monitoring and LRU eviction
4. Update `processAudioToRawPCM()` to check cache first
5. Add cache cleanup on app termination

**Benefits**:
- Skip audio conversion for repeated files (debug scenarios)
- Useful for development/testing workflows
- Reduces AudioProcessor CPU usage

**Use Cases**:
- Debug audio mode with same test file
- User re-transcribing recent audio
- Development iteration cycles

### 4. Model Preloading at Startup (Medium Impact)
**Status**: 🚧 **PLANNED**  
**Estimated Gain**: 500ms reduction (first transcription only)  
**Complexity**: Medium  

**Current Behavior**:
```python
# Model loaded on first transcription attempt:
model = from_pretrained("mlx-community/parakeet-tdt-0.6b-v3")  # 500ms delay
```

**Proposed Solution**:
```python
# Preload model during app startup:
- Background task: Load Parakeet model into memory
- Cache model globally for all transcription requests  
- First transcription: Instant start (model already loaded)
```

**Implementation Plan**:
1. Extend app startup MLX initialization task
2. Add Parakeet model preloading alongside WhisperKit preloading
3. Create separate Python process for model warming
4. Add model warm-up status indicator in logs
5. Handle preload failures gracefully (fallback to lazy loading)

**Benefits**:
- Eliminates first-use model loading delay
- Consistent transcription performance from first use
- Better user experience for immediate productivity

**Trade-offs**:
- Increased app startup time (~500ms)
- Higher baseline memory usage (~600MB)
- May conflict with other MLX model usage

### 5. Pipeline Parallelization (Low Impact)
**Status**: 🚧 **PLANNED**  
**Estimated Gain**: 20-50ms reduction  
**Complexity**: High  

**Current Sequential Flow**:
```
Audio Recording → Audio Processing → PCM Conversion → Python Transcription
```

**Proposed Parallel Flow**:
```
Audio Recording → Audio Processing ──┐
                                     ├─→ Python Transcription
          PCM Conversion (streaming) ──┘
```

**Implementation Plan**:
1. Stream PCM data to Python process as it's generated
2. Start transcription before full audio processing completes
3. Handle backpressure if Python is slower than audio processing
4. Coordinate completion signals between parallel streams

**Benefits**:
- Overlap I/O and computation phases
- Reduced perceived latency for longer audio files
- Better CPU/memory utilization

**Complexity**:
- Streaming IPC protocol design
- Error handling for partial data
- Synchronization between parallel processes

### 6. Batch Processing for Long Audio (Low Priority)
**Status**: 🚧 **PLANNED**  
**Estimated Gain**: Significant for >60s audio  
**Complexity**: High  

**Proposed Solution**:
```
Split long audio (>30s) into overlapping chunks:
- Chunk 1: 0-20s
- Chunk 2: 15-35s  
- Chunk 3: 30-50s
- Process chunks in parallel
- Merge results with overlap detection
```

**Use Cases**:
- Long meetings or presentations
- Transcription of recorded calls
- Batch processing workflows

## Performance Analysis

### Current Baseline Performance
**Test Audio**: 1.9s German speech  
**Current Performance**: 
```
📊 PERF (parakeet-tts): Audio=1.9s, Words=5, Time=0.88s, RTF=0.46, ms/word=176, WPS=5.7
```

### Optimization Impact Estimates

| Optimization | Time Saved | RTF Improvement | Implementation |
|-------------|------------|-----------------|----------------|
| MLX Cache Init ✅ | 25ms | 0.46 → 0.45 | **COMPLETED** |
| Python Subprocess | 250ms | 0.45 → 0.32 | **PLANNED** |
| PCM Caching | 50ms* | 0.32 → 0.29 | **PLANNED** |
| Model Preloading | 0ms** | No change | **PLANNED** |
| Pipeline Parallel | 30ms | 0.29 → 0.27 | **PLANNED** |

*Only for repeated audio files  
**Only affects first transcription

### Target Performance (ACHIEVED)
**Optimized Performance Results**:
```bash
# Target (estimated):
📊 PERF (parakeet-optimized): Audio=1.9s, Words=5, Time=0.30s, RTF=0.16, WPS=16.7

# Actual (achieved):
📊 PERF (parakeet-preloaded): Audio=1.7s, Words=5, Time=0.09s, RTF=0.05, WPS=54.7
```

**Achievement**: **10x faster transcription**, significantly exceeding targets and surpassing WhisperKit Base performance while maintaining superior multilingual quality.

## Implementation Priority

### Phase 1: High Impact (Next Release)
1. **Python Subprocess Reuse** - Biggest performance gain
2. **Model Preloading** - Eliminate first-use delay

### Phase 2: Polish (Future Release)  
3. **PCM Caching** - Development workflow optimization
4. **Pipeline Parallelization** - Advanced optimization

### Phase 3: Specialized (On Demand)
5. **Batch Processing** - Long audio use cases

## Technical Considerations

### Memory Usage Impact
- **Current**: ~50MB baseline + ~200MB during transcription
- **With Optimizations**: ~650MB baseline (model always loaded)
- **Trade-off**: 13x memory increase for 3x speed improvement

### Stability Considerations
- Long-running Python processes may have memory leaks
- Need robust process monitoring and restart mechanisms
- Graceful degradation when optimizations fail

### Development Complexity
- IPC protocol design and error handling
- Process lifecycle management  
- Cache invalidation and storage management
- Parallel processing synchronization

## Related Documentation

- **[Performance Metrics System](../docs/performance-metrics.md)** - Measurement and analysis framework
- **[Parakeet v3 Multilingual Upgrade](parakeet-v3-multilingual-upgrade.md)** - Current implementation
- **[Model Preloading System](done/model-preloading-feature.md)** - WhisperKit preloading patterns

## Success Metrics

### Performance Targets
- **Short Audio (<5s)**: RTF < 0.2 (sub-300ms transcription)
- **Medium Audio (5-30s)**: RTF < 0.15 
- **Long Audio (>30s)**: RTF < 0.1 with parallel processing

### Quality Assurance
- Maintain current transcription accuracy
- No regression in multilingual performance
- Stable memory usage over extended sessions
- Reliable error recovery and fallback mechanisms

## Future Considerations

### Hardware Optimization
- Neural Engine utilization for audio preprocessing
- GPU acceleration for parallel chunk processing
- Memory-mapped file I/O for large audio files

### Cloud Hybrid Approach
- Fallback to cloud APIs when local optimization fails
- Distributed processing for batch transcription jobs
- Edge computing integration for real-time applications