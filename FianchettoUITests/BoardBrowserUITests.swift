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
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
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

        let core = app.descendants(matching: .any)["node-row-Core"]
        XCTAssertTrue(core.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["node-row-Dev"].exists)

        // 회귀: 선택한(접힌) 그룹 안에 그룹을 추가하면 그 그룹이 펼쳐져 새 항목이 보인다.
        core.click()
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Data", into: field)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Data"].waitForExistence(timeout: 5))
    }

    /// W28-commands: 아이콘 보기로 바꾸고, Wing 타일 이중 클릭으로 들어갔다가 보기 메뉴로 위로 나온다.
    @MainActor
    func test_W28_iconViewEnterAndGoUp() {
        let test = UITestApp(name: "icons")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Icons", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Icons"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForExistence(timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        for title in ["아이콘으로 보기", "목록으로 보기", "들어가기", "상위 Wing으로", "뒤로"] {
            XCTAssertTrue(viewMenu.menuItems[title].exists, title)
        }
        viewMenu.menuItems["아이콘으로 보기"].click()
        let tile = app.descendants(matching: .any)["icon-tile-Dev"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["path-bar"].exists)

        tile.doubleClick()
        XCTAssertTrue(app.staticTexts["Wing이 비어 있습니다"].waitForExistence(timeout: 5))

        viewMenu.click()
        viewMenu.menuItems["상위 Wing으로"].click()
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
    }

    /// W17-open-history: 보기 메뉴 '이력 보기'(⌘Y)로 이력 탭을 열면 'Board 만들기'·'Wing 추가' 행이 순번 역순으로 보이고, 다시 하면 항목 탭으로 돌아간다.
    @MainActor
    func test_W17_historyTabShowsRevisions() {
        let test = UITestApp(name: "history")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Plan", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Plan"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForExistence(timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        let showHistory = viewMenu.menuItems["이력 보기"]
        XCTAssertTrue(showHistory.waitForExistence(timeout: 5))
        showHistory.click()
        let first = app.descendants(matching: .any)["revision-row-1"]
        let second = app.descendants(matching: .any)["revision-row-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(first.exists)
        XCTAssertTrue((second.label as String).hasPrefix("Wing 추가, #2, "), second.label)
        XCTAssertTrue((first.label as String).hasPrefix("Board 만들기, #1, "), first.label)
        XCTAssertLessThan(second.frame.minY, first.frame.minY, "최신 revision이 위에 있다")
        XCTAssertTrue(app.staticTexts["현재 구성"].exists)

        // 이력 탭에서 다시 '이력 보기'를 하면 항목 탭으로 돌아간다. 메뉴를 누른 직후의 키 합성은 불안정해 메뉴로 확인한다.
        viewMenu.click()
        showHistory.click()
        XCTAssertTrue(second.waitForNonExistence(timeout: 5))
    }

    /// W18-past-view·W18-return-to-current: 이력에서 Wing을 더하기 전 revision을 고르면 과거 구성 띠가 보이고 Wing이 사라지며,
    /// 띠의 '현재로 돌아가기'로 현재 구성에 돌아온다.
    @MainActor
    func test_W18_pastConfigurationAndReturn() {
        let test = UITestApp(name: "past")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Past", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Past"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        let wing = app.descendants(matching: .any)["node-row-Dev"]
        XCTAssertTrue(wing.waitForExistence(timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        XCTAssertFalse(viewMenu.menuItems["현재 구성으로 돌아가기"].isEnabled)
        viewMenu.menuItems["이력 보기"].click()
        let first = app.descendants(matching: .any)["revision-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        let banner = app.descendants(matching: .any)["past-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertTrue((banner.label as String).hasPrefix("과거 구성, 읽기 전용, #1, "), banner.label)
        XCTAssertTrue(wing.waitForNonExistence(timeout: 5))

        app.buttons["return-to-current"].click()
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        XCTAssertTrue(wing.waitForExistence(timeout: 5))
    }

    /// W18 회귀(디자인 세션 렌더링 확인에서 발견): 기록 뒤 대상이 옮겨진 Bishop을 과거 구성에서 골라도 앱이 멈추거나 끝나지 않고,
    /// '고른 항목' 카드에 '당시와 다른 위치'가 보인다.
    @MainActor
    func test_W18_movedTargetInPastConfigurationDoesNotCrash() throws {
        // 러너의 임시 폴더(샌드박스 컨테이너) 아래에 테스트 폴더를 만든다.
        let fixtures = FileManager.default.temporaryDirectory.appending(path: "w18-\(UUID().uuidString)")
        // 폴더 Bishop을 쓴다. 파일 선택 창 안의 항목은 누를 수 없어(별도 프로세스) 처음 위치의 폴더를 Return으로 고른다.
        let original = fixtures.appending(path: "plan")
        let moved = fixtures.appending(path: "moved/plan")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtures) }

        let test = UITestApp(name: "moved")
        test.app.launchEnvironment["FIANCHETTO_UI_TEST_PICK_DIRECTORY"] = original.path
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Moved", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Moved"].waitForExistence(timeout: 5))

        // 파일 선택 창은 테스트 폴더("plan")를 처음 위치로 열리고(Debug UI 테스트 전용 환경 변수), Return으로 그 폴더를 고른다.
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Bishop 추가…"].click()
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey(.return, modifierFlags: [])
        let row = app.descendants(matching: .any)["node-row-plan"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // 앱을 끄고 파일을 옮긴 뒤 같은 저장소로 다시 띄운다.
        app.terminate()
        try FileManager.default.moveItem(at: original, to: moved)
        test.relaunch()
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Moved"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["board-row-Moved"].click()

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        viewMenu.menuItems["이력 보기"].click()
        let revision = app.descendants(matching: .any)["revision-row-2"]
        XCTAssertTrue(revision.waitForExistence(timeout: 5))
        revision.click()
        XCTAssertTrue(app.descendants(matching: .any)["past-banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        XCTAssertTrue(app.staticTexts["당시와 다른 위치"].waitForExistence(timeout: 10))
        // 충돌은 고른 뒤 2–4초 안에 났다. 그동안 앱 상태가 실행 중에서 벗어나지 않아야 한다(뒤집은 기대: 일어나면 실패).
        let crashed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue), object: app
        )
        crashed.isInverted = true
        XCTAssertEqual(XCTWaiter().wait(for: [crashed], timeout: 6), .completed)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    /// W19 핵심 흐름: 과거 구성에서 '현재와 비교'를 열면 비교 띠와 추가된 Wing의 '추가됨' 표시가 보이고, '비교 닫기'로 과거 구성에 돌아온다.
    @MainActor
    func test_W19_compareWithCurrentAndClose() {
        let test = UITestApp(name: "compare")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Plan", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Plan"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForExistence(timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        viewMenu.menuItems["이력 보기"].click()
        let first = app.descendants(matching: .any)["revision-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        let banner = app.descendants(matching: .any)["past-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))

        app.buttons["compare-with-current"].click()
        XCTAssertTrue(app.descendants(matching: .any)["compare-bar"].waitForExistence(timeout: 5))
        let row = app.descendants(matching: .any)["compare-row-Dev"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue((row.label as String).contains("추가됨"), row.label)
        XCTAssertFalse(banner.exists, "비교 중에는 과거 구성 띠 대신 비교 띠만 보인다")

        app.buttons["compare-close"].click()
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["compare-bar"].exists)
    }

    /// 라벨 없이 식별자만 붙인 Text는 macOS에서 문구를 value로 노출한다. value가 비어 있으면 label을 쓴다.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        if let value = element.value as? String, !value.isEmpty { return value }
        return element.label
    }

    // [W20-restore-menu-opens-sheet] [W20-file-menu-same-sheet] [W20-sheet-keyboard-accessibility]
    // 띠의 '이 구성으로…' › '복원…'과 파일 메뉴 '이 구성으로 복원…'이 같은 시트를 열고, Esc는 취소, Return은 복원이다.
    @MainActor
    func test_W20_restoreFromPastConfiguration() {
        let test = UITestApp(name: "restore")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Plan", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Plan"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForExistence(timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        viewMenu.menuItems["이력 보기"].click()
        let first = app.descendants(matching: .any)["revision-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        let banner = app.descendants(matching: .any)["past-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))

        // 띠의 메뉴로 시트를 연다.
        var menu = app.menuButtons["restore-menu"]
        if !menu.waitForExistence(timeout: 5) {
            menu = app.descendants(matching: .any)["restore-menu"]
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        let restoreItem = app.menuItems["복원…"]
        XCTAssertTrue(restoreItem.waitForExistence(timeout: 5))
        restoreItem.click()
        let title = app.descendants(matching: .any)["restore-sheet-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: title), "#1 구성으로 복원")
        let summary = app.descendants(matching: .any)["restore-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: summary), "변화 1개")
        let row = app.descendants(matching: .any)["restore-row-Dev"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Dev, 제거됨")
        XCTAssertTrue(app.descendants(matching: .any)["restore-cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["restore-confirm"].waitForExistence(timeout: 5))

        // Esc는 취소: 시트만 닫히고 과거 구성은 그대로다.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(banner.exists)

        // 파일 메뉴도 같은 시트를 연다.
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["이 구성으로 복원…"].click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: title), "#1 구성으로 복원")

        // Return은 복원: 현재 구성으로 돌아와 Dev가 없어지고 이력에 복원 기록이 쌓인다.
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForNonExistence(timeout: 5))
        let restored = app.descendants(matching: .any)["revision-row-3"]
        XCTAssertTrue(restored.waitForExistence(timeout: 5))
        XCTAssertTrue(restored.label.hasPrefix("#1에서 복원, #3, "), restored.label)
    }

    // [W21-menu-opens-sheet] [W21-menu-order] [W21-file-menu-same-sheet] [W21-sheet-keyboard-accessibility] [W21-blank-name-disables-confirm]
    // 띠의 '이 구성으로…' › '새 Board 만들기…'와 파일 메뉴 '이 구성으로 새 Board 만들기…'가 같은 시트를 열고, 기본 이름은 전체 선택되며,
    // Esc는 취소, Return은 만들기다. 만든 뒤 새 Board가 선택된다.
    @MainActor
    func test_W21_createBoardFromPastConfiguration() {
        let test = UITestApp(name: "duplicate")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Plan", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Plan"].waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
        test.type("Dev", into: app.textFields["node-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-Dev"].waitForExistence(timeout: 5))

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        viewMenu.menuItems["이력 보기"].click()
        let first = app.descendants(matching: .any)["revision-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.click()
        let banner = app.descendants(matching: .any)["past-banner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 5))

        // 띠의 메뉴: '복원…' 다음에 '새 Board 만들기…'가 있다.
        var menu = app.menuButtons["restore-menu"]
        if !menu.waitForExistence(timeout: 5) {
            menu = app.descendants(matching: .any)["restore-menu"]
        }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        let duplicateItem = app.menuItems["새 Board 만들기…"]
        XCTAssertTrue(duplicateItem.waitForExistence(timeout: 5))
        let titles = app.menuItems.allElementsBoundByIndex.map(\.title)
        let restoreIndex = titles.firstIndex(of: "복원…")
        let duplicateIndex = titles.firstIndex(of: "새 Board 만들기…")
        XCTAssertNotNil(restoreIndex, "\(titles)")
        XCTAssertNotNil(duplicateIndex, "\(titles)")
        if let restoreIndex, let duplicateIndex { XCTAssertLessThan(restoreIndex, duplicateIndex, "\(titles)") }
        duplicateItem.click()
        let title = app.descendants(matching: .any)["duplicate-sheet-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: title), "#1 구성으로 새 Board 만들기")
        let field = app.textFields["duplicate-name-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Plan 사본")

        // 기본 이름은 전체 선택: 바로 입력하면 통째로 바뀐다.
        app.typeText("Copy")
        XCTAssertEqual(field.value as? String, "Copy")

        // 이름을 비우면 '만들기'가 꺼지고 Return으로도 만들지 않는다.
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        let confirmButton = app.descendants(matching: .any)["duplicate-confirm"]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        XCTAssertFalse(confirmButton.isEnabled)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.exists)
        XCTAssertFalse(app.descendants(matching: .any)["board-row-Plan 사본"].exists)

        // Esc는 취소: 시트만 닫히고 과거 구성은 그대로다.
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(banner.exists)

        // 파일 메뉴도 같은 시트를 같은 기본 이름으로 연다.
        app.menuBars.menuBarItems["파일"].click()
        app.menuBars.menuBarItems["파일"].menuItems["이 구성으로 새 Board 만들기…"].click()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: title), "#1 구성으로 새 Board 만들기")
        XCTAssertEqual(field.value as? String, "Plan 사본")

        // Return은 만들기: 새 Board가 선택되고 현재 구성(순번 1에는 Dev가 없다)을 보인다.
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(banner.waitForNonExistence(timeout: 5))
        // 이력 탭을 열면 사이드바가 접히므로(0032) 다시 펼쳐 목록 행을 확인한다.
        viewMenu.click()
        let showSidebar = viewMenu.menuItems["사이드바 보기"]
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        showSidebar.click()
        let created = app.descendants(matching: .any)["board-row-Plan 사본"]
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.isSelected)
        XCTAssertFalse(app.descendants(matching: .any)["node-row-Dev"].exists)
        let firstOfCopy = app.descendants(matching: .any)["revision-row-1"]
        XCTAssertTrue(firstOfCopy.waitForExistence(timeout: 5))
        XCTAssertTrue(firstOfCopy.label.hasPrefix("과거 구성에서 만듦, #1, "), firstOfCopy.label)
    }

    /// W19 ② 나란히 보기: 세그먼트로 바꾸면 왼쪽 '이전 구성'·오른쪽 '이후 구성' 열이 열 머리와 함께 보이고,
    /// 한쪽에서 고른 항목은 반대쪽에서도 고른 상태가 되며, 한쪽에만 있는 항목은 반대쪽에 행이 없다.
    @MainActor
    func test_W19_sideBySideColumns() {
        let test = UITestApp(name: "compare-side")
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        test.activateForKeyboard()
        app.typeKey("n", modifierFlags: .command)
        test.type("Plan", into: app.textFields["board-name-field"])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["board-row-Plan"].waitForExistence(timeout: 5))
        for name in ["Docs", "Dev"] {
            app.menuBars.menuBarItems["파일"].click()
            app.menuBars.menuBarItems["파일"].menuItems["Wing 추가…"].click()
            test.type(name, into: app.textFields["node-name-field"])
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(app.descendants(matching: .any)["node-row-\(name)"].waitForExistence(timeout: 5))
        }

        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        viewMenu.menuItems["이력 보기"].click()
        let second = app.descendants(matching: .any)["revision-row-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        second.click()
        XCTAssertTrue(app.buttons["compare-with-current"].waitForExistence(timeout: 5))
        app.buttons["compare-with-current"].click()
        let mode = app.descendants(matching: .any)["compare-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.radioButtons["나란히"].click()

        let before = app.descendants(matching: .any)["compare-before-tree"]
        let after = app.descendants(matching: .any)["compare-after-tree"]
        XCTAssertTrue(before.waitForExistence(timeout: 5))
        XCTAssertTrue(after.exists)
        XCTAssertEqual(before.label, "이전 구성")
        XCTAssertEqual(after.label, "이후 구성")
        let beforeTitle = app.staticTexts["compare-before-title"]
        XCTAssertTrue(beforeTitle.label.hasPrefix("#2 · "), beforeTitle.label)
        let afterTitle = app.staticTexts["compare-after-title"]
        XCTAssertEqual(afterTitle.label, "현재 구성")

        // Dev는 이후 구성에만 있다.
        XCTAssertTrue(after.descendants(matching: .any)["compare-row-Dev"].exists)
        XCTAssertFalse(before.descendants(matching: .any)["compare-row-Dev"].exists)

        // 오른쪽에서 Docs를 고르면 왼쪽 Docs도 고른 상태다.
        after.descendants(matching: .any)["compare-row-Docs"].click()
        // 고른 상태는 행 내용이 아니라 목록의 행(OutlineRow)에 붙는다.
        let selectedLeft = before.outlineRows.containing(.any, identifier: "compare-row-Docs").firstMatch
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: selectedLeft)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed, "반대쪽 열도 같은 항목을 고른다")

        app.buttons["compare-close"].click()
        XCTAssertFalse(app.descendants(matching: .any)["compare-bar"].waitForExistence(timeout: 2))
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
        XCTAssertTrue(fileMenu.menuItems["Wing 추가…"].exists)
        XCTAssertTrue(fileMenu.menuItems["웹 링크 추가…"].exists)
        // W14-commands: 열기(⌘O)·Finder에서 보기(⌘R)도 파일 메뉴에 있다.
        XCTAssertTrue(fileMenu.menuItems["열기"].exists)
        XCTAssertTrue(fileMenu.menuItems["Finder에서 보기"].exists)
        // W15-commands: 다시 선택…·상태 새로고침도 파일 메뉴에 있다.
        XCTAssertTrue(fileMenu.menuItems["다시 선택…"].exists)
        XCTAssertTrue(fileMenu.menuItems["상태 새로고침"].exists)
        app.typeKey(.escape, modifierFlags: [])
        let editMenu = app.menuBars.menuBarItems["편집"]
        editMenu.click()
        XCTAssertTrue(editMenu.menuItems["이름 변경…"].waitForExistence(timeout: 5))
        XCTAssertTrue(editMenu.menuItems["URL 변경…"].exists)
        // W12-commands: 이동 명령도 편집 메뉴에 있다.
        // W13-commands-and-terms: 제거…도 편집 메뉴에 있고, 메뉴 어디에도 삭제 표현이 없다.
        XCTAssertTrue(editMenu.menuItems["제거…"].exists)
        XCTAssertFalse(editMenu.menuItems.allElementsBoundByIndex.contains { $0.title.contains("파일 삭제") })
        for title in ["위로 이동", "아래로 이동", "이동…"] {
            XCTAssertTrue(editMenu.menuItems[title].exists, title)
        }
        // W29-pick-disabled: Bishop 용도 "아이콘" 하위 메뉴가 편집 메뉴에 있고, 고른 Bishop이 없으면 항목이 꺼져 있다.
        // 하위 메뉴를 가진 항목 자체는 AppKit이 켜 두므로 하위 항목으로 확인한다.
        let purposeMenu = editMenu.menuItems["아이콘"]
        XCTAssertTrue(purposeMenu.exists)
        purposeMenu.hover()
        let documentPurpose = purposeMenu.menuItems["문서"]
        XCTAssertTrue(documentPurpose.waitForExistence(timeout: 5))
        XCTAssertFalse(documentPurpose.isEnabled, "고른 Bishop이 없으면 용도 항목이 꺼져 있다")
        app.typeKey(.escape, modifierFlags: [])
        // 단축키는 XCUITest가 노출하지 않으므로, ⌘N이 이 명령을 실행하는지로 확인한다.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["board-name-field"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.textFields["board-name-field"].waitForNonExistence(timeout: 5))

        // 오른쪽 열(인스펙터): 보기 메뉴로 접고 다시 편다. ⌥+I는 데드 키(ˆ)라 XCUITest 키 합성으로는 ⌥⌘I가 전달되지 않아
        // 메뉴로 확인한다(실제 키보드의 ⌥⌘I는 메뉴 단축키로 동작한다).
        let inspectorEmpty = app.staticTexts["항목을 고르세요"]
        XCTAssertTrue(inspectorEmpty.waitForExistence(timeout: 5))
        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        let hide = viewMenu.menuItems["인스펙터 가리기"]
        XCTAssertTrue(hide.waitForExistence(timeout: 5))
        hide.click()
        XCTAssertTrue(inspectorEmpty.waitForNonExistence(timeout: 5))
        viewMenu.click()
        let show = viewMenu.menuItems["인스펙터 보기"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.click()
        XCTAssertTrue(inspectorEmpty.waitForExistence(timeout: 5))
    }
}
