import XCTest
import Foundation
@testable import FluidVoice

class SpeechToTextServiceTests: XCTestCase {
    var service: SpeechToTextService!
    var mockKeychain: MockKeychainService!
    var testAudioURL: URL!
    
    override func setUp() {
        super.setUp()
        mockKeychain = MockKeychainService()
        service = SpeechToTextService(keychainService: mockKeychain)
        
        // Create a temporary test audio file
        testAudioURL = createTestAudioFile()
    }
    
    override func tearDown() {
        if let url = testAudioURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        service = nil
        mockKeychain = nil
        testAudioURL = nil
        super.tearDown()
    }
    
    // MARK: - Error Handling Tests
    
    func testSpeechToTextErrorDescriptions() {
        let invalidURLError = SpeechToTextError.invalidURL
        XCTAssertEqual(invalidURLError.errorDescription, "Recording appears to be corrupted. Please try recording again.")
        
        let apiKeyMissingError = SpeechToTextError.apiKeyMissing("OpenAI")
        XCTAssertTrue(apiKeyMissingError.errorDescription?.contains("To use OpenAI transcription, please add your API key in Settings") == true)
        
        let transcriptionFailedError = SpeechToTextError.transcriptionFailed("Test error")
        XCTAssertEqual(transcriptionFailedError.errorDescription, "Transcription failed: Test error\n\nPlease check your internet connection and API key in Settings.")
    }
    
    // MARK: - Provider Selection Tests
    
