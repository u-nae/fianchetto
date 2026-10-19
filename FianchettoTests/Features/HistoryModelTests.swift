import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 인스펙터 '이력' 탭(W17): 목록 묶음 불러오기, 날짜로 찾기, 행 표시, 탭·사이드바 규칙.
@MainActor
@Suite("이력 탭(W17)")
struct HistoryModelTests {
    /// revision 하나의 씨앗: 순번, 기록 시각, 원인. 원인 문자열을 직접 넣으면 손상 기록을 만들 수 있다.
    struct Seed {
        var sequence: Int
        var at: Date
        var cause: RevisionCause = .edited(.renameNode)
        var damagedCause = false
        var damagedSnapshot = false
    }

    nonisolated static let board = RecordFixtures.project
    nonisolated static let otherBoard = RecordFixtures.otherProject

    nonisolated static func revisionID(_ sequence: Int, board: UUID = board) -> UUID {
        fixedID((board == Self.board ? 7000 : 8000) + sequence)
    }

    @MainActor
    struct Opened {
        let harness: BrowserHarness
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }

        func row(_ sequence: Int) throws -> HistoryPanelModel.Row {
            try #require(history.rows.first { $0.summary.sequence == sequence })
        }

        var sequences: [Int] { history.rows.map(\.summary.sequence) }

        /// 저장소에 남은 revision 수(디코딩 없이 순번 범위로 센다). 손상 레코드가 있으면 읽기가 실패하므로 범위를 나눠 센다.
        func storedSequences(_ range: ClosedRange<Int>, board: UUID = HistoryModelTests.board) async throws -> [Int] {
            try await #require(model.openedStore).store.revisionSummaries(projectID: board, sequences: range).map(\.sequence)
        }

