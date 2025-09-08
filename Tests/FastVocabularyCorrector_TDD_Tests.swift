import XCTest
@testable import FluidVoice

final class FastVocabularyCorrector_TDD_Tests: XCTestCase {
    
    var corrector: FastVocabularyCorrector!
    
    override func setUp() {
        super.setUp()
        corrector = FastVocabularyCorrector()
        
        // Simple test glossary
        let canonicalMap: [String: [String]] = [
            "API": ["api"],
            "CLAUDE.md": ["claude m d"]
        ]
        
        let rules: [String: CanonRule] = [
            "API": CanonRule(caseMode: .upper),
            "CLAUDE.md": CanonRule(caseMode: .exact)
        ]
        
        let glossary = VocabularyGlossary(canonicalMap: canonicalMap, rules: rules)
        corrector.load(glossary: glossary)
    }
    
    override func tearDown() {
        corrector = nil
        super.tearDown()
    }
    
    // TDD Step 1: Green - Already working simple case
    func test_api_with_period_becomes_API() {
        let input = "api."
        let expected = "API"
        let result = corrector.correct(input)
        
        XCTAssertEqual(result, expected, "Should strip trailing period from 'api.' and return 'API'")
    }
    
    // TDD Step 2a: Debug - Test multi-word without punctuation first
    func test_claude_m_d_without_punctuation_becomes_CLAUDE_md() {
        let input = "claude m d"
        let expected = "CLAUDE.md"
        let result = corrector.correct(input)
        
        XCTAssertEqual(result, expected, "Should convert 'claude m d' to 'CLAUDE.md'")
    }
    
    // TDD Step 2: Red - Multi-word failing test
    func test_claude_m_d_with_period_becomes_CLAUDE_md() {
        let input = "claude m d."
        let expected = "CLAUDE.md"
        let result = corrector.correct(input)
        
        XCTAssertEqual(result, expected, "Should strip trailing period from 'claude m d.' and return 'CLAUDE.md'")
    }
}