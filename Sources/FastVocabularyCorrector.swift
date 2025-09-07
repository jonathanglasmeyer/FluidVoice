import Foundation
import os.log

// MARK: - Data Models

enum CaseMode: String, Codable {
    case upper      // "API"
    case camel      // "TypeScript"  
    case mixed      // "GitHub" (exact as stored)
    case exact      // exact canonical form
}

struct CanonRule: Codable {
    let caseMode: CaseMode
    
    init(caseMode: CaseMode = .mixed) {
        self.caseMode = caseMode
    }
}

struct VocabularyGlossary: Codable {
    let canonicalMap: [String: [String]]  // "GitHub": ["git hub", "github"]
    let rules: [String: CanonRule]
    
    init() {
        self.canonicalMap = [:]
        self.rules = [:]
    }
    
    init(canonicalMap: [String: [String]], rules: [String: CanonRule] = [:]) {
        self.canonicalMap = canonicalMap
        self.rules = rules
    }
}

// MARK: - Vocabulary Settings (File-Based Only)

struct VocabularySettings {
    private static let configManager = VocabularyConfigManager.shared
    
    static func getGlossary() -> VocabularyGlossary {
        return configManager.loadGlossary()
    }
    
    static func setGlossary(_ glossary: VocabularyGlossary) {
        configManager.saveGlossary(glossary)
    }
    
    static func getTerms() -> [String] {
        let glossary = getGlossary()
        return Array(glossary.canonicalMap.keys)
    }
    
    static func addTerm(_ canonical: String, aliases: [String] = [], caseMode: CaseMode = .mixed) {
        configManager.addTerm(canonical, aliases: aliases, caseMode: caseMode)
    }
    
    static func removeTerm(_ canonical: String) {
        configManager.removeTerm(canonical)
    }
    
    static var configFilePath: String {
        configManager.configFilePath
    }
}

// MARK: - Match Result

struct VocabMatch {
    let startIndex: Int
    let endIndex: Int
    let canonical: String
    let priority: Int
    let caseMode: CaseMode
    
    var length: Int { endIndex - startIndex }
}

// MARK: - Fast Vocabulary Corrector

