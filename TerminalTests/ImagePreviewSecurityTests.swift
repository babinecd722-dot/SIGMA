import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Terminal

final class ImagePreviewSecurityTests: XCTestCase {
    @MainActor
    func testOversizedImageUsesBoundedThumbnailAndNormalImageStillOpens() throws {
        let large = try png(width: 8192, height: 32)
        let scaled = try XCTUnwrap(FilePreviewView.downsampled(large))
        XCTAssertLessThanOrEqual(try XCTUnwrap(scaled.cgImage).width, 4096)
        XCTAssertLessThanOrEqual(try XCTUnwrap(scaled.cgImage).height, 4096)
        let normal = try XCTUnwrap(FilePreviewView.downsampled(try png(width: 64, height: 32)))
        XCTAssertEqual(normal.cgImage?.width, 64)
        XCTAssertEqual(normal.cgImage?.height, 32)
    }

    @MainActor
    func testThumbnailFailureOrOversizedResultCannotFallBackToFullRaster() throws {
        let data = try png(width: 8192, height: 32)
        // Simulate a thumbnail decoder refusing a file that a full image
        // decoder could otherwise accept. Failure must remain bounded.
        XCTAssertNil(FilePreviewView.downsampled(data, makeThumbnail: { _, _ in nil }))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let full = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertNil(FilePreviewView.downsampled(data, makeThumbnail: { _, _ in full }))
    }

    @MainActor
    private func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(UIColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        let image = try XCTUnwrap(context.makeImage())
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
