import SwiftUI
import AVFoundation
import ApplicationServices

enum PermissionState {
    case unknown
    case notRequested
    case requesting
    case granted
    case denied
    case restricted
    
    var needsRequest: Bool {
        switch self {
        case .unknown, .notRequested:
            return true
        default:
            return false
        }
    }
    
    var canRetry: Bool {
        switch self {
        case .denied:
            return true
        default:
            return false
        }
    }
}

class PermissionManager: ObservableObject {
    @Published var microphonePermissionState: PermissionState = .unknown
    @Published var accessibilityPermissionState: PermissionState = .unknown
    @Published var showEducationalModal = false
    @Published var showRecoveryModal = false
    private let isTestEnvironment: Bool
    private let accessibilityManager = AccessibilityPermissionManager()
    
    var allPermissionsGranted: Bool {
        return microphonePermissionState == .granted && accessibilityPermissionState == .granted
    }
    
    init() {
        // Detect if running in tests
        isTestEnvironment = NSClassFromString("XCTestCase") != nil
    }
    
    func checkPermissionState() {
        checkMicrophonePermission()
        
        // Always check accessibility permission for auto-typing
        checkAccessibilityPermission()
    }
    
    private func checkMicrophonePermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        DispatchQueue.main.async {
            switch status {
            case .authorized:
                self.microphonePermissionState = .granted
            case .denied:
                self.microphonePermissionState = .denied
            case .restricted:
                self.microphonePermissionState = .restricted
            case .notDetermined:
                self.microphonePermissionState = .notRequested
            @unknown default:
                self.microphonePermissionState = .unknown
            }
        }
    }
    
    private func checkAccessibilityPermission() {
        // Use dedicated AccessibilityPermissionManager for consistent checking
        let trusted = accessibilityManager.checkPermission()
        
        DispatchQueue.main.async {
            self.accessibilityPermissionState = trusted ? .granted : .notRequested
        }
    }
    
    func requestPermissionWithEducation() {
        let needsMicrophone = microphonePermissionState.needsRequest
        let needsAccessibility = accessibilityPermissionState.needsRequest
        
        let canRetryMicrophone = microphonePermissionState.canRetry
        let canRetryAccessibility = accessibilityPermissionState.canRetry
        
        if needsMicrophone || needsAccessibility {
            showEducationalModal = true
        } else if canRetryMicrophone || canRetryAccessibility {
            showRecoveryModal = true
        }
    }
    
    func proceedWithPermissionRequest() {
        if isTestEnvironment {
            // In tests, simulate permission behavior without actual system dialog
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Simulate denied for consistent test behavior
                self.microphonePermissionState = .denied
                self.accessibilityPermissionState = .denied
                self.showRecoveryModal = true
            }
        } else {
            requestMicrophonePermission()
            
            // Always request accessibility permission
            requestAccessibilityPermission()
        }
    }
    
    private func requestMicrophonePermission() {
        if microphonePermissionState.needsRequest {
            microphonePermissionState = .requesting
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.microphonePermissionState = granted ? .granted : .denied
                    self?.checkIfAllPermissionsHandled()
                }
            }
        }
    }
    
    private func requestAccessibilityPermission() {
        if accessibilityPermissionState.needsRequest {
            accessibilityPermissionState = .requesting
            
            // Use dedicated AccessibilityPermissionManager for proper explanation and handling
            accessibilityManager.requestPermissionWithExplanation { [weak self] granted in
                DispatchQueue.main.async {
                    self?.accessibilityPermissionState = granted ? .granted : .denied
                    self?.checkIfAllPermissionsHandled()
                }
            }
        }
    }
    
    private func checkIfAllPermissionsHandled() {
        let hasFailures = microphonePermissionState == .denied || accessibilityPermissionState == .denied
        if hasFailures && !showRecoveryModal {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showRecoveryModal = true
            }
        }
    }
    
    func openSystemSettings() {
        // Skip actual system settings in test environment
        if isTestEnvironment {
            return
        }
        
        // Open the main Privacy & Security preferences
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}