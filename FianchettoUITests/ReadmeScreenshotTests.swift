import AppKit
import XCTest

/// README용 화면 캡처. 평소 테스트 실행에서는 건너뛰고, `scripts/capture-readme-screenshots.sh`가 환경 변수
/// `FIANCHETTO_README_SHOTS=1`로 켜면 샘플 Board를 만들어 창을 테스트 첨부(PNG)로 남긴다. 테스트 러너는 앱과 같은
/// 샌드박스라 임의 폴더에 쓸 수 없어, 스크립트가 결과 번들에서 첨부를 꺼낸다. 절차는 docs/images/CAPTURE.md.
/// 샘플 데이터는 UI 테스트 전용 저장소(Debug 컨테이너)와 임시 폴더에만 만든다.
final class ReadmeScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func test_captureReadmeScreenshots() throws {
        guard ProcessInfo.processInfo.environment["FIANCHETTO_README_SHOTS"] == "1" else {
            throw XCTSkip("FIANCHETTO_README_SHOTS=1 이 아니라 README 캡처를 건너뛴다")
        }

        // 연결 대상이 될 샘플 폴더. 이름이 그대로 Bishop 이름이 된다(개인 정보 없음).
        let fixtures = FileManager.default.temporaryDirectory.appending(path: "readme-\(UUID().uuidString)")
        let bishops: [(wing: String, name: String, purpose: String)] = [
            ("설계", "디자인 시안", "디자인"),
            ("설계", "회의록", "문서"),
            ("소스", "api-server", "코드"),
            ("소스", "web-client", "코드"),
            ("참고 자료", "경쟁 제품 분석", "참고"),
            ("참고 자료", "발표 자료", "발표"),
        ]
        for bishop in bishops {
            try FileManager.default.createDirectory(at: fixtures.appending(path: bishop.name), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: fixtures) }

        let test = UITestApp(name: "readme")
        test.app.launchEnvironment["FIANCHETTO_UI_TEST_PICK_DIRECTORY"] = fixtures.appending(path: bishops[0].name).path
        test.launch()
        defer { test.terminate() }
        let app = test.app
        XCTAssertTrue(app.staticTexts["Board가 없습니다"].waitForExistence(timeout: 10))
        zoomWindow(app)
        test.activateForKeyboard()

        // Board와 Wing.
        app.typeKey("n", modifierFlags: .command)
        paste("서비스 A 리팩토링", into: app.textFields["board-name-field"], app: app)
        app.typeKey(.return, modifierFlags: [])
        let boardRow = app.descendants(matching: .any)["board-row-서비스 A 리팩토링"]
        XCTAssertTrue(boardRow.waitForExistence(timeout: 5))
        let fileMenu = app.menuBars.menuBarItems["파일"]
        for wing in ["설계", "소스", "참고 자료"] {
            boardRow.click()
            fileMenu.click()
            fileMenu.menuItems["Wing 추가…"].click()
            paste(wing, into: app.textFields["node-name-field"], app: app)
            app.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(app.descendants(matching: .any)["node-row-\(wing)"].waitForExistence(timeout: 5))
        }

