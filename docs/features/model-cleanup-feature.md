# Model Architecture Simplification Plan

**Date**: 2025-09-04  
**Status**: Planning  
**Priority**: High  
**Goal**: Streamline FluidVoice to WhisperKit-only, removing MLX/Parakeet complexity

## Current State Analysis

### Model Services (BEFORE)
- **WhisperKit** (CoreML) - Local transcription ✅ Keep
- **Parakeet/MLX** - Apple Silicon transcription ❌ Remove  
- **MLX-LM** - Semantic correction ❌ Remove
- **OpenAI/Anthropic APIs** - Cloud transcription ✅ Keep (minimal)

### Files to Remove (33 files affected)

#### Core MLX/Parakeet Files
```
Sources/ParakeetService.swift           # 400+ LOC MLX integration
Sources/MLXCorrectionService.swift      # 300+ LOC semantic correction
Sources/MLXModelManager.swift           # 500+ LOC model downloads  
Sources/MLXModelManagementView.swift    # Complex UI for MLX models
Sources/PythonDetector.swift            # Python environment detection
```

#### Python Integration
```
Sources/parakeet_transcribe_pcm.py      # MLX transcription script
Sources/mlx_semantic_correct.py         # MLX correction script
Sources/Resources/pyproject.toml        # Python dependencies
Sources/Resources/uv.lock              # UV lockfile
test_semantic_correction.py            # Standalone test
```

#### Supporting Infrastructure  
```
Sources/UvBootstrap.swift              # UV package manager
Sources/SemanticCorrectionService.swift # LLM orchestration
Sources/SemanticCorrectionTypes.swift   # MLX-related types
Sources/AppSetupHelper.swift           # MLX setup code (partial)
```

#### Test Files (11 files)
```
Tests/MLXScriptTests.swift
Tests/ParakeetServiceTests.swift
Tests/ParakeetDownloadTests.swift
Tests/SemanticCorrectionTests.swift
Tests/test_parakeet_transcribe.py
# + 6 more integration tests
```

### Dependencies to Remove

#### Package.swift
```swift
// REMOVE these from dependencies:
.package(url: "https://github.com/huggingface/swift-transformers.git", from: "0.1.15")
// This pulls in: Jinja, Hub, TensorUtils, Tokenizers, Generation, Models

// KEEP:
.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.13.1")
.package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.10.2") 
.package(url: "https://github.com/soffes/HotKey", from: "0.2.1")
```

## Simplification Benefits

### Code Reduction
- **~3,000 LOC removed** (27% of codebase!)
- **33 files eliminated** 
- **Build time reduction** (no swift-transformers compilation)
- **Binary size reduction** (~3-4MB smaller)

### Complexity Reduction  
- **No Python integration** - eliminates subprocess complexity
- **No model downloads** - WhisperKit handles this
- **Simpler UI** - remove MLX settings panels
- **Fewer permissions** - no Python execution needs
- **Easier testing** - no Python mocking needed

### User Experience
- **Faster startup** - no Python environment detection
- **Simpler setup** - no MLX model downloads
- **More reliable** - fewer points of failure
- **Better performance** - WhisperKit is highly optimized

## Implementation Plan

### Phase 1: Analysis & Backup
1. **Create feature branch**: `feature/whisperkit-only`
2. **Document removed functionality** in case rollback needed
3. **Backup current state** before modifications

### Phase 2: Remove MLX/Parakeet Core
1. Delete Python scripts and resources
2. Remove MLX service classes
3. Update Package.swift dependencies
4. Remove MLX-related types and enums

### Phase 3: Update UI Components
1. Simplify SettingsView (remove MLX sections)
2. Remove MLXModelManagementView entirely
3. Update ContentView (remove MLX references)
4. Simplify model selection UI

### Phase 4: Clean Up Integration
1. Update SpeechToTextService (WhisperKit + APIs only)
2. Simplify AppSetupHelper
3. Remove semantic correction features
4. Update error handling

### Phase 5: Test Cleanup
1. Remove MLX-related test files
2. Update integration tests
3. Verify WhisperKit functionality intact
4. Test build and runtime

## Affected Components Analysis

### SpeechToTextService.swift (Core Changes)
**BEFORE:**
```swift
enum TranscriptionService {
    case whisperKit
    case parakeet      // ❌ REMOVE
    case openAI
    case anthropic
}
```

**AFTER:**
```swift
enum TranscriptionService {
    case whisperKit    // ✅ Default local
    case openAI        // ✅ Cloud option
    case anthropic     // ✅ Cloud option  
}
```

### SettingsView.swift Simplification
**Remove Sections:**
- MLX Model Management
- Parakeet Configuration  
- Python Environment Setup
- Semantic Correction Settings
- Model Download Progress

**Keep Sections:**
- WhisperKit Model Selection
- API Key Management
- Hotkey Configuration
- General Preferences

### ContentView.swift Updates
**Remove:**
- MLX model status indicators
- Semantic correction options
- Python setup guidance
- Complex model selection

**Keep:**
- Simple recording interface
- WhisperKit transcription
- Basic settings access

## Risk Assessment

### Low Risk Changes
- ✅ Python script removal - not critical path
- ✅ MLX UI removal - simplifies experience
- ✅ Test file cleanup - reduces maintenance

### Medium Risk Changes  
- ⚠️ SpeechToTextService refactor - core functionality
- ⚠️ Settings migration - user preferences
- ⚠️ Package.swift changes - build system

### Mitigation Strategies
1. **Feature branch development** - safe experimentation
2. **Incremental removal** - one component at a time  
3. **Comprehensive testing** - verify WhisperKit still works
4. **User migration** - handle existing MLX settings gracefully

## Timeline Estimate

- **Day 1**: Analysis, backup, feature branch setup
- **Day 2**: Remove Python/MLX core files, update Package.swift
- **Day 3**: Update UI components, settings simplification
- **Day 4**: Integration cleanup, error handling
- **Day 5**: Testing, documentation updates

## Success Criteria

### Technical Metrics
- ✅ Build completes successfully
- ✅ App launches without errors  
- ✅ WhisperKit transcription works
- ✅ Settings save/load properly
- ✅ Reduced binary size (<7MB)

### Quality Metrics
- ✅ No regression in core functionality
- ✅ Cleaner, simpler codebase
- ✅ Faster build times
- ✅ Simplified user experience

### User Experience  
- ✅ Setup process streamlined
- ✅ Recording still works seamlessly
- ✅ No missing critical features
- ✅ Performance maintained or improved

## Future Considerations

### If MLX Needed Later
- **Modular reintegration** - plugin architecture
- **Optional dependency** - not core to basic functionality  
- **Advanced user feature** - behind feature flag

### WhisperKit Enhancements
- **Focus resources** on WhisperKit optimization
- **Contribute upstream** to WhisperKit improvements
- **Better model management** within WhisperKit ecosystem

---

**Next Steps**: Start with Phase 1 analysis and create feature branch for safe experimentation.

**Expected Outcome**: Cleaner, faster, more maintainable FluidVoice focused on core transcription functionality.