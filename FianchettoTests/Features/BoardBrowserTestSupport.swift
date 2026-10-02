import Foundation
import Synchronization
import Testing
@testable import Fianchetto

/// 마지막 Board 기록의 메모리 구현.
@MainActor
final class InMemoryLastBoard: LastBoardRecord {
    var lastBoardID: UUID?
    init(_ id: UUID? = nil) { lastBoardID = id }
}

/// Finder·종료 요청을 기록한다.
@MainActor
final class RecordedActions {
    var revealed: [URL] = []
    var quits = 0
}

/// 저장소 열기 호출 기록과 결과 순서.
final class OpenScript: Sendable {
    private let state: Mutex<(results: [StoreOpenError.Category?], calls: Int, onMain: [Bool])>

    /// nil은 성공, 값은 그 원인으로 실패. 목록이 끝나면 마지막 결과를 반복한다.
    init(_ results: [StoreOpenError.Category?] = [nil]) { state = Mutex((results, 0, [])) }

    var calls: Int { state.withLock { $0.calls } }
    var openedOnMainThread: [Bool] { state.withLock { $0.onMain } }

    func next() -> StoreOpenError.Category? {
        state.withLock { state in
            defer { state.calls += 1 }
            state.onMain.append(Thread.isMainThread)
            return state.results[min(state.calls, state.results.count - 1)]
        }
    }
}

/// 화면 상태 모델 테스트 묶음: 임시 디렉토리의 실제 저장소, 주입된 시계·UUID·실패 지점·마지막 Board 기록·Finder·종료.
/// 파일 선택 창 결과를 차례로 돌려준다. nil은 취소다.
@MainActor
final class PickerScript {
    var results: [[URL]?] = []
    var calls = 0
    /// 연결 대상 변경용 선택 창 결과와, 그 창에 요청된 종류.
    var replacementResults: [URL?] = []
    var replacementKinds: [LinkedTarget.Kind] = []

    func pick() -> [URL]? {
        defer { calls += 1 }
        return calls < results.count ? results[calls] : nil
    }

    func pickReplacement(_ kind: LinkedTarget.Kind) -> URL? {
        defer { replacementKinds.append(kind) }
        let index = replacementKinds.count
        return index < replacementResults.count ? replacementResults[index] : nil
    }
}

@MainActor
struct BrowserHarness {
    let directory: URL
    let url: URL
    let fault = FaultPoint()
    let lastBoard: InMemoryLastBoard
    let actions = RecordedActions()
    let script: OpenScript
    let picker = PickerScript()
    let bookmarks = ScriptedBookmarkSystem()
    let model: BoardBrowserModel

    init(directory: URL, lastBoard: InMemoryLastBoard = InMemoryLastBoard(), script: OpenScript = OpenScript(), storeKnown: Bool = true) {
        self.directory = directory
        url = directory.appending(path: "Fianchetto.store")
        self.lastBoard = lastBoard
        self.script = script
        let fault = self.fault, clock = TestClock(startingAt: date(0)), ids = TestIDs(startingAt: 30001)
        let actions = self.actions, picker = self.picker, bookmarks = self.bookmarks
        let openStore: @Sendable (URL) throws(StoreOpenError) -> OpenedStore = { url throws(StoreOpenError) in
            if let category = script.next() { throw StoreOpenError(category: category, url: url) }
            let store = ProjectStore(container: try StoreOpener.open(at: url), beforeSave: { try fault.check() })
            let service = ConfigurationService(store: store, now: { clock.now() }, makeID: { ids.make() })
            let adapter = BookmarkAdapter(system: bookmarks)
            return OpenedStore(
                store: store, service: service,
                linking: LinkingService(bookmarks: adapter, configuration: service),
                replacement: TargetReplacementService(bookmarks: adapter, configuration: service)
            )
        }
        model = BoardBrowserModel(dependencies: .init(
            storeURL: storeKnown ? url : nil,
            openStore: openStore,
            lastBoard: lastBoard,
            revealInFinder: { actions.revealed.append($0) },
            quit: { actions.quits += 1 },
            pickTargets: { picker.pick() },
            pickReplacement: { picker.pickReplacement($0) }
        ))
    }
}

/// seed 디렉토리에서 서비스로 데이터를 만든 뒤, 열린 연결이 없는 저장소 파일 묶음을 destination에 복사한다.
func seedStore(
    isolation: isolated (any Actor)? = #isolation,
    in directory: URL, at destination: URL, _ build: (ServiceHarness) async throws -> Void
) async throws {
    let seed = try ServiceHarness(directory: directory.appending(path: "seed-\(destination.deletingLastPathComponent().lastPathComponent)"))
    try await build(seed)
    try copyStoreFiles(from: seed.url, to: destination)
}

extension BoardBrowserModel {
    var activeNames: [String] { activeBoards.map(\.name) }
    var archivedNames: [String] { archivedBoards.map(\.name) }
    var loadedSnapshot: ConfigurationSnapshot? {
        if case let .loaded(snapshot) = current { snapshot } else { nil }
    }
    func board(named name: String) -> ProjectListing? { (activeBoards + archivedBoards).first { $0.name == name } }
}