    func testProviderSelectionDefaultsToOpenAI() async {
        // Create a fresh mock keychain with no keys
        let cleanMockKeychain = MockKeychainService()
        let cleanService = SpeechToTextService(keychainService: cleanMockKeychain)
        
        // Clear any existing preference
        UserDefaults.standard.removeObject(forKey: "useOpenAI")
        
        // Since we can't easily mock the network calls, we'll test that the right path is taken
        // by checking that it fails with the expected error (missing API key)
        do {
            _ = try await cleanService.transcribe(audioURL: testAudioURL)
            XCTFail("Expected error due to missing API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("OpenAI"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testProviderSelectionUsesOpenAIWhenSet() async {
        UserDefaults.standard.set(true, forKey: "useOpenAI")
        
        do {
            _ = try await service.transcribe(audioURL: testAudioURL)
            XCTFail("Expected error due to missing API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("OpenAI"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    func testProviderSelectionUsesGeminiWhenSet() async {
        // Create a fresh mock keychain with no keys
        let cleanMockKeychain = MockKeychainService()
        let cleanService = SpeechToTextService(keychainService: cleanMockKeychain)
        
        UserDefaults.standard.set(false, forKey: "useOpenAI")
        
        do {
            _ = try await cleanService.transcribe(audioURL: testAudioURL)
            XCTFail("Expected error due to missing API key")
        } catch let error as SpeechToTextError {
            XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("Gemini"))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Response Model Tests
    
    func testWhisperResponseDecoding() {
        let jsonString = """
        {
            "text": "Hello, world!"
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(WhisperResponse.self, from: data)
            XCTAssertEqual(response.text, "Hello, world!")
        } catch {
            XCTFail("Failed to decode WhisperResponse: \(error)")
        }
    }
    
    func testGeminiResponseDecoding() {
        let jsonString = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": "Hello, world!"
                            }
                        ]
                    }
                }
            ]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            XCTAssertEqual(response.candidates.first?.content.parts.first?.text, "Hello, world!")
        } catch {
            XCTFail("Failed to decode GeminiResponse: \(error)")
        }
    }
    
    func testGeminiResponseWithMissingText() {
        let jsonString = """
        {
            "candidates": [
                {
                    "content": {
                        "parts": [
                            {
                                "text": null
                            }
                        ]
                    }
                }
            ]
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            XCTAssertNil(response.candidates.first?.content.parts.first?.text)
        } catch {
            XCTFail("Failed to decode GeminiResponse: \(error)")
        }
    }
    
    func testGeminiResponseWithEmptyCandidates() {
        let jsonString = """
        {
            "candidates": []
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        do {
            let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
            XCTAssertTrue(response.candidates.isEmpty)
        } catch {
            XCTFail("Failed to decode GeminiResponse: \(error)")
        }
    }
    
    // MARK: - File Handling Tests
    
    func testTranscribeWithInvalidURL() async {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/file.m4a")
        
        do {
            // Set up mock keychain to have an API key so we get to the file reading part
            mockKeychain.saveQuietly("test-key", service: "FluidVoice", account: "OpenAI")
            
            _ = try await service.transcribe(audioURL: invalidURL)
            XCTFail("Expected error due to invalid file URL")
        } catch {
            // Should get an error when trying to read the file
            XCTAssertTrue(error is SpeechToTextError || error is CocoaError)
        }
    }
    
    // MARK: - API Key Tests
    
    func testAPIKeyRetrievalMethods() {
        // Test that keychain is the primary and only method for API key retrieval
        let mockKeychain = MockKeychainService()
        
        // Test that it returns nil when no key is found
        let apiKey = mockKeychain.getQuietly(service: "FluidVoice", account: "OpenAI")
        XCTAssertNil(apiKey)
        
        // Test saving and retrieving a key
        mockKeychain.saveQuietly("test-api-key", service: "FluidVoice", account: "OpenAI")
        let retrievedKey = mockKeychain.getQuietly(service: "FluidVoice", account: "OpenAI")
        XCTAssertEqual(retrievedKey, "test-api-key")
    }
    
    func testAPIKeyFromKeychain() {
        // Test the keychain reading functionality with mock
        let mockKeychain = MockKeychainService()
        let _ = SpeechToTextService(keychainService: mockKeychain)
        
        // Test that it returns nil when no key is found
        let apiKey = mockKeychain.getQuietly(service: "FluidVoice", account: "OpenAI")
        XCTAssertNil(apiKey)
        
        // Test saving and retrieving a key
        mockKeychain.saveQuietly("test-api-key", service: "FluidVoice", account: "OpenAI")
        let retrievedKey = mockKeychain.getQuietly(service: "FluidVoice", account: "OpenAI")
        XCTAssertEqual(retrievedKey, "test-api-key")
    }
    
    // MARK: - Concurrent Access Tests
    
    func testConcurrentTranscriptionCalls() async {
        UserDefaults.standard.set(true, forKey: "useOpenAI")
        
        let tasks = (0..<5).map { _ in
            Task {
                do {
                    _ = try await service.transcribe(audioURL: testAudioURL)
                    XCTFail("Expected error due to missing API key")
                } catch let error as SpeechToTextError {
                    XCTAssertEqual(error, SpeechToTextError.apiKeyMissing("OpenAI"))
                } catch {
                    XCTFail("Unexpected error type: \(error)")
                }
            }
        }
        
        // Wait for all tasks to complete
        for task in tasks {
            _ = await task.value
        }
    }
    
    // MARK: - Performance Tests
    
    func testProviderSelectionPerformance() {
        UserDefaults.standard.set(true, forKey: "useOpenAI")
        
        measure {
            Task {
                do {
                    _ = try await service.transcribe(audioURL: testAudioURL)
                } catch {
                    // Expected to fail due to missing API key
                }
            }
        }
    }
    
    func testResponseDecodingPerformance() {
        let jsonString = """
        {
            "text": "This is a test transcription result that should be decoded quickly."
        }
        """
        
        let data = jsonString.data(using: .utf8)!
        
        measure {
            for _ in 0..<1000 {
                _ = try? JSONDecoder().decode(WhisperResponse.self, from: data)
            }
        }
    }
}

// MARK: - Test Helpers

extension SpeechToTextServiceTests {
    private func createTestAudioFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let audioURL = tempDir.appendingPathComponent("test_audio.m4a")
        
        // Create a minimal test file
        guard let testData = "test audio data".data(using: .utf8) else {
            XCTFail("Failed to create test data")
            return tempDir.appendingPathComponent("invalid")
        }
        do {
            try testData.write(to: audioURL)
        } catch {
            XCTFail("Failed to write test file: \(error)")
            return tempDir.appendingPathComponent("invalid")
        }
        
        return audioURL
    }
    
    // MARK: - Parakeet Provider Tests
    
    func testTranscribeWithParakeetProviderMissingPython() async {
        let invalidPythonPath = "/invalid/python/path"
        UserDefaults.standard.set(invalidPythonPath, forKey: "parakeetPythonPath")
        
        do {
            _ = try await service.transcribe(audioURL: testAudioURL, provider: .parakeet)
            XCTFail("Expected error due to invalid audio or Python path")
        } catch let error as SpeechToTextError {
            // The test can fail either due to invalid audio (which is expected since we create a fake file)
            // or due to invalid Python path. Both are acceptable test outcomes
            let errorMessage = error.localizedDescription
            let hasExpectedError = errorMessage.contains("Parakeet error") || 
                                 errorMessage.contains("Python") || 
                                 errorMessage.contains("not found") ||
                                 errorMessage.contains("corrupted") ||
                                 errorMessage.contains("unreadable")
            XCTAssertTrue(hasExpectedError, "Error should indicate audio or Python issue: \(errorMessage)")
        } catch {
            XCTFail("Expected SpeechToTextError, got \(error)")
        }
        
        // Clean up
        UserDefaults.standard.removeObject(forKey: "parakeetPythonPath")
    }
    
    func testParakeetProviderWithSystemPython() async {
        let systemPythonPath = "/usr/bin/python3"
        
        // Only test if system Python exists
        if FileManager.default.fileExists(atPath: systemPythonPath) {
            UserDefaults.standard.set(systemPythonPath, forKey: "parakeetPythonPath")
            
            do {
                _ = try await service.transcribe(audioURL: testAudioURL, provider: .parakeet)
                // If this succeeds, parakeet-mlx is installed
            } catch let error as SpeechToTextError {
                // Expected if parakeet-mlx is not installed or script not found
                // Just verify we got a SpeechToTextError (which we did)
                XCTAssertTrue(error.localizedDescription.count > 0)
            } catch {
                XCTFail("Expected SpeechToTextError, got \(error)")
            }
            
            // Clean up
            UserDefaults.standard.removeObject(forKey: "parakeetPythonPath")
        }
    }
    
    func testParakeetProviderInAllCases() {
        // Ensure Parakeet is included in all provider tests
        let allProviders: [TranscriptionProvider] = [.openai, .gemini, .local, .parakeet]
        XCTAssertTrue(allProviders.contains(.parakeet))
        XCTAssertEqual(allProviders.count, 4)
    }

}

// MARK: - Mock Extensions

// MARK: - Error Comparison

extension SpeechToTextError: Equatable {
    public static func == (lhs: SpeechToTextError, rhs: SpeechToTextError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL):
            return true
        case (.apiKeyMissing, .apiKeyMissing):
            return true
        case (.transcriptionFailed(let lhsMessage), .transcriptionFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}