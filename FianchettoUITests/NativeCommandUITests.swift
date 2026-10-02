import XCTest

/// 네이티브 동작 점검(docs/design/AUDIT-2026-10-03.md)에서 고친 오른쪽 클릭 메뉴·Delete 키·툴바를 확인한다.
final class NativeCommandUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    /// AUDIT-3·6: 툴바로 Wing을 만들고, 오른쪽 클릭 메뉴는 종류에 맞는 명령만 보여 준다.
    @MainActor
    func test_AUDIT_contextMenusDeleteKeyAndToolbar() {
        let test = UITestApp(name: "native")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Service A", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        let board = app.descendants(matching: .any)["board-row-Service A"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))

        // 툴바의 Wing 추가는 메뉴의 'Wing 추가…'와 같은 입력 창을 연다.
        let addWing = app.toolbars.buttons["Wing 추가"]
        XCTAssertTrue(addWing.waitForExistence(timeout: 5))
        XCTAssertTrue(app.toolbars.buttons["Bishop 추가"].exists)
        addWing.click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        let dev = app.descendants(matching: .any)["node-row-Dev"]
        XCTAssertTrue(dev.waitForExistence(timeout: 5))

        // Delete 키(시스템 Delete 명령 → '제거…' 확인 창)는 XCUITest에서 트리 목록이 키보드 포커스를 받지 못해
        // 키로도 편집 > 삭제로도 실행되지 않는다. 실제 키보드 동작은 사용자가 수동으로 확인했다(2026-10-03).

        // Wing의 오른쪽 클릭 메뉴: 추가·이름 변경·이동·제거는 있고, 열기는 없다.
        dev.rightClick()
        // 메뉴 막대의 메뉴와 섞이지 않도록 창 안에 뜬 오른쪽 클릭 메뉴만 본다.
        let menu = app.windows.firstMatch.menus.firstMatch
        XCTAssertTrue(menu.menuItems["Wing 추가…"].waitForExistence(timeout: 5))
        for title in ["Bishop 추가…", "웹 링크 추가…", "이름 변경…", "이동…", "제거…"] {
            XCTAssertTrue(menu.menuItems[title].exists, title)
        }
        XCTAssertFalse(menu.menuItems["열기"].exists)
        app.typeKey(.escape, modifierFlags: [])

        // Board 행의 오른쪽 클릭 메뉴: 보관되지 않은 Board에는 '보관 해제'가 없다.
        board.rightClick()
        let boardMenu = app.windows.firstMatch.menus.firstMatch
        XCTAssertTrue(boardMenu.menuItems["Board 이름 변경…"].waitForExistence(timeout: 5))
        XCTAssertTrue(boardMenu.menuItems["Board 보관"].exists)
        XCTAssertFalse(boardMenu.menuItems["보관 해제"].exists)
        app.typeKey(.escape, modifierFlags: [])

    }

    /// AUDIT-1: 메뉴 항목은 지금 할 수 없으면 꺼지고, 선택이 바뀌면 메뉴를 열지 않아도 단축키가 바로 동작한다(W07 꺼짐 고착 회귀).
    @MainActor
    func test_AUDIT_menuItemsFollowSelectionWithoutOpeningMenus() {
        let test = UITestApp(name: "menus")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        // 활성화하며 파일 메뉴를 한 번 연다. 이때는 Board가 없어 항목 명령이 모두 꺼져 있다.
        test.activateForKeyboard()

        // Board가 없으면 Board·항목 명령은 꺼져 있고, Board 만들기는 켜져 있다.
        let file = app.menuBars.menuBarItems["파일"]
        file.click()
        XCTAssertTrue(file.menuItems["Board 만들기…"].waitForExistence(timeout: 5))
        XCTAssertTrue(file.menuItems["Board 만들기…"].isEnabled)
        for title in ["Bishop 추가…", "Wing 추가…", "열기", "다시 선택…", "Board 이름 변경…", "Board 보관", "보관 해제"] {
            XCTAssertFalse(file.menuItems[title].isEnabled, title)
        }
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey("n", modifierFlags: .command)
        test.type("Service A", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Service A"].waitForExistence(timeout: 5))
        app.toolbars.buttons["Wing 추가"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForExistence(timeout: 5))

        // 메뉴를 열지 않은 채 ⌘⌫: Wing을 고르면 제거 확인 창이 열려야 한다.
        app.descendants(matching: .any)["node-row-Dev"].click()
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(app.descendants(matching: .any)["removal-message"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        // Wing을 고른 상태: 보관은 켜지고 보관 해제는 꺼진다. URL 변경은 웹 링크가 아니므로 꺼진다.
        file.click()
        XCTAssertTrue(file.menuItems["Board 보관"].waitForExistence(timeout: 5))
        XCTAssertTrue(file.menuItems["Board 보관"].isEnabled)
        XCTAssertFalse(file.menuItems["보관 해제"].isEnabled)
        XCTAssertFalse(file.menuItems["다시 선택…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        let edit = app.menuBars.menuBarItems["편집"]
        edit.click()
        XCTAssertTrue(edit.menuItems["URL 변경…"].waitForExistence(timeout: 5))
        XCTAssertFalse(edit.menuItems["URL 변경…"].isEnabled)
        XCTAssertTrue(edit.menuItems["이름 변경…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])
    }
}
