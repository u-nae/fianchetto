import AppKit
import XCTest

/// 테스트마다 앱 컨테이너 안의 전용 저장소·마지막 Board 기록을 쓰도록 실행한다. 실사용 데이터를 건드리지 않기 위해서다.
/// 첫 실행은 이전 테스트가 남긴 테스트 폴더를 모두 지운다(앱 컨테이너는 테스트 러너가 직접 지울 수 없다).
/// 앱은 이 환경 변수를 Debug 빌드에서만 읽는다.
@MainActor
struct UITestApp {
    let id: String
    let app = XCUIApplication()

    init(name: String) {
        id = "\(name)-\(UUID().uuidString)"
        app.launchEnvironment["FIANCHETTO_UI_TEST_ID"] = id
        app.launchEnvironment["FIANCHETTO_UI_TEST_RESET"] = "1"
    }

    func launch() {
        app.launch()
        ensureWindow()
    }

    /// 사용자가 다른 앱을 쓰는 중이면 macOS가 활성화 요청을 거절해 앱이 백그라운드로 실행될 수 있다. 그렇게 실행된 SwiftUI 앱은
    /// 활성화만으로는 창을 만들지 않고, Dock 아이콘을 누를 때와 같은 다시 열기(reopen) 이벤트를 받아야 창을 연다.
    /// 그래서 창이 없으면 테스트가 띄운 바로 그 인스턴스(같은 실행 파일 경로)에 다시 열기를 보낸다.
    /// 번들 ID로 앱을 찾으면 다른 빌드 경로의 같은 앱이 열릴 수 있어 쓰지 않는다.
    private func ensureWindow() {
        guard !app.windows.firstMatch.waitForExistence(timeout: 3) else { return }
        // 테스트 러너와 같은 빌드 폴더의 앱이 테스트 대상이다.
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "Fianchetto.app")
        let isRunning = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.u-nae.Fianchetto")
            .contains { $0.bundleURL?.standardizedFileURL == url.standardizedFileURL }
        guard isRunning else {
            XCTFail("테스트 대상 앱이 실행 중이 아니다: \(url.path)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        let reopened = XCTestExpectation(description: "reopen")
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in reopened.fulfill() }
        _ = XCTWaiter().wait(for: [reopened], timeout: 10)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "다시 열기 후에도 창이 없다")
    }

    /// 같은 테스트 저장소로 다시 실행한다(정리하지 않음).
    func relaunch() {
        app.terminate()
        app.launchEnvironment["FIANCHETTO_UI_TEST_RESET"] = "0"
        app.launch()
        ensureWindow()
    }

    /// macOS 14부터 다른 프로세스의 활성화 요청은 협조적이라 무시될 수 있다. 앱의 메뉴 막대를 직접 열었다 닫아
    /// 앱을 확실히 활성화한 뒤 키보드 입력을 보낸다.
    func activateForKeyboard() {
        let fileMenu = app.menuBars.menuBarItems["파일"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 10))
        fileMenu.click()
        XCTAssertTrue(fileMenu.menuItems.firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// 시트가 나타나는 동안 입력하면 키가 사라질 수 있어, 입력 칸이 실제로 눌릴 수 있게 된 뒤에 입력한다.
    func type(_ text: String, into element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: timeout), .completed)
        element.click()
        // 입력 칸은 키 입력마다 다시 그려질 수 있어, 초점을 준 뒤에는 요소 참조 대신 앱에 입력한다.
        guard !text.isEmpty else { return }
        app.typeText(text)
        ensureValue(text, in: element)
    }

    /// 입력 칸의 기존 값을 지우고 새 값을 넣는다. 커서를 끝으로 옮긴 뒤 기존 글자 수만큼 지운다.
    func replaceText(in element: XCUIElement, with text: String) {
        type("", into: element)
        clearAndType(text, in: element)
        ensureValue(text, in: element)
    }

    /// 키 합성이 글자를 빠뜨리는 일이 있어(예: draft → drat), 입력 칸의 값이 기대와 다르면 지우고 다시 입력한다(최대 두 번).
    /// 테스트가 확인하는 것은 앱 동작이지 키 합성 도구가 아니므로, 입력 단계의 흔들림만 걷어 낸다.
    private func ensureValue(_ text: String, in element: XCUIElement) {
        for _ in 0..<2 {
            let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: element)
            guard XCTWaiter().wait(for: [typed], timeout: 2) != .completed, element.exists else { return }
            clearAndType(text, in: element)
        }
    }

    private func clearAndType(_ text: String, in element: XCUIElement) {
        let current = element.value as? String ?? ""
        app.typeKey(.rightArrow, modifierFlags: .command)
        for _ in current { app.typeKey(.delete, modifierFlags: []) }
        app.typeText(text)
    }

    func terminate() {
        app.terminate()
    }
}
