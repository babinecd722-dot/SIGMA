import XCTest
import UIKit
import ImageIO
@testable import SwiftTerm
@testable import Terminal

final class TerminalSecurityTests: XCTestCase {
    private let smallPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg=="

    // A valid, losslessly compressed 8192 x 2049 one-bit grayscale PNG.
    // It is only 2115 bytes on the wire but exceeds the 16M-pixel ceiling.
    private let oversizedPNG = "iVBORw0KGgoAAAANSUhEUgAAIAAAAAgBAQAAAABt31OqAAAICklEQVR42u3BMQEAAADCoPVPbQsvoAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABOBg3hAAEZusn9AAAAAElFTkSuQmCC"

    @MainActor
    func testInlineImageChecksRasterSizeBeforeDecodeAndKeepsSmallImages() async throws {
        let large = try XCTUnwrap(Data(base64Encoded: oversizedPNG))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(large as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual((props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 8192)
        XCTAssertEqual((props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, 2049)
        XCTAssertFalse(terminalInlineImageWithinLimits(large))
        XCTAssertFalse(terminalInlineImageWithinLimits(Data("not an image".utf8)))
        XCTAssertTrue(terminalInlineImageWithinLimits(try XCTUnwrap(Data(base64Encoded: smallPNG))))

        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 240), options: TerminalSurface.terminalOptions)
        view.feed(text: "\u{1b}]1337;File=inline=1:\(oversizedPNG)\u{7}OK")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(imageCount(in: view), 0, "Rejected raster must never be attached to a screen line")
        XCTAssertTrue(view.accessibilityValue?.contains("OK") == true)
        view.feed(text: "\u{1b}]1337;File=inline=1:\(smallPNG)\u{7}")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(imageCount(in: view), 0, "Ordinary inline graphics must remain supported")
    }

    @MainActor
    func testOversizedOSCIsDiscardedAndParserRecovers() {
        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 240), options: TerminalSurface.terminalOptions)
        view.feed(text: "\u{1b}]2;BASE_TITLE\u{7}\u{1b}]2;")
        let block = Array(repeating: UInt8(ascii: "A"), count: 32 * 1024)
        for _ in 0...256 { view.feed(byteArray: block[...]) }
        view.feed(text: "\u{7}AFTER_OVERSIZED_OSC")
        XCTAssertTrue(view.accessibilityValue?.contains("AFTER_OVERSIZED_OSC") == true)
        XCTAssertTrue(view.withTerminal { $0.terminalTitle == "BASE_TITLE" }, "Oversized title must be discarded before it reaches app UI")
    }

    func testRenderedImageBudgetIncludesRetinaScaleAndPartialStripes() {
        let cell = CGSize(width: 8, height: 16)
        XCTAssertTrue(terminalRenderedImageWithinLimits(CGSize(width: 100, height: 100), cellSize: cell, scale: 3))
        // These dimensions pass OSC's 4096-point limit, but require far
        // more than 16M physical pixels on a 3x screen.
        XCTAssertFalse(terminalRenderedImageWithinLimits(CGSize(width: 4095, height: 4095), cellSize: cell, scale: 3))
        // The final stripe is a whole cell high even when only part of
        // its logical row is occupied. Its allocation belongs in the cap.
        XCTAssertFalse(terminalRenderedImageWithinLimits(CGSize(width: 4096, height: 4096),
                                                        cellSize: CGSize(width: 8, height: 17), scale: 1))
        for size in [CGSize.zero, CGSize(width: -1, height: 1),
                     CGSize(width: CGFloat.infinity, height: 1), CGSize(width: 1, height: CGFloat.nan),
                     CGSize(width: CGFloat(Int.max), height: CGFloat(Int.max)),
                     CGSize(width: 0.1, height: 1)] {
            XCTAssertFalse(terminalRenderedImageWithinLimits(size, cellSize: cell, scale: 3))
        }
        for invalid in [CGFloat.zero, -1, .nan, .infinity, .leastNonzeroMagnitude] {
            XCTAssertFalse(terminalRenderedImageWithinLimits(CGSize(width: 10, height: 10),
                                                            cellSize: CGSize(width: 8, height: invalid), scale: 3))
        }
        for invalid in [CGFloat.zero, -1, 0.5, .nan, .infinity] {
            XCTAssertFalse(terminalRenderedImageWithinLimits(CGSize(width: 10, height: 10), cellSize: cell, scale: invalid))
        }
    }

    @MainActor
    func testLargeValidImageRequestsAreRejectedBeforeRenderingAndParserRecovers() async throws {
        let (window, view) = imageViewOnRetinaScreen()
        defer { view.removeFromSuperview(); window.isHidden = true }
        XCTAssertGreaterThanOrEqual(view.cachedImageMetricsValue()?.imageScale ?? 0, 2)
        for (index, request) in ["width=4095px;height=4095px;preserveAspectRatio=1",
                                 "width=199;height=199;preserveAspectRatio=0"].enumerated() {
            let marker = "AFTER_LARGE_REQUEST_\(index)"
            view.feed(text: "\u{1b}]1337;File=inline=1;\(request):\(smallPNG)\u{7}\(marker)\r\n")
            await waitForText(marker, in: view)
            XCTAssertEqual(imageCount(in: view), 0, "A small source must not bypass the rendered-raster cap")
            XCTAssertTrue(view.accessibilityValue?.contains(marker) == true)
        }
    }

    @MainActor
    func testInvalidImageDimensionsDoNotFallBackToAutoAndSmallImagesStillRender() async throws {
        let (window, view) = imageViewOnRetinaScreen()
        defer { view.removeFromSuperview(); window.isHidden = true }
        for (index, invalid) in ["0", "-1", "0px", "-1px", "4096px", "200", "101%", "18446744073709551615px"].enumerated() {
            for axis in ["width", "height"] {
                view.feed(text: "\u{1b}]1337;File=inline=1;\(axis)=\(invalid):\(smallPNG)\u{7}")
            }
            let marker = "AFTER_INVALID_REQUEST_\(index)"
            view.feed(text: marker + "\r\n")
            await waitForText(marker, in: view)
            XCTAssertEqual(imageCount(in: view), 0, "Malformed dimensions must not be converted into an automatic image")
            XCTAssertTrue(view.accessibilityValue?.contains(marker) == true)
        }
        view.feed(text: "\u{1b}]1337;File=inline=1;width=auto;height=auto:\(smallPNG)\u{7}AFTER_AUTO_IMAGE\r\n")
        await waitForText("AFTER_AUTO_IMAGE", in: view)
        let autoCount = imageCount(in: view)
        XCTAssertGreaterThan(autoCount, 0, "Missing and explicit auto dimensions remain supported")
        view.feed(text: "\u{1b}]1337;File=inline=1;width=8px;height=8px:\(smallPNG)\u{7}AFTER_SMALL_IMAGE\r\n")
        await waitForText("AFTER_SMALL_IMAGE", in: view)
        XCTAssertGreaterThan(imageCount(in: view), autoCount, "Ordinary explicit dimensions remain supported")
    }

    @MainActor
    private func imageViewOnRetinaScreen() -> (UIWindow, AccessibleTerminalView) {
        let frame = CGRect(x: 0, y: 0, width: 390, height: 240)
        let window = UIWindow(frame: frame)
        window.contentScaleFactor = 3
        let view = AccessibleTerminalView(frame: frame, options: TerminalSurface.terminalOptions)
        window.addSubview(view)
        window.layoutIfNeeded()
        return (window, view)
    }

    @MainActor
    private func waitForText(_ marker: String, in view: AccessibleTerminalView) async {
        let rendered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            view.accessibilityValue?.contains(marker) == true
        }, object: view)
        await fulfillment(of: [rendered], timeout: 3)
    }

    @MainActor
    private func imageCount(in view: AccessibleTerminalView) -> Int {
        view.withTerminal { terminal in
            (0..<terminal.buffer.lines.count).reduce(0) { $0 + (terminal.buffer.lines[$1].images?.count ?? 0) }
        }
    }
}
