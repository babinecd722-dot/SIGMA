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

        XCTAssertLessThan(terminal.frame.minY, 95, "Terminal must start below the status bar, without a navigation header")
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.01)).press(forDuration: 0.5)
        XCTAssertTrue(app.descendants(matching: .any)["Copy"].firstMatch.waitForExistence(timeout: 10))
        shot("01-native-copy-keyboard-closed")
        tap("Copy")
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Holding output must not open the keyboard")

        terminal.tap()
        let tips = app.buttons["Continue"].firstMatch
        if tips.waitForExistence(timeout: 2) { tips.tap() }
        assertControlAvailable()
        try assertKeyboardCorners(light: false)
        shot("01-compact-keyboard-dark")
        app.typeText("printf 'USER_COMMAND_OK\\n'\n")
        waitForText("USER_COMMAND_OK")
        // A hold must select local text and offer native Copy even
        // though this tmux fixture has mouse reporting switched on.
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.01)).press(forDuration: 0.7)
        shot("01-native-copy-menu")
        tap("Copy")
        // The native menu must release input immediately after Copy.
        assertControlAvailable()
        app.typeText("for i in {1..50}; do echo row-$i; done\n")
        waitForText("row-50")
        hideKeyboard()
        terminal.swipeDown()
        assertCleanTerminal()
        shot("02-scrollback")
        terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.15)).press(forDuration: 0.5)
        tap("Copy")
        XCTAssertFalse(app.keyboards.firstMatch.exists)
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
            shot("04-terminal-\(index)-\(appearance.lowercased())")
            let light = try terminalBackgroundBrightness()
            if appearance == "Light" { XCTAssertGreaterThan(light, 0.85) }
            else { XCTAssertLessThan(light, 0.2) }
            try assertChrome(light: appearance == "Light")
            assertCleanTerminal()
        }

        // Explicit terminal palettes also update an existing buffer.
        openSettings()
        tap("Theme")
        tap("theme-graphite")
        app.navigationBars["Theme"].buttons.firstMatch.tap()
        dismissSettings()

        XCTAssertLessThan(try terminalBackgroundBrightness(), 0.25)
        shot("05-graphite-light-chrome")
        try assertChrome(light: true)

        openSettings()
        tap("Theme")
        tap("theme-paper")
        app.navigationBars["Theme"].buttons.firstMatch.tap()
        dismissSettings()
        XCTAssertGreaterThan(try terminalBackgroundBrightness(), 0.85)
        shot("05-paper")
        try assertChrome(light: true)

        openSettings()
        tap("appearancePicker")
        tap("Dark")
        dismissSettings()
        XCTAssertGreaterThan(try terminalBackgroundBrightness(), 0.85)
        shot("05-paper-dark-chrome")
        try assertChrome(light: false)
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
        shot("06-reconnected-keyboard")
        // Ctrl-C cancels copy mode or clears the prompt. A standalone
        // Escape can instead turn the next 'h' into a shell Meta chord.
        tap("Control")
        app.typeText("c")
        app.typeText("history\n")
        waitForText("printf 'USER_COMMAND_OK") // actual server history, not just command echo
        assertCleanTerminal() // setup must not enter server-side history
        hideKeyboard()
        shot("06-reconnected-light")
        try assertChrome(light: true)

        terminal.tap()
        assertControlAvailable()
        try assertKeyboardCorners(light: true)
        shot("05-compact-keyboard-light")
        hideKeyboard()
        try verifyFiles(label: "07-files-before-restart")

        // Restart only the dedicated CI SSH account/server. This loses
        // tmux state like a reboot, without rebooting the runner itself.
        terminal.tap()
        assertControlAvailable()
        app.typeText("touch ~/.sigma-test-restart\n")
        waitForText("SHOT_READY")
        app.typeText("printf 'AFTER_RESTART_OK\\n'\n")
        waitForText("AFTER_RESTART_OK")
        assertCleanTerminal()
        hideKeyboard()
        shot("08-after-server-restart")
        try verifyFiles(label: "09-files-after-restart")
        terminal.tap()
        assertControlAvailable()
        app.typeText("exit\n")
        let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: terminal)
        XCTAssertEqual(XCTWaiter.wait(for: [ended], timeout: 20), .completed, app.debugDescription)
        shot("10-normal-exit")
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
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: element)
        let result = XCTWaiter.wait(for: [available], timeout: 10)
        if result != .completed { shot("unavailable-\(id)") }
        XCTAssertEqual(result, .completed, "Unavailable \(id): \(app.debugDescription)")
        element.tap()
    }

    private func assertControlAvailable() {
        let control = app.buttons["Control"].firstMatch
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: control)
        let result = XCTWaiter.wait(for: [available], timeout: 10)
        if result != .completed { shot("unavailable-keyboard-after-copy") }
        XCTAssertEqual(result, .completed, app.debugDescription)
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
        let done = app.buttons["settingsDone"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), app.debugDescription)
        done.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed, app.debugDescription)
        let menu = app.buttons["workspaceMenu"].firstMatch
        let usable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == YES"), object: menu)
        XCTAssertEqual(XCTWaiter.wait(for: [usable], timeout: 10), .completed, app.debugDescription)
    }

    private func hideKeyboard() {
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            tap("terminalKeysMenu")
            tap("Hide keyboard")
            let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == NO"), object: keyboard)
            XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 10), .completed)
        }
    }

    private func assertKeyboardCorners(light: Bool) throws {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.buttons["Control"].firstMatch.frame.height, 40)
        XCTAssertFalse(app.buttons["Backtick"].exists)
        let image = app.screenshot().image
        let keyboardTop = app.buttons["Control"].firstMatch.frame.maxY + 4
        let y = (keyboardTop + 3) / app.frame.height
        let reference = try brightness(image, x: 0.5, y: (keyboardTop + 12) / app.frame.height)
        for x in [0.004, 0.986] {
            let value = try brightness(image, x: x, y: y)
            XCTAssertGreaterThan(value, light ? 0.6 : 0.05, "Keyboard corner at x=\(x) must not be black")
            XCTAssertLessThan(abs(value - reference), 0.08, "Keyboard corner must match its backing")
        }
    }

    private func verifyFiles(label: String) throws {
        tap("workspaceMenu")
        tap("Files")
        let search = app.textFields["filesSearch"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertLessThan(app.buttons["uploadButton"].firstMatch.frame.maxY, search.frame.minY)
        shot(label)
        search.tap()
        search.typeText("welcome")
        tap("remote-file-welcome.txt")
        tap("Open")
        XCTAssertTrue(app.navigationBars["welcome.txt"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.buttons["Save"].firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        shot(label + "-preview")
        tap("Done")
        let browser = app.descendants(matching: .any)["filesBrowser"].firstMatch
        for _ in 0..<8 {
            if !browser.exists { break }
            tap("filesBack")
            sleep(1)
        }
        XCTAssertFalse(browser.exists, app.debugDescription)
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
        return try brightness(terminal.screenshot().image, x: 0.5, y: 0.75)
    }

    private func assertChrome(light: Bool) throws {
        let image = app.screenshot().image
        // Blank parts of the navigation bar and bottom safe area must
        // follow app appearance, independently of the terminal palette.
        for y in [0.015, 0.97] {
            let value = try brightness(image, x: 0.04, y: y)
            if light { XCTAssertGreaterThan(value, 0.85, "Light chrome at y=\(y)") }
            else { XCTAssertLessThan(value, 0.2, "Dark chrome at y=\(y)") }
        }
    }

    private func brightness(_ image: UIImage, x: Double, y: Double) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage)
        let crop = try XCTUnwrap(cg.cropping(to: CGRect(x: Int(Double(cg.width) * x), y: Int(Double(cg.height) * y), width: 8, height: 8)))
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
