import Foundation
import Synchronization
import Testing
@testable import Fianchetto

/// 마지막 Board 기록의 메모리 구현.
@MainActor
final class InMemoryLastBoard: LastBoardRecord {
    var lastBoardID: UUID?
    var isInspectorHidden = false
    var viewModes: [UUID: String] = [:]
    var bishopIconStyle: String?
    var comparisonStyle: String?
    var comparisonHidesReorder = false
    func viewMode(for boardID: UUID) -> String? { viewModes[boardID] }
    func setViewMode(_ mode: String, for boardID: UUID) { viewModes[boardID] = mode }
    init(_ id: UUID? = nil) { lastBoardID = id }
}

/// Finder·종료 요청을 기록한다.
@MainActor
final class RecordedActions {
    var revealed: [URL] = []
    var quits = 0
}

/// 접근 범위 시작·종료와 열기 요청의 순서 기록. 접근 범위 시작 결과를 정할 수 있다.
final class AccessEvents: Sendable {
    private let state = Mutex((events: [String](), startSucceeds: true))

    var events: [String] { state.withLock { $0.events } }
    var startSucceeds: Bool {
        get { state.withLock { $0.startSucceeds } }
        set { state.withLock { $0.startSucceeds = newValue } }
    }

    func record(_ event: String) { state.withLock { $0.events.append(event) } }
}

/// 시작·종료를 AccessEvents에 남기는 접근 범위.
struct RecordedScope: SecurityScopedResource, Sendable {
    let events: AccessEvents

    func startAccessingSecurityScopedResource() -> Bool {
        events.record("start")
        return events.startSucceeds
    }

    func stopAccessingSecurityScopedResource() {
        events.record("stop")
    }
}

/// 기본 앱 열기·Finder 표시 요청을 기록한다. 열기 결과를 정할 수 있다.
@MainActor
final class RecordingLauncher: TargetLauncher {
    var opened: [URL] = []
    var revealed: [URL] = []
    var openSucceeds = true
    let events: AccessEvents

    init(events: AccessEvents) { self.events = events }

    func open(_ url: URL) -> Bool {
        events.record("open")
        opened.append(url)
        return openSucceeds
    }

    func reveal(_ url: URL) {
        events.record("reveal")
        revealed.append(url)
    }
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

/// 비교 대상 revision 읽기를 테스트가 멈췄다 풀 수 있게 한다(W19). sleep 없이 순서를 정한다.
final class LoadGate: Sendable {
    private let state = Mutex((held: Set<UUID>(), waiting: [UUID: CheckedContinuation<Void, Never>](), arrived: [UUID: [CheckedContinuation<Void, Never>]]()))

    /// 이 revision의 읽기를 멈춘다.
    func hold(_ id: UUID) { state.withLock { _ = $0.held.insert(id) } }

    /// 읽기가 멈춘 지점에 닿을 때까지 기다린다.
    func waitUntilWaiting(_ id: UUID) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { state -> Bool in
                if state.waiting[id] != nil { return true }
                state.arrived[id, default: []].append(continuation)
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func release(_ id: UUID) {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.held.remove(id)
            return state.waiting.removeValue(forKey: id)
        }
        continuation?.resume()
    }

    func pass(_ id: UUID) async {
        guard state.withLock({ $0.held.contains(id) }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let arrived = state.withLock { state -> [CheckedContinuation<Void, Never>] in
                state.waiting[id] = continuation
                return state.arrived.removeValue(forKey: id) ?? []
            }
            arrived.forEach { $0.resume() }
        }
    }
}

/// 이력 화면의 현재 시각과 시스템 시간대. 테스트가 바꾼 뒤 clockChanged()로 알린다.
@MainActor
final class HistoryClock {
    var now: Date
    var zone: String
    init(now: Date = Date(timeIntervalSince1970: 1_790_000_000), zone: String = "Asia/Seoul") {
        self.now = now
        self.zone = zone
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
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
    let launcher: RecordingLauncher
    let model: BoardBrowserModel
    let clock: HistoryClock
    /// 서비스가 revision·체크포인트 기록 시각에 쓰는 시계. 요청마다 1초씩 늘어난다.
    let serviceClock: TestClock

    init(
        directory: URL, lastBoard: InMemoryLastBoard = InMemoryLastBoard(), script: OpenScript = OpenScript(), storeKnown: Bool = true,
        clock: HistoryClock = HistoryClock(), loadGate: LoadGate? = nil, serviceClock: TestClock = TestClock(startingAt: date(0))
    ) {
        self.clock = clock
        self.serviceClock = serviceClock
        let historyClock = clock
        self.directory = directory
        url = directory.appending(path: "Fianchetto.store")
        self.lastBoard = lastBoard
        self.script = script
        let fault = self.fault, clock = self.serviceClock, ids = TestIDs(startingAt: 30001)
        let events = AccessEvents()
        let launcher = RecordingLauncher(events: events)
        self.launcher = launcher
        let actions = self.actions, picker = self.picker, bookmarks = self.bookmarks
        let openStore: @Sendable (URL) throws(StoreOpenError) -> OpenedStore = { url throws(StoreOpenError) in
            if let category = script.next() { throw StoreOpenError(category: category, url: url) }
            let store = ProjectStore(container: try StoreOpener.open(at: url), beforeSave: { try fault.check() })
            let service = ConfigurationService(store: store, now: { clock.now() }, makeID: { ids.make() })
            let adapter = BookmarkAdapter(system: bookmarks)
            let links = LinkStatusService(store: store, bookmarks: adapter)
            return OpenedStore(
                store: store, service: service,
                linking: LinkingService(bookmarks: adapter, configuration: service),
                replacement: TargetReplacementService(bookmarks: adapter, configuration: service),
                lifecycle: ProjectLifecycleService(store: store, now: { clock.now() }),
                opening: TargetOpeningService(
                    store: store, links: links, launcher: launcher, accessScope: { _ in RecordedScope(events: events) }
                ),
                links: links
            )
        }
        var loadRevision: (@Sendable (ProjectStore, UUID) async throws -> ConfigurationSnapshot)?
        if let loadGate {
            loadRevision = { store, id in
                await loadGate.pass(id)
                return try await store.snapshot(revisionID: id)
            }
        }
        model = BoardBrowserModel(dependencies: .init(
            storeURL: storeKnown ? url : nil,
            openStore: openStore,
            lastBoard: lastBoard,
            revealInFinder: { actions.revealed.append($0) },
            quit: { actions.quits += 1 },
            pickTargets: { picker.pick() },
            pickReplacement: { picker.pickReplacement($0) },
            now: { historyClock.now },
            calendar: { historyClock.calendar },
            locale: Locale(identifier: "ko_KR"),
            loadRevisionSnapshot: loadRevision
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
