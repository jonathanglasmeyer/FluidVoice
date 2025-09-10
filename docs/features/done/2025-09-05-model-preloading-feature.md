# Model Preloading & Streaming UX Feature

**Date**: 2025-09-04  
**Priority**: High (UX Critical)  
**Problem**: "Preparing large turbo" blocks recording for 1+ minute on first use

## Problem Statement

### Current Horrible UX:
1. **User presses hotkey** to record
2. **"Preparing large turbo..."** appears and hangs for 60+ seconds
3. **User thinks app is broken** - no progress indicator
4. **Recording attempt fails** - user loses momentum
5. **WhisperKit loads 1.5GB model** synchronously on first use

### Impact:
- **First impression destroyed** ❌
- **Hotkey becomes unreliable** ❌  
- **Users switch to smaller models** to avoid delay ❌
- **Large-turbo adoption low** despite being best quality ❌

## Solution Design

### 1. **Background Model Preloading** 

#### App Startup Preloading:
```swift
// AppDelegate.swift - after UI setup
DispatchQueue.global(qos: .utility).async {
    let selectedModel = UserDefaults.standard.selectedWhisperModel
    if selectedModel == .largeTurbo {
        try? await LocalWhisperService.shared.preloadModel(selectedModel)
    }
}
```

#### Smart Preloading Triggers:
- **App launch** (background priority)
- **Model selection change** (immediate)
- **First recording attempt** (if not preloaded)
- **Idle time detection** (opportunistic)

### 2. **Progressive Loading UX**

#### Recording Window States:
```swift
enum ModelState {
    case notLoaded
    case preloading(progress: Double)
    case ready
    case failed(Error)
}
```

#### UI Flow:
1. **Hotkey pressed** → Recording window opens immediately
2. **Model check** → Show appropriate state
3. **If loading** → Progress bar with "Preparing large-turbo..." 
4. **If ready** → Normal recording UI
5. **If failed** → Fallback to smaller model option

### 3. **Intelligent Fallbacks**

#### Model Selection Strategy:
```swift
// Priority cascade for reliable recording
func getBestAvailableModel() -> WhisperModel {
    let preferred = UserDefaults.selectedModel
    
    if LocalWhisperService.shared.isModelReady(preferred) {
        return preferred
    } else if LocalWhisperService.shared.isModelReady(.base) {
        return .base  // Fast fallback
    } else {
        return .tiny  // Always available
    }
}
```

#### Smart Suggestions:
- **"Large-turbo is loading, record with Base now?"**
- **"Switch to Base model for instant recording?"**
- **Auto-fallback with notification**

### 4. **Streaming Progress UX**

#### Progress Indicators:
```swift
// Real-time feedback during model loading
struct ModelLoadingView: View {
    @State private var progress: Double = 0
    @State private var stage: LoadingStage = .downloading
    
    enum LoadingStage {
        case downloading    // "Downloading model..."
        case processing     // "Processing model..."
        case loading        // "Loading into memory..."
        case ready          // "Ready to record!"
    }
}
```

#### Visual Design:
```
┌─────────────────────────────┐
│  🎤 Preparing Large-Turbo   │
│                             │
│  ████████████░░░░░  75%     │
│  Loading into memory...     │
│                             │
│  ⏱️ ~15 seconds remaining   │
│                             │
│  [ Use Base Model Now ]     │
└─────────────────────────────┘
```

## Implementation Plan

### Phase 1: Background Preloading (2 hours)
```swift
// LocalWhisperService.swift extension
class LocalWhisperService {
    private var preloadTasks: [WhisperModel: Task<Void, Error>] = [:]
    
    func preloadModel(_ model: WhisperModel) async throws {
        // Cancel existing preload for this model
        preloadTasks[model]?.cancel()
        
        // Start new preload task
        preloadTasks[model] = Task {
            _ = try await cache.getOrCreate(modelName: model.whisperKitModelName, ...)
        }
    }
    
    func isModelReady(_ model: WhisperModel) -> Bool {
        return cache.instances[model.whisperKitModelName] != nil
    }
}
```

### Phase 2: Progressive Recording UI (3 hours)
```swift
// ContentView.swift updates
struct ContentView: View {
    @State private var modelState: ModelState = .notLoaded
    @State private var showFallbackOption = false
    
    var body: some View {
        VStack {
            switch modelState {
            case .preloading(let progress):
                ModelLoadingView(progress: progress, model: selectedModel)
                    .onReceive(loadingProgress) { progress in
                        if progress >= 1.0 {
                            modelState = .ready
                            // Auto-start recording if user is waiting
                            if isWaitingToRecord {
                                startRecording()
                            }
                        }
                    }
            case .ready:
                RecordingView()
            case .failed:
                FallbackModelView()
            }
        }
    }
}
```

