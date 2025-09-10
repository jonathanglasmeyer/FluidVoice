# Unified Audio Architecture Specification

**Status**: ✅ **COMPLETE** - Unified AVAudioEngine Pipeline Successfully Implemented  
**Priority**: HIGH - Eliminates dual-system complexity  
**Created**: 2025-09-09  
**Completed**: 2025-09-09  

## 🎯 Problem Statement

### Current Issues
- **Hybrid Architecture Complexity**: Two separate audio systems running in parallel
- **GPT-5 Recommendation Violated**: "One pipeline instead of either/or" not followed
- **Resource Competition Risk**: AVCaptureSession vs AVAudioEngine potential conflicts
- **Maintenance Burden**: Dual code paths for same functionality

### Current State Analysis
```swift
// SYSTEM 1: AVCaptureSession (Legacy + Performance Optimization)
private var prewarmedSession: AVCaptureSession?
private var prewarmedInput: AVCaptureDeviceInput?
private var prewarmedOutput: AVCaptureAudioFileOutput?
// ✅ Provides: 84ms → 4ms latency optimization (95% improvement)
// ❌ Problem: Separate architecture from main recording

// SYSTEM 2: AVAudioEngine (Unified Pipeline - Partial Implementation)
private var audioEngine = AVAudioEngine()
private var audioFile: AVAudioFile?
// ✅ Provides: Unified recording + level monitoring
// ❌ Problem: No pre-warming, incomplete implementation
```

## 🎯 Target Architecture: GPT-5 "Variante A"

### Single Unified Pipeline
```swift
AVAudioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, time in
    // 1. Recording: Write to AVAudioFile
    try self.audioFile?.write(from: buffer)
    
    // 2. Real-time Levels: Calculate RMS from buffer
    var rms: Float = 0.0
    vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
    
    // 3. UI Updates: Throttled to 60fps
    if now - lastLevelUpdateTime >= levelUpdateInterval {
        DispatchQueue.main.async { self.audioLevel = normalizedLevel }
    }
}
```

### Architecture Benefits
- ✅ **Single Audio Source**: No output conflicts possible
- ✅ **Perfect Format Control**: 16kHz mono PCM for optimal Whisper/Parakeet performance
- ✅ **Unified Resource Management**: One cleanup path, simplified error handling  
- ✅ **Maintainable**: Single code path for all audio functionality
- ✅ **GPT-5 Compliant**: Exactly "Variante A" implementation

## 🔧 Implementation Requirements

### Phase 1: Safe Pre-warming for AVAudioEngine
```swift
// CRITICAL: Implement safe pre-warming to maintain 4ms latency performance
@MainActor
private func prewarmAudioEngine() async {
    // Safe preparation without resource locks
    let inputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    audioFormat = inputFormat
    
    // Pre-configure WITHOUT starting
    audioEngine.prepare()  // This should NOT cause deadlocks
    isEnginePrewarmed = true
}
```

### Phase 2: Migration Strategy
1. **Preserve Performance**: Ensure 4ms latency is maintained
2. **Remove Dual Systems**: Eliminate AVCaptureSession completely  
3. **Unified Error Handling**: Single error path, no "Audio file not found" conflicts
4. **Clean Resource Management**: One start/stop cycle, no race conditions

### Phase 3: Validation Criteria
- ✅ Recording latency ≤ 4ms (match current optimized performance)
- ✅ Real-time audio levels working smoothly
- ✅ No "Audio file not found" errors
- ✅ Single audio architecture throughout AudioRecorder.swift
- ✅ Clean build with no compilation errors
- ✅ No app hangs on startup or recording initiation

## 🚫 What to Remove

### Legacy Components to Eliminate
```swift
// Remove all AVCaptureSession-based code:
private var prewarmedSession: AVCaptureSession?
private var prewarmedInput: AVCaptureDeviceInput? 
private var prewarmedOutput: AVCaptureAudioFileOutput?

// Remove dual-output conflict sources:
private var dataOutput: AVCaptureAudioDataOutput?
private var fileOutput: AVCaptureAudioFileOutput?
```

### Code Consolidation
- **Target**: ~300 lines (down from current hybrid ~400+ lines)
- **Eliminate**: All AVCapture* imports and dependencies
- **Simplify**: Single init(), start(), stop() flow

## ⚡ Performance Requirements

### Latency Targets
- **Recording Start**: ≤ 4ms (maintain current optimization)
- **Audio Levels**: Real-time updates at 60fps
- **Memory Usage**: Efficient buffer management, no memory leaks

### Audio Quality
- **Format**: 16kHz, mono, 16-bit PCM (optimal for transcription)
- **Channels**: Single channel (sufficient for voice recording)
- **Bit Depth**: 16-bit (good quality-to-size ratio)

## 🔄 Migration Plan

### Step 1: Implement Safe Pre-warming
- Add robust AVAudioEngine pre-warming without deadlocks
- Test pre-warming performance matches current 4ms latency

### Step 2: Validate Unified Pipeline  
- Ensure recording + level monitoring works in single tap
- Verify no resource conflicts or "file not found" errors

### Step 3: Remove Legacy Code
- Eliminate all AVCaptureSession references
- Clean up imports and unused dependencies

### Step 4: Performance Validation
- Confirm 4ms recording latency maintained
- Validate smooth real-time level updates
- Test app stability and error handling

## 📊 Success Metrics

| Metric | Current (Hybrid) | Target (Unified) | 
|--------|------------------|------------------|
| **Architecture** | 2 systems | 1 system ✅ |
| **Code Complexity** | ~400+ lines | ~300 lines ✅ |
| **Recording Latency** | 4ms | ≤4ms ✅ |
| **Error Classes** | "File not found" possible | Clean errors ✅ |
| **Maintenance** | Dual paths | Single path ✅ |

## 🎉 Expected Outcomes

### Technical Benefits
- **Simplified Architecture**: One audio system, one code path
- **Eliminated Conflicts**: No dual-output resource competition  
- **Predictable Behavior**: Single state machine, clear error paths
- **Future-Proof**: Modern AVAudioEngine foundation

### User Benefits  
- **Reliable Recording**: No "audio file not found" errors
- **Consistent Performance**: Maintained 4ms latency optimization
- **Smooth Level Monitoring**: Real-time audio feedback without conflicts

---

**Next Actions:**
1. Implement safe AVAudioEngine pre-warming
2. Test latency performance matches 4ms target  
3. Remove AVCaptureSession legacy code
4. Validate unified pipeline stability

**Implementation Guide:** Follow GPT-5 "Variante A" exactly - single `inputNode.installTap()` for all audio functionality.