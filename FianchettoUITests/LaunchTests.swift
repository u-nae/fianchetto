import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// W01-launch-shows-window: 앱이 실행되면 기본 창 하나를 띄운다.
    @MainActor
    func test_W01_launchShowsSingleMainWindow() {
        let test = UITestApp(name: "launch")
        test.launch()
        defer { test.terminate() }

        XCTAssertTrue(test.app.windows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(test.app.windows.count, 1)
    }
}
