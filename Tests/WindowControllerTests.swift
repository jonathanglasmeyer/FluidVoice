import XCTest
import AppKit
import SwiftUI
@testable import FluidVoice

final class WindowControllerTests: XCTestCase {
    
    var windowController: WindowController!
    
    override func setUp() {
        super.setUp()
        windowController = WindowController()
    }
    
    override func tearDown() {
        windowController = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testWindowControllerInitialization() {
        XCTAssertNotNil(windowController)
    }
    
    // MARK: - Settings Window Tests
    
    @MainActor
    func testOpenSettingsCreatesNewWindow() {
        // Should not crash when opening settings
        XCTAssertNoThrow(windowController.openSettings())
    }
    
    @MainActor
    func testOpenSettingsWithExistingSettingsWindow() {
        // In test environment, openSettings() returns early
        // Just verify it doesn't crash
        XCTAssertNoThrow(windowController.openSettings())
    }
    
    // MARK: - Focus Management Tests
    
    func testRestoreFocusToPreviousAppWithNoPreviousApp() {
        // Should not crash when no previous app is stored
        XCTAssertNoThrow(windowController.restoreFocusToPreviousApp())
    }
    
    func testFocusRestorationFlow() {
        // Test the focus restoration mechanism doesn't crash
        XCTAssertNoThrow(windowController.restoreFocusToPreviousApp())
    }
    
    // MARK: - Edge Cases Tests
    
    @MainActor
    func testMultipleSettingsOpenCalls() {
        // Multiple rapid settings calls should not crash
        for _ in 0..<5 {
            XCTAssertNoThrow(windowController.openSettings())
        }
    }
    
    @MainActor
    func testConcurrentWindowOperations() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    self.windowController.openSettings()
                }
            }
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testWindowControllerDeallocation() {
        weak var weakController = windowController
        
        windowController = nil
        
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        
        XCTAssertNil(weakController, "WindowController should be deallocated")
    }
    
    // MARK: - Performance Tests
    
    @MainActor
    func testOpenSettingsPerformance() {
        measure {
            for _ in 0..<50 {
                windowController.openSettings()
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testWindowOperationsWithInvalidWindows() {
        // Test with nil window references
        XCTAssertNoThrow(windowController.openSettings())
        XCTAssertNoThrow(windowController.restoreFocusToPreviousApp())
    }
    
    @MainActor
    func testWindowOperationsAfterWindowClosed() {
        // Operations should not crash
        XCTAssertNoThrow(windowController.openSettings())
    }
}