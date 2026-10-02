import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("Bishop·그룹 제거 화면 (W13)")
struct RemoveNodesModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let directory: URL
        var model: BoardBrowserModel { harness.model }

        func id(_ name: String) throws -> UUID {
            try #require(model.loadedSnapshot?.node(named: name)).id
        }
    }

    /// 최상위: 그룹 "개발"(0), 웹 링크 "API 명세"(1), Bishop 파일 "README"(2), 빈 그룹 "보관함"(3).
    /// "개발" 안: Bishop 폴더 "backend", Bishop 파일 "설계 메모", 그룹 "하위". "하위" 안: 웹 링크 "위키".
    private func opened(_ directory: URL, archived: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let backend = try TargetFiles.folder(directory, "targets/backend")
        _ = try TargetFiles.file(directory, "targets/backend/main.swift", contents: "print(1)")
        let memo = try TargetFiles.file(directory, "targets/설계 메모", contents: "memo")
        let readme = try TargetFiles.file(directory, "targets/README", contents: "readme")
        var project = UUID()
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            project = board
            func add(_ edit: ConfigurationEdit) async throws -> ConfigurationSnapshot {
                try #require(try await seed.service.apply(edit, to: board).committed).snapshot
            }
            let dev = try #require(try await add(.addGroup(name: "개발", parentID: nil, position: nil)).node(named: "개발")).id
            _ = try await add(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil))
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [readme]))
            _ = try await add(.addGroup(name: "보관함", parentID: nil, position: nil))
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: dev, position: nil, urls: [backend, memo]))
            let sub = try #require(try await add(.addGroup(name: "하위", parentID: dev, position: nil)).node(named: "하위")).id
            _ = try await add(.addWebLink(name: "위키", url: "https://example.com/wiki", parentID: sub, position: nil))
            if archived { try await seed.store.setArchived(board, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(project)
        return Opened(harness: harness, project: project, directory: directory)
    }

    private func revisions(_ o: Opened) async throws -> [RevisionSummary] {
        try await o.model.openedStore!.store.revisionSummaries(projectID: o.project)
    }

    private func storedSnapshot(_ o: Opened) async throws -> ConfigurationSnapshot {
        try await o.model.openedStore!.store.currentSnapshot(projectID: o.project)
    }

    private func names(_ snapshot: ConfigurationSnapshot, under parentID: UUID?) -> [String] {
        snapshot.nodes.filter { $0.parentID == parentID }.sorted { $0.sortIndex < $1.sortIndex }.map(\.displayName)
    }

    private func expectNothingRecorded(_ o: Opened, _ action: () async throws -> Void) async throws {
        let before = try await revisions(o).count
        let stored = try await storedSnapshot(o)
        try await action()
        #expect(try await revisions(o).count == before)
        #expect(try await storedSnapshot(o) == stored)
        #expect(o.model.loadedSnapshot == stored)
    }

    /// 대상 디렉토리의 상대 경로별 (내용, 수정 시각).
    private func targetState(_ directory: URL) throws -> [String: String] {
        let targets = directory.appending(path: "targets")
        var result: [String: String] = [:]
        for path in FileManager.default.enumerator(atPath: targets.path)?.compactMap({ $0 as? String }) ?? [] {
            let url = targets.appending(path: path)
            let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? "<dir>"
            result[path] = "\(contents)|\(modified?.timeIntervalSinceReferenceDate ?? -1)"
        }
        return result
    }

    // MARK: 확인 창

    struct DialogCase: Sendable, CustomTestStringConvertible {
        var item: String
        var title: String
        var message: String
        var testDescription: String { item }
    }

    nonisolated static let dialogs: [DialogCase] = [
        DialogCase(item: "개발", title: "그룹 제거", message: "현재 구성에서 제거합니다: 그룹 \"개발\"(포함된 항목 4개)."),
        DialogCase(item: "보관함", title: "그룹 제거", message: "현재 구성에서 제거합니다: 그룹 \"보관함\"(포함된 항목 없음)."),
        DialogCase(item: "backend", title: "Bishop 제거", message: "현재 구성에서 제거합니다: Bishop \"backend\"."),
        DialogCase(item: "API 명세", title: "웹 링크 제거", message: "현재 구성에서 제거합니다: 웹 링크 \"API 명세\"."),
    ]

    @Test("[W13-confirm-dialog] 제거 확인 창은 종류별 제목과 제거 범위를 보여 주고 열기만으로는 기록하지 않는다", .tags(.A14), arguments: dialogs)
    func confirmDialog(dialog: DialogCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id(dialog.item)
            try await expectNothingRecorded(o) {
                o.model.beginRemove()
            }
            let removal = try #require(o.model.removal)
            #expect(o.model.removalTitle(removal) == dialog.title)
            let text = o.model.removalMessage(removal)
            #expect(text.hasPrefix(dialog.message))
            #expect(text.contains("연결된 파일과 폴더는 그대로 남습니다."))
            #expect(!text.contains("파일 삭제"))
            #expect(!o.model.removalTitle(removal).contains("삭제"))
        }
    }

    // MARK: 확정

    @Test("[W13-remove-group] 그룹 제거는 그룹과 모든 자손을 revision 하나로 빼고 선택을 지운다", .tags(.A14))
    func removeGroup() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("개발")
            let before = try await revisions(o).count

            o.model.beginRemove()
            await o.model.confirmRemove()

            #expect(o.model.removal == nil)
            let after = try await revisions(o)
            #expect(after.count == before + 1)
            #expect(after.last?.cause == .edited(.remove))
            let snapshot = try #require(o.model.loadedSnapshot)
            #expect(Set(snapshot.nodes.map(\.displayName)) == ["API 명세", "README", "보관함"])
            #expect(names(snapshot, under: nil) == ["API 명세", "README", "보관함"])
            #expect(snapshot.nodes.filter { $0.parentID == nil }.map(\.sortIndex).sorted() == [0, 1, 2])
            #expect(try await storedSnapshot(o) == snapshot)
            #expect(o.model.selectedNodeID == nil)
        }
    }

    @Test("[W13-history-keeps-removed] 제거 직전 revision에 제거된 항목과 참조가 그대로 남는다", .tags(.A14))
    func historyKeepsRemoved() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let original = try #require(o.model.loadedSnapshot)
            let removedNames: Set<String> = ["개발", "backend", "설계 메모", "하위", "위키"]
            let removed = original.nodes.filter { removedNames.contains($0.displayName) }
            o.model.selectedNodeID = try o.id("개발")
            let previousID = try #require(try await revisions(o).last).id

            o.model.beginRemove()
            await o.model.confirmRemove()

            let store = o.model.openedStore!.store
            let previous = try await store.snapshot(revisionID: previousID)
            for node in removed {
                #expect(previous.nodes.first { $0.id == node.id } == node)
            }
            for node in removed where node.referenceID != nil {
                let reference = try await store.reference(try #require(node.referenceID))
                #expect(reference?.initialPath == node.recordedPath)
            }
        }
    }

    @Test("[W13-remove-leaf] Bishop·웹 링크 제거는 그 항목만 빼고 형제 순서를 다시 매긴다", arguments: [
        ("설계 메모", "개발"), ("API 명세", nil as String?),
    ])
    func removeLeaf(item: String, parent: String?) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let original = try #require(o.model.loadedSnapshot)
            let parentID = try parent.map { try o.id($0) }
            o.model.selectedNodeID = try o.id(item)
            let before = try await revisions(o).count

            o.model.beginRemove()
            await o.model.confirmRemove()

            let after = try await revisions(o)
            #expect(after.count == before + 1)
            #expect(after.last?.cause == .edited(.remove))
            let snapshot = try #require(o.model.loadedSnapshot)
            #expect(Set(snapshot.nodes.map(\.id)) == Set(original.nodes.map(\.id)).subtracting([try #require(original.node(named: item)).id]))
            #expect(names(snapshot, under: parentID) == names(original, under: parentID).filter { $0 != item })
            let indices = snapshot.nodes.filter { $0.parentID == parentID }.map(\.sortIndex).sorted()
            #expect(indices == Array(0..<indices.count))
        }
    }

    @Test("[W13-targets-untouched] 제거는 연결 대상 파일과 폴더를 지우거나 바꾸지 않는다")
    func targetsUntouched() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try targetState(directory)
            #expect(before.count == 4)

            for name in ["개발", "README"] {
                o.model.selectedNodeID = try o.id(name)
                o.model.beginRemove()
                await o.model.confirmRemove()
            }

            #expect(Set(try #require(o.model.loadedSnapshot).nodes.map(\.displayName)) == ["API 명세", "보관함"])
            #expect(try targetState(directory) == before)
        }
    }

    // MARK: 기록하지 않는 경우

    @Test("[W13-cancel] 확인 창에서 취소하면 기록하지 않고 선택을 유지한다", .tags(.A14))
    func cancel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let dev = try o.id("개발")
            o.model.selectedNodeID = dev
            try await expectNothingRecorded(o) {
                o.model.beginRemove()
                #expect(o.model.removal != nil)
                o.model.cancelRemove()
                // 닫힌 뒤의 확정은 아무것도 하지 않는다.
                await o.model.confirmRemove()
            }
            #expect(o.model.removal == nil)
            #expect(o.model.selectedNodeID == dev)
        }
    }

    @Test("[W13-save-failure] 제거 저장이 실패하면 안내하고 구성과 선택은 그대로다", arguments: ["backend", "개발"])
    func saveFailure(item: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let selected = try o.id(item)
            o.model.selectedNodeID = selected
            o.harness.fault.failNext()
            try await expectNothingRecorded(o) {
                o.model.beginRemove()
                await o.model.confirmRemove()
            }
            #expect(o.model.removal == nil)
            let notice = try #require(o.model.linkNotice)
            #expect(notice.kind == .saveFailed)
            #expect(o.model.noticeTitle(notice) == "제거")
            #expect(o.model.selectedNodeID == selected)
        }
    }

    @Test("[W13-save-failure] 확정 시점에 항목이 이미 없으면 저장하지 못했다고 안내하고 더 기록하지 않는다")
    func removedMeanwhile() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let backend = try o.id("backend")
            o.model.selectedNodeID = backend
            o.model.beginRemove()
            // 확인 창이 열린 사이에 다른 경로로 같은 항목이 제거됐다.
            _ = try await o.model.openedStore!.service.apply(.remove(backend), to: o.project)
            let before = try await revisions(o).count

            await o.model.confirmRemove()

            #expect(try await revisions(o).count == before)
            #expect(o.model.linkNotice?.kind == .saveFailed)
        }
    }

    @Test("[W13-remove-leaf] 대상이 사라진 Bishop도 제거할 수 있고 다른 대상은 그대로다")
    func removeBishopWithMissingTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: directory.appending(path: "targets/설계 메모"))
            let before = try targetState(directory)
            o.model.selectedNodeID = try o.id("설계 메모")

            o.model.beginRemove()
            await o.model.confirmRemove()

            #expect(try #require(o.model.loadedSnapshot).node(named: "설계 메모") == nil)
            #expect(o.model.linkNotice == nil)
            #expect(try targetState(directory) == before)
        }
    }

    enum Blocked: String, CaseIterable, Sendable { case archived, noSelection }

    @Test("[W13-archived-or-no-selection] 보관된 Board는 확인 창 없이 안내하고 선택 없음은 아무 일도 없다", arguments: Blocked.allCases)
    func archivedOrNoSelection(blocked: Blocked) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: blocked == .archived)
            o.model.selectedNodeID = blocked == .archived ? try o.id("개발") : nil
            try await expectNothingRecorded(o) {
                o.model.beginRemove()
                #expect(o.model.removal == nil)
                await o.model.confirmRemove()
            }
            switch blocked {
            case .archived: #expect(o.model.linkNotice?.kind == .archived)
            case .noSelection: #expect(o.model.linkNotice == nil)
            }
        }
    }
}
