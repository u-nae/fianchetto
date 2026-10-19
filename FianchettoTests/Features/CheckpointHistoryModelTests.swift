import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 이력 탭의 체크포인트 행(W22): 행 문구, 저장 시각 자리 병합, 묶음 불러오기, 선택과 과거 모드.
@MainActor
@Suite("이력 탭의 체크포인트 행 (W22)")
struct CheckpointHistoryModelTests {
    struct RevisionSeed {
        var sequence: Int
        var at: Date
        var damagedSnapshot = false
        var damagedCause = false
        var snapshot: ConfigurationSnapshot?
    }

    struct CheckpointSeed {
        var id: UUID
        var sequence: Int
        var title: String
        var at: Date
        var note = ""
        var next = ""
    }

    nonisolated static let board = RecordFixtures.project
    nonisolated static let otherBoard = RecordFixtures.otherProject
    nonisolated static func revisionID(_ sequence: Int, board: UUID = board) -> UUID {
        fixedID((board == Self.board ? 7000 : 8000) + sequence)
    }

    nonisolated static let now = localTime("2026-10-19 15:30:00")
    nonisolated static func today(_ hour: Int, _ minute: Int) -> Date { localTime(String(format: "2026-10-19 %02d:%02d:00", hour, minute)) }
    nonisolated static func yesterday(_ hour: Int, _ minute: Int) -> Date { localTime(String(format: "2026-10-18 %02d:%02d:00", hour, minute)) }

    /// 순번 1…count, 어제 10:00부터 한 시간 간격.
    nonisolated static func yesterdayHourly(_ count: Int) -> [RevisionSeed] {
        (1...count).map { RevisionSeed(sequence: $0, at: yesterday(9 + $0, 0)) }
    }

    @MainActor
    struct Opened {
        let harness: BrowserHarness
        var model: BoardBrowserModel { harness.model }
        var history: HistoryPanelModel { harness.model.history }
        var store: ProjectStore { model.openedStore!.store }

        /// 행 이름: revision은 "#n", 체크포인트는 제목.
        var names: [String] {
            history.entries.map { entry in
                switch entry {
                case let .revision(row): "#\(row.summary.sequence)"
                case let .checkpoint(summary): summary.title
                }
            }
        }

        func sectionNames() -> [(String, [String])] {
            history.sections.map { section in
                (section.title, section.entries.map { entry in
                    switch entry {
                    case let .revision(row): "#\(row.summary.sequence)"
                    case let .checkpoint(summary): summary.title
                    }
                })
            }
        }

        func row(_ sequence: Int) throws -> HistoryPanelModel.Row {
            try #require(history.rows.first { $0.summary.sequence == sequence })
        }

        func checkpoint(_ title: String) throws -> CheckpointSummary {
            try #require(history.checkpoints.first { $0.title == title })
        }

        func open() async { await model.selectInspectorTab(.history) }
    }

    private func opened(
        _ directory: URL, revisions: [RevisionSeed], checkpoints: [CheckpointSeed] = [], other: [RevisionSeed] = [],
        clock: HistoryClock = HistoryClock(now: CheckpointHistoryModelTests.now)
    ) async throws -> Opened {
        let staging = directory.appending(path: "staging/Fianchetto.store")
        try withStore(at: staging) { store throws in
            for (board, list, name) in [(Self.board, revisions, "서비스 A"), (Self.otherBoard, other, "서비스 B")] where !list.isEmpty {
                let last = try #require(list.max { $0.sequence < $1.sequence })
                try store.insert(ProjectRecord(
                    id: board, createdAt: list[0].at, currentRevisionID: Self.revisionID(last.sequence, board: board), archivedAt: nil, origin: nil
                ))
                for seed in list {
                    try store.insertRevision(RevisionDraft(
                        id: Self.revisionID(seed.sequence, board: board), projectID: board, sequence: seed.sequence, recordedAt: seed.at,
                        cause: seed.sequence == 1 ? .created : .edited(.renameNode), snapshot: seed.snapshot ?? RecordFixtures.snapshot(named: name)
                    ))
                }
            }
            for seed in checkpoints {
                try store.insert(CheckpointRecord(
                    id: seed.id, revisionID: Self.revisionID(seed.sequence), title: seed.title, progressNote: seed.note,
                    nextSteps: seed.next, createdAt: seed.at, attachments: []
                ))
            }
            try store.save()
            let models = try store.context.fetch(FetchDescriptor<SchemaV1.RevisionModel>())
            for seed in revisions where seed.damagedSnapshot || seed.damagedCause {
                let model = try #require(models.first { $0.id == Self.revisionID(seed.sequence) })
                if seed.damagedSnapshot { model.snapshotData = Data("{".utf8) }
                if seed.damagedCause { model.cause = "rollback" }
            }
            try store.save()
        }
        let harness = BrowserHarness(directory: directory.appending(path: "tested"), clock: clock)
        try copyStoreFiles(from: staging, to: harness.url)
        await harness.model.start()
        await harness.model.select(Self.board)
        return Opened(harness: harness)
    }

