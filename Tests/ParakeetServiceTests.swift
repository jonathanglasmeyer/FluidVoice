import XCTest
import Foundation
@testable import FluidVoice

final class ParakeetServiceTests: XCTestCase {

    private var service: ParakeetService { ParakeetService.shared }

    // MARK: - Errors

    func testErrorDescriptions() {
        XCTAssertTrue(ParakeetError.modelNotAvailable.errorDescription?.contains("not downloaded") == true)
        XCTAssertTrue(ParakeetError.audioFileNotFound("/x.m4a").errorDescription?.contains("/x.m4a") == true)
        XCTAssertTrue(ParakeetError.transcriptionFailed("boom").errorDescription?.contains("boom") == true)
    }

    func testModelNotAvailableMapsToModelNotFound() {
        let message = ParakeetError.modelNotAvailable.errorDescription ?? ""
        guard case .modelNotFound(let model) = TranscriptionError.from(errorMessage: message) else {
            return XCTFail("Expected .modelNotFound")
        }
        XCTAssertEqual(model, "Parakeet v3")
    }

    // MARK: - Input validation

    func testTranscribeMissingAudioFileThrows() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing_\(UUID().uuidString).m4a")
        do {
            _ = try await service.transcribe(audioFileURL: missing)
            XCTFail("Expected audioFileNotFound")
        } catch let error as ParakeetError {
            XCTAssertEqual(error, .audioFileNotFound(missing.path))
        } catch {
            XCTFail("Expected ParakeetError, got \(error)")
        }
    }

    // MARK: - End-to-end (needs the CoreML model; FLUIDVOICE_E2E=1 downloads it if missing)

    func testTranscribesGermanAndEnglishSpeech() async throws {
        if ProcessInfo.processInfo.environment["FLUIDVOICE_E2E"] != nil {
            try await service.prepare()
        }
        try XCTSkipUnless(ParakeetService.isModelAvailable, "Parakeet CoreML model not downloaded")

        let german = try await transcribeSynthesized("Guten Morgen, heute ist ein schöner Tag.", voice: "Anna")
        XCTAssertTrue(german.lowercased().contains("morgen"), "German transcript was: \(german)")

        let english = try await transcribeSynthesized("The quick brown fox jumps over the lazy dog.", voice: "Samantha")
        XCTAssertTrue(english.lowercased().contains("fox"), "English transcript was: \(english)")
    }

    /// Renders `text` with macOS `say` and transcribes it (language is auto-detected, no hint passed).
    private func transcribeSynthesized(_ text: String, voice: String) async throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("parakeet_test_\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }

        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", url.path, text]
        try say.run()
        say.waitUntilExit()
        try XCTSkipUnless(say.terminationStatus == 0, "`say` voice \(voice) unavailable")

        let start = Date()
        let transcript = try await service.transcribe(audioFileURL: url)
        print("[\(voice)] \(String(format: "%.3f", Date().timeIntervalSince(start)))s: \(transcript)")
        return transcript
    }
}
