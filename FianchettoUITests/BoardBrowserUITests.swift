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
        test.type("Service A", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])

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

    /// W11-ui-create-group-and-rename (A01): 메뉴로 그룹을 만들고 이름을 바꾼다.
    @MainActor
    func test_W11_createGroupAndRenameIt() {
        let test = UITestApp(name: "group")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Service A", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Service A"].waitForExistence(timeout: 5))

        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["그룹 추가…"].click()
        let field = app.textFields["node-name-field"]
        test.type("Dev", into: field)
        app.typeKey(.return, modifierFlags: [])
        let dev = app.descendants(matching: .any)["node-row-Dev"]
        XCTAssertTrue(dev.waitForExistence(timeout: 5))

        dev.click()
        app.menuBars.menuBarItems["편집"].click()
        app.menuBars.menuBarItems["편집"].menuItems["이름 변경…"].click()
        test.replaceText(in: field, with: "Core")
        // Return이 시트를 닫으므로 입력과 분리해, 사라진 입력 칸을 다시 확인하지 않게 한다.
        app.typeKey(.return, modifierFlags: [])

        XCTAssertTrue(app.descendants(matching: .any)["node-row-Core"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["node-row-Dev"].exists)
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
        // W10-commands-no-delete: 이름 변경·보관·보관 해제가 있고 영구 삭제 명령은 없다.
        for title in ["Board 이름 변경…", "Board 보관", "보관 해제"] {
            XCTAssertTrue(fileMenu.menuItems[title].exists, title)
        }
        XCTAssertFalse(fileMenu.menuItems.allElementsBoundByIndex.contains { $0.title.contains("삭제") })
        // W11-commands: 그룹 추가·웹 링크 추가는 파일 메뉴, 이름 변경·URL 변경은 편집 메뉴에 있다.
        XCTAssertTrue(fileMenu.menuItems["그룹 추가…"].exists)
        XCTAssertTrue(fileMenu.menuItems["웹 링크 추가…"].exists)
        app.typeKey(.escape, modifierFlags: [])
        let editMenu = app.menuBars.menuBarItems["편집"]
        editMenu.click()
        XCTAssertTrue(editMenu.menuItems["이름 변경…"].waitForExistence(timeout: 5))
        XCTAssertTrue(editMenu.menuItems["URL 변경…"].exists)
        // W12-commands: 이동 명령도 편집 메뉴에 있다.
        for title in ["위로 이동", "아래로 이동", "이동…"] {
            XCTAssertTrue(editMenu.menuItems[title].exists, title)
        }
        // 단축키는 XCUITest가 노출하지 않으므로, 메뉴를 닫고 ⌘N이 이 명령을 실행하는지로 확인한다.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["board-name-field"].waitForExistence(timeout: 5))
    }
}
