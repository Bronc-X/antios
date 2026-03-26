import XCTest

final class antios10UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertNotEqual(app.state, .notRunning)
    }

    func testHomeShowsGuidanceCard() throws {
        let app = XCUIApplication()
        app.launch()

        let guidanceCard = app.otherElements["home.guidanceCard"]
        XCTAssertTrue(guidanceCard.waitForExistence(timeout: 8))
        add(XCTAttachment(screenshot: app.screenshot()))
    }

    func testMaxShowsStructuredEntrySurface() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-debug-a10-tab=max"]
        app.launch()

        let fusionCard = app.otherElements["max.fusionReplyCard"]
        let followUpCard = app.otherElements["max.followUpCard"]
        XCTAssertTrue(
            fusionCard.waitForExistence(timeout: 8) || followUpCard.waitForExistence(timeout: 8),
            "Expected Max structured entry surface"
        )
        add(XCTAttachment(screenshot: app.screenshot()))
    }
}
