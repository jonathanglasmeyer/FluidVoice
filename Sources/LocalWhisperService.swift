import Foundation
@preconcurrency import WhisperKit
import AVFoundation
import CoreML
import os.log
import os.signpost

// Actor to manage WhisperKit instances safely across concurrency boundaries
private actor WhisperKitCache {
    private var instances: [String: WhisperKit] = [:]
    private var accessTimes: [String: Date] = [:]
    
    func getOrCreate(modelName: String, model: WhisperModel, maxCached: Int, progressCallback: (@Sendable (String) -> Void)?) async throws -> WhisperKit {
        // Check if we have a cached instance
        if let existingInstance = instances[modelName] {
            // Update access time for LRU tracking
            accessTimes[modelName] = Date()
            return existingInstance
        }

        // Check if model is downloaded locally before attempting to create WhisperKit instance
        if !(await isModelDownloadedLocally(model)) {
            throw LocalWhisperError.modelNotDownloaded
        }

        // Create new instance
        progressCallback?("Preparing \(model.displayName) model...")

        // Set environment variables to ensure offline operation
        setenv("HF_HUB_OFFLINE", "1", 1)
        setenv("TRANSFORMERS_OFFLINE", "1", 1)
        setenv("HF_HUB_DISABLE_IMPLICIT_TOKEN", "1", 1)

        // Try to use local model path if available with optimized config
        let newInstance: WhisperKit
        do {
            // Create ModelComputeOptions for CPU+GPU (avoid Neural Engine delays)
            let computeOptions = ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU, // Use CPU+GPU instead of default
                textDecoderCompute: .cpuAndGPU,  // Avoid Neural Engine delays
                prefillCompute: .cpuOnly
            )
            
            let config: WhisperKitConfig
            if let localModelPath = getLocalModelPath(for: model) {
                config = WhisperKitConfig(
                    modelFolder: localModelPath,
                    computeOptions: computeOptions
                )
            } else {
                // Fallback to model name with same optimizations
                config = WhisperKitConfig(
                    model: modelName,
                    computeOptions: computeOptions
                )
            }
            newInstance = try await WhisperKit(config)
        } catch {
            // If WhisperKit fails due to network issues, provide a more helpful error
            if error.localizedDescription.contains("offline") ||
               error.localizedDescription.contains("network") ||
               error.localizedDescription.contains("connection") {
                throw LocalWhisperError.modelNotDownloaded
            } else {
                throw error
            }
        }
        
        // Remove least recently used models if cache is full
        evictLeastRecentlyUsedIfNeeded(maxCached: maxCached)
        
        // Cache the new instance
        instances[modelName] = newInstance
        accessTimes[modelName] = Date()
        
        return newInstance
    }
    
    func clear() {
        instances.removeAll()
        accessTimes.removeAll()
    }
    
    func clearExceptMostRecent() {
        let sortedByAccess = accessTimes.sorted { $0.value > $1.value }
        
        // Keep only the most recent model
        for (index, model) in sortedByAccess.enumerated() {
            if index > 0 {
                instances.removeValue(forKey: model.key)
                accessTimes.removeValue(forKey: model.key)
            }
        }
    }
    
    private func evictLeastRecentlyUsedIfNeeded(maxCached: Int) {
        guard instances.count >= maxCached else { return }

        // Find the least recently used model
        let sortedByAccess = accessTimes.sorted { $0.value < $1.value }

        // Remove the oldest accessed model
        if let oldestModel = sortedByAccess.first {
            instances.removeValue(forKey: oldestModel.key)
            accessTimes.removeValue(forKey: oldestModel.key)
        }
    }

    private func isModelDownloadedLocally(_ model: WhisperModel) async -> Bool {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }

        let modelPath = documentsPath
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(model.whisperKitModelName)

        // Check if the model directory exists and contains model files
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            // Check for typical model files (config.json, pytorch_model.bin, etc.)
            let contents = try? FileManager.default.contentsOfDirectory(atPath: modelPath.path)
            let hasModelFiles = contents?.contains { $0.hasSuffix(".json") || $0.hasSuffix(".bin") || $0.hasSuffix(".mlmodelc") } ?? false
            return hasModelFiles
        }

        return false
    }

    private func getLocalModelPath(for model: WhisperModel) -> String? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let modelPath = documentsPath
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent(model.whisperKitModelName)

        // Check if the model directory exists and contains model files
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            // Check for typical model files (config.json, pytorch_model.bin, etc.)
            let contents = try? FileManager.default.contentsOfDirectory(atPath: modelPath.path)
            let hasModelFiles = contents?.contains { $0.hasSuffix(".json") || $0.hasSuffix(".bin") || $0.hasSuffix(".mlmodelc") } ?? false
            return hasModelFiles ? modelPath.path : nil
        }

        return nil
    }
}

final class LocalWhisperService: Sendable {
    static let shared = LocalWhisperService()
    
    // Use actor isolation for thread-safe access to mutable state
    private let cache = WhisperKitCache()
    private let maxCachedModels = 3 // Limit cache to prevent excessive memory usage
    private let memoryPressureSource: DispatchSourceMemoryPressure?
    
    init() {
        // Create memory pressure source inline to avoid self reference
        let queue = DispatchQueue(label: "whisperkit.memorypressure")
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        
        // Capture cache reference weakly to avoid retain cycle
        let weakCache = cache
        
        source.setEventHandler { [weak weakCache] in
            guard let cache = weakCache else { return }
            
            let memoryPressure = source.mask
            
            if memoryPressure.contains(.critical) {
                // Critical memory pressure - clear all cached models
                Task {
                    await cache.clear()
                }
            } else if memoryPressure.contains(.warning) {
                // Warning level - remove least recently used models aggressively
                Task {
                    await cache.clearExceptMostRecent()
                }
            }
        }
        
        source.resume()
        self.memoryPressureSource = source
    }
    
