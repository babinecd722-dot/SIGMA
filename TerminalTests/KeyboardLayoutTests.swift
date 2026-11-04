import XCTest
import UIKit
@testable import Terminal

final class KeyboardLayoutTests: XCTestCase {
    @MainActor
    func testEveryMainKeyFitsWithoutScrollingOnCompactAndWideScreens() {
        for width in [CGFloat(320), 393, 430, 768, 1024] {
            let bar = KeyboardAccessoryView()
            bar.frame = CGRect(x: 0, y: 0, width: width, height: 44)
            bar.layoutIfNeeded()
            let stack = bar.subviews.compactMap { $0 as? UIStackView }.first
            XCTAssertEqual(stack?.arrangedSubviews.count, 9)
            XCTAssertFalse(bar.subviews.contains { $0 is UIScrollView })
            let frames = stack?.arrangedSubviews.map { $0.convert($0.bounds, to: bar) } ?? []
            for frame in frames {
                XCTAssertGreaterThan(frame.width, 25)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width)
                XCTAssertLessThanOrEqual(frame.maxY, 44)
            }
            for pair in zip(frames, frames.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX)
            }
        }
    }
}