final class FastVocabularyCorrector {
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "FastVocabularyCorrector")
    private var automaton: AhoCorasickAutomaton?
    private var glossary: VocabularyGlossary
    
    init() {
        self.glossary = VocabularyGlossary()
        self.automaton = nil
    }
    
    func load(glossary: VocabularyGlossary) {
        self.glossary = glossary
        self.automaton = buildAutomaton(from: glossary)
        logger.infoDev("FastVocabularyCorrector loaded with \(glossary.canonicalMap.count) canonical terms")
    }
    
    func correct(_ text: String, maxTimeMs: Int = 30) -> String {
        let startTime = DispatchTime.now()
        
        guard let automaton = automaton, !glossary.canonicalMap.isEmpty else {
            return text
        }
        
        // Phase 1: Normalization (streaming, O(n))
        let (normalizedText, originalIndices) = normalizeStream(text)
        
        if timeExceeded(startTime, maxMs: maxTimeMs / 4) {
            logger.infoDev("FastVocabularyCorrector: timeout during normalization")
            return text
        }
        
        // Phase 2: Multi-Pattern Replace (Aho-Corasick, O(n))
        let matches = scanAhoCorasick(automaton, normalizedText)
        let filteredMatches = filterOverlaps(matches)
        
        if timeExceeded(startTime, maxMs: maxTimeMs * 3 / 4) {
            logger.infoDev("FastVocabularyCorrector: timeout during scanning")
            return text
        }
        
        // Phase 3: Replace with original indices mapping
        let result = applyReplacements(text, matches: filteredMatches, originalIndices: originalIndices)
        
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        logger.infoDev("FastVocabularyCorrector: completed in \(String(format: "%.1f", elapsed))ms, \(filteredMatches.count) replacements")
        
        return result
    }
    
    // MARK: - Phase 1: Normalization
    
    private func normalizeStream(_ text: String) -> (normalized: String, originalIndices: [Int]) {
        var result = ""
        var indices: [Int] = []
        var i = text.startIndex
        
        while i < text.endIndex {
            let char = text[i]
            
            // Letter spacing detection: "a p i" -> "api" 
            if char.isLetter && i < text.index(text.endIndex, offsetBy: -4) {
                let next1 = text.index(after: i)
                let next2 = text.index(next1, offsetBy: 1)
                let next3 = text.index(next2, offsetBy: 1)
                let next4 = text.index(next3, offsetBy: 1)
                
                if next4 < text.endIndex &&
                   text[next1] == " " && text[next2].isLetter &&
                   text[next3] == " " && text[next4].isLetter {
                    // Found "a p i" pattern - collapse to "api"
                    result.append(char)
                    result.append(text[next2])
                    result.append(text[next4])
                    indices.append(text.distance(from: text.startIndex, to: i))
                    indices.append(text.distance(from: text.startIndex, to: next2))
                    indices.append(text.distance(from: text.startIndex, to: next4))
                    i = text.index(after: next4)
                    continue
                }
            }
            
            // Regular character processing
            if char.isWhitespace {
                if !result.isEmpty && result.last != " " {
                    result.append(" ")
                    indices.append(text.distance(from: text.startIndex, to: i))
                }
            } else {
                result.append(char)
                indices.append(text.distance(from: text.startIndex, to: i))
            }
            
            i = text.index(after: i)
        }
        
        return (result.trimmingCharacters(in: .whitespaces), indices)
    }
    
    // MARK: - Phase 2: Aho-Corasick Implementation
    
    private func buildAutomaton(from glossary: VocabularyGlossary) -> AhoCorasickAutomaton {
        var patterns: [(pattern: String, canonical: String, priority: Int)] = []
        
        for (canonical, aliases) in glossary.canonicalMap {
            let priority = canonical.contains(" ") ? 100 : 50 // Multi-word gets higher priority
            
            for alias in aliases {
                let normalized = alias.lowercased().replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
                patterns.append((pattern: normalized, canonical: canonical, priority: priority + normalized.count))
            }
        }
        
        return AhoCorasickAutomaton(patterns: patterns)
    }
    
    private func scanAhoCorasick(_ automaton: AhoCorasickAutomaton, _ text: String) -> [VocabMatch] {
        var matches: [VocabMatch] = []
        let lowercased = text.lowercased()
        
        for result in automaton.search(in: lowercased) {
            let canonical = result.canonical
            let caseMode = glossary.rules[canonical]?.caseMode ?? .mixed
            
            // Check word boundaries for safety
            if requiresWordBoundaries(canonical) && !hasWordBoundaries(text, start: result.startIndex, end: result.endIndex) {
                continue
            }
            
            let match = VocabMatch(
                startIndex: result.startIndex,
                endIndex: result.endIndex,
                canonical: canonical,
                priority: result.priority,
                caseMode: caseMode
            )
            matches.append(match)
        }
        
        return matches
    }
    
    private func requiresWordBoundaries(_ canonical: String) -> Bool {
        // Terms with punctuation don't need word boundaries
        return !canonical.contains(".") && !canonical.contains("-") && !canonical.contains("_")
    }
    
    private func hasWordBoundaries(_ text: String, start: Int, end: Int) -> Bool {
        let beforeOK = start == 0 || !text[text.index(text.startIndex, offsetBy: start - 1)].isWordChar
        let afterOK = end >= text.count || !text[text.index(text.startIndex, offsetBy: end)].isWordChar
        return beforeOK && afterOK
    }
    
    // MARK: - Phase 3: Overlap Filtering & Replacement
    
    private func filterOverlaps(_ matches: [VocabMatch]) -> [VocabMatch] {
        let sorted = matches.sorted { a, b in
            if a.startIndex != b.startIndex {
                return a.startIndex < b.startIndex
            }
            if a.length != b.length {
                return a.length > b.length // Longer match wins
            }
            return a.priority > b.priority // Higher priority wins
        }
        
        var result: [VocabMatch] = []
        var lastEnd = 0
        
        for match in sorted {
            if match.startIndex >= lastEnd {
                result.append(match)
                lastEnd = match.endIndex
            }
        }
        
        return result
    }
    
    private func applyReplacements(_ text: String, matches: [VocabMatch], originalIndices: [Int]) -> String {
        guard !matches.isEmpty else { return text }
        
        var result = ""
        var lastIndex = 0
        
        for match in matches.sorted(by: { $0.startIndex < $1.startIndex }) {
            // Add text before match
            if match.startIndex > lastIndex {
                let startIdx = text.index(text.startIndex, offsetBy: lastIndex)
                let endIdx = text.index(text.startIndex, offsetBy: match.startIndex)
                result.append(String(text[startIdx..<endIdx]))
            }
            
            // Add replacement with proper case
            let replacement = applyCaseMode(match.canonical, caseMode: match.caseMode)
            result.append(replacement)
            
            lastIndex = match.endIndex
        }
        
        // Add remaining text
        if lastIndex < text.count {
            let startIdx = text.index(text.startIndex, offsetBy: lastIndex)
            result.append(String(text[startIdx...]))
        }
        
        return result
    }
    
    private func applyCaseMode(_ canonical: String, caseMode: CaseMode) -> String {
        switch caseMode {
        case .upper:
            return canonical.uppercased()
        case .camel, .mixed, .exact:
            return canonical
        }
    }
    
    // MARK: - Utilities
    
    private func timeExceeded(_ startTime: DispatchTime, maxMs: Int) -> Bool {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        return elapsed > Double(maxMs)
    }
}

// MARK: - Character Extensions

extension Character {
    var isWordChar: Bool {
        return isLetter || isNumber || self == "_"
    }
}

// MARK: - Aho-Corasick Automaton (Simplified Implementation)

struct AhoCorasickResult {
    let startIndex: Int
    let endIndex: Int
    let canonical: String
    let priority: Int
}

final class AhoCorasickAutomaton {
    private struct Pattern {
        let text: String
        let canonical: String
        let priority: Int
    }
    
    private let patterns: [Pattern]
    
    init(patterns: [(pattern: String, canonical: String, priority: Int)]) {
        self.patterns = patterns.map { Pattern(text: $0.pattern, canonical: $0.canonical, priority: $0.priority) }
    }
    
    func search(in text: String) -> [AhoCorasickResult] {
        var results: [AhoCorasickResult] = []
        
        // Simplified implementation - brute force for now
        // TODO: Implement proper Aho-Corasick with failure links for production
        for pattern in patterns {
            var searchStart = text.startIndex
            
            while searchStart < text.endIndex {
                if let range = text[searchStart...].range(of: pattern.text, options: [.caseInsensitive]) {
                    let startIndex = text.distance(from: text.startIndex, to: range.lowerBound)
                    let endIndex = text.distance(from: text.startIndex, to: range.upperBound)
                    
                    results.append(AhoCorasickResult(
                        startIndex: startIndex,
                        endIndex: endIndex,
                        canonical: pattern.canonical,
                        priority: pattern.priority
                    ))
                    
                    searchStart = range.upperBound
                } else {
                    break
                }
            }
        }
        
        return results
    }
}