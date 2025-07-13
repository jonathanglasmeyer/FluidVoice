import SwiftUI

enum AppStatus: Equatable {
    case error(String)
    case recording
    case processing(String)
    case success
    case ready
    case permissionRequired
    
    var message: String {
        switch self {
        case .error(let message):
            return message
        case .recording:
            return "Recording..."
        case .processing(let message):
            return message
        case .success:
            return "Success!"
        case .ready:
            return "Ready"
        case .permissionRequired:
            return "Microphone access required"
        }
    }
    
    var color: Color {
        switch self {
        case .error:
            return .red
        case .recording:
            return .red
        case .processing:
            return .orange
        case .success:
            return .green
        case .ready:
            return .blue
        case .permissionRequired:
            return .gray
        }
    }
    
    var icon: String? {
        switch self {
        case .error:
            return "exclamationmark.triangle.fill"
        case .recording:
            return nil // Will use pulsing circle
        case .processing:
            return nil // Will use spinning indicator
        case .success:
            return "checkmark.circle.fill"
        case .ready:
            return nil
        case .permissionRequired:
            return "mic.slash.fill"
        }
    }
    
    var shouldAnimate: Bool {
        switch self {
        case .recording, .processing:
            return true
        default:
            return false
        }
    }
    
    var showInfoButton: Bool {
        switch self {
        case .permissionRequired:
            return true
        default:
            return false
        }
    }
}

class StatusViewModel: ObservableObject {
    @Published var currentStatus: AppStatus = .ready
    
    func updateStatus(
        isRecording: Bool,
        isProcessing: Bool,
        progressMessage: String,
        hasPermission: Bool,
        showSuccess: Bool,
        errorMessage: String? = nil
    ) {
        if let error = errorMessage {
            currentStatus = .error(error)
        } else if showSuccess {
            currentStatus = .success
        } else if isRecording {
            currentStatus = .recording
        } else if isProcessing {
            currentStatus = .processing(progressMessage)
        } else if hasPermission {
            currentStatus = .ready
        } else {
            currentStatus = .permissionRequired
        }
    }
}