import XCTest
@testable import MacZoomerCore

final class PermissionKindTests: XCTestCase {
    func testEveryPermissionKindHasASystemSettingsURL() {
        for kind in PermissionKind.allCases {
            XCTAssertNotNil(
                kind.systemSettingsURL,
                "PermissionKind \(kind.rawValue) is missing a System Settings deep link"
            )
        }
    }

    func testEveryPermissionKindHasNonEmptyCopy() {
        for kind in PermissionKind.allCases {
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertFalse(kind.rationale.isEmpty)
        }
    }
}
