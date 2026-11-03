import XCTest
import UIKit

/// Regression against a real SSH server and tmux. Every screenshot is
/// attached to the result bundle; a missing control fails the test.
final class Shots: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.terminal.app")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        addUIInterruptionMonitor(withDescription: "System password save offer") { alert in
            let notNow = alert.buttons["Not Now"].firstMatch
            guard notNow.exists else { return false }
            notNow.tap()
            return true
        }
    }

    func testAppearanceAndCleanStartup() throws {
        app.launch()
        field("server.example.com").typeText("127.0.0.1:22222")
        field("root").typeText("shotbot")
        let password = app.secureTextFields["Optional"].firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 10))
        password.tap()
        password.typeText("Term1n4lSh0ts")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        tap("connectButton")
        dismissPasswordSaveOffer()
        let trust = app.buttons["Trust"].firstMatch
        XCTAssertTrue(trust.waitForExistence(timeout: 60), app.debugDescription)
        // A person can read the fingerprint for longer than Citadel's
        // former ten-second login timeout before making a decision.
        sleep(12)
        dismissPasswordSaveOffer()
        // Trigger the interruption monitor if Passwords presented its
        // sheet after the app's own host-key alert became accessible.
        if !trust.isHittable { app.tap() }
        XCTAssertTrue(trust.waitForExistence(timeout: 10))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: trust)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 10), .completed)
        shot("00-host-key")
        trust.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: trust)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        waitForText("SHOT_READY")
        shot("01-connected-dark")
        assertCleanTerminal()

        terminal.tap()
        let tips = app.buttons["Continue"].firstMatch
        if tips.waitForExistence(timeout: 2) { tips.tap() }
        app.typeText("printf 'USER_COMMAND_OK\\n'\n")
        waitForText("USER_COMMAND_OK")
        app.typeText("for i in {1..50}; do echo row-$i; done\n")
        waitForText("row-50")
        hideKeyboard()
        terminal.swipeDown()
        assertCleanTerminal()
        shot("02-scrollback")
        terminal.swipeUp()

        // Change appearance while the app stays foregrounded. The
        // terminal must repaint immediately, including its blank cells.
        for (index, appearance) in ["Light", "Dark", "Light"].enumerated() {
            openSettings()
            tap("appearancePicker")
            tap(appearance)
            shot("03-settings-\(index)-\(appearance.lowercased())")
            dismissSettings()
            XCTAssertTrue(terminal.waitForExistence(timeout: 10))
            let light = try terminalBackgroundBrightness()
            if appearance == "Light" { XCTAssertGreaterThan(light, 0.85) }
            else { XCTAssertLessThan(light, 0.2) }
            assertCleanTerminal()
            shot("04-terminal-\(index)-\(appearance.lowercased())")
        }

        // Explicit terminal palettes also update an existing buffer.
        openSettings()
        tap("Theme")
        tap("theme-graphite")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        dismissSettings()
        XCTAssertLessThan(try terminalBackgroundBrightness(), 0.25)
        shot("05-graphite-light-chrome")
        openSettings()
        tap("Theme")
        tap("theme-paper")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        dismissSettings()
        XCTAssertGreaterThan(try terminalBackgroundBrightness(), 0.85)
        shot("05-paper")

        openSettings()
        tap("appearancePicker")
        tap("Dark")
        dismissSettings()
        XCTAssertGreaterThan(try terminalBackgroundBrightness(), 0.85)
        shot("05-paper-dark-chrome")
        openSettings()
        tap("appearancePicker")
        tap("Light")
        dismissSettings()

        tap("workspaceMenu")
        tap("Reconnect")
        let connected = NSPredicate(format: "value == %@", "Connected")
        let status = app.descendants(matching: .any)["activeSessionStatus"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15))
        let online = XCTNSPredicateExpectation(predicate: connected, object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [online], timeout: 30), .completed)
        waitForText("row-50") // tmux retained the existing shell
        assertCleanTerminal()
        terminal.tap()
        // Leaving tmux copy mode restores command entry after scrolling.
        let escape = app.buttons["Escape"].firstMatch
        if escape.waitForExistence(timeout: 3), escape.isHittable { escape.tap() }
        app.typeText("history\n")
        sleep(1)
        assertCleanTerminal() // setup must not enter server-side history
        hideKeyboard()
        shot("06-reconnected-light")
    }

    private var terminal: XCUIElement { app.descendants(matching: .any)["terminalSurface"].firstMatch }

    private func field(_ name: String) -> XCUIElement {
        let element = app.textFields[name].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 15), app.debugDescription)
        element.tap()
        return element
    }

    private func tap(_ id: String) {
        let button = app.buttons[id].firstMatch
        if button.waitForExistence(timeout: 3), button.isHittable {
            button.tap()
            return
        }
        let element = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 15), "Missing \(id): \(app.debugDescription)")
        element.tap()
    }

    private func waitForText(_ text: String) {
        XCTAssertTrue(terminal.waitForExistence(timeout: 60), app.debugDescription)
        let predicate = NSPredicate { [weak self] _, _ in
            (self?.terminal.value as? String)?.contains(text) == true
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 30), .completed, app.debugDescription)
    }

    private func assertCleanTerminal() {
        let text = terminal.value as? String ?? ""
        XCTAssertFalse(text.contains("tmux new-session"), text)
        XCTAssertFalse(text.contains("tmux attach"), text)
        XCTAssertFalse(text.contains("term-"), text)
    }

    private func openSettings() { tap("workspaceMenu"); tap("Settings") }

    private func dismissSettings() {
        app.navigationBars["Settings"].swipeDown()
        XCTAssertTrue(app.buttons["workspaceMenu"].waitForExistence(timeout: 10), app.debugDescription)
    }

    private func hideKeyboard() {
        let button = app.buttons["Hide keyboard"].firstMatch
        if button.exists { button.tap() }
    }

    private func dismissPasswordSaveOffer() {
        guard let application = app else { return }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for owner in [springboard, application] {
            let notNow = owner.buttons["Not Now"].firstMatch
            if notNow.waitForExistence(timeout: 2), notNow.isHittable { notNow.tap() }
        }
    }

    private func terminalBackgroundBrightness() throws -> Double {
        // Sample blank cells below the prompt, away from bars and text.
        sleep(1)
        let image = terminal.screenshot().image
        let cg = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(cg.cropping(to: CGRect(x: cg.width / 2, y: cg.height * 3 / 4, width: 8, height: 8)))
        var rgba = [UInt8](repeating: 0, count: 8 * 8 * 4)
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 8, height: 8, bitsPerComponent: 8,
                bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        var total: UInt64 = 0
        for pixel in 0..<64 {
            let offset = pixel * 4
            total += UInt64(rgba[offset]) + UInt64(rgba[offset + 1]) + UInt64(rgba[offset + 2])
        }
        return Double(total) / (64.0 * 3.0 * 255.0)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
