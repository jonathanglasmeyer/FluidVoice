import Foundation
import os.log
import CryptoKit

// MARK: - File-Based Vocabulary Configuration Manager

final class VocabularyConfigManager {
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "VocabularyConfig")
    private let fileManager = FileManager.default
    
    // In-memory cache with SHA256 tracking
    private var cachedGlossary: VocabularyGlossary?
    private var cachedFileHash: String?
    
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
        // Check if file exists
        guard fileManager.fileExists(atPath: vocabularyConfigURL.path) else {
            // No file exists - create default
            logger.infoDev("Creating default vocabulary config at \(self.vocabularyConfigURL.path)")
            let defaultGlossary = createDefaultGlossary()
            saveToFile(defaultGlossary)
            return defaultGlossary
        }
        
        // Calculate current file hash
        let currentHash = calculateFileHash()
        
        // Return cached version if hash hasn't changed
        if let cachedGlossary = cachedGlossary, 
           let cachedHash = cachedFileHash,
           currentHash == cachedHash {
            logger.infoDev("Using cached vocabulary config (hash unchanged: \(String(currentHash.prefix(8)))...)")
            return cachedGlossary
        }
        
        // Hash changed or no cache - load from file
        if let glossary = loadFromFile() {
            // Update cache
            self.cachedGlossary = glossary
            self.cachedFileHash = currentHash
            logger.infoDev("Loaded vocabulary config from file (hash: \(String(currentHash.prefix(8)))...)")
            return glossary
        }
        
        // Fallback to default if file load failed
        logger.infoDev("Failed to load config file, creating default")
        let defaultGlossary = createDefaultGlossary()
        saveToFile(defaultGlossary)
        self.cachedGlossary = defaultGlossary
        self.cachedFileHash = calculateFileHash()
        return defaultGlossary
    }
    
    func saveGlossary(_ glossary: VocabularyGlossary) {
        saveToFile(glossary)
        // Invalidate cache when saving
        self.cachedGlossary = nil
        self.cachedFileHash = nil
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
        
        // For new files, create with comprehensive JSONC documentation
        let isNewFile = !fileManager.fileExists(atPath: vocabularyConfigURL.path)
        
        if isNewFile {
            createDocumentedJSONCTemplate(glossary)
        } else {
            // For existing files, save as regular JSON to preserve existing format
            saveAsJSON(glossary)
        }
    }
    
    private func createDocumentedJSONCTemplate(_ glossary: VocabularyGlossary) {
        // Use .jsonc extension for the documented template
        let jsoncURL = configDirectory.appendingPathComponent("vocabulary.jsonc")
        
        let jsoncContent = createJSONCTemplate(glossary)
        
        do {
            try jsoncContent.write(to: jsoncURL, atomically: true, encoding: .utf8)
            logger.infoDev("Created documented vocabulary config template at \(jsoncURL.path)")
        } catch {
            logger.error("Failed to create JSONC template: \(error.localizedDescription)")
            // Fallback to regular JSON
            saveAsJSON(glossary)
        }
    }
    
    private func saveAsJSON(_ glossary: VocabularyGlossary) {
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
    
    private func createJSONCTemplate(_ glossary: VocabularyGlossary) -> String {
        return """
{
  // FluidVoice Vocabulary Correction Configuration
  // Location: ~/.config/fluidvoice/vocabulary.jsonc
  // 
  // ============================================================================
  // SUPPORTED PATTERN TYPES (as of 2025-09-08)
  // ============================================================================
  //
  // ✅ FULLY SUPPORTED:
  //
  // 1. Single-word corrections:
  //    Input: "api"       → Output: "API"
  //    Input: "github"    → Output: "GitHub"
  //    Input: "typescript" → Output: "TypeScript"
  //
  // 2. Single-word with punctuation:
  //    Input: "api."      → Output: "API"
  //    Input: "github!"   → Output: "GitHub"
  //    Input: "api?"      → Output: "API"
  //    (Automatically handles: . ! ? , ; : ' " ) )
  //
  // 3. Multi-word patterns (FIXED 2025-09-08):
  //    Input: "claude m d"    → Output: "CLAUDE.md"
  //    Input: "read me"       → Output: "README"  
  //    Input: "docker compose" → Output: "docker-compose"
  //
  // 4. Multi-word with punctuation:
  //    Input: "claude m d."   → Output: "CLAUDE.md"
  //    Input: "read me!"      → Output: "README"
  //
  // ⚠️  LIMITATIONS:
  //
  // - Letter-spacing patterns like "i o s" → "iOS" may not work reliably
  // - Very long multi-word patterns may have issues
  // - Complex punctuation within words needs testing
  //
  // ============================================================================
  // CONFIGURATION STRUCTURE
  // ============================================================================
  
  "version": "1.0",
  
  // VOCABULARY: Maps canonical terms to their speech recognition aliases
  // Format: "CANONICAL_OUTPUT": ["spoken_alias_1", "spoken_alias_2", ...]
  "vocabulary": {
    
    // ✅ Single-word technical terms (acronyms, tools, etc.)
    "API": ["api"],
    "GitHub": ["github"],  
    "OAuth": ["oauth"],
    "TypeScript": ["typescript"],
    "SSH": ["ssh"],
    "URL": ["url"],
    "SQL": ["sql"],
    "JWT": ["jwt"],
    "JSON": ["json"],
    "HTML": ["html"],
    "CSS": ["css"],
    "HTTP": ["http"],
    "HTTPS": ["https"],
    "CLI": ["cli"],
    
    // ✅ Multi-word patterns (works after 2025-09-08 fix)
    "CLAUDE.md": ["claude m d"],
    "README": ["read me"],
    "docker-compose": ["docker compose"],
    "Node.js": ["node j s"],
    
    // Additional useful patterns  
    "webpack": ["web pack"],
    "VS Code": ["v s code", "visual studio code"],
    "npm": ["n p m"]
    
    // ADD YOUR CUSTOM TERMS HERE:
    // "YourTerm": ["how it sounds when spoken"],
    // "Custom.config": ["custom config"],
    // "MyProject": ["my project"]
  },
  
  // RULES: Define how each canonical term should be formatted
  "rules": {
    
    // "upper": CONVERTS TO UPPERCASE (good for acronyms)
    "API": { "caseMode": "upper" },
    "SSH": { "caseMode": "upper" },
    "URL": { "caseMode": "upper" },
    "SQL": { "caseMode": "upper" },
    "JWT": { "caseMode": "upper" },
    "JSON": { "caseMode": "upper" },
    "HTML": { "caseMode": "upper" },
    "CSS": { "caseMode": "upper" },
    "HTTP": { "caseMode": "upper" },
    "HTTPS": { "caseMode": "upper" },
    "CLI": { "caseMode": "upper" },
    
    // "mixed": Uses PascalCase/CamelCase (good for proper names)
    "GitHub": { "caseMode": "mixed" },
    "OAuth": { "caseMode": "mixed" },
    "TypeScript": { "caseMode": "mixed" },
    "Node.js": { "caseMode": "mixed" },
    "VS Code": { "caseMode": "mixed" },
    
    // "exact": Uses the exact spelling as defined in vocabulary (good for files/commands)
    "CLAUDE.md": { "caseMode": "exact" },
    "README": { "caseMode": "exact" },
    "docker-compose": { "caseMode": "exact" },
    "webpack": { "caseMode": "exact" },
    "npm": { "caseMode": "exact" }
    
    // CASE MODE OPTIONS:
    // - "upper": FULL UPPERCASE
    // - "mixed": PascalCase/Mixed Case (as written in vocabulary key)  
    // - "exact": Exact case as specified in vocabulary key
    // - "camel": camelCase (first letter lowercase)
  }
  
  // ============================================================================
  // USAGE EXAMPLES
  // ============================================================================
  //
  // Speech Input          → Corrected Output
  // ──────────────────────────────────────────────────────────────────────────
  // "call the api"        → "call the API"
  // "use github for this" → "use GitHub for this"  
  // "edit claude m d"     → "edit CLAUDE.md"
  // "check the read me"   → "check the README"
  // "run docker compose" → "run docker-compose"
  // "api."               → "API"
  // "claude m d!"        → "CLAUDE.md"
  //
  // ============================================================================
  // TROUBLESHOOTING
  // ============================================================================
  //
  // If corrections don't work:
  // 1. Check that your spoken phrase exactly matches the alias
  // 2. Test without punctuation first  
  // 3. Ensure your canonical term is in both "vocabulary" and "rules" sections
  // 4. Restart FluidVoice to reload configuration
  // 5. Check logs: /usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info
  //
  // For support: https://github.com/FluidVoice/FluidVoice/issues
}
"""
    }
    
    private func createDefaultGlossary() -> VocabularyGlossary {
        let defaultMap: [String: [String]] = [
            // ✅ Single-word patterns (fully supported)
            "API": ["api"],
            "GitHub": ["github"],
            "OAuth": ["oauth"],
            "TypeScript": ["typescript"],
            "SSH": ["ssh"],
            "URL": ["url"],  
            "SQL": ["sql"],
            "JWT": ["jwt"],
            "JSON": ["json"],
            "HTML": ["html"],
            "CSS": ["css"],
            "HTTP": ["http"],
            "HTTPS": ["https"],
            "CLI": ["cli"],
            
            // ✅ Multi-word patterns (supported after 2025-09-08 fix)
            "CLAUDE.md": ["claude m d"],
            "README": ["read me"],
            "docker-compose": ["docker compose"],
            "Node.js": ["node j s"],
            
            // Additional useful patterns
            "webpack": ["web pack"],
            "VS Code": ["v s code", "visual studio code"],
            "npm": ["n p m"]
        ]
        
        let defaultRules: [String: CanonRule] = [
            // Upper case for acronyms
            "API": CanonRule(caseMode: .upper),
            "SSH": CanonRule(caseMode: .upper),
            "URL": CanonRule(caseMode: .upper),
            "SQL": CanonRule(caseMode: .upper),
            "JWT": CanonRule(caseMode: .upper),
            "JSON": CanonRule(caseMode: .upper),
            "HTML": CanonRule(caseMode: .upper),
            "CSS": CanonRule(caseMode: .upper),
            "HTTP": CanonRule(caseMode: .upper),
            "HTTPS": CanonRule(caseMode: .upper),
            "CLI": CanonRule(caseMode: .upper),
            
            // Mixed case for proper names
            "GitHub": CanonRule(caseMode: .mixed),
            "OAuth": CanonRule(caseMode: .mixed),
            "TypeScript": CanonRule(caseMode: .mixed),
            "Node.js": CanonRule(caseMode: .mixed),
            "VS Code": CanonRule(caseMode: .mixed),
            
            // Exact case for files/commands
            "CLAUDE.md": CanonRule(caseMode: .exact),
            "README": CanonRule(caseMode: .exact),
            "docker-compose": CanonRule(caseMode: .exact),
            "webpack": CanonRule(caseMode: .exact),
            "npm": CanonRule(caseMode: .exact)
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
    
    // MARK: - File Hash Calculation
    
    private func calculateFileHash() -> String {
        guard let data = try? Data(contentsOf: vocabularyConfigURL) else {
            return ""
        }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
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

