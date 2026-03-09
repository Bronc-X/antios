import XCTest

final class antios5UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchAndNavigatePrimaryTabsInLightMode() throws {
        let app = launchApp(initialTab: "dashboard", appearance: "light")

        assertScreen("screen.dashboard", in: app)
        captureScreenshot(named: "dashboard-light", app: app)

        tapTab(identifier: "tab.report", fallbackLabel: "解释", in: app)
        assertScreen("screen.report", in: app)
        captureScreenshot(named: "report-light", app: app)

        tapTab(identifier: "tab.plans", fallbackLabel: "行动", in: app)
        assertScreen("screen.plans", in: app)
        captureScreenshot(named: "plans-light", app: app)

        tapTab(identifier: "tab.settings", fallbackLabel: "设置", in: app)
        assertScreen("screen.settings", in: app)
        captureScreenshot(named: "settings-light", app: app)
    }

    func testLaunchMaxInLightMode() throws {
        let app = launchApp(initialTab: "max", appearance: "light")
        assertScreen("screen.max", in: app)
        captureScreenshot(named: "max-light", app: app)
    }

    func testLaunchAndNavigatePrimaryTabsInDarkMode() throws {
        let app = launchApp(initialTab: "dashboard", appearance: "dark")

        assertScreen("screen.dashboard", in: app)
        captureScreenshot(named: "dashboard-dark", app: app)

        tapTab(identifier: "tab.report", fallbackLabel: "解释", in: app)
        assertScreen("screen.report", in: app)
        captureScreenshot(named: "report-dark", app: app)

        tapTab(identifier: "tab.plans", fallbackLabel: "行动", in: app)
        assertScreen("screen.plans", in: app)
        captureScreenshot(named: "plans-dark", app: app)

        tapTab(identifier: "tab.settings", fallbackLabel: "设置", in: app)
        assertScreen("screen.settings", in: app)
        captureScreenshot(named: "settings-dark", app: app)
    }

    func testLaunchMaxInDarkMode() throws {
        let app = launchApp(initialTab: "max", appearance: "dark")
        assertScreen("screen.max", in: app)
        captureScreenshot(named: "max-dark", app: app)
    }

    private func launchApp(initialTab: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["UI_TEST_BYPASS_GATEKEEPING"] = "1"
        app.launchEnvironment["UI_TEST_INITIAL_TAB"] = initialTab
        app.launchEnvironment["UI_TEST_APPEARANCE_MODE"] = appearance
        app.launch()
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.otherElements["screen.main"].waitForExistence(timeout: 5))
        return app
    }

    private func assertScreen(_ identifier: String, in app: XCUIApplication) {
        XCTAssertTrue(app.otherElements[identifier].waitForExistence(timeout: 5), "Missing screen \(identifier)")
    }

    private func tapTab(identifier: String, fallbackLabel: String, in app: XCUIApplication) {
        let identifiedButton = app.buttons[identifier]
        if identifiedButton.waitForExistence(timeout: 2) {
            identifiedButton.tap()
            return
        }

        let fallbackButton = app.buttons[fallbackLabel]
        XCTAssertTrue(
            fallbackButton.waitForExistence(timeout: 5),
            "Missing tab button \(identifier) / \(fallbackLabel)"
        )
        fallbackButton.tap()
    }

    private func captureScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
