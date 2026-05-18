import XCTest
@testable import MacZoomerCore

final class BreakTimerTests: XCTestCase {
    // MARK: - Formatter

    func testFormatterUnderOneHour() {
        XCTAssertEqual(BreakTimerFormatter.string(from: 0), "0:00")
        XCTAssertEqual(BreakTimerFormatter.string(from: 9), "0:09")
        XCTAssertEqual(BreakTimerFormatter.string(from: 65), "1:05")
        XCTAssertEqual(BreakTimerFormatter.string(from: 599), "9:59")
    }

    func testFormatterOverOneHour() {
        XCTAssertEqual(BreakTimerFormatter.string(from: 3600), "1:00:00")
        XCTAssertEqual(BreakTimerFormatter.string(from: 3725), "1:02:05")
    }

    func testFormatterNegativeIsZero() {
        XCTAssertEqual(BreakTimerFormatter.string(from: -42), "0:00")
    }

    // MARK: - State transitions

    @MainActor
    func testInitialStateMatchesRequestedDuration() {
        let state = BreakTimerState(initialDuration: 600)
        XCTAssertEqual(state.remaining, 600)
        XCTAssertFalse(state.isRunning)
        XCTAssertFalse(state.didFinish)
    }

    @MainActor
    func testNegativeInitialDurationIsClampedToZero() {
        let state = BreakTimerState(initialDuration: -10)
        XCTAssertEqual(state.initialDuration, 0)
        XCTAssertEqual(state.remaining, 0)
    }

    @MainActor
    func testAdjustClampsAtZeroAndMarksFinished() {
        let state = BreakTimerState(initialDuration: 30)
        state.adjust(by: -100)
        XCTAssertEqual(state.remaining, 0)
        XCTAssertTrue(state.didFinish)
    }

    @MainActor
    func testAdjustAddingTimeAfterFinishClearsFinish() {
        let state = BreakTimerState(initialDuration: 0)
        XCTAssertEqual(state.remaining, 0)
        state.adjust(by: -10) // already zero — should also mark finished
        XCTAssertTrue(state.didFinish)
        state.adjust(by: 60)
        XCTAssertEqual(state.remaining, 60)
        XCTAssertFalse(state.didFinish)
    }

    @MainActor
    func testResetReturnsToInitialDuration() {
        let state = BreakTimerState(initialDuration: 120)
        state.adjust(by: -60)
        XCTAssertEqual(state.remaining, 60)
        state.reset()
        XCTAssertEqual(state.remaining, 120)
        XCTAssertFalse(state.isRunning)
        XCTAssertFalse(state.didFinish)
    }

    @MainActor
    func testToggleTogglesRunningFlag() {
        let state = BreakTimerState(initialDuration: 60)
        XCTAssertFalse(state.isRunning)
        state.toggle()
        XCTAssertTrue(state.isRunning)
        state.toggle()
        XCTAssertFalse(state.isRunning)
        // Clean up the scheduled timer.
        state.pause()
    }

    @MainActor
    func testStartIsNoOpWhenNothingRemains() {
        let state = BreakTimerState(initialDuration: 0)
        state.start()
        XCTAssertFalse(state.isRunning)
    }
}
