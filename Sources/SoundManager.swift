import Foundation
import AppKit

@MainActor
class SoundManager: ObservableObject {
    
    /// Plays a gentle completion sound when transcription finishes
    func playCompletionSound() {
        // Sounds disabled
        return
    }

    /// Plays a quick sound when recording starts in express mode
    func playRecordingStartSound() {
        // Sounds disabled
        return
    }
    
    /// Alternative completion sounds that can be used
    private enum CompletionSound: String, CaseIterable {
        case glass = "Glass"           // Gentle chime - recommended
        case tink = "Tink"            // Soft metallic sound
        case pop = "Pop"              // Gentle pop
        case purr = "Purr"            // Very soft sound
        
        var sound: NSSound? {
            return NSSound(named: self.rawValue)
        }
    }
    
    /// Test different completion sounds (for development/testing)
    func testCompletionSounds() {
        for soundType in CompletionSound.allCases {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(soundType.hashValue)) {
                soundType.sound?.play()
            }
        }
    }
}
