import XCTest
import AppKit
@testable import MacZoomerCore

final class ScreenshotTests: XCTestCase {
    // MARK: - RegionSelectorGeometry

    func testRectFromTwoPointsNormalisesNegativeDelta() {
        let r = RegionSelectorGeometry.rect(
            from: NSPoint(x: 100, y: 200),
            to: NSPoint(x: 60, y: 240)
        )
        XCTAssertEqual(r.origin.x, 60)
        XCTAssertEqual(r.origin.y, 200)
        XCTAssertEqual(r.width, 40)
        XCTAssertEqual(r.height, 40)
    }

    func testRectFromIdenticalPointsHasZeroArea() {
        let r = RegionSelectorGeometry.rect(
            from: NSPoint(x: 0, y: 0),
            to: NSPoint(x: 0, y: 0)
        )
        XCTAssertEqual(r.width, 0)
        XCTAssertEqual(r.height, 0)
    }

    func testRectFromPositiveDeltaPreservesOrigin() {
        let r = RegionSelectorGeometry.rect(
            from: NSPoint(x: 10, y: 20),
            to: NSPoint(x: 110, y: 70)
        )
        XCTAssertEqual(r.origin.x, 10)
        XCTAssertEqual(r.origin.y, 20)
        XCTAssertEqual(r.width, 100)
        XCTAssertEqual(r.height, 50)
    }

    // MARK: - ImageFileWriter

    func testUniqueFileURLAppendsCounterWhenFileExists() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacZoomerScreenshotTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let baseName = "Fixed Test Stamp"
        let first = ImageFileWriter.uniqueFileURL(in: tmp, baseName: baseName)
        XCTAssertEqual(first.lastPathComponent, "Fixed Test Stamp.png")

        // Touch the first path; next call must pick a suffixed name.
        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = ImageFileWriter.uniqueFileURL(in: tmp, baseName: baseName)
        XCTAssertEqual(second.lastPathComponent, "Fixed Test Stamp (2).png")

        FileManager.default.createFile(atPath: second.path, contents: Data())
        let third = ImageFileWriter.uniqueFileURL(in: tmp, baseName: baseName)
        XCTAssertEqual(third.lastPathComponent, "Fixed Test Stamp (3).png")
    }
}
