import Foundation
import SwiftData

/// 앱 의존성 조립. 저장소 위치와 실행 모드를 정하고 화면 상태 모델을 만든다.
@MainActor
enum AppComposition {
    enum LaunchMode {
        /// 단위 테스트 호스트: 저장소를 열지 않는다(실사용 저장소 보호).
        case unitTestHost
        case app(storeURL: URL?, lastBoard: any LastBoardRecord)
    }

    static func launchMode(environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchMode {
        #if DEBUG
        if environment["XCTestConfigurationFilePath"] != nil {
            return .unitTestHost
        }
        // UI 테스트 전용 저장소와 마지막 Board 기록. 실사용 데이터와 설정을 건드리지 않는다.
        // 이름은 외부 입력이므로 허용 문자만 받는다. 첫 실행(RESET)에서는 이전 테스트가 남긴 폴더를 모두 지운다.
        if let id = environment["FIANCHETTO_UI_TEST_ID"], isSafeTestID(id),
           let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let root = support.appending(path: "FianchettoUITests")
            if environment["FIANCHETTO_UI_TEST_RESET"] == "1" {
                try? FileManager.default.removeItem(at: root)
            }
            let directory = root.appending(path: id)
            return .app(
                storeURL: directory.appending(path: "Fianchetto.store"),
                lastBoard: FileLastBoard(url: directory.appending(path: "lastBoard"))
            )
        }
        #endif
        return .app(storeURL: try? StoreOpener.defaultStoreURL(), lastBoard: UserDefaultsLastBoard(defaults: .standard))
    }

    static func makeModel(storeURL: URL?, lastBoard: any LastBoardRecord) -> BoardBrowserModel {
        BoardBrowserModel(dependencies: .init(
            storeURL: storeURL,
            openStore: { url throws(StoreOpenError) in
                let store = ProjectStore(container: try StoreOpener.open(at: url))
                let service = ConfigurationService(store: store, now: { Date() }, makeID: { UUID() })
                let bookmarks = BookmarkAdapter(system: FoundationBookmarkSystem())
                let links = LinkStatusService(store: store, bookmarks: bookmarks)
                return OpenedStore(
                    store: store, service: service,
                    linking: LinkingService(bookmarks: bookmarks, configuration: service),
                    replacement: TargetReplacementService(bookmarks: bookmarks, configuration: service),
                    lifecycle: ProjectLifecycleService(store: store, now: { Date() }),
                    opening: TargetOpeningService(store: store, links: links, launcher: WorkspaceLauncher()),
                    links: links
                )
            },
            lastBoard: lastBoard,
            revealInFinder: WorkspaceActions.revealInFinder,
            quit: WorkspaceActions.quit,
            pickTargets: TargetPicker.pick,
            pickReplacement: TargetPicker.pickReplacement
        ))
    }

    private static func isSafeTestID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
