import Foundation
import Observation

/// 인스펙터 '이력' 탭의 화면 상태(W17, DESIGN.md 16.2, 0019).
/// 목록은 순번 역순으로 묶음씩 불러오고 스냅샷은 디코딩하지 않는다. 고른 revision만 디코딩한다(PRD §8 경량화).
/// 조회만 하므로 revision을 만들거나 현재 구성을 바꾸지 않는다(PRD §7). 저장된 기록은 읽기 실패에도 지우거나 고치지 않는다.
@MainActor
@Observable
final class HistoryPanelModel {
    struct Environment {
        var now: () -> Date
        /// 시스템 시간대가 들어 있는 달력. 날짜 구역·행 시각·날짜 선택에 쓴다.
        var calendar: () -> Calendar
        var locale: Locale
    }

    /// 목록 행 하나. 복원 원인이면 출처 revision의 순번을 함께 둔다.
    struct Row: Identifiable, Equatable {
        var summary: RevisionSummary
        var restoredSourceSequence: Int?
        var id: UUID { summary.id }
    }

    /// 목록의 고른 행. '현재 구성' 행 또는 revision 행 하나(단일 선택).
    enum Selection: Hashable {
        case current
        case revision(UUID)
    }

    enum Notice: Equatable {
        /// 고른 revision의 구성을 읽지 못했다.
        case unreadableRevision
        /// 다음 묶음이나 날짜로 찾기에서 목록 정보를 읽지 못했다.
        case loadFailed
    }

    struct Section: Identifiable, Equatable {
        var day: Date
        var title: String
        var rows: [Row]
        var id: Date { day }
    }

    /// 한 번에 불러오는 행 수(구현 상수, 성능 측정 후 조정할 수 있다).
    static let pageSize = 50

    private(set) var boardID: UUID?
    private(set) var rows: [Row] = []
    /// 아직 불러오지 않은 더 오래된 revision이 있을 수 있다.
    private(set) var hasMore = false
    /// 첫 묶음을 읽지 못했다. 목록 대신 오류를 보인다.
    private(set) var listFailed = false
    private(set) var notice: Notice?
    private(set) var selectedRevisionID: UUID?
    /// 고른 revision의 구성(W18이 가운데 영역에 그린다).
    private(set) var selectedSnapshot: ConfigurationSnapshot?
    /// 고른 revision의 목록 정보(과거 구성 띠의 순번·기록 시각).
    private(set) var selectedSummary: RevisionSummary?
    /// 고른 revision이 바뀐 뒤 부른다(과거·현재 모드 전환, W18).
    var selectionChanged: (@MainActor () async -> Void)?
    /// 행을 고르려 할 때(바뀌지 않아도) 먼저 부른다(W19: 비교 닫기).
    var selectionRequested: (@MainActor () -> Void)?
    /// 날짜로 찾은 시각이 Board가 생기기 전이다.
    private(set) var lookupFoundNothing = false
    /// 날짜로 찾은 행. 화면이 그 행으로 스크롤한다.
    private(set) var scrollTarget: UUID?
    /// 날짜·시각 선택 칸의 값.
    var lookupDate: Date
    /// 날짜 구역의 '오늘' 기준. 날짜·시간대가 바뀌면 clockChanged()로 다시 잡는다.
    private(set) var now: Date
    private(set) var calendar: Calendar

    private var isLoaded = false
    private var pagingFailed = false
    private let environment: Environment
    private let store: () -> ProjectStore?

    init(environment: Environment, store: @escaping () -> ProjectStore?) {
        self.environment = environment
        self.store = store
        let now = environment.now()
        self.now = now
        calendar = environment.calendar()
        lookupDate = now
    }

    var selection: Selection { selectedRevisionID.map(Selection.revision) ?? .current }

    // MARK: 불러오기

    /// 다른 Board를 고르면 목록과 선택을 비운다. 목록은 이력 탭을 열 때 불러온다.
    func reset(boardID: UUID?) {
        self.boardID = boardID
        rows = []
        hasMore = false
        listFailed = false
        notice = nil
        selectedRevisionID = nil
        selectedSnapshot = nil
        selectedSummary = nil
        lookupFoundNothing = false
        scrollTarget = nil
        isLoaded = false
        pagingFailed = false
    }

