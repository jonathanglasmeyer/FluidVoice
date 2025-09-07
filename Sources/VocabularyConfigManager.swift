import Foundation
import os.log

// MARK: - File-Based Vocabulary Configuration Manager

final class VocabularyConfigManager {
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "VocabularyConfig")
    private let fileManager = FileManager.default
    
    // Standard XDG config location like VS Code, Git, etc.
    private var configDirectory: URL {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        return homeURL.appendingPathComponent(".config/fluidvoice", isDirectory: true)
    }
    
    private var vocabularyConfigURL: URL {
        // Try .jsonc first (JSONC with comments), fallback to .json for backwards compatibility
        let jsoncURL = configDirectory.appendingPathComponent("vocabulary.jsonc")
        let jsonURL = configDirectory.appendingPathComponent("vocabulary.json")
        
        if fileManager.fileExists(atPath: jsoncURL.path) {
            return jsoncURL
        }
        return jsonURL
    }
    
    // MARK: - Config File Operations
    
    func loadGlossary() -> VocabularyGlossary {
        // Try to load from file first
        if let glossary = loadFromFile() {
            logger.infoDev("Loaded vocabulary config from \(self.vocabularyConfigURL.path)")
            return glossary
        }
        
        // Fallback to default + create file
        logger.infoDev("Creating default vocabulary config at \(self.vocabularyConfigURL.path)")
        let defaultGlossary = createDefaultGlossary()
        saveToFile(defaultGlossary)
        return defaultGlossary
    }
    
    func saveGlossary(_ glossary: VocabularyGlossary) {
        saveToFile(glossary)
    }
    
    private func loadFromFile() -> VocabularyGlossary? {
        guard fileManager.fileExists(atPath: vocabularyConfigURL.path) else {
            return nil
        }
        
        let startTime = DispatchTime.now()
        
        do {
            let fileReadStart = DispatchTime.now()
            let data = try Data(contentsOf: vocabularyConfigURL)
            let fileReadElapsed = Double(DispatchTime.now().uptimeNanoseconds - fileReadStart.uptimeNanoseconds) / 1_000_000
            
            let jsonDecodeStart = DispatchTime.now()
            // Support JSONC (JSON with Comments) by preprocessing
            let processedData = preprocessJSONC(data)
            let config = try JSONDecoder().decode(VocabularyConfig.self, from: processedData)
            let jsonDecodeElapsed = Double(DispatchTime.now().uptimeNanoseconds - jsonDecodeStart.uptimeNanoseconds) / 1_000_000
            
            let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
            
            logger.infoDev("Config file I/O: file read \(String(format: "%.1f", fileReadElapsed))ms, JSON decode \(String(format: "%.1f", jsonDecodeElapsed))ms, total \(String(format: "%.1f", totalElapsed))ms")
            
            // Convert from file format to runtime format
            return VocabularyGlossary(
                canonicalMap: config.vocabulary,
                rules: config.rules
            )
        } catch {
            logger.error("Failed to load vocabulary config: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func saveToFile(_ glossary: VocabularyGlossary) {
        // Ensure config directory exists
        do {
            try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create config directory: \(error.localizedDescription)")
            return
        }
        
        // Convert to file format
        let config = VocabularyConfig(
            version: "1.0",
            vocabulary: glossary.canonicalMap,
            rules: glossary.rules
        )
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: vocabularyConfigURL)
            logger.infoDev("Saved vocabulary config to \(self.vocabularyConfigURL.path)")
        } catch {
            logger.error("Failed to save vocabulary config: \(error.localizedDescription)")
        }
    }
    
    private func createDefaultGlossary() -> VocabularyGlossary {
        let defaultMap: [String: [String]] = [
            "API": ["a p i", "api"],
            "GitHub": ["git hub", "github", "git-hub"],
            "OAuth": ["o auth", "oauth", "o-auth"],
            "TypeScript": ["type script", "typescript", "type-script"],
            "CLAUDE.md": ["claude md", "cloutmd", "cloude.md", "claude.md"],
            "SSH": ["s s h", "ssh"],
            "URL": ["u r l", "url"],  
            "SQL": ["s q l", "sql"],
            "JWT": ["j w t", "jwt"],
            "JSON": ["j s o n", "json"],
            "HTML": ["h t m l", "html"],
            "CSS": ["c s s", "css"],
            "HTTP": ["h t t p", "http"],
            "HTTPS": ["h t t p s", "https"],
            "CLI": ["c l i", "cli"]
        ]
        
        let defaultRules: [String: CanonRule] = [
            "API": CanonRule(caseMode: .upper),
            "GitHub": CanonRule(caseMode: .mixed),
            "OAuth": CanonRule(caseMode: .mixed),
            "TypeScript": CanonRule(caseMode: .mixed),
            "CLAUDE.md": CanonRule(caseMode: .exact),
            "SSH": CanonRule(caseMode: .upper),
            "URL": CanonRule(caseMode: .upper),
            "SQL": CanonRule(caseMode: .upper),
            "JWT": CanonRule(caseMode: .upper),
            "JSON": CanonRule(caseMode: .upper),
            "HTML": CanonRule(caseMode: .upper),
            "CSS": CanonRule(caseMode: .upper),
            "HTTP": CanonRule(caseMode: .upper),
            "HTTPS": CanonRule(caseMode: .upper),
            "CLI": CanonRule(caseMode: .upper)
        ]
        
        return VocabularyGlossary(canonicalMap: defaultMap, rules: defaultRules)
    }
    
    // MARK: - Convenience Methods
    
    func addTerm(_ canonical: String, aliases: [String] = [], caseMode: CaseMode = .mixed) {
        let glossary = loadGlossary()
        var mutableMap = glossary.canonicalMap
        var mutableRules = glossary.rules
        
        mutableMap[canonical] = aliases.isEmpty ? [canonical.lowercased()] : aliases
        mutableRules[canonical] = CanonRule(caseMode: caseMode)
        
        let updatedGlossary = VocabularyGlossary(canonicalMap: mutableMap, rules: mutableRules)
        saveGlossary(updatedGlossary)
        
        logger.infoDev("Added vocabulary term: \(canonical)")
    }
    
    func removeTerm(_ canonical: String) {
        let glossary = loadGlossary()
        var mutableMap = glossary.canonicalMap
        var mutableRules = glossary.rules
        
        mutableMap.removeValue(forKey: canonical)
        mutableRules.removeValue(forKey: canonical)
        
        let updatedGlossary = VocabularyGlossary(canonicalMap: mutableMap, rules: mutableRules)
        saveGlossary(updatedGlossary)
        
        logger.infoDev("Removed vocabulary term: \(canonical)")
    }
    
    var configFilePath: String {
        vocabularyConfigURL.path
    }
    
    // MARK: - JSONC Support
    
    private func preprocessJSONC(_ data: Data) -> Data {
        guard let string = String(data: data, encoding: .utf8) else { return data }
        
        let processedString = string.components(separatedBy: .newlines)
            .map { line in
                // Remove full-line comments
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { return "" }
                
                // Remove inline comments (simple approach - doesn't handle strings with // inside)
                if let commentIndex = line.range(of: "//")?.lowerBound {
                    return String(line[..<commentIndex]).trimmingCharacters(in: .whitespaces)
                }
                return line
            }
            .joined(separator: "\n")
        
        return processedString.data(using: .utf8) ?? data
    }
}

// MARK: - JSON Config File Format

struct VocabularyConfig: Codable {
    let version: String
    let vocabulary: [String: [String]]  // canonical -> aliases
    let rules: [String: CanonRule]      // canonical -> case rules
    
    private enum CodingKeys: String, CodingKey {
        case version
        case vocabulary
        case rules
    }
}

// MARK: - Global Instance

extension VocabularyConfigManager {
    static let shared = VocabularyConfigManager()
}

