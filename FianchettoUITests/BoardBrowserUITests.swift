import XCTest

final class BoardBrowserUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// W07-ui-create-board-keyboard (A01): 키보드로 Board를 만들고, 다시 실행해도 선택된 채 남는다.
    /// 이름은 ASCII로 입력한다. XCUITest의 키 합성은 한글 조합 입력에서 멈출 수 있고, 한글 이름은 단위 테스트가 검증한다.
    @MainActor
    func test_W07_createBoardWithKeyboardSurvivesRelaunch() {
        let test = UITestApp(name: "create")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        let nameField = app.textFields["board-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.typeText("Service A\r")

        let row = app.descendants(matching: .any)["board-row-Service A"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.isSelected)
        XCTAssertTrue(app.staticTexts["구성이 비어 있습니다"].waitForExistence(timeout: 5))

        test.relaunch()
        test.activateForKeyboard()
        let restored = app.descendants(matching: .any)["board-row-Service A"]
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertTrue(restored.isSelected)
    }

    /// W07-ui-menu-command: 파일 메뉴에 ⌘N의 "Board 만들기…"가 있다.
    @MainActor
    func test_W07_fileMenuHasCreateBoardCommand() {
        let test = UITestApp(name: "menu")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))

        let fileMenu = app.menuBars.menuBarItems["파일"]
        fileMenu.click()
        let item = fileMenu.menuItems["Board 만들기…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        XCTAssertTrue(item.isEnabled)
        // W08-menu-command: Bishop 추가(⇧⌘A)도 파일 메뉴에 있다.
        XCTAssertTrue(fileMenu.menuItems["Bishop 추가…"].exists)
        // W09-commands: 연결 대상 변경(⇧⌘R)도 파일 메뉴에 있다.
        XCTAssertTrue(fileMenu.menuItems["연결 대상 변경…"].exists)
        // 단축키는 XCUITest가 노출하지 않으므로, 메뉴를 닫고 ⌘N이 이 명령을 실행하는지로 확인한다.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["board-name-field"].waitForExistence(timeout: 5))
    }
}
