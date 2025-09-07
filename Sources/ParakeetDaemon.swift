import Foundation
import os.log

/// Manages a long-running Parakeet transcription daemon process
/// Eliminates Python startup and model loading overhead for optimal performance
final class ParakeetDaemon {
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "ParakeetDaemon")
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isReady = false
    private var pythonPath: String
    private var consecutiveFailures = 0
    private var lastHealthyTime = Date()
    
    // Connection pooling optimization
    private var lastPingTime = Date.distantPast
    private var lastPingResult = false
    private var isCurrentlyTranscribing = false
    
    /// Shared daemon instance
    static let shared = ParakeetDaemon()
    
    private init() {
        self.pythonPath = ""
    }
    
    /// Start the daemon with the specified Python path
    func start(pythonPath: String) async throws {
        self.pythonPath = pythonPath
        
        // Stop existing daemon if running
        await stop()
        
        logger.infoDev("Starting Parakeet daemon with Python: \(pythonPath)")
        
        // Setup process and pipes
        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        // Get daemon script path
        guard let daemonScriptURL = Bundle.main.url(forResource: "parakeet_daemon", withExtension: "py") else {
            throw ParakeetDaemonError.daemonScriptNotFound
        }
        
        // Configure process
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [daemonScriptURL.path]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Store pipes for communication
        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        
        // Setup output monitoring
        setupOutputMonitoring()
        
        // Start the process
        try process.run()
        logger.infoDev("Parakeet daemon process started (PID: \(process.processIdentifier))")
        
        // Wait for daemon to be ready
        try await waitForReady(timeout: 10.0)
        
        logger.infoDev("Parakeet daemon is ready for requests")
        // Health tracking starts with first actual transcription
    }
    
    /// Stop the daemon gracefully
    func stop() async {
        guard let process = process, process.isRunning else {
            return
        }
        
        logger.info("Stopping Parakeet daemon...")
        
        // Send graceful shutdown command
        do {
            _ = try await sendCommand(["command": "shutdown"])
        } catch {
            logger.warning("Failed to send shutdown command: \(error.localizedDescription)")
        }
        
        // Give process time to shutdown gracefully
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Force terminate if still running
        if process.isRunning {
            logger.warning("Force terminating daemon process")
            process.terminate()
        }
        
        // Wait for termination
        process.waitUntilExit()
        
        // Cleanup
        cleanup()
        
        logger.info("Parakeet daemon stopped")
    }
    
    /// Send transcription request to daemon
    func transcribe(pcmFilePath: String) async throws -> ParakeetDaemonResponse {
        guard isReady else {
            recordFailure()
            throw ParakeetDaemonError.daemonNotReady
        }
        
        // Mark as transcribing to skip unnecessary pings
        isCurrentlyTranscribing = true
        defer { isCurrentlyTranscribing = false }
        
        do {
            let request = ["pcm_path": pcmFilePath]
            let response = try await sendCommand(request)
            
            let result = ParakeetDaemonResponse(
                status: response["status"] as? String ?? "unknown",
                text: response["text"] as? String ?? "",
                language: response["language"] as? String,
                confidence: response["confidence"] as? Float,
                error: response["message"] as? String
            )
            
            // Record success or failure based on response
            if result.isSuccess {
                recordSuccess()
            } else {
                recordFailure()
                logger.warning("🚨 DAEMON ALERT: Transcription failed - \(result.error ?? "unknown error")")
            }
            
            return result
            
        } catch {
            recordFailure()
            logger.error("🚨 DAEMON ALERT: Command failed - \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Check if daemon is alive (optimized with caching)
    func ping() async throws -> Bool {
        guard isReady else { return false }
        
        // Fast path: Skip ping if recently successful transcription or recent ping
        let now = Date()
        let timeSinceLastPing = now.timeIntervalSince(lastPingTime)
        
        // Skip ping if:
        // 1. Currently transcribing (daemon is obviously alive)
        // 2. Recent successful ping (within 5 seconds)
        // 3. Recent successful transcription (within 10 seconds) 
        if isCurrentlyTranscribing {
            logger.infoDev("🚀 Skipping ping - currently transcribing (daemon alive)")
            return true
        }
        
        if lastPingResult && timeSinceLastPing < 5.0 {
            logger.infoDev("🚀 Using cached ping result (\(String(format: "%.1f", timeSinceLastPing))s ago)")
            return true
        }
        
        let timeSinceLastSuccess = now.timeIntervalSince(lastHealthyTime)
        if timeSinceLastSuccess < 10.0 && consecutiveFailures == 0 {
            logger.infoDev("🚀 Skipping ping - recent successful transcription (\(String(format: "%.1f", timeSinceLastSuccess))s ago)")
            return true
        }
        
        // Slow path: Actually ping daemon
        logger.infoDev("🔍 Performing actual daemon ping")
        do {
            let response = try await sendCommand(["command": "ping"])
            let isAlive = response["status"] as? String == "pong"
            
            // Cache result
            lastPingTime = now
            lastPingResult = isAlive
            
            if isAlive {
                recordSuccess()
            } else {
                recordFailure()
            }
            
            return isAlive
        } catch {
            logger.warning("Ping failed: \(error.localizedDescription)")
            lastPingTime = now
            lastPingResult = false
            recordFailure()
            return false
        }
    }
    
    // MARK: - Private Implementation
    
    private func sendCommand(_ command: [String: Any]) async throws -> [String: Any] {
        guard let stdinPipe = stdinPipe else {
            throw ParakeetDaemonError.daemonNotRunning
        }
        
        // Serialize command to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: command)
        var jsonString = String(data: jsonData, encoding: .utf8) ?? ""
        jsonString += "\n" // Add newline for readline()
        
        // Send command
        guard let commandData = jsonString.data(using: .utf8) else {
            throw ParakeetDaemonError.encodingError
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            // Setup response handler before sending command
            let responseHandler = DaemonResponseHandler { result in
                continuation.resume(with: result)
            }
            
            // Store handler temporarily (will be cleaned up by handler itself)
            self.pendingResponseHandler = responseHandler
            
            // Send command
            stdinPipe.fileHandleForWriting.write(commandData)
        }
    }
    
    private var pendingResponseHandler: DaemonResponseHandler?
    
    private func setupOutputMonitoring() {
        guard let stdoutPipe = stdoutPipe, let stderrPipe = stderrPipe else {
            return
        }
        
        // Monitor stdout for responses
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            
            if let output = String(data: data, encoding: .utf8) {
                self.handleDaemonOutput(output)
            }
        }
        
        // Monitor stderr for errors
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            
            if let error = String(data: data, encoding: .utf8) {
                self.logger.warning("Daemon stderr: \(error)")
            }
        }
    }
    
    private func handleDaemonOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        
        for line in lines {
            do {
                guard let data = line.data(using: .utf8) else { continue }
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
                
                let status = json["status"] as? String ?? "unknown"
                let message = json["message"] as? String ?? ""
                
                logger.infoDev("Daemon: \(status) - \(message)")
                
                // Handle status changes
                switch status {
                case "ready", "listening":
                    isReady = true
                    readyCompletion?(.success(()))
                    readyCompletion = nil
                    
                case "error", "stopped":
                    isReady = false
                    if let completion = readyCompletion {
                        let error = ParakeetDaemonError.initializationFailed(message)
                        completion(.failure(error))
                        readyCompletion = nil
                    }
                    
                case "success", "pong":
                    // Response to transcription or ping request
                    pendingResponseHandler?.complete(with: .success(json))
                    pendingResponseHandler = nil
                    
                default:
                    break
                }
                
            } catch {
                logger.warning("Failed to parse daemon output: \(line)")
            }
        }
    }
    
    private var readyCompletion: ((Result<Void, Error>) -> Void)?
    
    private func waitForReady(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readyCompletion = { result in
                continuation.resume(with: result)
            }
            
            // Setup timeout
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if self.readyCompletion != nil {
                    self.readyCompletion?(.failure(ParakeetDaemonError.startupTimeout))
                    self.readyCompletion = nil
                }
            }
        }
    }
    
    private func cleanup() {
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        isReady = false
        pendingResponseHandler = nil
        readyCompletion = nil
    }
    
    // MARK: - Health Monitoring
    
    private func recordSuccess() {
        self.consecutiveFailures = 0
        self.lastHealthyTime = Date()
    }
    
    private func recordFailure() {
        self.consecutiveFailures += 1
        
        let timeSinceHealthy = Date().timeIntervalSince(self.lastHealthyTime)
        
        // Alert on consecutive failures or prolonged unhealthiness
        if self.consecutiveFailures >= 3 {
            logger.error("🚨 DAEMON CRITICAL: \(self.consecutiveFailures) consecutive failures!")
        } else if timeSinceHealthy > 300 { // 5 minutes
            logger.error("🚨 DAEMON CRITICAL: No successful operation for \(Int(timeSinceHealthy))s")
        }
    }
}

// MARK: - Response Handler

private class DaemonResponseHandler {
    private let completion: (Result<[String: Any], Error>) -> Void
    
    init(completion: @escaping (Result<[String: Any], Error>) -> Void) {
        self.completion = completion
    }
    
    func complete(with result: Result<[String: Any], Error>) {
        completion(result)
    }
}

// MARK: - Data Types

struct ParakeetDaemonResponse {
    let status: String
    let text: String
    let language: String?
    let confidence: Float?
    let error: String?
    
    var isSuccess: Bool {
        return status == "success"
    }
}

enum ParakeetDaemonError: LocalizedError {
    case daemonScriptNotFound
    case daemonNotRunning
    case daemonNotReady
    case initializationFailed(String)
    case startupTimeout
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .daemonScriptNotFound:
            return "Parakeet daemon script not found in app bundle"
        case .daemonNotRunning:
            return "Parakeet daemon is not running"
        case .daemonNotReady:
            return "Parakeet daemon is not ready for requests"
        case .initializationFailed(let message):
            return "Parakeet daemon initialization failed: \(message)"
        case .startupTimeout:
            return "Parakeet daemon startup timeout"
        case .encodingError:
            return "Failed to encode daemon command"
        }
    }
}