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
    }

    /// 같은 테스트 저장소로 다시 실행한다(정리하지 않음).
    func relaunch() {
        app.terminate()
        app.launchEnvironment["FIANCHETTO_UI_TEST_RESET"] = "0"
        app.launch()
    }

    /// macOS 14부터 다른 프로세스의 활성화 요청은 협조적이라 무시될 수 있다. 앱의 메뉴 막대를 직접 열었다 닫아
    /// 앱을 확실히 활성화한 뒤 키보드 입력을 보낸다.
    func activateForKeyboard() {
        app.menuBars.menuBarItems["파일"].click()
        app.typeKey(.escape, modifierFlags: [])
    }

    func terminate() {
        app.terminate()
    }
}
