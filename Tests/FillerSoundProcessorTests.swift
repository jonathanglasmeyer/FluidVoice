import XCTest
@testable import FluidVoice

final class FillerSoundProcessorTests: XCTestCase {
    
    var processor: FillerSoundProcessor!
    
    override func setUp() {
        super.setUp()
        processor = FillerSoundProcessor()
    }
    
    override func tearDown() {
        processor = nil
        super.tearDown()
    }
    
    // MARK: - German Filler Sound Tests
    
    func testRemoveGermanFillers() {
        let input = "Das ist äh sehr interessant und ähm wichtig für uns."
        let output = processor.removeFillerSounds(from: input, language: .german)
        let expected = "Das ist sehr interessant und wichtig für uns."
        XCTAssertEqual(output, expected)
    }
    
    func testRemoveGermanFillersWithPunctuation() {
        let input = "Ich denke, äh, das ist richtig. Ähm... ja, genau."
        let output = processor.removeFillerSounds(from: input, language: .german)
        let expected = "Ich denke, das ist richtig. ja, genau."
        XCTAssertEqual(output, expected)
    }
    
    func testGermanFillersCaseInsensitive() {
        let input = "Das ist ÄH sehr gut und ÄHM perfekt."
        let output = processor.removeFillerSounds(from: input, language: .german)
        let expected = "Das ist sehr gut und perfekt."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - English Filler Sound Tests
    
    func testRemoveEnglishFillers() {
        let input = "This is uh very interesting and um important to us."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "This is very interesting and important to us."
        XCTAssertEqual(output, expected)
    }
    
    func testRemoveEnglishFillersWithPunctuation() {
        let input = "I think, uh, this is right. Um... yes, exactly."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "I think, this is right. yes, exactly."
        XCTAssertEqual(output, expected)
    }
    
    func testEnglishFillersCaseInsensitive() {
        let input = "This is UH very good and UM perfect."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "This is very good and perfect."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Auto-Detection Tests
    
    func testAutoDetectGerman() {
        let input = "Das ist äh sehr gut und ähm wichtig."
        let output = processor.removeFillerSounds(from: input, language: .auto)
        let expected = "Das ist sehr gut und wichtig."
        XCTAssertEqual(output, expected)
    }
    
    func testAutoDetectEnglish() {
        let input = "This is uh very good and um important."
        let output = processor.removeFillerSounds(from: input, language: .auto)
        let expected = "This is very good and important."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Sensitivity Level Tests
    
    func testConservativeSensitivity() {
        let input = "This is uh, very good. Um... perfect."
        let output = processor.removeFillerSounds(from: input, language: .english, sensitivity: .conservative)
        let expected = "This is very good. perfect."
        XCTAssertEqual(output, expected)
    }
    
    func testModerateSensitivity() {
        let input = "This is uh very good and um perfect."
        let output = processor.removeFillerSounds(from: input, language: .english, sensitivity: .moderate)
        let expected = "This is very good and perfect."
        XCTAssertEqual(output, expected)
    }
    
    func testAggressiveSensitivity() {
        let input = "This is uh very good and um perfect."
        let output = processor.removeFillerSounds(from: input, language: .english, sensitivity: .aggressive)
        let expected = "This is very good and perfect."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Edge Cases and Legitimate Words
    
    func testPreserveLegitimateWords() {
        let input = "I said uh-oh when I saw the problem. That's a hum-dinger!"
        let output = processor.removeFillerSounds(from: input, language: .english)
        // Should preserve "uh-oh" as it's a legitimate expression
        XCTAssertTrue(output.contains("uh-oh"))
    }
    
    func testPreserveWordsWithHyphens() {
        let input = "The uh-huh response was clear."
        let output = processor.removeFillerSounds(from: input, language: .english)
        // Should preserve hyphenated words
        XCTAssertTrue(output.contains("uh-huh"))
    }
    
    func testEmptyString() {
        let output = processor.removeFillerSounds(from: "", language: .auto)
        XCTAssertEqual(output, "")
    }
    
    func testOnlyFillers() {
        let input = "uh um äh ähm"
        let output = processor.removeFillerSounds(from: input, language: .auto)
        XCTAssertEqual(output, "")
    }
    
    func testNoFillers() {
        let input = "This is a clean sentence without any fillers."
        let output = processor.removeFillerSounds(from: input, language: .auto)
        XCTAssertEqual(output, input)
    }
    
    func testMultipleConsecutiveFillers() {
        let input = "This is uh um äh very good."
        let output = processor.removeFillerSounds(from: input, language: .auto)
        let expected = "This is very good."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Whitespace Cleanup Tests
    
    func testWhitespaceCleanup() {
        let input = "This is  uh   very    good and  um   perfect."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "This is very good and perfect."
        XCTAssertEqual(output, expected)
    }
    
    func testFillerAtSentenceStart() {
        let input = "Uh, ich bin mir nicht sicher."
        let output = processor.removeFillerSounds(from: input, language: .german)
        let expected = "Ich bin mir nicht sicher."
        XCTAssertEqual(output, expected)
    }
    
    func testFillerAtSentenceStartEnglish() {
        let input = "Um, I think this is right."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "I think this is right."
        XCTAssertEqual(output, expected)
    }
    
    func testPunctuationSpacing() {
        let input = "I think, uh , this is good . Um , yes."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "I think, this is good. yes."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Detection Pattern Tests
    
    func testDetectFillerPatterns() {
        let input = "This is uh very good and um important. Das ist äh gut."
        let matches = processor.detectFillerPatterns(in: input)
        
        XCTAssertEqual(matches.count, 3)
        XCTAssertTrue(matches.contains { $0.originalText.lowercased() == "uh" })
        XCTAssertTrue(matches.contains { $0.originalText.lowercased() == "um" })
        XCTAssertTrue(matches.contains { $0.originalText.lowercased() == "äh" })
    }
    
    func testDetectNoFillers() {
        let input = "This is a clean sentence."
        let matches = processor.detectFillerPatterns(in: input)
        XCTAssertEqual(matches.count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceShortText() {
        let input = "This is uh very good and um important for us."
        
        measure {
            for _ in 0..<1000 {
                _ = processor.removeFillerSounds(from: input, language: .auto)
            }
        }
    }
    
    func testPerformanceLongText() {
        let shortText = "This is uh very good and um important. "
        let input = String(repeating: shortText, count: 100) // ~5000 characters
        
        measure {
            for _ in 0..<10 {
                _ = processor.removeFillerSounds(from: input, language: .auto)
            }
        }
    }
    
    // MARK: - Mixed Language Tests
    
    func testMixedLanguageContent() {
        let input = "This is uh good. Das ist äh wichtig. Very um nice and ähm perfect."
        let output = processor.removeFillerSounds(from: input, language: .auto)
        let expected = "This is good. Das ist wichtig. Very nice and perfect."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Word Boundary Tests
    
    func testWordBoundaries() {
        let input = "The hummer vehicle and the drummer both make sounds."
        let output = processor.removeFillerSounds(from: input, language: .english)
        // Should not remove "um" from middle of words
        XCTAssertTrue(output.contains("hummer"))
        XCTAssertTrue(output.contains("drummer"))
    }
    
    func testFillerAtBeginning() {
        let input = "Um, this is very good."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "this is very good."
        XCTAssertEqual(output, expected)
    }
    
    func testFillerAtEnd() {
        let input = "This is very good, um."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "This is very good."
        XCTAssertEqual(output, expected)
    }
    
    // MARK: - Special Characters Tests
    
    func testWithSpecialCharacters() {
        let input = "This is uh... very good! Um, perfect?"
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "This is very good! perfect?"
        XCTAssertEqual(output, expected)
    }
    
    func testWithNumbers() {
        let input = "The number is uh 42 and um 100."
        let output = processor.removeFillerSounds(from: input, language: .english)
        let expected = "The number is 42 and 100."
        XCTAssertEqual(output, expected)
    }
}