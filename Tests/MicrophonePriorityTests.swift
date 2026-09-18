import XCTest
@testable import FluidVoice

final class MicrophonePriorityTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "MicrophonePriorityTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private let hollyland = MicrophoneEntry(uid: "~:AMS2_Aggregate:0", name: "Hollyland")
    private let airpods = MicrophoneEntry(uid: "airpods-uid", name: "AirPods")
    private let builtIn = MicrophoneEntry(uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")

    // MARK: - Resolution

    func testFirstAvailablePicksHighestPriorityAvailableDevice() {
        let list = [hollyland, airpods, builtIn]
        let available: Set<String> = [airpods.uid, builtIn.uid]
        XCTAssertEqual(MicrophonePriority.firstAvailable(in: list) { available.contains($0) }, airpods)
    }

    func testFirstAvailablePrefersTopEntryWhenPresent() {
        let list = [hollyland, airpods, builtIn]
        XCTAssertEqual(MicrophonePriority.firstAvailable(in: list) { _ in true }, hollyland)
    }

    func testFirstAvailableReturnsNilWhenNothingAvailable() {
        XCTAssertNil(MicrophonePriority.firstAvailable(in: [hollyland, airpods]) { _ in false })
        XCTAssertNil(MicrophonePriority.firstAvailable(in: []) { _ in true })
    }

    // MARK: - Persistence & migration

    func testSaveAndLoadRoundTripKeepsOrder() {
        MicrophonePriority.save([airpods, hollyland], to: defaults)
        XCTAssertEqual(MicrophonePriority.load(from: defaults), [airpods, hollyland])
    }

    func testLoadMigratesLegacySingleSelection() {
        defaults.set(builtIn.uid, forKey: MicrophonePriority.legacySelectionKey)
        let list = MicrophonePriority.load(from: defaults)
        XCTAssertEqual(list.map(\.uid), [builtIn.uid])
        // Migration is persisted, so it survives the legacy key being cleared
        defaults.removeObject(forKey: MicrophonePriority.legacySelectionKey)
        XCTAssertEqual(MicrophonePriority.load(from: defaults).map(\.uid), [builtIn.uid])
    }

    func testLoadWithoutAnyConfigurationIsEmpty() {
        XCTAssertEqual(MicrophonePriority.load(from: defaults), [])
    }

    func testExplicitlyEmptiedListDoesNotRemigrateLegacySelection() {
        defaults.set(builtIn.uid, forKey: MicrophonePriority.legacySelectionKey)
        MicrophonePriority.save([], to: defaults)
        XCTAssertEqual(MicrophonePriority.load(from: defaults), [])
    }

    // MARK: - Editing

    func testMoveUpAndDown() {
        var list = [hollyland, airpods, builtIn]
        MicrophonePriority.move(&list, uid: builtIn.uid, by: -1)
        XCTAssertEqual(list, [hollyland, builtIn, airpods])
        MicrophonePriority.move(&list, uid: hollyland.uid, by: 1)
        XCTAssertEqual(list, [builtIn, hollyland, airpods])
    }

    func testMoveBeyondBoundsIsNoOp() {
        var list = [hollyland, airpods]
        MicrophonePriority.move(&list, uid: hollyland.uid, by: -1)
        MicrophonePriority.move(&list, uid: airpods.uid, by: 1)
        XCTAssertEqual(list, [hollyland, airpods])
    }

    func testAddIgnoresDuplicates() {
        var list = [hollyland]
        MicrophonePriority.add(&list, hollyland)
        MicrophonePriority.add(&list, airpods)
        XCTAssertEqual(list, [hollyland, airpods])
    }
}