    /// 이력 탭을 열 때 부른다. 이미 불러왔으면 그대로 둔다(탭을 닫았다 열어도 선택이 남는다).
    func open() async {
        clockChanged()
        guard !isLoaded, let boardID, let store = store() else { return }
        do {
            let page = try await rows(from: store.revisionSummaries(projectID: boardID, below: nil, limit: Self.pageSize), store: store)
            guard self.boardID == boardID else { return }
            rows = page
            hasMore = page.count == Self.pageSize
            listFailed = false
            isLoaded = true
        } catch {
            guard self.boardID == boardID else { return }
            listFailed = true
        }
    }

    /// 불러온 마지막 행이 보이면 부른다. 묶음 경계는 불러온 가장 작은 순번이다.
    func loadMore() async {
        guard isLoaded, hasMore, !pagingFailed, let boardID, let store = store(), let oldest = rows.last?.summary.sequence else { return }
        do {
            let page = try await rows(from: store.revisionSummaries(projectID: boardID, below: oldest, limit: Self.pageSize), store: store)
            guard self.boardID == boardID, rows.last?.summary.sequence == oldest else { return }
            rows += page
            hasMore = page.count == Self.pageSize
        } catch {
            pagingFailed = true
            notice = .loadFailed
        }
    }

    /// 새 revision이 기록되면 부른다. 불러온 가장 큰 순번 뒤의 것을 맨 위에 더하고 선택은 그대로 둔다.
    func loadNewer() async {
        guard isLoaded, let boardID, let store = store() else { return }
        let newest = rows.first?.summary.sequence ?? 0
        do {
            let newer = try await rows(from: store.revisionSummaries(projectID: boardID, sequences: (newest + 1)...Int.max), store: store)
            guard self.boardID == boardID, rows.first?.summary.sequence ?? 0 == newest else { return }
            rows = newer + rows
        } catch {
            notice = .loadFailed
        }
    }

    // MARK: 고르기와 날짜로 찾기

    func select(_ selection: Selection) async {
        // 행을 고르는 것은 '이 구성을 본다'는 뜻이라, 비교 중이면 먼저 비교를 닫는다(W19, 0027).
        selectionRequested?()
        switch selection {
        case .current:
            guard selectedRevisionID != nil else { return }
            selectedRevisionID = nil
            selectedSnapshot = nil
            selectedSummary = nil
            await selectionChanged?()
        case let .revision(id):
            guard id != selectedRevisionID, let store = store() else { return }
            let boardID = boardID
            do {
                let snapshot = try await store.snapshot(revisionID: id)
                guard self.boardID == boardID else { return }
                selectedRevisionID = id
                selectedSnapshot = snapshot
                selectedSummary = rows.first { $0.id == id }?.summary
                await selectionChanged?()
            } catch {
                guard self.boardID == boardID else { return }
                notice = .unreadableRevision
            }
        }
    }

    /// '날짜로 찾기': 고른 분의 끝(0023) 이하의 마지막 기록을 고르고 그 행까지 불러와 보이게 한다.
    /// Board가 생기기 전이면 기록 없음을 보이고 선택을 바꾸지 않는다.
    func lookUp(_ picked: Date) async {
        lookupDate = picked
        guard let boardID, let store = store() else { return }
        let threshold = RevisionLookup.threshold(forPickedMinute: picked, calendar: calendar)
        do {
            guard let found = try await store.latestRevision(projectID: boardID, atOrBefore: threshold) else {
                guard self.boardID == boardID else { return }
                lookupFoundNothing = true
                return
            }
            if !isLoaded { await open() }
            guard isLoaded else { throw StoreReadError.storeUnavailable }
            if let oldest = rows.last?.summary.sequence, found.sequence < oldest {
                let more = try await rows(from: store.revisionSummaries(projectID: boardID, sequences: found.sequence...(oldest - 1)), store: store)
                guard self.boardID == boardID, rows.last?.summary.sequence == oldest else { return }
                rows += more
                hasMore = found.sequence > 1
            }
            guard self.boardID == boardID else { return }
            lookupFoundNothing = false
            await select(.revision(found.id))
            if selectedRevisionID == found.id { scrollTarget = found.id }
        } catch {
            guard self.boardID == boardID else { return }
            notice = .loadFailed
        }
    }

    func dismissNotice() {
        notice = nil
    }

    /// 날짜가 바뀌거나 시스템 시간대가 바뀌면 부른다. 날짜 구역 머리글과 행 시각을 다시 계산한다.
    func clockChanged() {
        now = environment.now()
        calendar = environment.calendar()
    }

