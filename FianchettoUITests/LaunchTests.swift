import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// W01-launch-shows-window: 앱이 실행되면 기본 창 하나를 띄운다.
    @MainActor
    func test_W01_launchShowsSingleMainWindow() {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.windows.count, 1)
    }
}
