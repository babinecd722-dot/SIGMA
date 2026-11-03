import XCTest
import UIKit
import SwiftTerm
@testable import Terminal

final class TerminalAppearanceTests: XCTestCase {
    @MainActor
    func testPaperANSITextHasReadableContrast() {
        func luminance(_ red: Double, _ green: Double, _ blue: Double) -> Double {
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let background = luminance(0.98, 0.98, 0.97)
        for (index, color) in TerminalTheme.paper.ansiColors.enumerated() {
            let foreground = luminance(Double(color.red) / 65535, Double(color.green) / 65535, Double(color.blue) / 65535)
            XCTAssertGreaterThanOrEqual((background + 0.05) / (foreground + 0.05), 4.5, "ANSI color \(index)")
        }
    }

    @MainActor
    func testLightDarkSwitchRepaintsExistingTerminalAndSurvivesResize() async throws {
        let view = AccessibleTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let host = UIViewController()
        host.view.addSubview(view)
        let window = UIWindow(frame: view.frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        view.feed(text: "Visible text\r\n\u{1b}[31mRed\u{1b}[0m\r\n")

        for theme in [TerminalTheme.paper, .pro, .paper, .graphite, .paper] {
            TerminalSurface.applyStyle(view, fontSize: 14, theme: theme)
            view.frame.size = CGSize(width: theme.id == "paper" ? 600 : 390, height: 400)
            view.setNeedsLayout()
            view.layoutIfNeeded()
            // Drain the library's queued color callbacks and display frames.
            try await Task.sleep(for: .milliseconds(100))
            assertColor(view.nativeBackgroundColor, equals: theme.uiBackground)
            assertColor(view.nativeForegroundColor, equals: theme.uiForeground)
            assertColor(UIColor(cgColor: try XCTUnwrap(view.layer.backgroundColor)), equals: theme.uiBackground)
            // Check the pixels draw(_:) paints, not just the stored
            // properties: transparent blank cells looked black in the
            // scrolling terminal even with the correct layer color.
            let rendered = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
                view.draw(view.bounds)
            }
            let cg = try XCTUnwrap(rendered.cgImage)
            let blank = try XCTUnwrap(cg.cropping(to: CGRect(x: cg.width / 2, y: cg.height * 3 / 4, width: 1, height: 1)))
            var pixel = [UInt8](repeating: 0, count: 4)
            try pixel.withUnsafeMutableBytes { bytes in
                let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(blank, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            XCTAssertEqual(pixel[3], 255, "Blank cells must paint the opaque theme")
            assertColor(UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                blue: CGFloat(pixel[2]) / 255, alpha: CGFloat(pixel[3]) / 255), equals: theme.uiBackground)
            XCTAssertEqual(view.keyboardAppearance, theme.id == "paper" ? .light : .dark)
            XCTAssertTrue(view.accessibilityValue?.contains("Visible text") == true)
            XCTAssertTrue(view.accessibilityValue?.contains("Red") == true)
        }
    }

    @MainActor
    func testThemeChangePreservesGrid() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        TerminalSurface.applyStyle(view, fontSize: 14, theme: .pro)
        let dimensions = view.terminalDimensions
        TerminalSurface.applyStyle(view, fontSize: 14, theme: .paper)
        XCTAssertEqual(view.terminalDimensions.cols, dimensions.cols)
        XCTAssertEqual(view.terminalDimensions.rows, dimensions.rows)
    }

    @MainActor
    private func assertColor(_ actual: UIColor, equals expected: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        actual.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        XCTAssertEqual(ar, er, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(ag, eg, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(ab, eb, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(aa, ea, accuracy: 0.01, file: file, line: line)
    }
}