    // MARK: 표시

    var sections: [Section] {
        HistorySections.group(rows, recordedAt: \.summary.recordedAt, calendar: calendar).map { day, rows in
            Section(day: day, title: headingText(HistoryDayHeading.classify(day, now: now, calendar: calendar)), rows: rows)
        }
    }

    func headingText(_ heading: HistoryDayHeading) -> String {
        let monthDay = heading.day.formatted(dateStyle.month(.wide).day())
        switch heading.kind {
        case .today: return String(localized: "오늘 · \(monthDay)")
        case .yesterday: return String(localized: "어제 · \(monthDay)")
        case .sameYear: return monthDay
        case .otherYear: return heading.day.formatted(dateStyle.year().month(.wide).day())
        }
    }

    func timeText(_ row: Row) -> String {
        row.summary.recordedAt.formatted(Date.FormatStyle(
            date: .omitted, time: .shortened, locale: environment.locale, calendar: calendar, timeZone: calendar.timeZone
        ))
    }

    /// 날짜와 시각(시스템 시간대·로캘). 과거 구성 띠의 기록 시각에 쓴다.
    func dateTimeText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .shortened, locale: environment.locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// 행 아래 줄: '#순번 · 시각'.
    func caption(_ row: Row) -> String {
        String(localized: "#\(row.summary.sequence) · \(timeText(row))")
    }

    func accessibilityLabel(_ row: Row) -> String {
        [causeText(row), "#\(row.summary.sequence)", timeText(row)].joined(separator: ", ")
    }

    /// 원인 문구(DESIGN.md 16.2).
    func causeText(_ row: Row) -> String {
        switch row.summary.cause {
        case .created: String(localized: "Board 만들기")
        case let .edited(kind):
            switch kind {
            case .renameProject: String(localized: "Board 이름 변경")
            case .addGroup: String(localized: "Wing 추가")
            case .addLinkedItems: String(localized: "Bishop 추가")
            case .addWebLink: String(localized: "웹 링크 추가")
            case .renameNode: String(localized: "이름 변경")
            case .changeURL: String(localized: "URL 변경")
            case .move: String(localized: "이동")
            case .remove: String(localized: "제거")
            case .replaceTarget: String(localized: "연결 대상 변경")
            case .changePurpose: String(localized: "아이콘 변경")
            }
        case .restored: String(localized: "#\(row.restoredSourceSequence ?? 0)에서 복원")
        case .duplicated: String(localized: "과거 구성에서 만듦")
        case .imported: String(localized: "가져오기")
        }
    }

    /// 원인 기호(SF Symbols, DESIGN.md 16.2).
    func causeSymbol(_ row: Row) -> String {
        switch row.summary.cause {
        case .created: "plus.square"
        case let .edited(kind):
            switch kind {
            case .renameProject, .renameNode, .changeURL, .changePurpose: "pencil"
            case .addGroup, .addLinkedItems, .addWebLink: "plus"
            case .move: "arrow.up.and.down"
            case .remove: "minus"
            case .replaceTarget: "arrow.triangle.swap"
            }
        case .restored: "arrow.uturn.backward"
        case .duplicated: "plus.square.on.square"
        case .imported: "square.and.arrow.down"
        }
    }

    var lookupNothingText: String { String(localized: "이 시점의 기록 없음") }

    func noticeText(_ notice: Notice) -> String {
        switch notice {
        case .unreadableRevision: String(localized: "이 기록을 읽을 수 없습니다")
        case .loadFailed: String(localized: "기록을 불러오지 못했습니다")
        }
    }

    // MARK: 내부

    private var dateStyle: Date.FormatStyle {
        Date.FormatStyle(locale: environment.locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    /// 목록 정보를 행으로 바꾼다. 복원 출처는 지워지지 않으므로(불변식) 찾지 못하면 손상 기록으로 본다.
    private func rows(from summaries: [RevisionSummary], store: ProjectStore) async throws -> [Row] {
        var result: [Row] = []
        for summary in summaries {
            var row = Row(summary: summary)
            if case let .restored(source) = summary.cause {
                guard let origin = try await store.revisionSummary(source) else { throw StoreReadError.damagedRecord(summary.id) }
                row.restoredSourceSequence = origin.sequence
            }
            result.append(row)
        }
        return result
    }
}