    nonisolated static let c1 = fixedID(7101)
    nonisolated static let c2 = fixedID(7102)
    nonisolated static let c3 = fixedID(7103)

    // MARK: 행 표시와 순서

    @Test("[W22-history-row-shape] 체크포인트 행의 문구·VoiceOver 라벨은 제목·순번·시각을 담는다")
    func rowShape() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "인증 1차", at: Self.today(15, 5))])
            await o.open()
            let summary = try o.checkpoint("인증 1차")
            #expect(o.history.entries.first == .checkpoint(summary))
            #expect(o.history.caption(checkpoint: summary) == "체크포인트 · #5 · 오후 3:05")
            #expect(o.history.accessibilityLabel(checkpoint: summary) == "체크포인트, 인증 1차, #5 구성, 오후 3:05 저장")
            #expect(o.history.savedText(summary.createdAt) == "\(o.history.dateTimeText(summary.createdAt)) 저장")
        }
    }

    @Test("[W22-history-row-order] 체크포인트 행은 저장 시각 자리에 끼어들고 날짜 구역은 행 자신의 시각을 따른다")
    func rowOrder() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5), checkpoints: [
                CheckpointSeed(id: Self.c1, sequence: 5, title: "어제 메모", at: Self.yesterday(18, 0)),
                CheckpointSeed(id: Self.c2, sequence: 5, title: "오늘 메모", at: Self.today(15, 5)),
            ])
            await o.open()
            let sections = o.sectionNames()
            #expect(sections.count == 2)
            #expect(sections[0].0 == "오늘 · 10월 19일")
            #expect(sections[0].1 == ["오늘 메모"])
            #expect(sections[1].0 == "어제 · 10월 18일")
            #expect(sections[1].1 == ["어제 메모", "#5", "#4", "#3", "#2", "#1"])
        }
    }

    @Test("[W22-history-old-revision-new-checkpoint] 오래된 revision에 나중에 저장한 체크포인트는 자기 시각 자리에 온다")
    func oldRevisionNewCheckpoint() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 2, title: "오늘 저장", at: Self.today(15, 5))])
            await o.open()
            #expect(o.names == ["오늘 저장", "#5", "#4", "#3", "#2", "#1"])
            let sections = o.sectionNames()
            #expect(sections[0].1 == ["오늘 저장"])
            #expect(sections[1].1.contains("#2"))
        }
    }

    @Test("[W22-history-no-count-on-revision-rows] revision 행 문구에는 체크포인트 수가 없다")
    func noCountOnRevisionRows() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5), checkpoints: [
                CheckpointSeed(id: Self.c1, sequence: 5, title: "1차", at: Self.today(15, 5)),
                CheckpointSeed(id: Self.c2, sequence: 5, title: "2차", at: Self.today(15, 20)),
            ])
            await o.open()
            let row = try o.row(5)
            #expect(o.history.caption(row) == "#5 · 오후 2:00")
            #expect(!o.history.accessibilityLabel(row).contains("체크포인트"))
        }
    }

    // MARK: 묶음 불러오기

    @Test("[W22-history-paging-keeps-rows] 불러온 범위보다 오래된 체크포인트는 첫 묶음에서 맨 아래, 다음 묶음 뒤에는 자기 자리에 한 번만 있다")
    func pagingKeepsRows() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let base = Self.yesterday(10, 0)
            let revisions = (1...60).map { RevisionSeed(sequence: $0, at: base.addingTimeInterval(Double($0) * 60)) }
            let o = try await opened(directory, revisions: revisions, checkpoints: [
                CheckpointSeed(id: Self.c1, sequence: 60, title: "최신", at: base.addingTimeInterval(61 * 60)),
                CheckpointSeed(id: Self.c2, sequence: 2, title: "오래된 revision의 메모", at: base.addingTimeInterval(59.5 * 60)),
                CheckpointSeed(id: Self.c3, sequence: 2, title: "당시 메모", at: base.addingTimeInterval(2.5 * 60)),
            ])
            await o.open()
            #expect(o.history.rows.map(\.summary.sequence) == Array((11...60).reversed()))
            #expect(Array(o.names.prefix(3)) == ["최신", "#60", "오래된 revision의 메모"])
            #expect(o.names.last == "당시 메모")
            #expect(o.history.entries.last?.id == Self.c3)
            await o.history.loadMore()
            #expect(Array(o.names.suffix(4)) == ["#3", "당시 메모", "#2", "#1"])
            #expect(o.names.filter { $0 == "당시 메모" }.count == 1)
            #expect(o.names.filter { $0 == "오래된 revision의 메모" }.count == 1)
            #expect(o.history.rows.count == 60)
        }
    }

    @Test("[W22-history-paging-keeps-rows] 목록을 불러오기 전에 더한 체크포인트는 무시되고 열 때 한 번만 읽는다")
    func addBeforeOpenIgnored() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "저장됨", at: Self.today(15, 5))])
            o.history.add(checkpoint: CheckpointSummary(id: Self.c1, revisionID: Self.revisionID(5), sequence: 5, title: "저장됨", createdAt: Self.today(15, 5)))
            #expect(o.history.checkpoints.isEmpty)
            await o.open()
            #expect(o.names.filter { $0 == "저장됨" }.count == 1)
            o.history.add(checkpoint: CheckpointSummary(id: Self.c2, revisionID: Self.revisionID(3), sequence: 3, title: "나중", createdAt: Self.today(16, 0)))
            #expect(o.names == ["나중", "저장됨", "#5", "#4", "#3", "#2", "#1"])
        }
    }

    @Test("[W22-history-paging-keeps-rows] 체크포인트 목록을 읽지 못하면 revision 목록 읽기 실패와 같은 상태다")
    func listFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            var revisions = Self.yesterdayHourly(5)
            revisions[2].damagedCause = true
            let o = try await opened(directory, revisions: revisions,
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "있음", at: Self.today(15, 5))])
            await o.open()
            #expect(o.history.listFailed)
            #expect(o.history.checkpoints.isEmpty)
            #expect(o.history.entries.isEmpty)
            #expect(o.model.loadedSnapshot?.projectName == "서비스 A")
            #expect(o.model.canAddToBoard)
            #expect(try await o.store.checkpointSummaries(projectID: Self.board).count == 1)
        }
    }

    // MARK: 선택

    @Test("[W22-select-current-revision-checkpoint] 현재 revision에 붙은 체크포인트를 고르면 과거 모드가 되고 선택은 체크포인트다", .tags(.A10))
    func selectCurrentRevisionCheckpoint() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "인증 1차", at: Self.today(15, 5))])
            await o.open()
            await o.history.select(.checkpoint(Self.c1))
            #expect(o.history.selection == .checkpoint(Self.c1))
            #expect(o.history.selectedRevisionID == Self.revisionID(5))
            #expect(o.history.selectedSnapshot != nil)
            #expect(o.history.selectedCheckpoint?.title == "인증 1차")
            #expect(o.model.isViewingPast)
            #expect(o.model.pastBannerDetail?.hasPrefix("#5 · ") == true)
            #expect(!o.model.canAddToBoard)
        }
    }

    @Test("[W22-switch-to-revision-row] 체크포인트를 보다가 같은 revision 행을 고르면 선택만 revision으로 바뀌고 구성은 그대로다")
    func switchToRevisionRow() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "인증 1차", at: Self.today(15, 5))])
            await o.open()
            await o.history.select(.checkpoint(Self.c1))
            let snapshot = o.history.selectedSnapshot
            await o.history.select(.revision(Self.revisionID(5)))
            #expect(o.history.selection == .revision(Self.revisionID(5)))
            #expect(o.history.selectedCheckpoint == nil)
            #expect(o.history.selectedSnapshot == snapshot)
            #expect(o.model.isViewingPast)
        }
    }

    enum Return: CaseIterable { case banner, currentRow }

    @Test("[W22-return-to-current] 체크포인트를 보다가 현재로 돌아가면 선택이 비고 띠가 사라진다", arguments: Return.allCases)
    func returnToCurrent(_ way: Return) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 3, title: "명세 확정", at: Self.today(15, 5))])
            await o.open()
            await o.history.select(.checkpoint(Self.c1))
            #expect(o.model.isViewingPast)
            switch way {
            case .banner: await o.model.returnToCurrent()
            case .currentRow: await o.history.select(.current)
            }
            #expect(o.history.selection == .current)
            #expect(o.history.selectedCheckpoint == nil)
            #expect(!o.model.isViewingPast)
        }
    }

    @Test("[W22-unreadable-revision-notice] 연결 revision의 구성을 읽을 수 없으면 선택을 바꾸지 않고 안내한다")
    func unreadableRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            var revisions = Self.yesterdayHourly(5)
            revisions[2].damagedSnapshot = true
            let o = try await opened(directory, revisions: revisions,
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 3, title: "명세 확정", at: Self.today(15, 5))])
            await o.open()
            await o.history.select(.checkpoint(Self.c1))
            #expect(o.history.notice == .unreadableRevision)
            #expect(o.history.selection == .current)
            #expect(o.history.selectedCheckpoint == nil)
            #expect(!o.model.isViewingPast)
            #expect(try await o.store.checkpointSummaries(projectID: Self.board).count == 1)
        }
    }

    @Test("[W22-weblink-from-revision] 체크포인트가 가리키는 구성의 웹 링크 URL은 그 revision의 값이다")
    func webLinkFromRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            var revisions = Self.yesterdayHourly(5)
            revisions[2].snapshot = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
                SnapshotFixtures.webLink(fixedID(4), "명세", order: 0, url: "https://example.com/spec"),
            ])
            revisions[4].snapshot = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
                SnapshotFixtures.webLink(fixedID(4), "명세", order: 0, url: "https://example.com/spec-v2"),
            ])
            let o = try await opened(directory, revisions: revisions,
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 3, title: "명세 확정", at: Self.today(15, 5))])
            await o.open()
            await o.history.select(.checkpoint(Self.c1))
            #expect(o.history.selectedSnapshot?.node(named: "명세")?.url == "https://example.com/spec")
            #expect(o.model.loadedSnapshot?.node(named: "명세")?.url == "https://example.com/spec-v2")
            let record = try #require(try await o.store.checkpoint(Self.c1))
            #expect(record == CheckpointRecord(id: Self.c1, revisionID: Self.revisionID(3), title: "명세 확정", progressNote: "", nextSteps: "", createdAt: Self.today(15, 5), attachments: []))
        }
    }

    @Test("다른 Board를 고르면 체크포인트 목록·선택이 비워진다")
    func boardSwitchClears() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "인증 1차", at: Self.today(15, 5))],
                                     other: [RevisionSeed(sequence: 1, at: Self.yesterday(9, 0))])
            await o.open()
            await o.history.select(.checkpoint(Self.c1))
            await o.model.select(Self.otherBoard)
            #expect(o.history.checkpoints.isEmpty)
            #expect(o.history.selectedCheckpoint == nil)
            #expect(o.history.selection == .current)
            #expect(!o.model.isViewingPast)
        }
    }

    @Test("체크포인트 선택도 비교를 먼저 닫는다")
    func selectionClosesComparison() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, revisions: Self.yesterdayHourly(5),
                                     checkpoints: [CheckpointSeed(id: Self.c1, sequence: 5, title: "인증 1차", at: Self.today(15, 5))])
            await o.open()
            await o.history.select(.revision(Self.revisionID(4)))
            await o.model.compareWithCurrent()
            #expect(o.model.isComparing)
            await o.history.select(.checkpoint(Self.c1))
            #expect(!o.model.isComparing)
            #expect(o.history.selection == .checkpoint(Self.c1))
        }
    }
}
