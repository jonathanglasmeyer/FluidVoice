import Foundation
import os.log
import FluidAudio

enum ParakeetError: Error, LocalizedError, Equatable {
    case modelNotAvailable
    case audioFileNotFound(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Parakeet v3 model is not downloaded\n\nFix: Restart FluidVoice to open the model download"
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)"
        case .transcriptionFailed(let message):
            return "Parakeet transcription failed: \(message)"
        }
    }
}

/// Owns the single FluidAudio `AsrManager`; concurrent callers share one load.
private actor ParakeetEngine {
    private var loadTask: Task<AsrManager, Error>?

    var isLoaded: Bool { loadTask != nil }

    func manager(progressHandler: ProgressHandler?) async throws -> AsrManager {
        if let loadTask {
            return try await loadTask.value
        }
        let task = Task {
            let models = try await AsrModels.downloadAndLoad(
                version: ParakeetService.modelVersion, progressHandler: progressHandler)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        loadTask = task
        do {
            return try await task.value
        } catch {
            loadTask = nil
            throw error
        }
    }
}

/// Parakeet TDT v3 via FluidAudio (CoreML on the Neural Engine). Auto-detects language per recording.
class ParakeetService: ObservableObject {
    static let shared = ParakeetService()
    static let modelVersion: AsrModelVersion = .v3

    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "ParakeetService")
    private let engine = ParakeetEngine()

    /// Cheap file-existence check against FluidAudio's model cache.
    static var isModelAvailable: Bool {
        AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: modelVersion), version: modelVersion)
    }

    private init() {}

    /// Downloads (if missing) and loads the model. First load compiles for the ANE and is slow; later loads hit the cache.
    func prepare(progressHandler: ProgressHandler? = nil) async throws {
        let start = Date()
        _ = try await engine.manager(progressHandler: progressHandler)
        logger.infoDev("Parakeet model ready in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw ParakeetError.audioFileNotFound(audioFileURL.path)
        }
        // Never trigger a ~600 MB download from the dictation hotkey
        guard await engine.isLoaded || Self.isModelAvailable else {
            throw ParakeetError.modelNotAvailable
        }

        do {
            let manager = try await engine.manager(progressHandler: nil)
            var decoderState = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
            let result = try await manager.transcribe(audioFileURL, decoderState: &decoderState)
            logger.infoDev(
                "Parakeet: \(String(format: "%.2f", result.duration))s audio in \(String(format: "%.3f", result.processingTime))s, confidence \(result.confidence)"
            )
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as ParakeetError {
            throw error
        } catch {
            logger.errorDev("Parakeet transcription error: \(error.localizedDescription)")
            throw ParakeetError.transcriptionFailed(error.localizedDescription)
        }
    }
}
