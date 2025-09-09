import Foundation
import Alamofire

import os.log

final class SemanticCorrectionService {
    private let mlxService = MLXCorrectionService()
    private let keychainService: KeychainServiceProtocol
    private let logger = Logger(subsystem: "com.fluidvoice.app", category: "SemanticCorrection")
    private let fillerSoundProcessor = FillerSoundProcessor()
    private lazy var fastVocabularyCorrector: FastVocabularyCorrector = {
        let corrector = FastVocabularyCorrector()
        corrector.load(glossary: VocabularySettings.getGlossary())
        return corrector
    }()
    
    // Chunking configuration for 32k context window
    // 32k tokens ≈ 24k words (0.75 ratio) ≈ 120k chars
    // Use conservative 6k words to leave room for system prompt
    private static let chunkSizeWords = 6000
    private static let overlapSizeWords = 200 // Small overlap for context continuity

    init(keychainService: KeychainServiceProtocol = KeychainService.shared) {
        self.keychainService = keychainService
    }

    func correct(text: String, providerUsed: TranscriptionProvider) async -> String {
        // Always run Fast Vocabulary Correction first (privacy-first, instant)
        logger.infoDev("Running fast vocabulary correction")
        let vocabularyCorrectedText = correctWithFastVocabulary(text: text)
        
        // Always run Filler Sound Removal after vocabulary correction
        logger.infoDev("Running filler sound removal")
        let correctedText = fillerSoundProcessor.removeFillerSounds(from: vocabularyCorrectedText)
        
        // Then check for additional semantic correction modes
        let modeRaw = UserDefaults.standard.string(forKey: "semanticCorrectionMode") ?? SemanticCorrectionMode.off.rawValue
        let mode = SemanticCorrectionMode(rawValue: modeRaw) ?? .off

        switch mode {
        case .off, .fastVocabulary:
            return correctedText
        case .localMLX:
            // Allow local MLX correction regardless of STT provider
            logger.infoDev("Running local MLX correction")
            return await correctLocallyWithMLX(text: correctedText)
        case .cloud:
            switch providerUsed {
            case .openai:
                logger.infoDev("Running cloud correction: OpenAI")
                return await correctWithOpenAI(text: correctedText)
            case .gemini:
                logger.infoDev("Running cloud correction: Gemini")
                return await correctWithGemini(text: correctedText)
            case .local, .parakeet: return correctedText // don't send local text to cloud
            }
        }
    }

    // MARK: - Fast Vocabulary (Privacy-First)
    private func correctWithFastVocabulary(text: String) -> String {
        let totalStartTime = DispatchTime.now()
        
        // Load glossary if it has changed (now with caching)
        let loadStartTime = DispatchTime.now()
        fastVocabularyCorrector.load(glossary: VocabularySettings.getGlossary())
        let loadElapsed = Double(DispatchTime.now().uptimeNanoseconds - loadStartTime.uptimeNanoseconds) / 1_000_000
        
        let correctionStartTime = DispatchTime.now()
        let corrected = fastVocabularyCorrector.correct(text, maxTimeMs: 30)
        let correctionElapsed = Double(DispatchTime.now().uptimeNanoseconds - correctionStartTime.uptimeNanoseconds) / 1_000_000
        
        let totalElapsed = Double(DispatchTime.now().uptimeNanoseconds - totalStartTime.uptimeNanoseconds) / 1_000_000
        
        logger.infoDev("Fast vocabulary timing: config load \(String(format: "%.1f", loadElapsed))ms, correction \(String(format: "%.1f", correctionElapsed))ms, total \(String(format: "%.1f", totalElapsed))ms")
        
        if corrected != text {
            logger.infoDev("Fast vocabulary correction applied changes")
        } else {
            logger.infoDev("Fast vocabulary correction made no changes")
        }
        
        return corrected
    }

    // MARK: - Local (MLX)
    private func correctLocallyWithMLX(text: String) async -> String {
        guard Arch.isAppleSilicon else { return text }
        let modelRepo = UserDefaults.standard.string(forKey: "semanticCorrectionModelRepo") ?? "mlx-community/Llama-3.2-3B-Instruct-4bit"
        do {
            let pyURL = try await UvBootstrap.ensureVenv(userPython: nil)
            let output = try await mlxService.correct(text: text, modelRepo: modelRepo, pythonPath: pyURL.path)
            let merged = Self.safeMerge(original: text, corrected: output, maxChangeRatio: 0.6)
            if merged == text {
                logger.info("MLX correction produced no accepted change (kept original)")
            } else {
                logger.info("MLX correction applied changes")
            }
            return merged
        } catch {
            logger.error("MLX correction failed: \(error.localizedDescription)")
            return text
        }
    }