### Phase 3: Smart Model Selection (2 hours)
```swift
// ModelSelectionLogic.swift
class SmartModelSelector {
    func selectOptimalModel(userPreference: WhisperModel) -> WhisperModel {
        // Check if preferred model is ready
        if LocalWhisperService.shared.isModelReady(userPreference) {
            return userPreference
        }
        
        // Suggest fallback with user consent
        let fallback = getFastestAvailableModel()
        showFallbackDialog(preferred: userPreference, fallback: fallback)
        
        return fallback
    }
    
    private func getFastestAvailableModel() -> WhisperModel {
        for model in [WhisperModel.tiny, .base, .small] {
            if LocalWhisperService.shared.isModelReady(model) {
                return model
            }
        }
        return .tiny // Always fallback to tiny
    }
}
```

### Phase 4: Settings Integration (1 hour)
```swift
// SettingsView.swift additions
VStack {
    // Existing model selection
    Picker("Model", selection: $selectedModel) { ... }
    
    // New: Preloading preferences
    Section("Performance") {
        Toggle("Preload model on startup", isOn: $preloadOnStartup)
        Toggle("Auto-fallback to faster models", isOn: $autoFallback)
        
        if selectedModel == .largeTurbo {
            HStack {
                Image(systemName: isModelReady ? "checkmark.circle.fill" : "clock")
                Text(isModelReady ? "Large-turbo ready" : "Large-turbo loading...")
                Spacer()
                if !isModelReady {
                    Button("Preload Now") {
                        Task { try await preloadModel(.largeTurbo) }
                    }
                }
            }
        }
    }
}
```

## User Experience Scenarios

### Scenario 1: First-Time Large-Turbo User
1. **Selects large-turbo** in settings
2. **"This model needs to be prepared. Preload now?"** dialog
3. **User confirms** → Background loading starts
4. **Progress shown** in settings
5. **When ready** → Notification: "Large-turbo ready for recording!"
6. **Hotkey works instantly** thereafter

### Scenario 2: Impatient User
1. **Presses hotkey** while large-turbo loading
2. **Recording window opens** with progress bar
3. **"Use Base model now?"** option shown
4. **User clicks "Use Base"** → Instant recording
5. **Large-turbo continues** loading in background
6. **Next recording** uses large-turbo (if ready)

### Scenario 3: Power User
1. **Enable "Preload on startup"** in settings
2. **Large-turbo loads** during coffee time
3. **All recordings** use best model instantly
4. **Perfect workflow** with no delays

## Success Metrics

### UX Improvements:
- **Time-to-first-transcription**: < 2 seconds (vs current 60+ seconds)
- **Hotkey reliability**: 99% instant response
- **Large-turbo adoption**: +300% (due to better UX)
- **User complaints**: -90% ("app is broken" reports)

### Technical Metrics:
- **Model preload success rate**: >95%
- **Fallback activation rate**: <10% (only when needed)
- **Memory usage**: Controlled (preload only selected model)
- **App startup time**: No degradation (background loading)

## Risk Assessment

### Low Risks:
- **Background loading** - WhisperKit already supports async loading
- **Progress tracking** - WhisperKit provides progress callbacks
- **Model state management** - Extension of existing cache system

### Medium Risks:  
- **Memory pressure** - Large model preloading uses 1.5GB+ RAM
- **Startup performance** - Background tasks might affect app launch
- **Fallback complexity** - Multiple model management increases complexity

### Mitigations:
- **Memory monitoring** - Cancel preload on memory warnings
- **Lazy preloading** - Only preload after UI is ready
- **Simple fallback logic** - Clear priority cascade: large→base→tiny

## Future Enhancements

### Phase 5: Streaming Transcription
- **Real-time model switching** during recording
- **Quality vs speed** preference slider
- **Adaptive model selection** based on audio length

### Phase 6: Model Caching
- **Persistent model cache** across app launches
- **Shared model instances** between app sessions
- **LRU model eviction** for memory management

---

**Outcome**: Transform the **worst UX moment** (preparing large-turbo) into a **seamless experience** where users never wait for model loading.