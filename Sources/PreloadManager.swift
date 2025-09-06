import Foundation
import os.log
import os.signpost

@MainActor
final class PreloadManager {
    static let shared = PreloadManager()
    
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "PreloadManager")
    private var preloadTask: Task<Void, Never>?
    
    private init() {}
    
    /// Triggers app-idle preloading of user's preferred WhisperKit model
    func startIdlePreload() {
        // Prevent multiple preload attempts
        guard preloadTask == nil else {
            logger.info("Preload already in progress - skipping")
            return
        }
        
        preloadTask = Task.detached(priority: .utility) { [weak self] in
            // Wait for UI to settle (ultrathink pattern)
            try? await Task.sleep(for: .milliseconds(500))
            await self?.performPreload()
        }
    }
    
    private func performPreload() async {
        let signpostID = OSSignpostID(log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"))
        os_signpost(.begin, log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"), name: "Model Preload", signpostID: signpostID)
        
        do {
            // 1. Determine which model to preload
            let targetModel = await determinePreloadModel()
            guard let model = targetModel else {
                logger.info("No suitable model found for preloading")
                return
            }
            
            logger.info("Starting preload for model: \(model.displayName)")
            
            // 2. Preload via existing LocalWhisperService
            try await LocalWhisperService.shared.preloadModel(model) { progress in
                // Silent preload - no UI progress
                Logger(subsystem: "com.fluidvoice.app", category: "PreloadManager").infoDev("Preload: \(progress)")
            }
            
            os_signpost(.event, log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"), name: "Model Loaded", signpostID: signpostID)
            
            // 3. Warmup execution
            await performWarmup(for: model)
            
            os_signpost(.end, log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"), name: "Model Preload", signpostID: signpostID)
            logger.info("✅ Preload completed successfully for \(model.displayName)")
            
        } catch {
            os_signpost(.end, log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"), name: "Model Preload", signpostID: signpostID)
            logger.error("❌ Preload failed: \(error.localizedDescription)")
            // Graceful degradation - app continues with lazy loading
        }
        
        // Mark preload task as completed
        await MainActor.run {
            preloadTask = nil
        }
    }
    
    private func determinePreloadModel() async -> WhisperModel? {
        // Read user's preferred model from settings (same logic as ContentView)
        let selectedModelString = UserDefaults.standard.string(forKey: "selectedWhisperModel") ?? "large-v3-turbo"
        
        // Check if local transcription is enabled
        let transcriptionProvider = UserDefaults.standard.string(forKey: "transcriptionProvider") ?? "local"
        guard transcriptionProvider == "local" else {
            // User prefers API transcription - no preload needed
            return nil
        }
        
        // Try user's preferred model first
        if let preferredModel = WhisperModel(rawValue: selectedModelString) {
            return preferredModel
        }
        
        // Fallback priority: largeTurbo → small → tiny
        let fallbackPriority: [WhisperModel] = [.largeTurbo, .small, .tiny]
        return fallbackPriority.first
    }
    
    private func performWarmup(for model: WhisperModel) async {
        do {
            let signpostID = OSSignpostID(log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"))
            os_signpost(.begin, log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"), name: "Model Warmup", signpostID: signpostID)
            
            // Use new warmup method
            try await LocalWhisperService.shared.warmupModel(model)
            
            os_signpost(.end, log: OSLog(subsystem: "com.fluidvoice.app", category: "PreloadManager"), name: "Model Warmup", signpostID: signpostID)
            logger.info("✅ Warmup completed for \(model.displayName)")
            
        } catch {
            logger.error("❌ Warmup failed: \(error.localizedDescription)")
            // Non-fatal - model is still loaded, just not warmed up
        }
    }
}