        func currentRevisionID(board: UUID = HistoryModelTests.board) async throws -> UUID? {
            try await #require(model.openedStore).store.project(board)?.currentRevisionID
        }
    }

    /// 주어진 revision들로 저장소를 만들고 Board를 고른다. 현재 revision은 가장 큰 순번이다.
    private func opened(
        _ directory: URL, _ seeds: [Seed], other: [Seed] = [], archived: Bool = false, clock: HistoryClock = HistoryClock()
    ) async throws -> Opened {
        let staging = directory.appending(path: "staging/Fianchetto.store")
        try withStore(at: staging) { store throws in
            for (board, list, name) in [(Self.board, seeds, "서비스 A"), (Self.otherBoard, other, "서비스 B")] where !list.isEmpty {
                let last = try #require(list.max { $0.sequence < $1.sequence })
                try store.insert(ProjectRecord(
                    id: board, createdAt: list[0].at, currentRevisionID: Self.revisionID(last.sequence, board: board),
                    archivedAt: archived && board == Self.board ? list[0].at : nil, origin: nil
                ))
                for seed in list {
                    try store.insertRevision(RevisionDraft(
                        id: Self.revisionID(seed.sequence, board: board), projectID: board, sequence: seed.sequence,
                        recordedAt: seed.at, cause: seed.cause, snapshot: RecordFixtures.snapshot(named: name)
                    ))
                }
            }
            try store.save()
            let models = try store.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>())
            for seed in seeds {
                let model = try #require(models.first { $0.id == Self.revisionID(seed.sequence) })
                if seed.damagedCause { model.cause = "rollback" }
                if seed.damagedSnapshot { model.snapshotData = Data("{".utf8) }
            }
            try store.save()
        }
        let harness = BrowserHarness(directory: directory.appending(path: "tested"), clock: clock)
        try copyStoreFiles(from: staging, to: harness.url)
        await harness.model.start()
        await harness.model.select(Self.board)
        return Opened(harness: harness)
    }

    /// 순번 1부터 하루 간격으로 count개.
    private func daily(_ count: Int, damaged: Set<Int> = [], damagedSnapshots: Set<Int> = []) -> [Seed] {
        (1...count).map {
            Seed(sequence: $0, at: localTime("2026-01-01 10:00:00").addingTimeInterval(Double($0 - 1) * 86_400),
                 cause: $0 == 1 ? .created : .edited(.renameNode), damagedCause: damaged.contains($0), damagedSnapshot: damagedSnapshots.contains($0))
        }
    }

    private func openHistory(_ o: Opened) async {
        await o.model.selectInspectorTab(.history)
    }

    // MARK: 목록 불러오기

    @Test("[W17-page-first] 이력 탭은 순번 역순으로 첫 묶음(50개)만 불러온다")
    func firstPage() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(120))
            #expect(o.history.rows.isEmpty)
            await openHistory(o)
            #expect(o.sequences == Array((71...120).reversed()))
            #expect(o.history.hasMore)
        }
    }

    @Test("[W17-page-more] 목록 끝에 닿으면 다음 묶음을 불러오고 다 불러오면 더 불러오지 않는다")
    func morePages() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(120))
            await openHistory(o)
            await o.history.loadMore()
            #expect(o.sequences.count == 100)
            #expect(o.sequences.last == 21)
            await o.history.loadMore()
            #expect(o.sequences == Array((1...120).reversed()))
            #expect(!o.history.hasMore)
            await o.history.loadMore()
            #expect(o.sequences.count == 120)
        }
    }

    @Test("[W17-decode-selected-only] 목록은 스냅샷을 디코딩하지 않고, 고른 revision만 디코딩하며 읽지 못하면 안내하고 선택과 저장 기록을 유지한다")
    func decodeSelectedOnly() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(5, damagedSnapshots: [2]))
            await openHistory(o)
            #expect(o.sequences == [5, 4, 3, 2, 1])
            #expect(!o.history.listFailed)

            await o.history.select(.revision(Self.revisionID(3)))
            #expect(o.history.selection == .revision(Self.revisionID(3)))
            #expect(o.history.selectedSnapshot?.projectName == "서비스 A")

            await o.history.select(.revision(Self.revisionID(2)))
            #expect(o.history.notice == .unreadableRevision)
            #expect(o.history.noticeText(.unreadableRevision) == "이 기록을 읽을 수 없습니다")
            #expect(o.history.selection == .revision(Self.revisionID(3)))
            #expect(try await o.storedSequences(1...5) == [5, 4, 3, 2, 1])
            await #expect(throws: StoreReadError.self) { try await o.model.openedStore?.store.snapshot(revisionID: Self.revisionID(2)) }
        }
    }

    @Test("[W17-list-load-failure] 첫 묶음의 목록 정보를 읽지 못하면 이력 탭에 오류를 보이고 현재 구성·편집과 저장 기록은 그대로다")
    func firstPageFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(10, damaged: [7]))
            await openHistory(o)
            #expect(o.history.listFailed)
            #expect(o.history.noticeText(.loadFailed) == "기록을 불러오지 못했습니다")
            #expect(o.model.loadedSnapshot?.projectName == "서비스 A")
            #expect(o.model.canAddToBoard)
            #expect(try await o.storedSequences(8...10) == [10, 9, 8])
            #expect(try await o.storedSequences(1...6) == [6, 5, 4, 3, 2, 1])
            await #expect(throws: StoreReadError.damagedRecord(Self.revisionID(7))) {
                try await o.model.openedStore?.store.revisionSummary(Self.revisionID(7))
            }
        }
    }

    @Test("[W17-next-page-failure] 다음 묶음을 읽지 못하면 불러온 행·선택을 유지하고 안내하며 저장 기록은 그대로다")
    func nextPageFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(120, damaged: [60]))
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(100)))
            await o.history.loadMore()
            #expect(o.history.notice == .loadFailed)
            #expect(o.sequences == Array((71...120).reversed()))
            #expect(o.history.selection == .revision(Self.revisionID(100)))
            await #expect(throws: StoreReadError.damagedRecord(Self.revisionID(60))) {
                try await o.model.openedStore?.store.revisionSummary(Self.revisionID(60))
            }
        }
    }

    @Test("[W17-lookup-failure] 날짜로 찾기 중 기록을 읽지 못하면 선택을 바꾸지 않고 안내하며 저장 기록은 그대로다")
    func lookupFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = daily(120, damaged: [30])
            let o = try await opened(directory, seeds)
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(110)))
            await o.history.lookUp(seeds[29].at)
            #expect(o.history.notice == .loadFailed)
            #expect(o.history.selection == .revision(Self.revisionID(110)))
            await #expect(throws: StoreReadError.damagedRecord(Self.revisionID(30))) {
                try await o.model.openedStore?.store.revisionSummary(Self.revisionID(30))
            }
        }
    }

    @Test("[W17-lookup-failure] 찾은 행까지 불러오는 도중의 묶음에 손상 기록이 있어도 선택을 바꾸지 않고 안내한다")
    func lookupFillFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = daily(120, damaged: [40])
            let o = try await opened(directory, seeds)
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(110)))
            await o.history.lookUp(seeds[9].at)
            #expect(o.history.notice == .loadFailed)
            #expect(o.history.selection == .revision(Self.revisionID(110)))
            #expect(o.sequences == Array((71...120).reversed()))
        }
    }

    @Test("[W17-restored-label] 복원 revision 문구는 출처 revision 순번을 넣은 '#N에서 복원'이다")
    func restoredLabel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            var seeds = daily(7)
            seeds[6].cause = .restored(from: Self.revisionID(4))
            let o = try await opened(directory, seeds)
            await openHistory(o)
            let row = try o.row(7)
            #expect(o.history.causeText(row) == "#4에서 복원")
            #expect(o.history.causeSymbol(row) == "arrow.uturn.backward")
        }
    }

    @Test("[W17-restored-source-missing] 복원 출처 revision을 찾을 수 없으면 손상 기록으로 다루고 저장 기록은 그대로다")
    func restoredSourceMissing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            var seeds = daily(7)
            seeds[6].cause = .restored(from: fixedID(9999))
            let o = try await opened(directory, seeds)
            await openHistory(o)
            #expect(o.history.listFailed)
            #expect(try await o.storedSequences(1...7) == [7, 6, 5, 4, 3, 2, 1])
        }
    }

    // MARK: 행 표시

    static let causes: [(RevisionCause, String, String)] = [
        (.created, "Board 만들기", "plus.square"),
        (.edited(.renameProject), "Board 이름 변경", "pencil"),
        (.edited(.addGroup), "Wing 추가", "plus"),
        (.edited(.addLinkedItems), "Bishop 추가", "plus"),
        (.edited(.addWebLink), "웹 링크 추가", "plus"),
        (.edited(.renameNode), "이름 변경", "pencil"),
        (.edited(.changeURL), "URL 변경", "pencil"),
        (.edited(.move), "이동", "arrow.up.and.down"),
        (.edited(.remove), "제거", "minus"),
        (.edited(.replaceTarget), "연결 대상 변경", "arrow.triangle.swap"),
        (.edited(.changePurpose), "아이콘 변경", "pencil"),
        (.duplicated, "과거 구성에서 만듦", "plus.square.on.square"),
        (.imported, "가져오기", "square.and.arrow.down"),
    ]

    @Test("[W17-cause-label] revision 행은 원인 문구와 기호를 보인다(DESIGN.md 16.2)")
    func causeLabels() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = Self.causes.enumerated().map { index, cause in
                Seed(sequence: index + 1, at: localTime("2026-10-01 09:00:00").addingTimeInterval(Double(index) * 60), cause: cause.0)
            }
            let o = try await opened(directory, seeds)
            await openHistory(o)
            for (index, cause) in Self.causes.enumerated() {
                let row = try o.row(index + 1)
                #expect(o.history.causeText(row) == cause.1)
                #expect(o.history.causeSymbol(row) == cause.2)
            }
            #expect(Set(Self.causes.map { "\($0.0)" }).count == RevisionCause.EditKind.allCases.count + 3)
        }
    }

    @Test("[W17-row-caption] 행 아래 줄은 '#순번 · 시각'이고 접근성 라벨은 '원인, #순번, 시각'이다")
    func rowCaption() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = (1...12).map { Seed(sequence: $0, at: localTime("2026-10-03 14:20:00").addingTimeInterval(Double($0 - 12) * 3600)) }
                .map { var seed = $0; if seed.sequence == 12 { seed.cause = .edited(.addGroup) }; return seed }
            let o = try await opened(directory, seeds, clock: HistoryClock(now: localTime("2026-10-03 18:00:00")))
            await openHistory(o)
            let row = try o.row(12)
            #expect(o.history.caption(row) == "#12 · 오후 2:20")
            #expect(o.history.accessibilityLabel(row) == "Wing 추가, #12, 오후 2:20")
        }
    }

    @Test("[W17-day-sections] 날짜 구역 머리글은 기록이 있는 날에만 만든다")
    func daySections() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = [
                Seed(sequence: 1, at: localTime("2025-12-30 10:00:00"), cause: .created),
                Seed(sequence: 2, at: localTime("2026-10-01 10:00:00")),
                Seed(sequence: 3, at: localTime("2026-10-03 09:00:00")),
                Seed(sequence: 4, at: localTime("2026-10-03 15:00:00")),
            ]
            let o = try await opened(directory, seeds, clock: HistoryClock(now: localTime("2026-10-03 18:00:00")))
            await openHistory(o)
            #expect(o.history.sections.map(\.title) == ["오늘 · 10월 3일", "10월 1일", "2025년 12월 30일"])
            #expect(o.history.sections.map { section in
                section.entries.compactMap { entry -> Int? in
                    if case let .revision(row) = entry { row.summary.sequence } else { nil }
                }
            } == [[4, 3], [2], [1]])
        }
    }

    @Test("[W17-day-sections-clock-back] 시계가 뒤로 간 기록은 순번 순서를 지키고 날짜 구역을 다시 연다")
    func daySectionsClockBack() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = [
                Seed(sequence: 1, at: localTime("2026-10-02 09:00:00"), cause: .created),
                Seed(sequence: 2, at: localTime("2026-10-03 10:00:00")),
                Seed(sequence: 3, at: localTime("2026-10-02 12:00:00")),
            ]
            let o = try await opened(directory, seeds, clock: HistoryClock(now: localTime("2026-10-03 18:00:00")))
            await openHistory(o)
            #expect(o.sequences == [3, 2, 1])
            #expect(o.history.sections.map(\.title) == ["어제 · 10월 2일", "오늘 · 10월 3일", "어제 · 10월 2일"])
        }
    }

    @Test("[W17-day-heading-examples] 날짜 구역 머리글 문구는 결정 history_day_heading의 예와 같다", arguments: [
        ("2026-10-03", "2026-10-03", "오늘 · 10월 3일"),
        ("2026-10-03", "2026-10-02", "어제 · 10월 2일"),
        ("2026-10-03", "2026-10-01", "10월 1일"),
        ("2026-10-03", "2025-12-30", "2025년 12월 30일"),
        ("2027-01-01", "2026-12-31", "어제 · 12월 31일"),
        ("2026-10-03", "2026-10-05", "10월 5일"),
    ])
    func headingTexts(today: String, recorded: String, expected: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, [Seed(sequence: 1, at: localTime("\(recorded) 23:30:00"), cause: .created)],
                                     clock: HistoryClock(now: localTime("\(today) 12:00:00")))
            await openHistory(o)
            #expect(o.history.sections.map(\.title) == [expected])
        }
    }

    @Test("[W17-day-change-refresh] 이력 탭이 열린 채 날짜가 바뀌면 날짜 구역 머리글을 다시 계산한다")
    func dayChangeRefresh() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let clock = HistoryClock(now: localTime("2026-10-03 23:59:00"))
            let o = try await opened(directory, [Seed(sequence: 1, at: localTime("2026-10-03 10:00:00"), cause: .created)], clock: clock)
            await openHistory(o)
            #expect(o.history.sections.map(\.title) == ["오늘 · 10월 3일"])
            clock.now = localTime("2026-10-04 00:01:00")
            o.history.clockChanged()
            #expect(o.history.sections.map(\.title) == ["어제 · 10월 3일"])
        }
    }

    @Test("[W17-time-zone] 같은 절대 시각 기록이 시스템 시간대에 따라 다른 머리글·행 시각으로 보이고 같은 지역 시각 찾기 결과가 달라진다", .tags(.A05))
    func timeZone() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let iso = ISO8601DateFormatter()
            let clock = HistoryClock(now: try #require(iso.date(from: "2026-10-03T06:00:00Z")))
            let seeds = [
                Seed(sequence: 1, at: try #require(iso.date(from: "2026-10-01T00:00:00Z")), cause: .created),
                Seed(sequence: 2, at: try #require(iso.date(from: "2026-10-02T15:30:00Z"))),
            ]
            let o = try await opened(directory, seeds, clock: clock)
            await openHistory(o)
            #expect(o.history.sections.first?.title == "오늘 · 10월 3일")
            #expect(o.history.caption(try o.row(2)) == "#2 · 오전 12:30")
            await o.history.lookUp(localTime("2026-10-02 23:59:00", in: "Asia/Seoul"))
            #expect(o.history.selection == .revision(Self.revisionID(1)))

            // 앱을 쓰는 동안 시스템 시간대가 바뀌면 다시 계산한다.
            clock.zone = "America/Los_Angeles"
            o.history.clockChanged()
            #expect(o.history.sections.first?.title == "오늘 · 10월 2일")
            #expect(o.history.caption(try o.row(2)) == "#2 · 오전 8:30")
            await o.history.lookUp(localTime("2026-10-02 23:59:00", in: "America/Los_Angeles"))
            #expect(o.history.selection == .revision(Self.revisionID(2)))
        }
    }

    // MARK: 고르기와 날짜로 찾기

    @Test("[W17-current-row] '현재 구성' 행이 처음에 골라져 있고 고르면 고른 revision이 없어진다")
    func currentRow() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            await openHistory(o)
            #expect(o.history.selection == .current)
            await o.history.select(.revision(Self.revisionID(1)))
            await o.history.select(.current)
            #expect(o.history.selection == .current)
            #expect(o.history.selectedSnapshot == nil)
        }
    }

    @Test("[W17-lookup-selects-row] 찾은 기록이 아직 불러오지 않은 묶음에 있어도 불러와 고르고 보이게 하며 실제 기록 시각이 보인다", .tags(.A05))
    func lookupSelectsRow() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = daily(120)
            let o = try await opened(directory, seeds)
            await openHistory(o)
            await o.history.lookUp(seeds[2].at)
            #expect(o.history.selection == .revision(Self.revisionID(3)))
            #expect(o.history.scrollTarget == Self.revisionID(3))
            #expect(o.sequences == Array((3...120).reversed()))
            #expect(o.history.caption(try o.row(3)) == "#3 · 오전 10:00")
            await o.history.loadMore()
            #expect(o.sequences == Array((1...120).reversed()))
        }
    }

    @Test("[W17-lookup-before-creation] Board가 생기기 전 시각이면 기록 없음을 보이고 선택을 바꾸지 않는다", .tags(.A05))
    func lookupBeforeCreation() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, [Seed(sequence: 1, at: localTime("2026-10-01 09:00:00"), cause: .created)])
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(1)))
            await o.history.lookUp(localTime("2026-09-30 23:59:00"))
            #expect(o.history.lookupFoundNothing)
            #expect(o.history.lookupNothingText == "이 시점의 기록 없음")
            #expect(o.history.selection == .revision(Self.revisionID(1)))
            await o.history.lookUp(localTime("2026-10-01 09:00:00"))
            #expect(!o.history.lookupFoundNothing)
        }
    }

    @Test("[W17-lookup-minute-boundary] 행에 보이는 분(오후 2:20)을 고르면 14:20:30 기록이 찾아지고 오후 2:19는 그 앞 기록이다", .tags(.A05))
    func lookupMinuteBoundary() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, [
                Seed(sequence: 1, at: localTime("2026-10-02 14:19:00"), cause: .created),
                Seed(sequence: 2, at: localTime("2026-10-02 14:20:30")),
                Seed(sequence: 3, at: localTime("2026-10-02 14:21:00")),
            ])
            await openHistory(o)
            await o.history.lookUp(localTime("2026-10-02 14:20:00"))
            #expect(o.history.selection == .revision(Self.revisionID(2)))
            await o.history.lookUp(localTime("2026-10-02 14:19:00"))
            #expect(o.history.selection == .revision(Self.revisionID(1)))
        }
    }

    @Test("[W17-latest-selects-revision-row] 날짜로 찾은 결과가 최신 revision이면 '현재 구성' 행이 아니라 그 revision 행을 고른다")
    func latestSelectsRevisionRow() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = daily(5)
            let o = try await opened(directory, seeds)
            await openHistory(o)
            await o.history.lookUp(seeds[4].at.addingTimeInterval(86_400))
            #expect(o.history.selection == .revision(Self.revisionID(5)))
        }
    }

    @Test("[W17-keyboard-lookup] 날짜 칸 값을 바꿔 찾으면 바뀐 값 기준의 revision이 골라진다")
    func keyboardLookup() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = daily(5)
            let o = try await opened(directory, seeds)
            await openHistory(o)
            await o.history.lookUp(seeds[3].at)
            #expect(o.history.selection == .revision(Self.revisionID(4)))
            #expect(o.history.lookupDate == seeds[3].at)
            await o.history.lookUp(seeds[3].at.addingTimeInterval(-86_400))
            #expect(o.history.selection == .revision(Self.revisionID(3)))
        }
    }

    @Test("[W17-keyboard-selection] 목록에서 다음 행을 고르면 고른 revision이 그 행 하나로 바뀐다")
    func keyboardSelection() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(3)))
            await o.history.select(.revision(Self.revisionID(2)))
            #expect(o.history.selection == .revision(Self.revisionID(2)))
            #expect(o.history.selectedRevisionID == Self.revisionID(2))
        }
    }

    // MARK: 조회는 기록하지 않는다

    @Test("[W17-browse-no-revision] 이력 열기·행 고르기·날짜로 찾기·현재 구성 고르기는 revision 수와 현재 revision을 바꾸지 않는다", .tags(.A05))
    func browsingRecordsNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let seeds = daily(5)
            let o = try await opened(directory, seeds)
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(2)))
            await o.history.lookUp(seeds[0].at)
            await o.history.select(.current)
            await o.model.selectInspectorTab(.item)
            #expect(try await o.storedSequences(1...100) == [5, 4, 3, 2, 1])
            #expect(try await o.currentRevisionID() == Self.revisionID(5))
            #expect(o.model.loadedSnapshot?.projectName == "서비스 A")
        }
    }

    @Test("[W17-archived-history] 보관된 Board도 이력을 보고 고를 수 있다")
    func archivedHistory() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3), archived: true)
            #expect(o.model.canShowHistory)
            await o.model.toggleHistory()
            #expect(o.sequences == [3, 2, 1])
            await o.history.select(.revision(Self.revisionID(1)))
            #expect(o.history.selection == .revision(Self.revisionID(1)))
        }
    }

    /// W18 이후 과거 revision을 고른 동안에는 편집이 꺼지므로(DESIGN 16.4), 새 revision은 현재 구성을 보는 동안에만 기록된다.
    @Test("[W17-new-revision-prepends] 이력 탭이 열린 채 새 revision이 기록되면 맨 위에 더해지고 선택은 '현재 구성' 그대로다")
    func newRevisionPrepends() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(5))
            await openHistory(o)
            o.model.beginAddGroup()
            o.model.nodeForm?.name = "개발"
            await o.model.confirmNodeForm()
            #expect(o.sequences.first == 6)
            #expect(o.history.causeText(try o.row(6)) == "Wing 추가")
            #expect(o.history.selection == .current)
        }
    }

    @Test("[W17-page-after-prepend] 새 revision이 더해진 뒤 다음 묶음을 불러와도 순번이 겹치거나 빠지지 않는다")
    func pageAfterPrepend() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(120))
            await openHistory(o)
            for name in ["가", "나", "다"] {
                o.model.beginAddGroup()
                o.model.nodeForm?.name = name
                await o.model.confirmNodeForm()
            }
            await o.history.loadMore()
            #expect(o.sequences == Array((21...123).reversed()))
        }
    }

    @Test("[W17-board-switch] 다른 Board를 고르면 그 Board의 목록으로 바뀌고 선택은 비워진다")
    func boardSwitch() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let other = [Seed(sequence: 1, at: localTime("2026-05-01 10:00:00"), cause: .created)]
            let o = try await opened(directory, daily(3), other: other)
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(2)))
            await o.model.select(Self.otherBoard)
            #expect(o.history.boardID == Self.otherBoard)
            #expect(o.history.selection == .current)
            #expect(o.history.rows.map(\.id) == [Self.revisionID(1, board: Self.otherBoard)])
        }
    }

    // MARK: 여는 곳과 화면 구조

    enum Opening: String, CaseIterable, Sendable {
        case hiddenMenu, hiddenToolbar, shownToolbar, shownSegment, historyMenu, historyToolbar
    }

    @Test("[W17-open-history] 이력 보기는 인스펙터를 펴며 이력 탭을 열고, 이력 탭에서 다시 하면 항목 탭으로 돌아간다", arguments: Opening.allCases)
    func openHistoryCommand(way: Opening) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            switch way {
            case .hiddenMenu, .hiddenToolbar:
                o.model.isInspectorPresented = false
                await o.model.toggleHistory()
                #expect(o.model.inspectorTab == .history)
            case .shownToolbar:
                await o.model.toggleHistory()
                #expect(o.model.inspectorTab == .history)
            case .shownSegment:
                await o.model.selectInspectorTab(.history)
                #expect(o.model.inspectorTab == .history)
            case .historyMenu, .historyToolbar:
                await o.model.toggleHistory()
                await o.model.toggleHistory()
                #expect(o.model.inspectorTab == .item)
            }
            #expect(o.model.isInspectorPresented)
        }
    }

    @Test("[W17-hide-inspector-closes-history] 인스펙터를 접으면 이력 탭이 닫히고 사이드바가 열기 전 상태로 돌아가며 다시 펴면 항목 탭이다")
    func hideInspectorClosesHistory() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            await o.model.toggleHistory()
            #expect(!o.model.isSidebarVisible)
            o.model.toggleInspector()
            #expect(o.model.inspectorTab == .item)
            #expect(o.model.isSidebarVisible)
            o.model.toggleInspector()
            #expect(o.model.inspectorTab == .item)
        }
    }

    @Test("[W17-selection-kept-on-close] 이력 탭을 닫았다 다시 열어도 고른 revision이 남는다")
    func selectionKeptOnClose() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            await openHistory(o)
            await o.history.select(.revision(Self.revisionID(2)))
            await o.model.selectInspectorTab(.item)
            await o.model.selectInspectorTab(.history)
            #expect(o.history.selection == .revision(Self.revisionID(2)))
            o.model.toggleInspector()
            o.model.toggleInspector()
            await o.model.toggleHistory()
            #expect(o.history.selection == .revision(Self.revisionID(2)))
        }
    }

    enum SidebarCase: String, CaseIterable, Sendable {
        case visibleUntouched, hiddenUntouched, hiddenUserShows, visibleUserShowsAndHides
    }

    @Test("[W17-sidebar-collapse] 이력 탭을 열면 Board 사이드바를 접고, 닫으면 열기 전 상태로 돌린다. 그동안 사용자가 바꿨으면 마지막 선택을 지킨다(0032)", arguments: SidebarCase.allCases)
    func sidebarCollapse(sidebar: SidebarCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            let before = sidebar == .visibleUntouched || sidebar == .visibleUserShowsAndHides
            o.model.isSidebarVisible = before
            await openHistory(o)
            #expect(!o.model.isSidebarVisible)
            switch sidebar {
            case .visibleUntouched, .hiddenUntouched: break
            case .hiddenUserShows: o.model.isSidebarVisible = true
            case .visibleUserShowsAndHides:
                o.model.isSidebarVisible = true
                o.model.isSidebarVisible = false
            }
            await o.model.selectInspectorTab(.item)
            let expected = switch sidebar {
            case .visibleUntouched, .hiddenUntouched: before
            case .hiddenUserShows: true
            case .visibleUserShowsAndHides: false
            }
            #expect(o.model.isSidebarVisible == expected)
        }
    }

    @Test("[AUDIT-sidebar-menu] 보기 메뉴의 사이드바 가리기/보기는 표시를 바꾸고, 이력 탭이 자동으로 접은 동안 바꾸면 닫을 때 그 선택을 지킨다(0032)")
    func sidebarMenuToggle() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            #expect(o.model.isSidebarVisible)
            o.model.toggleSidebar()
            #expect(!o.model.isSidebarVisible)
            o.model.toggleSidebar()
            #expect(o.model.isSidebarVisible)

            o.model.toggleSidebar()
            await o.model.toggleHistory()
            #expect(!o.model.isSidebarVisible, "이력 탭이 자동으로 접는다")
            o.model.toggleSidebar()
            #expect(o.model.isSidebarVisible)
            await o.model.toggleHistory()
            #expect(o.model.isSidebarVisible, "이력 탭 동안 메뉴로 편 사이드바는 닫아도 편 채다")

            await o.model.toggleHistory()
            await o.model.toggleHistory()
            #expect(o.model.isSidebarVisible, "손대지 않으면 열기 전 상태로 돌아간다")
        }
    }

    @Test("[W17-sidebar-already-collapsed] 열기 전 사이드바가 접혀 있었어도, 이력 탭 동안 사용자가 폈으면 닫을 때 편 채로 둔다(0032)")
    func sidebarAlreadyCollapsed() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            o.model.isSidebarVisible = false
            await o.model.toggleHistory()
            o.model.isSidebarVisible = true
            await o.model.toggleHistory()
            #expect(o.model.isSidebarVisible)
        }
    }

    @Test("[W17-history-disabled] 고른 Board가 없으면 이력 보기가 꺼져 있고 실행해도 바뀌지 않는다")
    func historyDisabled() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = BrowserHarness(directory: directory)
            await harness.model.start()
            #expect(!harness.model.canShowHistory)
            await harness.model.toggleHistory()
            #expect(harness.model.inspectorTab == .item)
            #expect(harness.model.isSidebarVisible)
        }
    }

    @Test("[W17-relaunch] [W17-relaunch-sidebar] 다시 실행하면 항목 탭·현재 구성·보이는 사이드바로 시작한다")
    func relaunch() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, daily(3))
            await o.model.toggleHistory()
            await o.history.select(.revision(Self.revisionID(2)))
            #expect(!o.model.isSidebarVisible)

            let relaunched = BrowserHarness(directory: o.harness.directory, lastBoard: o.harness.lastBoard)
            await relaunched.model.start()
            #expect(relaunched.model.selectedBoardID == Self.board)
            #expect(relaunched.model.inspectorTab == .item)
            #expect(relaunched.model.isSidebarVisible)
            #expect(relaunched.model.history.selection == .current)
            #expect(relaunched.model.isInspectorPresented)
        }
    }
}
