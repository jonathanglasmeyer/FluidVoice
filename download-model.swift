#!/usr/bin/env swift

import Foundation
import WhisperKit

// Simple script to pre-download WhisperKit model
func downloadModel() async {
    print("🚀 Starting WhisperKit model download...")
    
    do {
        let whisperKit = try await WhisperKit(model: "large-v3-turbo")
        print("✅ Model download completed successfully!")
        print("📁 Model cached at: ~/Library/Caches/WhisperKit/")
    } catch {
        print("❌ Model download failed: \(error)")
        exit(1)
    }
}

await downloadModel()