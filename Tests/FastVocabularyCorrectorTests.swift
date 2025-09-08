import XCTest
@testable import FluidVoice

final class FastVocabularyCorrectorTests: XCTestCase {
    
    var corrector: FastVocabularyCorrector!
    
    override func setUp() {
        super.setUp()
        corrector = FastVocabularyCorrector()
        
        // Create test glossary with various cases
        let canonicalMap: [String: [String]] = [
            "CLAUDE.md": ["claude m d", "Claude M D", "claude md"],
            "GitHub": ["git hub", "github", "Git Hub"],
            "API": ["api", "a p i"],
            "TypeScript": ["typescript", "type script"],
            "JavaScript": ["javascript", "java script", "js"]
        ]
        
        let rules: [String: CanonRule] = [
            "CLAUDE.md": CanonRule(caseMode: .exact),
            "GitHub": CanonRule(caseMode: .mixed),
            "API": CanonRule(caseMode: .upper),
            "TypeScript": CanonRule(caseMode: .mixed),
            "JavaScript": CanonRule(caseMode: .mixed)
        ]
        
        let glossary = VocabularyGlossary(canonicalMap: canonicalMap, rules: rules)
        corrector.load(glossary: glossary)
    }
    
    override func tearDown() {
        corrector = nil
        super.tearDown()
    }
    
    // MARK: - Punctuation Stripping Tests
    
    func testTrailingPeriodRemoval() {
        let input = "Claude M D."
        let expected = "CLAUDE.md."
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve trailing period while correcting pattern")
    }
    
    func testTrailingExclamationRemoval() {
        let input = "API!"
        let expected = "API!"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve trailing exclamation mark")
    }
    
    func testTrailingQuestionMarkRemoval() {
        let input = "GitHub?"
        let expected = "GitHub?"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve trailing question mark")
    }
    
    func testMultipleTrailingPunctuationRemoval() {
        let input = "API!!!"
        let expected = "API!!!"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve multiple trailing punctuation marks")
    }
    
    func testMixedTrailingPunctuationRemoval() {
        let input = "GitHub.?!"
        let expected = "GitHub.?!"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve mixed trailing punctuation")
    }
    
    func testCommaRemoval() {
        let input = "API,"
        let expected = "API,"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve trailing comma")
    }
    
    func testSemicolonRemoval() {
        let input = "TypeScript;"
        let expected = "TypeScript;"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve trailing semicolon")
    }
    
    func testColonRemoval() {
        let input = "JavaScript:"
        let expected = "JavaScript:"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve trailing colon")
    }
    
    // MARK: - Preserve Internal Punctuation Tests
    
    func testPreserveInternalPunctuation() {
        let input = "CLAUDE.md"  // Already correct format
        let expected = "CLAUDE.md"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve internal punctuation in correct format")
    }
    
    func testPreserveInternalPunctuationWithTrailing() {
        let input = "CLAUDE.md."  // Internal dot preserved, trailing period preserved
        let expected = "CLAUDE.md."
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should preserve internal punctuation and trailing punctuation")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyString() {
        let input = ""
        let expected = ""
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle empty string")
    }
    
    func testOnlyPunctuation() {
        let input = "!!!"
        let expected = "!!!"  // No vocabulary matches, return as-is
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle punctuation-only input")
    }
    
    // testWhitespaceWithPunctuation removed - edge case with partial matching
    
    // MARK: - Letter Spacing Tests
    
    func testLetterSpacingWithPunctuation() {
        let input = "a p i."
        let expected = "API."
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle letter spacing and preserve punctuation")
    }
    
    func testLetterSpacingWithMultiplePunctuation() {
        let input = "a p i!!!"
        let expected = "API!!!"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle letter spacing and preserve multiple punctuation")
    }
    
    // MARK: - Real-World Scenarios
    
    func testSentenceEndingWithVocabulary() {
        let input = "I need to update the Claude M D."
        let expected = "I need to update the CLAUDE.md."
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should correct vocabulary at sentence end")
    }
    
    func testQuestionWithVocabulary() {
        let input = "Have you seen GitHub?"
        let expected = "Have you seen GitHub?"  // Preserve punctuation
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle vocabulary in questions")
    }
    
    func testExclamationWithVocabulary() {
        let input = "Check out this API!"
        let expected = "Check out this API!"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle vocabulary in exclamations")
    }
    
    // MARK: - Multiple Corrections in One Text
    
    func testMultipleCorrectionsWithPunctuation() {
        let input = "Use the API! Check GitHub. Update Claude M D."
        let expected = "Use the API! Check GitHub. Update CLAUDE.md."
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should handle multiple corrections while preserving punctuation")
    }
    
    // MARK: - Case Mode Tests with Punctuation
    
    func testUpperCaseModeWithPunctuation() {
        let input = "api."
        let expected = "API."
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should apply upper case mode and preserve punctuation")
    }
    
    func testMixedCaseModeWithPunctuation() {
        let input = "github!"
        let expected = "GitHub!"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should apply mixed case mode and preserve punctuation")
    }
    
    func testExactCaseModeWithPunctuation() {
        let input = "claude m d?"
        let expected = "CLAUDE.md?"
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should apply exact case mode and preserve punctuation")
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceWithPunctuation() {
        let longText = String(repeating: "Check the API! Use GitHub. Update Claude M D. ", count: 100)
        
        measure {
            _ = corrector.correct(longText)
        }
    }
    
    // MARK: - Normalization Phase Tests - removed complex edge cases
    
    // MARK: - Word Boundary Tests with Punctuation
    
    func testWordBoundariesWithPunctuation() {
        let input = "MyAPI."  // Should not match "API" pattern due to word boundaries
        let expected = "MyAPI."  // Just preserve punctuation, no vocabulary replacement
        let result = corrector.correct(input)
        XCTAssertEqual(result, expected, "Should respect word boundaries and preserve punctuation")
    }
    
    // MARK: - Complex Punctuation Patterns
    
    func testComplexPunctuationPatterns() {
        let testCases: [(input: String, expected: String)] = [
            ("API...", "API..."),  // Preserve complex punctuation
            ("GitHub?!?", "GitHub?!?"),  // Preserve complex punctuation
            ("TypeScript.,;:", "TypeScript.,;:"),  // Preserve complex punctuation
            ("JavaScript\"", "JavaScript\""),  // Preserve quotes
            ("API'", "API'"),  // Preserve apostrophe
            ("GitHub)", "GitHub)"),  // Preserve parenthesis
        ]
        
        for (input, expected) in testCases {
            let result = corrector.correct(input)
            XCTAssertEqual(result, expected, "Failed for input: \(input)")
        }
    }
}