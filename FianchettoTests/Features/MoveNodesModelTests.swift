import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("그룹 이동과 형제 순서 변경 화면 (W12)")
struct MoveNodesModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let directory: URL
        let backendURL: URL
        let memoURL: URL
        var model: BoardBrowserModel { harness.model }

        func id(_ name: String) throws -> UUID {
            try #require(model.loadedSnapshot?.node(named: name)).id
        }
    }

    /// 최상위: 그룹 "개발"(0), 그룹 "문서"(1), 웹 링크 "API 명세"(2).
    /// "개발" 안: Bishop 폴더 "backend"(0), Bishop 파일 "설계 메모"(1), 그룹 "하위"(2). "하위" 안: 그룹 "더 하위".
    private func opened(_ directory: URL, archived: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let backend = try TargetFiles.folder(directory, "targets/backend")
        let memo = try TargetFiles.file(directory, "targets/설계 메모", contents: "memo")
        var project = UUID()
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            project = board
            func add(_ edit: ConfigurationEdit) async throws -> ConfigurationSnapshot {
                try #require(try await seed.service.apply(edit, to: board).committed).snapshot
            }
            let dev = try #require(try await add(.addGroup(name: "개발", parentID: nil, position: nil)).node(named: "개발")).id
            _ = try await add(.addGroup(name: "문서", parentID: nil, position: nil))
            _ = try await add(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil))
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: dev, position: nil, urls: [backend, memo]))
            let sub = try #require(try await add(.addGroup(name: "하위", parentID: dev, position: nil)).node(named: "하위")).id
            _ = try await add(.addGroup(name: "더 하위", parentID: sub, position: nil))
            if archived { try await seed.store.setArchived(board, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(project)
        return Opened(harness: harness, project: project, directory: directory, backendURL: backend, memoURL: memo)
    }

    private func revisions(_ o: Opened) async throws -> [RevisionSummary] {
        try await o.model.openedStore!.store.revisionSummaries(projectID: o.project)
    }

    private func storedSnapshot(_ o: Opened) async throws -> ConfigurationSnapshot {
        try await o.model.openedStore!.store.currentSnapshot(projectID: o.project)
    }

    /// 부모 아래 이름을 정렬 순서대로. 부모 이름이 nil이면 최상위.
    private func names(_ snapshot: ConfigurationSnapshot, under parent: String?) throws -> [String] {
        let parentID = try parent.map { try #require(snapshot.node(named: $0)).id }
        return snapshot.nodes.filter { $0.parentID == parentID }.sorted { $0.sortIndex < $1.sortIndex }.map(\.displayName)
    }

    /// 배치(부모·순서)만 모은 값. 이름이 유일한 픽스처라 이름으로 비교한다.
    private func layout(_ snapshot: ConfigurationSnapshot) -> [String: String] {
        Dictionary(uniqueKeysWithValues: snapshot.nodes.map { node in
            let parent = node.parentID.flatMap { id in snapshot.nodes.first { $0.id == id }?.displayName } ?? "<root>"
            return (node.displayName, "\(parent)#\(node.sortIndex)")
        })
    }

    /// 상태를 기억해 두고, 동작 뒤 revision 수·저장된 배치·화면 배치가 그대로인지 확인한다.
    private func expectNothingRecorded(_ o: Opened, _ action: () async throws -> Void) async throws {
        let before = try await revisions(o).count
        let stored = layout(try await storedSnapshot(o))
        try await action()
        #expect(try await revisions(o).count == before)
        #expect(layout(try await storedSnapshot(o)) == stored)
        #expect(layout(try #require(o.model.loadedSnapshot)) == stored)
    }

    // MARK: 이동 창

    @Test("[W12-move-to-group] 이동 창에서 고른 그룹 끝으로 revision 하나로 옮기고 정체성·선택을 유지한다", .tags(.A04))
    func moveToGroup() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let backend = try #require(o.model.loadedSnapshot?.node(named: "backend"))
            let docs = try o.id("문서")
            o.model.selectedNodeID = backend.id
            let before = try await revisions(o)

            o.model.beginMove()
            await o.model.confirmMove(to: .group(docs))

            #expect(o.model.moveDialog == nil)
            let after = try await revisions(o)
            #expect(after.count == before.count + 1)
            #expect(after.last?.cause == .edited(.move))
            let snapshot = try #require(o.model.loadedSnapshot)
            #expect(try names(snapshot, under: "문서") == ["backend"])
            #expect(try names(snapshot, under: "개발") == ["설계 메모", "하위"])
            let moved = try #require(snapshot.node(named: "backend"))
            #expect(moved.id == backend.id)
            #expect(moved.referenceID == backend.referenceID)
            #expect(moved.recordedPath == backend.recordedPath)
            #expect(o.model.selectedNodeID == backend.id)
            #expect(layout(try await storedSnapshot(o)) == layout(snapshot))
            let previous = try await o.model.openedStore!.store.snapshot(revisionID: try #require(before.last).id)
            #expect(try names(previous, under: "개발") == ["backend", "설계 메모", "하위"])
        }
    }

    @Test("[W12-move-to-root] 이동 창에서 최상위를 고르면 최상위 끝으로 옮긴다")
    func moveToRoot() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("설계 메모")

            o.model.beginMove()
            await o.model.confirmMove(to: .root)

            #expect(try names(try #require(o.model.loadedSnapshot), under: nil) == ["개발", "문서", "API 명세", "설계 메모"])
        }
    }

    @Test("[W12-move-group-with-descendants] 그룹을 옮기면 자손의 부모와 순서는 그대로다", .tags(.A04))
    func moveGroupWithDescendants() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("하위")

            o.model.beginMove()
            await o.model.confirmMove(to: .group(try o.id("문서")))

            let snapshot = try #require(o.model.loadedSnapshot)
            #expect(try names(snapshot, under: "문서") == ["하위"])
            #expect(try names(snapshot, under: "하위") == ["더 하위"])
        }
    }

    @Test("[W12-destination-list] 이동 창 목적지는 최상위와 옮길 수 있는 그룹뿐이다")
    func destinationList() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("개발")

            o.model.beginMove()

            let dialog = try #require(o.model.moveDialog)
            #expect(dialog.destinations.map(\.target) == [.root, .group(try o.id("문서"))])
            #expect(dialog.destinations.map(\.name) == [o.model.rootDestinationName, "문서"])

            // 그룹이 아닌 항목을 옮길 때는 모든 그룹이 깊이와 함께 트리 순서로 나온다.
            o.model.cancelMove()
            o.model.selectedNodeID = try o.id("API 명세")
            o.model.beginMove()
            let all = try #require(o.model.moveDialog).destinations
            #expect(all.map(\.name) == [o.model.rootDestinationName, "개발", "하위", "더 하위", "문서"])
            #expect(all.map(\.depth) == [0, 1, 2, 3, 1])
        }
    }

    enum DialogEnd: String, CaseIterable, Sendable { case currentParent, cancel }

    @Test("[W12-move-dialog-unchanged-or-cancel] 이동 창에서 현재 부모를 고르거나 취소하면 기록하지 않는다", .tags(.A04), arguments: DialogEnd.allCases)
    func dialogUnchangedOrCancel(end: DialogEnd) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("backend")
            let dev = try o.id("개발")
            try await expectNothingRecorded(o) {
                o.model.beginMove()
                #expect(o.model.moveDialog != nil)
                switch end {
                case .currentParent: await o.model.confirmMove(to: .group(dev))
                case .cancel: o.model.cancelMove()
                }
                #expect(o.model.moveDialog == nil)
            }
        }
    }

    // MARK: 위로·아래로

    enum Step: String, CaseIterable, Sendable { case up, down }

    @Test("[W12-move-up-down] 위로·아래로 이동은 형제 안에서 한 칸 옮기고 revision 하나를 남긴다", .tags(.A04), arguments: Step.allCases)
    func moveUpDown(step: Step) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let memo = try o.id("설계 메모")
            o.model.selectedNodeID = memo
            let before = try await revisions(o).count

            switch step {
            case .up: await o.model.moveSelectedUp()
            case .down: await o.model.moveSelectedDown()
            }

            let after = try await revisions(o)
            #expect(after.count == before + 1)
            #expect(after.last?.cause == .edited(.move))
            let expected = step == .up ? ["설계 메모", "backend", "하위"] : ["backend", "하위", "설계 메모"]
            #expect(try names(try #require(o.model.loadedSnapshot), under: "개발") == expected)
            #expect(try names(try await storedSnapshot(o), under: "개발") == expected)
            #expect(o.model.selectedNodeID == memo)
        }
    }

    @Test("[W12-move-up-down-at-edge] 맨 위에서 위로, 맨 아래에서 아래로는 기록하지 않는다", .tags(.A04), arguments: Step.allCases)
    func moveAtEdge(step: Step) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id(step == .up ? "backend" : "하위")
            try await expectNothingRecorded(o) {
                switch step {
                case .up: await o.model.moveSelectedUp()
                case .down: await o.model.moveSelectedDown()
                }
            }
            #expect(o.model.linkNotice == nil)
        }
    }

    // MARK: 끌어다 놓기

    struct DropCase: Sendable, CustomTestStringConvertible {
        var item: String
        var target: String?
        var parent: String?
        var order: [String]
        var testDescription: String { "\(item) → \(target ?? "빈 곳")" }
    }

    nonisolated static let drops: [DropCase] = [
        DropCase(item: "API 명세", target: "개발", parent: "개발", order: ["backend", "설계 메모", "하위", "API 명세"]),
        DropCase(item: "문서", target: "개발", parent: "개발", order: ["backend", "설계 메모", "하위", "문서"]),
        DropCase(item: "API 명세", target: "설계 메모", parent: "개발", order: ["backend", "API 명세", "설계 메모", "하위"]),
        DropCase(item: "설계 메모", target: "API 명세", parent: nil, order: ["개발", "문서", "설계 메모", "API 명세"]),
        DropCase(item: "backend", target: nil, parent: nil, order: ["개발", "문서", "API 명세", "backend"]),
    ]

    @Test("[W12-drag-and-drop] 놓은 곳에 따라 revision 하나로 옮기고 옮긴 항목을 선택한다", .tags(.A04), arguments: drops)
    func dragAndDrop(drop: DropCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let item = try o.id(drop.item)
            let target = try drop.target.map { try o.id($0) }
            let before = try await revisions(o).count

            #expect(o.model.canAcceptNodeDrop(item, on: target))
            #expect(await o.model.dropNode(item, on: target))

            let after = try await revisions(o)
            #expect(after.count == before + 1)
            #expect(after.last?.cause == .edited(.move))
            #expect(try names(try #require(o.model.loadedSnapshot), under: drop.parent) == drop.order)
            #expect(try names(try await storedSnapshot(o), under: drop.parent) == drop.order)
            #expect(o.model.selectedNodeID == item)
        }
    }

    @Test("[W12-drop-on-linked-folder-refused] 연결 폴더 위에는 놓을 수 없다", .tags(.A14))
    func dropOnLinkedFolder() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let link = try o.id("API 명세"), backend = try o.id("backend")
            try await expectNothingRecorded(o) {
                #expect(!o.model.canAcceptNodeDrop(link, on: backend))
                #expect(await o.model.dropNode(link, on: backend) == false)
            }
        }
    }

    @Test("[W12-drop-same-position] 자기 자신이나 현재 자리에 놓으면 안내 없이 기록하지 않는다", .tags(.A04), arguments: [
        ("backend", "backend"), ("개발", "개발"), ("문서", "API 명세"),
    ])
    func dropSamePosition(item: String, target: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let itemID = try o.id(item), targetID = try o.id(target)
            try await expectNothingRecorded(o) {
                await o.model.dropNode(itemID, on: targetID)
            }
            #expect(o.model.linkNotice == nil)
        }
    }

    /// "설계 메모" 위에 놓으면 그 앞, 곧 "개발" 자신이 부모가 되므로 역시 순환이다.
    @Test("[W12-cycle-rejected] 그룹을 자손 위에 놓으면 순환으로 거부하고 안내한다", .tags(.A14), arguments: ["하위", "더 하위", "설계 메모"])
    func cycleRejected(target: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let dev = try o.id("개발"), targetID = try o.id(target)
            try await expectNothingRecorded(o) {
                await o.model.dropNode(dev, on: targetID)
            }
            let notice = try #require(o.model.linkNotice)
            #expect(notice.kind == .moveIntoItself)
            #expect(o.model.noticeText(notice) == "Wing을 자기 안으로 옮길 수 없습니다.")
        }
    }

    @Test("[W12-non-group-parent-rejected] 연결 항목·웹 링크를 부모로 직접 요청한 이동은 거부하고 안내한다", .tags(.A14), arguments: [
        "backend", "설계 메모", "API 명세",
    ])
    func nonGroupParentRejected(parent: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let docs = try o.id("문서"), parentID = try o.id(parent)
            o.model.selectedNodeID = docs
            try await expectNothingRecorded(o) {
                await o.model.requestMove(docs, toParent: parentID, position: nil)
            }
            let notice = try #require(o.model.linkNotice)
            #expect(notice.kind == .moveIntoNonGroup)
            #expect(o.model.noticeText(notice) == "그 항목 안으로는 옮길 수 없습니다.")
        }
    }

    @Test("[W12-unknown-item-drop] 현재 구성에 없는 항목 식별자는 받지 않는다")
    func unknownItemDrop() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let dev = try o.id("개발")
            let foreign = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000F00D"))
            try await expectNothingRecorded(o) {
                #expect(!o.model.canAcceptNodeDrop(foreign, on: dev))
                #expect(await o.model.dropNode(foreign, on: dev) == false)
                // 놓은 곳이 이 Board에 없어도 받지 않는다.
                #expect(await o.model.dropNode(dev, on: foreign) == false)
            }
            #expect(o.model.linkNotice == nil)
        }
    }

    @Test("[W12-finder-drop-unchanged] Finder 파일 드롭은 그룹 위에서 연결을 추가하고 Bishop 파일 위에서는 받지 않는다")
    func finderDropUnchanged() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let file = try TargetFiles.file(directory, "targets/notes.txt")
            let memo = try o.id("설계 메모")
            try await expectNothingRecorded(o) {
                #expect(!o.model.canAcceptDrop(on: memo))
                #expect(await o.model.drop([file], on: memo) == false)
            }
            let before = try await revisions(o).count
            #expect(await o.model.drop([file], on: try o.id("문서")))
            let after = try await revisions(o)
            #expect(after.count == before + 1)
            #expect(after.last?.cause == .edited(.addLinkedItems))
            #expect(try names(try #require(o.model.loadedSnapshot), under: "문서") == ["notes.txt"])
        }
    }

    // MARK: 공통

    @Test("[W12-targets-untouched] 이동은 실제 대상과 Bishop의 기록 당시 경로·참조를 바꾸지 않는다")
    func targetsUntouched() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            _ = try TargetFiles.file(directory, "targets/backend/main.swift", contents: "print(1)")
            let targets = directory.appending(path: "targets")
            let state = { () throws -> [String: Date] in
                var result: [String: Date] = [:]
                for path in FileManager.default.enumerator(atPath: targets.path)?.compactMap({ $0 as? String }) ?? [] {
                    let attributes = try FileManager.default.attributesOfItem(atPath: targets.appending(path: path).path)
                    result[path] = attributes[.modificationDate] as? Date
                }
                return result
            }
            let beforeFiles = try state()
            let snapshot = try #require(o.model.loadedSnapshot)
            let refs = snapshot.nodes.filter { $0.kind == .file || $0.kind == .folder }
                .map { "\($0.id)|\($0.referenceID?.uuidString ?? "")|\($0.recordedPath ?? "")" }

            o.model.selectedNodeID = try o.id("backend")
            o.model.beginMove()
            await o.model.confirmMove(to: .group(try o.id("문서")))
            o.model.selectedNodeID = try o.id("설계 메모")
            o.model.beginMove()
            await o.model.confirmMove(to: .root)

            #expect(try state() == beforeFiles)
            let after = try #require(o.model.loadedSnapshot)
            #expect(try names(after, under: "문서") == ["backend"])
            #expect(after.nodes.filter { $0.kind == .file || $0.kind == .folder }
                .map { "\($0.id)|\($0.referenceID?.uuidString ?? "")|\($0.recordedPath ?? "")" }.sorted() == refs.sorted())
        }
    }

    @Test("[W12-save-failure] 이동 저장이 실패하면 안내하고 revision과 배치는 그대로다")
    func saveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("backend")
            o.harness.fault.failNext()
            try await expectNothingRecorded(o) {
                await o.model.moveSelectedDown()
            }
            #expect(o.model.linkNotice?.kind == .saveFailed)
        }
    }

    enum Blocked: String, CaseIterable, Sendable { case archivedUp, archivedDialog, archivedDrop, noSelection }

    @Test("[W12-archived-or-no-selection] 보관된 Board에서는 이동을 막고 안내하며 선택 없음에서는 아무 일도 없다", arguments: Blocked.allCases)
    func archivedOrNoSelection(blocked: Blocked) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: blocked != .noSelection)
            let backend = try o.id("backend")
            o.model.selectedNodeID = blocked == .noSelection ? nil : backend
            try await expectNothingRecorded(o) {
                switch blocked {
                case .archivedUp:
                    await o.model.moveSelectedUp()
                case .archivedDialog:
                    o.model.beginMove()
                case .archivedDrop:
                    #expect(!o.model.canAcceptNodeDrop(backend, on: nil))
                    #expect(await o.model.dropNode(backend, on: nil) == false)
                case .noSelection:
                    await o.model.moveSelectedDown()
                    o.model.beginMove()
                }
            }
            #expect(o.model.moveDialog == nil)
            switch blocked {
            case .archivedUp, .archivedDialog: #expect(o.model.linkNotice?.kind == .archived)
            case .archivedDrop, .noSelection: #expect(o.model.linkNotice == nil)
            }
        }
    }
}
