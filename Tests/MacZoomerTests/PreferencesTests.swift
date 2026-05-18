import XCTest
@testable import MacZoomerCore

@MainActor
final class PreferencesTests: XCTestCase {
    func testDefaultHotkeyForZoomIsCommand1() {
        let prefs = Preferences.shared
        let binding = prefs.binding(for: .zoom)
        XCTAssertNotNil(binding)
        XCTAssertEqual(binding?.modifiers, [.command])
        XCTAssertEqual(binding?.keyCode, 18)
    }

    func testSetBindingOverridesDefault() {
        let prefs = Preferences.shared
        let original = prefs.binding(for: .draw)
        defer { prefs.setBinding(original, for: .draw) }

        let custom = HotkeyBinding(keyCode: 20, modifiers: [.command, .option])
        prefs.setBinding(custom, for: .draw)
        XCTAssertEqual(prefs.binding(for: .draw), custom)
    }

    func testClearingOverrideRevertsToDefault() {
        let prefs = Preferences.shared
        let custom = HotkeyBinding(keyCode: 24, modifiers: [.command])
        prefs.setBinding(custom, for: .record)
        prefs.setBinding(nil, for: .record)
        XCTAssertEqual(prefs.binding(for: .record), DefaultHotkeys.bindings[.record])
    }
}
