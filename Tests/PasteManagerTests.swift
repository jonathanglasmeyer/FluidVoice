import XCTest
import AppKit
@testable import FluidVoice

@MainActor 
class PasteManagerTests: XCTestCase {
    
    var pasteManager: PasteManager!
    var notificationObserver: NSObjectProtocol?
    
    override func setUp() {
        super.setUp()

        // Paste results are posted via main.async; deliver whatever the previous test left queued,
        // otherwise it lands in this test's observers and over-fulfills their expectations
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1.0)

        pasteManager = PasteManager()
        
        // Clear any existing clipboard content
        NSPasteboard.general.clearContents()
    }
    
    override func tearDown() {
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        pasteManager = nil
        super.tearDown()
    }
    
    
    func testPasteWithUserInteractionHandlesPermissionDenialGracefully() {
        // Test that user interaction method properly handles permission denial
        let expectation = expectation(description: "User interaction permission denial handled")
        
        // In test environment, this should trigger permission request flow
        // Since we can't easily mock the permission dialog, we expect it to complete
        // without crashing and either succeed or fail gracefully
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .pasteOperationFailed,
            object: nil,
            queue: .main
        ) { notification in
            // Should handle denial gracefully
            expectation.fulfill()
        }
        
        pasteManager.pasteWithUserInteraction(text: "test text")
        
        wait(for: [expectation], timeout: 5.0) // Longer timeout for user interaction
    }

    // MARK: - Paste to Active App Tests
    
    func testPasteTextDoesNotThrow() {
        // Without accessibility permission (the xctest default) this must fail gracefully
        XCTAssertNoThrow(pasteManager.pasteText("test text"))
    }
    
    // MARK: - User Interaction Tests
    
    func testPasteWithUserInteractionHandlesPermissionDenial() {
        // Test that pasteWithUserInteraction properly handles permission denial
        let expectation = expectation(description: "Permission denial handled")
        
        // In test environment, accessibility permission is typically denied
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .pasteOperationFailed,
            object: nil,
            queue: .main
        ) { notification in
            expectation.fulfill()
        }
        
        pasteManager.pasteWithUserInteraction(text: "test text")
        
        wait(for: [expectation], timeout: 3.0)
    }
    

    // MARK: - Error Handling Tests
    
    func testPasteErrorTypes() {
        // Test that all PasteError types have proper descriptions
        let errors: [PasteError] = [
            .accessibilityPermissionDenied,
            .eventSourceCreationFailed,
            .keyboardEventCreationFailed,
            .targetAppNotAvailable
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "PasteError should have error description: \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty: \(error)")
        }
    }
    
    // MARK: - Integration Tests

    func testPasteManagerIntegration() {
        XCTAssertNotNil(pasteManager, "PasteManager should initialize successfully")
        XCTAssertNoThrow(pasteManager.pasteText("test text"))
    }
}