    // MARK: - Cloud (OpenAI)
    private func correctWithOpenAI(text: String) async -> String {
        guard let apiKey = keychainService.getQuietly(service: "FluidVoice", account: "OpenAI") else {
            return text
        }
        let prompt = readPromptFile(name: "cloud_openai_prompt.txt") ?? "You are a transcription corrector. Fix grammar, casing, punctuation, and obvious mis-hearings that do not change meaning. Remove filler words and transcribed pauses that add no meaning (e.g., 'um', 'uh', 'erm', 'you know', 'like' as filler; '[pause]', '(pause)', ellipses for hesitations). Do not remove meaningful words. Do not summarize or add content. Output only the corrected text."
        let url = "https://api.openai.com/v1/chat/completions"
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        let body: [String: Any] = [
            "model": "gpt-5-nano",
            "messages": [
                ["role": "system", "content": prompt],
                ["role": "user", "content": text]
            ],
            // Note: gpt-5-nano doesn't support temperature adjustment
            "max_completion_tokens": 8192  // Standardized limit for long transcriptions
        ]

        do {
            let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                AF.request(url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
                    .responseDecodable(of: OpenAIChatResponse.self) { response in
                        switch response.result {
                        case .success(let r):
                            let content = r.choices.first?.message.content ?? text
                            cont.resume(returning: content)
                        case .failure(let err):
                            cont.resume(throwing: err)
                        }
                    }
            }
            return Self.safeMerge(original: text, corrected: result, maxChangeRatio: 0.25)
        } catch {
            return text
        }
    }

    // MARK: - Cloud (Gemini)
    private func correctWithGemini(text: String) async -> String {
        guard let apiKey = keychainService.getQuietly(service: "FluidVoice", account: "Gemini") else {
            return text
        }
        let url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent"
        let headers: HTTPHeaders = [
            "X-Goog-Api-Key": apiKey,
            "Content-Type": "application/json"
        ]
        let prompt = readPromptFile(name: "cloud_gemini_prompt.txt") ?? "You are a transcription corrector. Fix grammar, casing, punctuation, and obvious mis-hearings that do not change meaning. Remove filler words and transcribed pauses that add no meaning (e.g., 'um', 'uh', 'erm', 'you know', 'like' as filler; '[pause]', '(pause)', ellipses for hesitations). Do not remove meaningful words. Do not summarize or add content. Output only the corrected text."
        let body: [String: Any] = [
            "contents": [[
                "parts": [[
                    "text": "\(prompt)\n\n\(text)"
                ]]
            ]],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 8192  // Standardized limit
            ]
        ]
        do {
            let result = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                AF.request(url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
                    .responseDecodable(of: GeminiResponse.self) { response in
                        switch response.result {
                        case .success(let r):
                            let content = r.candidates.first?.content.parts.first?.text ?? text
                            cont.resume(returning: content)
                        case .failure(let err):
                            cont.resume(throwing: err)
                        }
                    }
            }
            return Self.safeMerge(original: text, corrected: result, maxChangeRatio: 0.25)
        } catch {
            return text
        }
    }

    // MARK: - Prompt file helpers
    private func promptsBaseDir() -> URL? {
        return try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FluidVoice/prompts", isDirectory: true)
    }

    private func readPromptFile(name: String) -> String? {
        guard let base = promptsBaseDir() else { return nil }
        let url = base.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - Safety Guard
    private static func safeMerge(original: String, corrected: String, maxChangeRatio: Double) -> String {
        guard !corrected.isEmpty else { return original }
        let ratio = normalizedEditDistance(a: original, b: corrected)
        if ratio > maxChangeRatio { return original }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedEditDistance(a: String, b: String) -> Double {
        if a == b { return 0 }
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count
        if m == 0 || n == 0 { return 1 }
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }
        for i in 1...m {
            for j in 1...n {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                dp[i][j] = min(
                    dp[i-1][j] + 1,
                    dp[i][j-1] + 1,
                    dp[i-1][j-1] + cost
                )
            }
        }
        let dist = dp[m][n]
        let denom = max(m, n)
        return Double(dist) / Double(denom)
    }
}

// MARK: - Response Models
struct OpenAIChatResponse: Codable {
    struct Choice: Codable { let message: Message }
    struct Message: Codable { let role: String; let content: String }
    let choices: [Choice]
}