        // Bishop: 파일 선택 창은 테스트 전용 환경 변수로 정한 폴더에서 열리고 Return이 그 폴더를 고른다.
        // 처음 위치는 실행 시점에 정해지므로 Bishop마다 같은 저장소로 다시 실행한다.
        for (index, bishop) in bishops.enumerated() {
            if index > 0 {
                app.launchEnvironment["FIANCHETTO_UI_TEST_PICK_DIRECTORY"] = fixtures.appending(path: bishop.name).path
                test.relaunch()
                test.activateForKeyboard()
                XCTAssertTrue(boardRow.waitForExistence(timeout: 10))
            }
            let wingRow = app.descendants(matching: .any)["node-row-\(bishop.wing)"]
            XCTAssertTrue(wingRow.waitForExistence(timeout: 5))
            wingRow.click()
            fileMenu.click()
            fileMenu.menuItems["Bishop 추가…"].click()
            XCTAssertTrue(app.dialogs["open-panel"].waitForExistence(timeout: 5))
            app.typeKey(.return, modifierFlags: [])
            let row = app.descendants(matching: .any)["node-row-\(bishop.name)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.click()
            let editMenu = app.menuBars.menuBarItems["편집"]
            editMenu.click()
            let purposeMenu = editMenu.menuItems["아이콘"]
            purposeMenu.hover()
            let choice = purposeMenu.menuItems[bishop.purpose]
            XCTAssertTrue(choice.waitForExistence(timeout: 5))
            choice.click()
        }

        // 웹 링크.
        let referenceWing = app.descendants(matching: .any)["node-row-참고 자료"]
        referenceWing.click()
        fileMenu.click()
        fileMenu.menuItems["웹 링크 추가…"].click()
        paste("GitHub 저장소", into: app.textFields["node-name-field"], app: app)
        paste("https://github.com/u-nae/fianchetto", into: app.textFields["node-url-field"], app: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-GitHub 저장소"].waitForExistence(timeout: 5))

        // 체크포인트.
        fileMenu.click()
        fileMenu.menuItems["체크포인트 저장…"].click()
        let titleField = app.textFields["checkpoint-title-field"]
        paste("1차 설계 리뷰 완료", into: titleField, app: app)
        let memoField = app.descendants(matching: .any)["checkpoint-memo-field"]
        memoField.click()
        pasteText("API 경계를 확정했고 데이터 모델 초안에 합의함. 성능 측정은 아직.", app: app)
        let nextField = app.descendants(matching: .any)["checkpoint-next-field"]
        nextField.click()
        pasteText("web-client 이전 계획 쓰기, 회의록 정리", app: app)
        app.descendants(matching: .any)["checkpoint-save"].click()
        XCTAssertTrue(app.descendants(matching: .any)["checkpoint-sheet-title"].waitForNonExistence(timeout: 5))

        // 1. 트리 보기: Wing을 모두 펼치고 웹 링크를 골라 인스펙터가 채워진 상태(폴더 Bishop은 테스트 임시 경로가 길게 보인다).
        expand(wings: [("설계", "회의록"), ("소스", "api-server"), ("참고 자료", "발표 자료")], app: app)
        app.descendants(matching: .any)["node-row-GitHub 저장소"].click()
        save(app, as: "board-tree")

        // 2. 아이콘 보기: 고른 항목의 상위 Wing에서 열리므로 최상위 Wing을 고른 뒤 전환한다.
        app.descendants(matching: .any)["node-row-참고 자료"].click()
        let viewMenu = app.menuBars.menuBarItems["보기"]
        viewMenu.click()
        viewMenu.menuItems["아이콘으로 보기"].click()
        XCTAssertTrue(app.descendants(matching: .any)["icon-tile-설계"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["icon-tile-참고 자료"].doubleClick()
        XCTAssertTrue(app.descendants(matching: .any)["icon-tile-발표 자료"].waitForExistence(timeout: 5))
        save(app, as: "icon-view")
        viewMenu.click()
        viewMenu.menuItems["목록으로 보기"].click()

        // 체크포인트 뒤의 편집: 이름 변경과 Wing 추가(비교 화면에 변화가 보이도록).
        let sourceWing = app.descendants(matching: .any)["node-row-소스"]
        XCTAssertTrue(sourceWing.waitForExistence(timeout: 5))
        sourceWing.click()
        let editMenu = app.menuBars.menuBarItems["편집"]
        editMenu.click()
        editMenu.menuItems["이름 변경…"].click()
        replace(with: "소스 저장소", in: app.textFields["node-name-field"], app: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-소스 저장소"].waitForExistence(timeout: 5))
        boardRow.click()
        fileMenu.click()
        fileMenu.menuItems["Wing 추가…"].click()
        paste("배포", into: app.textFields["node-name-field"], app: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["node-row-배포"].waitForExistence(timeout: 5))

        // 3. 연결 상태: 원본 폴더가 사라진 Bishop을 표시한다.
        try FileManager.default.removeItem(at: fixtures.appending(path: "경쟁 제품 분석"))
        fileMenu.click()
        fileMenu.menuItems["상태 새로고침"].click()
        expand(wings: [("설계", "회의록"), ("소스 저장소", "api-server"), ("참고 자료", "발표 자료")], app: app)
        let missing = app.descendants(matching: .any)["node-row-경쟁 제품 분석"]
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        missing.click()
        let labeled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "대상 없음"), object: missing)
        XCTAssertEqual(XCTWaiter().wait(for: [labeled], timeout: 10), .completed, missing.label)
        // 인스펙터의 긴 임시 경로 대신 트리 행의 상태 표시가 보이도록 인스펙터를 접고 찍는다.
        viewMenu.click()
        viewMenu.menuItems["인스펙터 가리기"].click()
        XCTAssertTrue(app.staticTexts["항목을 고르세요"].waitForNonExistence(timeout: 5) || true)
        save(app, as: "link-status")
        viewMenu.click()
        viewMenu.menuItems["인스펙터 보기"].click()
        // 이력 화면의 '고른 항목'에는 웹 링크(URL)가 보이도록 고른다.
        app.descendants(matching: .any)["node-row-GitHub 저장소"].click()

        // 4. 이력과 체크포인트: 체크포인트 행을 고르면 과거 구성 띠와 패널이 보인다.
        viewMenu.click()
        viewMenu.menuItems["이력 보기"].click()
        let checkpointRow = app.descendants(matching: .any)["checkpoint-row-1차 설계 리뷰 완료"]
        XCTAssertTrue(checkpointRow.waitForExistence(timeout: 5))
        checkpointRow.click()
        XCTAssertTrue(app.descendants(matching: .any)["past-banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["checkpoint-panel"].waitForExistence(timeout: 5))
        save(app, as: "checkpoint")

        // 5. 비교: 과거 구성과 현재를 한 트리로.
        app.buttons["compare-with-current"].click()
        XCTAssertTrue(app.descendants(matching: .any)["compare-bar"].waitForExistence(timeout: 5))
        let added = app.descendants(matching: .any)["compare-row-배포"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        added.click()
        save(app, as: "compare")
        app.buttons["compare-close"].click()

        // 6. 복원 시트.
        var menu = app.menuButtons["restore-menu"]
        if !menu.waitForExistence(timeout: 5) {
            menu = app.descendants(matching: .any)["restore-menu"]
        }
        menu.click()
        let restoreItem = app.menuItems["복원…"]
        XCTAssertTrue(restoreItem.waitForExistence(timeout: 5))
        restoreItem.click()
        XCTAssertTrue(app.descendants(matching: .any)["restore-sheet-title"].waitForExistence(timeout: 5))
        save(app, as: "restore")
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - 도우미

    /// 접힌 Wing을 펼친다(행을 고르고 →). 다시 실행하면 Wing이 접힌 채 열리므로 캡처 전에 펼친다.
    @MainActor
    private func expand(wings: [(wing: String, child: String)], app: XCUIApplication) {
        for item in wings {
            let child = app.descendants(matching: .any)["node-row-\(item.child)"]
            if child.exists { continue }
            let row = app.descendants(matching: .any)["node-row-\(item.wing)"]
            XCTAssertTrue(row.waitForExistence(timeout: 5), item.wing)
            row.click()
            app.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(child.waitForExistence(timeout: 5), "\(item.wing) 안의 \(item.child)")
        }
    }

    /// 창을 PNG 첨부로 남긴다. 창 영역만 담기고 그림자는 들어가지 않는다.
    @MainActor
    private func save(_ app: XCUIApplication, as name: String) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        // 바로 찍으면 애니메이션 중간 상태가 담길 수 있어 그려질 때까지 잠깐 기다린다(잠든 뒤 확인은 하지 않는다).
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate(value: false), object: nil)
        _ = XCTWaiter().wait(for: [settled], timeout: 0.6)
        let attachment = XCTAttachment(uniformTypeIdentifier: "public.png", name: "\(name).png",
                                       payload: window.screenshot().pngRepresentation, userInfo: nil)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// XCUITest의 키 합성은 한글 조합 입력에서 멈출 수 있어, 붙여넣기로 넣는다(일반 클립보드를 쓴다).
    @MainActor
    private func paste(_ text: String, into field: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 5), .completed)
        field.click()
        pasteText(text, app: app)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [typed], timeout: 3), .completed, "\(field.value ?? "")")
    }

    @MainActor
    private func pasteText(_ text: String, app: XCUIApplication) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        app.typeKey("v", modifierFlags: .command)
    }

