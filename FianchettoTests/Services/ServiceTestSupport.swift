import Foundation
import Synchronization
import Testing
@testable import Fianchetto

/// 요청마다 정해진 시각을 내주는 시계. 목록이 끝나면 마지막 시각에서 1초씩 늘린다.
final class TestClock: Sendable {
    private let state: Mutex<(times: [Date], index: Int)>

    init(_ times: [Date]) { state = Mutex((times, 0)) }

    /// start부터 요청마다 1초씩 증가.
    convenience init(startingAt start: Date) { self.init([start]) }

    func now() -> Date {
        state.withLock { state in
            defer { state.index += 1 }
            if state.index < state.times.count { return state.times[state.index] }
            return state.times[state.times.count - 1].addingTimeInterval(TimeInterval(state.index - state.times.count + 1))
        }
    }
}

/// 정한 번호부터 차례로 UUID를 내주는 결정적 생성기. 같은 저장소를 쓰는 하네스끼리는 번호대가 겹치지 않게 시작 번호를 다르게 준다.
final class TestIDs: Sendable {
    private let next: Mutex<Int>

    init(startingAt start: Int = 2001) { next = Mutex(start) }

    func make() -> UUID {
        next.withLock { value in
            defer { value += 1 }
            return fixedID(value)
        }
    }
}

struct InjectedSaveFailure: Error {}

/// 저장 직전 실패 지점. 설정한 횟수만큼 실패한다.
final class FaultPoint: Sendable {
    private let remaining = Mutex(0)

    func failNext(_ times: Int = 1) { remaining.withLock { $0 = times } }

    func check() throws {
        let fail = remaining.withLock { value -> Bool in
            guard value > 0 else { return false }
            value -= 1
            return true
        }
        if fail { throw InjectedSaveFailure() }
    }
}

/// 테스트용 서비스 묶음: 임시 디렉토리의 실제 SwiftData 저장소, 주입된 시계·UUID·실패 지점.
struct ServiceHarness {
    let url: URL
    let store: ProjectStore
    let service: ConfigurationService
    let fault: FaultPoint
    let bookmarks = ScriptedBookmarkSystem()
    var linking: LinkingService { LinkingService(bookmarks: BookmarkAdapter(system: bookmarks), configuration: service) }

    init(directory: URL, clock: TestClock = TestClock(startingAt: date(0))) throws {
        url = directory.appending(path: "Fianchetto.store")
        let fault = FaultPoint()
        self.fault = fault
        store = ProjectStore(container: try StoreOpener.open(at: url), beforeSave: { try fault.check() })
        let ids = TestIDs()
        service = ConfigurationService(store: store, now: { clock.now() }, makeID: { ids.make() })
    }

    /// 지금까지 저장된 파일을 다른 위치로 복사해 새 연결로 연 어댑터("저장소를 닫고 다시 연" 상태).
    func reopened<T>(_ body: (StoreAdapter) throws -> T) throws -> T {
        let copy = url.deletingLastPathComponent().appending(path: "reopened-\(copies.next())/Fianchetto.store")
        try copyStoreFiles(from: url, to: copy)
        return try withStore(at: copy, body)
    }

    private let copies = Counter()
}

final class Counter: Sendable {
    private let value = Mutex(0)
    func next() -> Int { value.withLock { $0 += 1; return $0 } }
}

extension ConfigurationCommitOutcome {
    var committed: (summary: RevisionSummary, snapshot: ConfigurationSnapshot)? {
        if case let .committed(summary, snapshot) = self { (summary, snapshot) } else { nil }
    }
}

/// Board를 만들고 그 Project UUID를 돌려준다.
func makeBoard(_ harness: ServiceHarness, _ name: String = "서비스 A") async throws -> UUID {
    let outcome = try await harness.service.createProject(named: name)
    return try #require(outcome.committed).summary.projectID
}
