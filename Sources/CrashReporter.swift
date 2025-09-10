import Foundation
import AppKit
import KSCrashInstallations
import os.log

/// Privacy-safe crash reporter that stores crash logs locally for manual sharing
class CrashReporter {
    static let shared = CrashReporter()
    
    private let crashesDirectory: URL
    private let installation: CrashInstallationConsole
    private var processingTask: Task<Void, Never>?
    
    private init() {
        // Create crashes directory in Application Support
        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        crashesDirectory = appSupportDir
            .appendingPathComponent("FluidVoice")
            .appendingPathComponent("Crashes")
        
        // Create directory if it doesn't exist
        try? FileManager.default.createDirectory(at: crashesDirectory, withIntermediateDirectories: true)
        
        // Initialize KSCrash with console installation for offline use
        installation = CrashInstallationConsole.shared
        installation.printAppleFormat = true
        
        Logger.app.infoDev("📊 CrashReporter initialized - logs will be stored in: \(crashesDirectory.path)")
    }
    
    /// Initializes crash reporting - call this at app startup
    func initializeCrashReporting() {
        let config = KSCrashConfiguration()
        config.monitors = [.machException, .signal, .cppException, .nsException]
        
        // Install crash reporting
        do {
            try installation.install(with: config)
            Logger.app.infoDev("✅ Crash reporting initialized")
            
            // Process crash reports asynchronously to avoid blocking startup
            processingTask = Task.detached { [weak self] in
                self?.processPendingCrashReports()
            }
        } catch {
            Logger.app.errorDev("❌ Failed to initialize crash reporting: \(error.localizedDescription)")
        }
    }
    
    /// Processes any crash reports from previous app launches
    private func processPendingCrashReports() {
        Logger.app.infoDev("📊 Starting crash report processing...")
        
        guard let reportStore = KSCrash.shared.reportStore else {
            Logger.app.infoDev("📊 No report store available")
            return
        }
        
        Logger.app.infoDev("📊 Got report store, getting report IDs...")
        let reportIDs = reportStore.reportIDs
        
        guard !reportIDs.isEmpty else {
            Logger.app.infoDev("📊 No pending crash reports")
            return
        }
        
        Logger.app.infoDev("📊 Found \(reportIDs.count) pending crash report(s)")
        
        for (index, reportID) in reportIDs.enumerated() {
            Logger.app.infoDev("📊 Processing crash report \(index + 1)/\(reportIDs.count): \(reportID)")
            
            if let report = reportStore.report(for: reportID.int64Value) {
                Logger.app.infoDev("📊 Got crash report data, saving to file...")
                saveCrashReportToFile(report, reportID: reportID.stringValue)
                Logger.app.infoDev("📊 Crash report \(index + 1) saved successfully")
            } else {
                Logger.app.infoDev("📊 Failed to get crash report data for ID: \(reportID)")
            }
        }
        
        Logger.app.infoDev("📊 Cleaning up processed reports...")
        // Clean up processed reports from KSCrash's internal storage
        reportStore.deleteAllReports()
        
        Logger.app.infoDev("📊 Creating README file...")
        // Create README file to explain what these files are
        createReadmeFile()
        
        Logger.app.infoDev("📊 Crash report processing completed")
    }
    
    /// Saves a crash report to the local crashes directory
    private func saveCrashReportToFile(_ report: CrashReportDictionary, reportID: String) {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestampString = formatter.string(from: timestamp)
        
        let filename = "crash_\(timestampString)_\(reportID).json"
        let fileURL = crashesDirectory.appendingPathComponent(filename)
        
        do {
            // Create a simplified crash report representation
            let jsonDict: [String: Any] = [
                "reportID": reportID,
                "timestamp": timestampString,
                "crashInfo": [
                    "description": report.description,
                    "debugDescription": report.debugDescription
                ],
                "note": "FluidVoice crash report - processed by KSCrash",
                "generatedBy": "FluidVoice CrashReporter v1.0"
            ]
            
            let finalJsonData = try JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted])
            try finalJsonData.write(to: fileURL)
            
            Logger.app.infoDev("📊 Crash report saved: \(filename)")
        } catch {
            Logger.app.errorDev("❌ Failed to save crash report: \(error.localizedDescription)")
        }
    }
    
    /// Creates a README file in the crashes directory explaining what the files are
    private func createReadmeFile() {
        let readmeURL = crashesDirectory.appendingPathComponent("README.txt")
        
        // Don't overwrite existing README
        guard !FileManager.default.fileExists(atPath: readmeURL.path) else { return }
        
        let readmeContent = """
        FluidVoice Crash Reports
        ========================
        
        This directory contains crash reports from FluidVoice that were collected automatically.
        
        What are these files?
        - These are detailed crash reports in JSON format
        - They contain information about what went wrong when the app crashed
        - All data is stored locally and never sent anywhere automatically
        
        Privacy:
        - No personal data or audio content is included in crash reports
        - Reports contain only technical information about the crash
        - You control when and how to share these files
        
        How to share with the development team:
        1. Identify the crash report file from the time the crash occurred
        2. Share the .json file via email or Slack
        3. Include a brief description of what you were doing when the crash happened
        
        File naming format: crash_YYYY-MM-DD_HH-mm-ss_[reportID].json
        
        Generated by FluidVoice Crash Reporter
        """
        
        try? readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
    }
    
    /// Opens the crashes directory in Finder
    func showCrashLogsInFinder() {
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: crashesDirectory.path) {
            try? FileManager.default.createDirectory(at: crashesDirectory, withIntermediateDirectories: true)
            createReadmeFile()
        }
        
        Logger.app.infoDev("📂 Opening crash logs directory in Finder")
        NSWorkspace.shared.open(crashesDirectory)
    }
    
    /// Returns the number of crash reports in the directory
    func getCrashReportCount() -> Int {
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: crashesDirectory, includingPropertiesForKeys: nil)
            return contents.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("crash_") }.count
        } catch {
            return 0
        }
    }
    
    /// Returns true if there are crash reports available
    func hasCrashReports() -> Bool {
        return getCrashReportCount() > 0
    }
    
    /// Cleanup method to call during app termination
    func cleanup() {
        Logger.app.infoDev("📊 CrashReporter cleanup - canceling any pending tasks")
        processingTask?.cancel()
        processingTask = nil
    }
}