    @MainActor
    private func replace(with text: String, in field: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        app.typeKey("a", modifierFlags: .command)
        pasteText(text, app: app)
        let typed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: field)
        XCTAssertEqual(XCTWaiter().wait(for: [typed], timeout: 3), .completed, "\(field.value ?? "")")
    }

    /// 창을 화면에 맞춘다(윈도우 메뉴의 채우기·확대/축소). 가상 머신 화면은 1024×768pt라 끌기로는 더 키울 수 없다.
    /// 실패해도 캡처는 계속한다(기본 크기).
    @MainActor
    private func zoomWindow(_ app: XCUIApplication) {
        let window = app.windows.firstMatch
        guard window.waitForExistence(timeout: 5) else { return }
        let before = window.frame.width
        let windowMenu = app.menuBars.menuBarItems["윈도우"]
        guard windowMenu.waitForExistence(timeout: 5) else { return }
        for title in ["채우기", "확대/축소", "Fill", "Zoom"] {
            windowMenu.click()
            let item = windowMenu.menuItems[title]
            guard item.waitForExistence(timeout: 2), item.isEnabled else {
                app.typeKey(.escape, modifierFlags: [])
                continue
            }
            item.click()
            let grown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "frame.size.width > %f", before + 10), object: window)
            if XCTWaiter().wait(for: [grown], timeout: 3) == .completed { return }
        }
        if window.frame.width > before + 10 { return }
        NSLog("README 캡처: 창 크기 조절 실패, 기본 크기(%.0f×%.0f)로 찍는다", window.frame.width, window.frame.height)
    }
}
