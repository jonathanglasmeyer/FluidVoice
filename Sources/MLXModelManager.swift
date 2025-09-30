import Foundation
import SwiftUI
import os.log

@MainActor
final class MLXModelManager: ObservableObject {
    static let shared = MLXModelManager()

    @Published var downloadedModels: Set<String> = []
    @Published var modelSizes: [String: Int64] = [:]
    @Published var isDownloading: [String: Bool] = [:]
    @Published var downloadProgress: [String: String] = [:]
    @Published var downloadPercent: [String: Double] = [:]
    @Published var totalCacheSize: Int64 = 0

    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "MLXModelManager")
    private let cacheDirectory: URL

    static let parakeetRepo = "mlx-community/parakeet-tdt-0.6b-v3"
    
    private init() {
        self.cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface")
        Task {
            await refreshModelList()
        }
    }
    
    func refreshModelList() async {
        await MainActor.run {
            self.downloadedModels.removeAll()
            self.modelSizes.removeAll()
            self.totalCacheSize = 0
        }
        
        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else {
            logger.info("Hugging Face cache directory doesn't exist")
            return
        }
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
            
            var totalSize: Int64 = 0
            
            for item in contents {
                guard item.lastPathComponent.hasPrefix("models--") else { continue }
                
                // Convert directory name back to repo format
                let modelName = item.lastPathComponent
                    .replacingOccurrences(of: "models--", with: "")
                    .replacingOccurrences(of: "--", with: "/")
                
                // Check if this looks like an MLX model
                let mlxKeywords = ["mlx", "qwen", "llama", "phi", "mistral", "gemma", "starcoder", "parakeet"]
                let isLikelyMLX = mlxKeywords.contains { modelName.lowercased().contains($0) }
                
                if isLikelyMLX {
                    let size = calculateDirectorySize(at: item)
                    await MainActor.run {
                        self.downloadedModels.insert(modelName)
                        self.modelSizes[modelName] = size
                        totalSize += size
                    }
                }
            }
            
            await MainActor.run {
                self.totalCacheSize = totalSize
            }
            
            logger.infoDev("Found \(self.downloadedModels.count) MLX models, total size: \(self.formatBytes(totalSize))")
        } catch {
            logger.error("Failed to scan model directory: \(error.localizedDescription)")
        }
    }
    
    func ensureParakeetModel() async {
        await refreshModelList()
        if downloadedModels.contains(Self.parakeetRepo) { return }
        await downloadParakeetModel()
    }

    nonisolated func downloadParakeetModel() async {
        let repo = Self.parakeetRepo
        logger.infoDev("Starting Parakeet model download for: \(repo)")

        // Set download state immediately for UI feedback
        await MainActor.run {
            self.isDownloading[repo] = true
            self.downloadProgress[repo] = "Preparing Python environment..."
        }

        let pythonPath: String
        do {
            let py = try await UvBootstrap.ensureVenv(userPython: nil) { msg in
                self.logger.infoDev("uv: \(msg)")
            }
            pythonPath = py.path
        } catch {
            logger.infoDev("Failed to prepare Python environment: \(error.localizedDescription)")
            await MainActor.run {
                self.downloadProgress[repo] = "Error: Could not prepare Python environment"
                self.isDownloading[repo] = false
            }
            return
        }

        await MainActor.run {
            self.downloadProgress[repo] = "Downloading Parakeet v3 model..."
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        let pythonScript = """
import json, sys, traceback, os, time, threading, logging
from pathlib import Path

# Configure logging to see HuggingFace activity
logging.basicConfig(
    level=logging.INFO,
    format='[HF] %(message)s',
    stream=sys.stderr,
    force=True
)
logging.getLogger('huggingface_hub').setLevel(logging.INFO)
logging.getLogger('huggingface_hub.file_download').setLevel(logging.INFO)

# Allow online downloads and enable progress bars
os.environ['HF_HUB_OFFLINE'] = '0'
os.environ['HF_HUB_DISABLE_PROGRESS_BARS'] = '0'  # Enable tqdm for progress tracking
os.environ['HF_HUB_VERBOSITY'] = 'info'  # Reduce verbosity (debug is too noisy)

try:
    print(json.dumps({"message": "Preparing Python environment..."}), flush=True)

    from huggingface_hub import snapshot_download

    # Known file sizes for mlx-community/parakeet-tdt-0.6b-v3 (from actual download)
    KNOWN_FILE_SIZES = {
        "05e01c7f396c298cf7d23f61da7b504adeab698f0aaeafd9c82d198625464592": 2508288736,  # model.safetensors (2.34 GB)
        "eacec2b0a77f336d4a2ca4a25a7047575d3c2b74de47e997f4c205126ed3135e": 360916,      # tokenizer.model
        "4f469c2e92c981861f7ce6bcd940e608401d931e": 244093,      # config.json
        "3fa4c819f33b03e876ce33c0aa34866ed2b5e17a": 101024,      # tokenizer.vocab
        "d2fc51742d86127c241018b728e72b3a336225a1": 46772,       # vocab.txt
        "2775a7563b1df0f1a13291973a3985163b88725f": 1081,        # README.md
        "a6344aac8c09253b3b630fb776ae94478aa0275b": 1519,        # .gitattributes
    }
    TOTAL_SIZE = sum(KNOWN_FILE_SIZES.values())  # ~2.51 GB

    cache_dir = Path.home() / ".cache" / "huggingface" / "models--mlx-community--parakeet-tdt-0.6b-v3"
    blobs_dir = cache_dir / "blobs"

    # Background thread to poll .incomplete files
    stop_polling = threading.Event()
    last_percent = [-1]
    last_mb = [-1]
    last_log_time = [0]
    hit_98_time = [None]

    def poll_incomplete_files():
        while not stop_polling.is_set():
            try:
                downloaded_bytes = 0

                # Sum up all completed blobs + incomplete files
                if blobs_dir.exists():
                    for blob_hash, expected_size in KNOWN_FILE_SIZES.items():
                        blob_path = blobs_dir / blob_hash
                        incomplete_path = blobs_dir / f"{blob_hash}.incomplete"

                        if blob_path.exists():
                            # File complete
                            downloaded_bytes += expected_size
                        elif incomplete_path.exists():
                            # File downloading - count partial size
                            downloaded_bytes += incomplete_path.stat().st_size

                # Calculate percentage
                if downloaded_bytes > 0:
                    percent = int((downloaded_bytes / TOTAL_SIZE) * 100)
                    percent = min(percent, 98)  # Cap at 98% until complete

                    mb_downloaded = downloaded_bytes / (1024 * 1024)
                    mb_total = TOTAL_SIZE / (1024 * 1024)
                    current_mb = int(mb_downloaded)

                    now = time.time()
                    changed = percent != last_percent[0] or current_mb != last_mb[0]
                    heartbeat_due = (now - last_log_time[0]) >= 5  # Heartbeat every 5s

                    # Track when we hit 98%
                    if percent >= 98 and hit_98_time[0] is None:
                        hit_98_time[0] = now

                    # Log if changed OR heartbeat due (important for verification phase)
                    if changed or heartbeat_due:
                        last_percent[0] = percent
                        last_mb[0] = current_mb
                        last_log_time[0] = now

                        # Special message during 98% verification phase
                        if percent >= 98 and hit_98_time[0] is not None:
                            elapsed = int(now - hit_98_time[0])
                            if elapsed > 10:
                                message = f"Verifying download (this will take 1-2 minutes)... {elapsed}s"
                            else:
                                message = f"Downloading: {percent}% ({mb_downloaded:.0f}/{mb_total:.0f} MB)"
                        else:
                            message = f"Downloading: {percent}% ({mb_downloaded:.0f}/{mb_total:.0f} MB)"

                        print(json.dumps({
                            "percent": percent,
                            "message": message
                        }), flush=True)
            except Exception as e:
                print(f"[POLLING ERROR] {e}", file=sys.stderr, flush=True)

            time.sleep(0.5)  # Poll twice per second

    print(json.dumps({"message": "Starting download from Hugging Face..."}), flush=True)

    # Start polling thread
    poll_thread = threading.Thread(target=poll_incomplete_files, daemon=True)
    poll_thread.start()

    start_time = time.time()

    model_path = snapshot_download(
        repo_id="\(repo)",
        cache_dir=str(Path.home() / ".cache" / "huggingface"),
        local_files_only=False
    )

    stop_polling.set()
    poll_thread.join(timeout=1)

    elapsed = time.time() - start_time
    print(json.dumps({"message": f"Download complete in {elapsed:.1f}s"}), flush=True)

    # Show progress after download finishes
    print(json.dumps({"message": "Verifying model files...", "percent": 99}), flush=True)
    print(json.dumps({"status": "complete", "message": "Download complete!", "percent": 100}), flush=True)
except Exception as e:
    print(json.dumps({"status": "error", "message": str(e)}), flush=True)
    traceback.print_exc()
    sys.exit(1)
"""
        process.arguments = ["-c", pythonScript]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Read stdout in a background task with polling
            Task.detached {
                var buffer = ""
                var lastOutputTime = Date()

                while process.isRunning {
                    let data = outputPipe.fileHandleForReading.availableData
                    if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                        buffer += text
                        lastOutputTime = Date()

                        // Process complete lines
                        let lines = buffer.components(separatedBy: "\n")
                        buffer = lines.last ?? ""

                        for line in lines.dropLast() {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { continue }

                            self.logger.infoDev("Download output: \(trimmed)")

                            guard let jsonData = trimmed.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                                self.logger.infoDev("Failed to parse JSON: \(trimmed)")
                                continue
                            }

                            await MainActor.run {
                                // Handle progress updates
                                if let message = json["message"] as? String {
                                    self.logger.infoDev("Progress message: \(message)")
                                    self.downloadProgress[repo] = message
                                }

                                // Handle percentage updates
                                if let percent = json["percent"] as? Int {
                                    self.logger.infoDev("Progress percent: \(percent)%")
                                    self.downloadPercent[repo] = Double(percent) / 100.0
                                }

                                // Handle completion
                                if let status = json["status"] as? String, status == "complete" {
                                    self.logger.infoDev("Download complete!")
                                    self.downloadedModels.insert(repo)
                                    self.downloadPercent[repo] = 1.0
                                    self.isDownloading[repo] = false
                                }
                            }
                        }
                    }

                    // Show heartbeat if no updates for 3 seconds
                    if Date().timeIntervalSince(lastOutputTime) > 3.0 {
                        await MainActor.run {
                            let current = self.downloadProgress[repo] ?? "Downloading..."
                            if !current.contains("still downloading") {
                                self.downloadProgress[repo] = "\(current) (still downloading...)"
                            }
                        }
                        lastOutputTime = Date()
                    }

                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                }

                // Process any remaining buffer
                if !buffer.isEmpty {
                    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        self.logger.infoDev("Final output: \(trimmed)")
                    }
                }
            }

            // Log stderr for debugging (tqdm visual bars go here, but we ignore them)
            Task.detached {
                while process.isRunning {
                    let data = errorPipe.fileHandleForReading.availableData
                    if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                        // Just log stderr for debugging, don't parse it
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.logger.infoDev("stderr: \(text)")
                        }
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                }
            }

            // Wait for process on background thread (don't block this function)
            Task.detached {
                process.waitUntilExit()

                let exitStatus = process.terminationStatus
                await MainActor.run {
                    self.isDownloading[repo] = false

                    if exitStatus == 0 {
                        self.logger.infoDev("Download completed successfully!")
                        Task {
                            await self.refreshModelList()
                        }
                    } else {
                        self.downloadProgress[repo] = "Error: Download failed (exit code: \(exitStatus))"
                        self.logger.infoDev("Download failed with exit code: \(exitStatus)")
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.downloadProgress[repo] = "Error: \(error.localizedDescription)"
                self.isDownloading[repo] = false
            }
        }
    }

    func deleteModel(_ repo: String) async {
        let escapedRepo = repo.replacingOccurrences(of: "/", with: "--")
        let modelPath = cacheDirectory.appendingPathComponent("models--\(escapedRepo)")
        
        do {
            try FileManager.default.removeItem(at: modelPath)
            await MainActor.run {
                downloadedModels.remove(repo)
                modelSizes.removeValue(forKey: repo)
            }
            await refreshModelList()
            logger.info("Deleted model: \(repo)")
        } catch {
            logger.error("Failed to delete model: \(error.localizedDescription)")
        }
    }
    
    private func calculateDirectorySize(at url: URL) -> Int64 {
        var size: Int64 = 0
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                size += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            } catch {
                continue
            }
        }
        
        return size
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