    deinit {
        memoryPressureSource?.cancel()
    }
    
    func transcribe(audioFileURL: URL, model: WhisperModel, progressCallback: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let modelName = model.whisperKitModelName
        
        // Get or create WhisperKit instance from actor-isolated cache
        let whisperKit = try await cache.getOrCreate(modelName: modelName, model: model, maxCached: maxCachedModels, progressCallback: progressCallback)
        
        // Provide helpful progress messaging with duration estimate
        let durationHint = getDurationHint(for: model)
        progressCallback?("Transcribing audio... \(durationHint)")
        
        // Transcribe the audio file with proper language detection
        progressCallback?("Processing audio...")
        
        // Create DecodingOptions with forced German language
        var decodingOptions = DecodingOptions()
        decodingOptions.language = "de"       // Force German (ISO 639-1 code)
        decodingOptions.detectLanguage = false // Disable auto-detection
        decodingOptions.verbose = true        // Enable for debugging
        decodingOptions.task = .transcribe
        decodingOptions.skipSpecialTokens = true
        decodingOptions.suppressBlank = true  // Helps with quality
        
        let results = try await whisperKit.transcribe(
            audioPath: audioFileURL.path, 
            decodeOptions: decodingOptions
        )
        
        // Combine all transcription segments into a single text
        let transcription = results.map { $0.text }.joined(separator: " ")
        
        guard !transcription.isEmpty else {
            throw LocalWhisperError.transcriptionFailed
        }
        
        progressCallback?("Transcription complete!")
        return transcription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
    
    
    // Method to clear cached instances if needed (for memory management)
    func clearCache() async {
        await cache.clear()
    }
    
    // Method to preload a specific model
    func preloadModel(_ model: WhisperModel, progressCallback: (@Sendable (String) -> Void)? = nil) async throws {
        let modelName = model.whisperKitModelName
        _ = try await cache.getOrCreate(modelName: modelName, model: model, maxCached: maxCachedModels, progressCallback: progressCallback)
    }
    
    /// Performs warmup inference to trigger Metal/CoreML shader compilation
    func warmupModel(_ model: WhisperModel) async throws {
        let signpostID = OSSignpostID(log: OSLog(subsystem: "com.fluidvoice.app", category: "performance"))
        
        // Create 1s silence sample for warmup (proper length for full pipeline trigger)
        let silenceDuration: Double = 1.0 // 1 second
        let sampleRate: Double = 16000 // WhisperKit standard sample rate
        let sampleCount = Int(silenceDuration * sampleRate)
        let silenceBuffer = [Float](repeating: 0.0, count: sampleCount)
        
        // Write silence to temporary audio file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("warmup_silence_\(UUID().uuidString).wav")
        
        try AudioFileHelper.writePCMToWAV(samples: silenceBuffer, sampleRate: sampleRate, to: tempURL)
        
        defer {
            // Cleanup temp file
            try? FileManager.default.removeItem(at: tempURL)
        }
        
        os_signpost(.begin, log: OSLog(subsystem: "com.fluidvoice.app", category: "performance"), name: "Warmup Inference", signpostID: signpostID)
        
        // Perform actual warmup transcription (triggers Metal/CoreML compilation)
        let modelName = model.whisperKitModelName
        let whisperKit = try await cache.getOrCreate(modelName: modelName, model: model, maxCached: maxCachedModels, progressCallback: nil)
        
        // Execute warmup inference - result is discarded
        // Use same DecodingOptions as main transcription
        var warmupOptions = DecodingOptions()
        warmupOptions.language = "de"       // Force German (ISO 639-1 code)
        warmupOptions.detectLanguage = false // Disable auto-detection
        warmupOptions.verbose = false       // Keep quiet for warmup
        warmupOptions.task = .transcribe
        warmupOptions.skipSpecialTokens = true
        warmupOptions.suppressBlank = true  // Consistent with main transcription
        
        let _ = try await whisperKit.transcribe(
            audioPath: tempURL.path,
            decodeOptions: warmupOptions
        )
        
        os_signpost(.end, log: OSLog(subsystem: "com.fluidvoice.app", category: "performance"), name: "Warmup Inference", signpostID: signpostID)
    }
    
    // Provide helpful duration hints based on model speed
    private func getDurationHint(for model: WhisperModel) -> String {
        switch model {
        case .tiny:
            return "This may take 30-60 seconds..."
        case .base:
            return "This may take 1-2 minutes..."
        case .small:
            return "This may take 2-3 minutes..."
        case .largeTurbo:
            return "This may take 3-5 minutes..."
        }
    }
}

enum LocalWhisperError: LocalizedError {
    case modelNotDownloaded
    case invalidAudioFile
    case bufferAllocationFailed
    case noChannelData
    case resamplingFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "Whisper model not downloaded. Please download the model in Settings before using offline transcription."
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .noChannelData:
            return "No audio channel data found"
        case .resamplingFailed:
            return "Failed to resample audio"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}

extension WhisperModel {
    var whisperKitModelName: String {
        switch self {
        case .tiny:
            return "openai_whisper-tiny"
        case .base:
            return "openai_whisper-base"
        case .small:
            return "openai_whisper-small"
        case .largeTurbo:
            return "openai_whisper-large-v3_turbo"
        }
    }
}