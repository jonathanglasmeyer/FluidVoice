import Foundation
import os.log

enum FilterLanguage: String, CaseIterable {
    case german = "de"
    case english = "en"
    case auto = "auto"
    
    var displayName: String {
        switch self {
        case .german: return "German"
        case .english: return "English"
        case .auto: return "Auto-detect"
        }
    }
}

enum FilterSensitivity: String, CaseIterable {
    case conservative = "conservative"
    case moderate = "moderate"
    case aggressive = "aggressive"
    
    var displayName: String {
        switch self {
        case .conservative: return "Conservative"
        case .moderate: return "Moderate"
        case .aggressive: return "Aggressive"
        }
    }
}

struct FillerMatch {
    let range: NSRange
    let originalText: String
    let language: FilterLanguage
}

struct FillerSoundProcessor {
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "FillerSoundProcessor")
    
    private static let germanFillers = [
        "äh", "ähm", "öh", "ehm", "ähem", "öhm", "hm", "hmm"
    ]
    
    private static let englishFillers = [
        "uh", "um", "er", "ah", "uhm", "erm", "hmm", "mm"
    ]
    
    func removeFillerSounds(from text: String, language: FilterLanguage = .auto, sensitivity: FilterSensitivity = .moderate) -> String {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard !text.isEmpty else { return text }
        
        let detectedLanguage = language == .auto ? detectLanguage(in: text) : language
        let fillerPatterns = getFillerPatterns(for: detectedLanguage, sensitivity: sensitivity)
        
        var processedText = text
        var totalMatches = 0
        
        for pattern in fillerPatterns {
            let matches = findMatches(pattern: pattern, in: processedText)
            totalMatches += matches.count
            
            for match in matches.reversed() {
                let nsRange = NSRange(location: match.range.location, length: match.range.length)
                let range = Range(nsRange, in: processedText)
                if let range = range {
                    processedText.removeSubrange(range)
                }
            }
        }
        
        let cleanedText = cleanupWhitespace(processedText)
        let processingTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        
        logger.infoDev("Filler sound removal: \(totalMatches) matches removed, \(String(format: "%.1f", processingTime))ms, language=\(detectedLanguage.rawValue)")
        
        return cleanedText
    }
    
    func detectFillerPatterns(in text: String) -> [FillerMatch] {
        let germanMatches = findFillerMatches(text: text, language: .german)
        let englishMatches = findFillerMatches(text: text, language: .english)
        return germanMatches + englishMatches
    }
    
    private func findFillerMatches(text: String, language: FilterLanguage) -> [FillerMatch] {
        let fillers = language == .german ? Self.germanFillers : Self.englishFillers
        var matches: [FillerMatch] = []
        
        for filler in fillers {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: filler))\\b"
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let nsString = text as NSString
                let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
                
                for result in results {
                    let matchedText = nsString.substring(with: result.range)
                    let match = FillerMatch(
                        range: result.range,
                        originalText: matchedText,
                        language: language
                    )
                    matches.append(match)
                }
            } catch {
                logger.error("Regex error for pattern '\(pattern)': \(error.localizedDescription)")
            }
        }
        
        return matches
    }
    
    private func detectLanguage(in text: String) -> FilterLanguage {
        let germanMatches = findFillerMatches(text: text, language: .german).count
        let englishMatches = findFillerMatches(text: text, language: .english).count
        
        if germanMatches > englishMatches {
            return .german
        } else if englishMatches > germanMatches {
            return .english
        } else {
            return .german
        }
    }
    
    private func getFillerPatterns(for language: FilterLanguage, sensitivity: FilterSensitivity) -> [String] {
        let baseFillersGerman = Self.germanFillers
        let baseFillersEnglish = Self.englishFillers
        
        let fillers: [String]
        switch language {
        case .german:
            fillers = baseFillersGerman
        case .english:
            fillers = baseFillersEnglish
        case .auto:
            fillers = baseFillersGerman + baseFillersEnglish
        }
        
        var patterns: [String] = []
        
        for filler in fillers {
            switch sensitivity {
            case .conservative:
                patterns.append("\\b\(NSRegularExpression.escapedPattern(for: filler))\\b(?=[\\s.,!?;:]|$)")
            case .moderate:
                patterns.append("\\b\(NSRegularExpression.escapedPattern(for: filler))\\b")
            case .aggressive:
                patterns.append("(?:^|\\s)\(NSRegularExpression.escapedPattern(for: filler))(?=\\s|[.,!?;:]|$)")
            }
        }
        
        return patterns
    }
    
    private func findMatches(pattern: String, in text: String) -> [FillerMatch] {
        var matches: [FillerMatch] = []
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let nsString = text as NSString
            let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
            
            for result in results {
                let matchedText = nsString.substring(with: result.range)
                
                if !isLegitimateWord(matchedText, in: text, at: result.range) {
                    let match = FillerMatch(
                        range: result.range,
                        originalText: matchedText,
                        language: .auto
                    )
                    matches.append(match)
                }
            }
        } catch {
            logger.error("Regex error for pattern '\(pattern)': \(error.localizedDescription)")
        }
        
        return matches
    }
    
    private func isLegitimateWord(_ word: String, in text: String, at range: NSRange) -> Bool {
        let nsString = text as NSString
        
        let contextStart = max(0, range.location - 10)
        let contextEnd = min(nsString.length, range.location + range.length + 10)
        let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
        let context = nsString.substring(with: contextRange).lowercased()
        
        if context.contains("uh-oh") || context.contains("um-hum") {
            return true
        }
        
        if range.location > 0 {
            let prevChar = nsString.substring(with: NSRange(location: range.location - 1, length: 1))
            if prevChar == "-" || prevChar == "'" {
                return true
            }
        }
        
        if range.location + range.length < nsString.length {
            let nextChar = nsString.substring(with: NSRange(location: range.location + range.length, length: 1))
            if nextChar == "-" || nextChar == "'" {
                return true
            }
        }
        
        return false
    }
    
    private func cleanupWhitespace(_ text: String) -> String {
        var cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s*,\\s*,", with: ",", options: .regularExpression)
            .replacingOccurrences(of: "\\.{3,}", with: "...", options: .regularExpression)
            .replacingOccurrences(of: "\\s+([.,!?;:])", with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Fix sentence-starting punctuation (e.g., ", ich bin..." -> "Ich bin...")
        cleaned = cleaned.replacingOccurrences(of: "^[,;:]+\\s*", with: "", options: .regularExpression)
        
        // Capitalize first letter after cleanup
        if !cleaned.isEmpty {
            cleaned = String(cleaned.prefix(1).uppercased() + cleaned.dropFirst())
        }
        
        return cleaned
    }
}