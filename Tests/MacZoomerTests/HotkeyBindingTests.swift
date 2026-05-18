import XCTest
@testable import MacZoomerCore

final class HotkeyBindingTests: XCTestCase {
    func testDisplayStringContainsCommandSymbolForCmdBinding() {
        let binding = HotkeyBinding(keyCode: 18, modifiers: [.command])
        XCTAssertEqual(binding.displayString, "⌘1")
    }

    func testDisplayStringOrdersModifiersCanonically() {
        let binding = HotkeyBinding(keyCode: 23, modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(binding.displayString, "⌃⌥⇧⌘5")
    }

    func testRoundTripCoding() throws {
        let original = HotkeyBinding(keyCode: 21, modifiers: [.command, .shift])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyBinding.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testModifierMaskIsNormalisedToDeviceIndependentFlags() {
        let raw = NSEvent.ModifierFlags(rawValue: 0xFFFF_FFFF)
        let binding = HotkeyBinding(keyCode: 18, modifiers: raw)
        XCTAssertTrue(binding.modifiers.isSubset(of: .deviceIndependentFlagsMask))
    }

    func testDefaultsCoverAllActions() {
        for action in HotkeyAction.allCases {
            XCTAssertNotNil(
                DefaultHotkeys.bindings[action],
                "Missing default binding for \(action.rawValue)"
            )
        }
    }

    func testDefaultsHaveNoExactDuplicates() {
        let bindings = Array(DefaultHotkeys.bindings.values)
        let uniqued = Set(bindings)
        XCTAssertEqual(bindings.count, uniqued.count, "Two default hotkeys collide")
    }
}
