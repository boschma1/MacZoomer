import XCTest
@testable import MacZoomerCore

final class ZoomGeometryTests: XCTestCase {
    func testClampLevelEnforcesBounds() {
        XCTAssertEqual(ZoomGeometry.clamp(level: 0.5), ZoomGeometry.minLevel)
        XCTAssertEqual(ZoomGeometry.clamp(level: 99), ZoomGeometry.maxLevel)
        XCTAssertEqual(ZoomGeometry.clamp(level: 2.5), 2.5)
    }

    func testImageLayerFrameAtUnityZoomFillsScreenWhenFocalsMatch() {
        let frame = ZoomGeometry.imageLayerFrame(
            sourcePointSize: CGSize(width: 1920, height: 1080),
            zoomLevel: 1.0,
            focalSource: .init(x: 960, y: 540),
            focalScreen: .init(x: 960, y: 540)
        )
        XCTAssertEqual(frame.origin.x, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.origin.y, 0, accuracy: 1e-9)
        XCTAssertEqual(frame.size.width, 1920)
        XCTAssertEqual(frame.size.height, 1080)
    }

    func testImageLayerFrameScalesWithZoomKeepingFocalAligned() {
        let frame = ZoomGeometry.imageLayerFrame(
            sourcePointSize: CGSize(width: 1000, height: 1000),
            zoomLevel: 2.0,
            focalSource: .init(x: 500, y: 500),
            focalScreen: .init(x: 500, y: 500)
        )
        XCTAssertEqual(frame.size.width, 2000)
        XCTAssertEqual(frame.size.height, 2000)
        // Focal point (500, 500) scaled by 2 = (1000, 1000) from origin; origin
        // should be at (500 - 1000, 500 - 1000) = (-500, -500).
        XCTAssertEqual(frame.origin.x, -500)
        XCTAssertEqual(frame.origin.y, -500)
    }

    func testSourcePointInverseOfImageLayerFrame() {
        // Picking a point on the screen and converting to source coords should
        // round-trip back through imageLayerFrame.
        let zoom: CGFloat = 3.0
        let focalSrc = CGPoint(x: 400, y: 300)
        let focalScr = CGPoint(x: 800, y: 600)
        let screenPoint = CGPoint(x: 950, y: 450)
        let src = ZoomGeometry.sourcePoint(
            forScreenPoint: screenPoint,
            zoomLevel: zoom,
            focalSource: focalSrc,
            focalScreen: focalScr
        )
        XCTAssertEqual(src.x, focalSrc.x + (screenPoint.x - focalScr.x) / zoom, accuracy: 1e-9)
        XCTAssertEqual(src.y, focalSrc.y + (screenPoint.y - focalScr.y) / zoom, accuracy: 1e-9)
    }

    func testClampFocalSourceCentersWhenImageSmallerThanDestination() {
        // At zoom=1.0, a 500×500 image is smaller than the 1000×1000 destination,
        // so the focal source should be clamped to the image centre.
        let focal = ZoomGeometry.clampFocalSource(
            CGPoint(x: 0, y: 0),
            zoomLevel: 1.0,
            sourcePointSize: CGSize(width: 500, height: 500),
            destinationSize: CGSize(width: 1000, height: 1000),
            focalScreen: CGPoint(x: 500, y: 500)
        )
        XCTAssertEqual(focal.x, 250)
        XCTAssertEqual(focal.y, 250)
    }

    func testClampFocalSourceLeavesValidFocalsUnchanged() {
        // At zoom=4.0 the image is larger than destination; a valid interior
        // focal point should pass through unchanged.
        let validFocal = CGPoint(x: 500, y: 500)
        let result = ZoomGeometry.clampFocalSource(
            validFocal,
            zoomLevel: 4.0,
            sourcePointSize: CGSize(width: 1000, height: 1000),
            destinationSize: CGSize(width: 800, height: 800),
            focalScreen: CGPoint(x: 400, y: 400)
        )
        XCTAssertEqual(result.x, validFocal.x, accuracy: 1e-9)
        XCTAssertEqual(result.y, validFocal.y, accuracy: 1e-9)
    }
}
