import XCTest

final class SmokeTests: XCTestCase {
    func testLaunchPlayPauseAndResume() {
        let app = XCUIApplication()
        app.launch()
        let enter = app.buttons["ENTER OUTPOST"]
        XCTAssertTrue(enter.waitForExistence(timeout: 15))
        attach("01-menu")
        enter.tap()
        let pause = app.buttons["PAUSE"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        attach("02-gameplay")
        pause.tap()
        let resume = app.buttons["RESUME"]
        XCTAssertTrue(resume.waitForExistence(timeout: 5))
        attach("03-paused")
        resume.tap()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state,.runningForeground)
    }
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
