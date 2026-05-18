import XCTest
@testable import MacZoomerCore
import AppKit

final class DrawingTests: XCTestCase {
    // MARK: - ShapeConstraint

    func testNoModifiersGivesFreehand() {
        XCTAssertEqual(ShapeConstraint.from(modifiers: []), .freehand)
    }

    func testShiftAloneGivesLine() {
        XCTAssertEqual(ShapeConstraint.from(modifiers: .shift), .line)
    }

    func testOptionAloneGivesRectangle() {
        XCTAssertEqual(ShapeConstraint.from(modifiers: .option), .rectangle)
    }

    func testControlAloneGivesEllipse() {
        XCTAssertEqual(ShapeConstraint.from(modifiers: .control), .ellipse)
    }

    func testShiftPlusOptionGivesArrow() {
        XCTAssertEqual(ShapeConstraint.from(modifiers: [.shift, .option]), .arrow)
    }

    func testCommandIsIgnoredForShapeConstraint() {
        // Cmd is reserved for global shortcuts and shouldn't change drawing mode.
        XCTAssertEqual(ShapeConstraint.from(modifiers: [.shift, .command]), .line)
    }

    // MARK: - PenStyle

    func testHighlightPenHasReducedAlpha() {
        let style = PenStyle(color: .yellow, width: 4, isHighlight: true)
        XCTAssertLessThan(style.renderingColor.alphaComponent, 1.0)
    }

    func testHighlightPenHasLargerRenderingWidth() {
        let opaque    = PenStyle(color: .yellow, width: 4, isHighlight: false)
        let highlight = PenStyle(color: .yellow, width: 4, isHighlight: true)
        XCTAssertGreaterThan(highlight.renderingWidth, opaque.renderingWidth)
    }

    // MARK: - DrawingState

    @MainActor
    func testCommitAndUndoMaintainsAnnotationList() {
        let state = DrawingState()
        XCTAssertEqual(state.annotations.count, 0)
        state.commit(.freehand(FreehandStroke(style: state.currentStyle, points: [.zero])))
        state.commit(.freehand(FreehandStroke(style: state.currentStyle, points: [.zero])))
        XCTAssertEqual(state.annotations.count, 2)
        state.undoLast()
        XCTAssertEqual(state.annotations.count, 1)
        state.undoLast()
        state.undoLast() // overshooting should be a no-op
        XCTAssertEqual(state.annotations.count, 0)
    }

    @MainActor
    func testEraseAllClearsAnnotationsAndResetsBackground() {
        let state = DrawingState()
        state.setBackground(.whiteboard)
        state.commit(.line(StraightShape(style: state.currentStyle, start: .zero, end: CGPoint(x: 10, y: 10))))
        state.eraseAll()
        XCTAssertTrue(state.annotations.isEmpty)
        XCTAssertEqual(state.background, .clear)
    }

    @MainActor
    func testAdjustWidthClampsToBounds() {
        let state = DrawingState()
        state.setWidth(PenStyle.maxWidth + 100)
        XCTAssertEqual(state.currentWidth, PenStyle.maxWidth)
        state.setWidth(PenStyle.minWidth - 100)
        XCTAssertEqual(state.currentWidth, PenStyle.minWidth)
    }

    // MARK: - PenColor

    func testEveryPenColorHasUniqueShortcut() {
        let chars = PenColor.allCases.map(\.shortcutCharacter)
        XCTAssertEqual(chars.count, Set(chars).count, "Two pen colors share a shortcut")
    }

    // MARK: - DrawingGeometry

    func testRectFromPointsIsAlwaysNormalised() {
        let a = CGPoint(x: 30, y: 50)
        let b = CGPoint(x: 10, y: 20)
        let r = DrawingGeometry.rect(from: a, to: b)
        XCTAssertEqual(r, CGRect(x: 10, y: 20, width: 20, height: 30))
    }

    func testSnapAngleRoundsTo15Degrees() {
        let start = CGPoint.zero
        // 5° from horizontal — should snap to 0°.
        let end = CGPoint(x: cos(5 * .pi / 180), y: sin(5 * .pi / 180))
        let snapped = DrawingGeometry.snapAngle(from: start, to: end, snapEnabled: true)
        XCTAssertEqual(snapped.x, 1.0, accuracy: 1e-6)
        XCTAssertEqual(snapped.y, 0.0, accuracy: 1e-6)
    }

    func testSnapAngleDisabledLeavesEndUnchanged() {
        let start = CGPoint.zero
        let end = CGPoint(x: 3, y: 7)
        let result = DrawingGeometry.snapAngle(from: start, to: end, snapEnabled: false)
        XCTAssertEqual(result, end)
    }
}
