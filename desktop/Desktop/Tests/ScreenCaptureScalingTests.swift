import XCTest

@testable import Omi_Computer

final class ScreenCaptureScalingTests: XCTestCase {

    let maxDim: CGFloat = 512

    // MARK: - Proportional Scaling (non-square)

    func testSquareImageScalesToMaxDimension() {
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 2000, imageHeight: 2000, maxDimension: maxDim)
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 512)
        XCTAssertEqual(cw, 512)
        XCTAssertEqual(ch, 512)
    }

    func testLandscapeScalesProportionally() {
        // 16:9 landscape (e.g. 2560x1440)
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 2560, imageHeight: 1440, maxDimension: maxDim)
        // 512 / 2560 = 0.2 → 512 x 288
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 288)
        XCTAssertEqual(cw, 512)
        XCTAssertEqual(ch, 288)
    }

    func testPortraitScalesProportionally() {
        // 9:16 portrait (e.g. 1080x1920)
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 1080, imageHeight: 1920, maxDimension: maxDim)
        // 512 / 1920 = 0.2666... → 288 x 512
        XCTAssertEqual(sw, 288)
        XCTAssertEqual(sh, 512)
        XCTAssertEqual(cw, 288)
        XCTAssertEqual(ch, 512)
    }

    func testUltrawideScalesToWidth() {
        // 21:9 ultrawide (e.g. 3440x1440)
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 3440, imageHeight: 1440, maxDimension: maxDim)
        // 512 / 3440 = 0.1488... → 512 x 214
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 214)
    }

    func testSmallImageDoesNotUpscale() {
        // Image smaller than maxDimension should not be scaled up
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 400, imageHeight: 300, maxDimension: maxDim)
        XCTAssertEqual(sw, 400)
        XCTAssertEqual(sh, 300)
        XCTAssertEqual(cw, 400)
        XCTAssertEqual(ch, 300)
    }

    func testRetinaDisplayScale() {
        // Retina 2x: 2880x1800 logical → 3456x2234 physical pixels
        let (sw, sh, _, _) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 3456, imageHeight: 2234, maxDimension: maxDim)
        // 512 / 3456 = 0.1481... → 512 x 330
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 330)
    }

    func testEdgeCaseTinyLandscape() {
        let (sw, sh, _, _) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 640, imageHeight: 480, maxDimension: maxDim)
        // Smaller than 512, no upscale
        XCTAssertEqual(sw, 640)
        XCTAssertEqual(sh, 480)
    }

    func testEdgeCaseExactly512() {
        let (sw, sh, _, _) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 512, imageHeight: 512, maxDimension: maxDim)
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 512)
    }

    // MARK: - Square (Center-Padded) Scaling

    func testSquareLandscapePadsCorrectly() {
        // 16:9 landscape → 512x288 scaled, padded to 512x512 canvas
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 2560, imageHeight: 1440, maxDimension: maxDim, square: true)
        XCTAssertEqual(sw, 512)   // scaled width
        XCTAssertEqual(sh, 288)   // scaled height
        XCTAssertEqual(cw, 512)   // square canvas width
        XCTAssertEqual(ch, 512)   // square canvas height
    }

    func testSquarePortraitPadsCorrectly() {
        // 9:16 portrait → 288x512 scaled, padded to 512x512 canvas
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 1080, imageHeight: 1920, maxDimension: maxDim, square: true)
        XCTAssertEqual(sw, 288)
        XCTAssertEqual(sh, 512)
        XCTAssertEqual(cw, 512)
        XCTAssertEqual(ch, 512)
    }

    func testSquareAlreadySquareDoesNotPad() {
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 2000, imageHeight: 2000, maxDimension: maxDim, square: true)
        // Already square, no padding needed
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 512)
        XCTAssertEqual(cw, 512)
        XCTAssertEqual(ch, 512)
    }

    func testSquareSmallImageNoUpscale() {
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 300, imageHeight: 200, maxDimension: maxDim, square: true)
        // No upscale: 300x200 stays, canvas becomes 512x512 for padding
        XCTAssertEqual(sw, 300)
        XCTAssertEqual(sh, 200)
        XCTAssertEqual(cw, 512)
        XCTAssertEqual(ch, 512)
    }

    func testSquareUltrawide() {
        // 21:9 ultrawide (3440x1440) → 512x214 scaled, padded to 512x512
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 3440, imageHeight: 1440, maxDimension: maxDim, square: true)
        XCTAssertEqual(sw, 512)
        XCTAssertEqual(sh, 214)
        XCTAssertEqual(cw, 512)
        XCTAssertEqual(ch, 512)
    }

    // MARK: - Boundary Conditions

    func testZeroDimensionReturnsZero() {
        let (sw, sh, cw, ch) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 0, imageHeight: 1000, maxDimension: maxDim)
        // Division by zero (max(0, 1000) = 1000, scale = 512/1000)
        XCTAssertEqual(sw, 0)  // 0 * 0.512 = 0
        XCTAssertEqual(sh, 512)
    }

    func testVerySmallWidth() {
        let (sw, sh, _, _) = ScreenCaptureManager.thumbnailDimensions(
            imageWidth: 1, imageHeight: 10000, maxDimension: maxDim)
        // max(1, 10000) = 10000, scale = 512/10000 = 0.0512
        // newWidth = 1 * 0.0512 = 0 (Int truncation)
        XCTAssertEqual(sw, 0)
        XCTAssertEqual(sh, 512)
    }
}
