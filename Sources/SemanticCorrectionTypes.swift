import Foundation

enum SemanticCorrectionMode: String, CaseIterable, Codable, Sendable {
    case off
    case fastVocabulary
    case localMLX
    case cloud
    
    var displayName: String {
        switch self {
        case .off: return "Off"
        case .fastVocabulary: return "Fast Vocabulary (Privacy-First)"
        case .localMLX: return "Local (MLX)"
        case .cloud: return "Cloud"
        }
    }
}

