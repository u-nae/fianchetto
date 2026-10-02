import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("연결 대상 변경 화면 (W09)")
struct TargetReplacementModelTests {
    struct Opened {
        let harness: BrowserHarness
        let targets: URL
        let project: UUID
        let group: UUID
        let backend: UUID
        let note: UUID
        let legacy: URL
    }

    /// 그룹 "개발" 안의 Bishop 폴더 "legacy-api"와 Bishop 파일 "설계 메모.md"가 있는 Board를 열고 선택한다.
    private func opened(_ directory: URL, archived: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let targets = directory.appending(path: "targets")
        let legacy = try TargetFiles.folder(targets, "legacy-api")
        let note = try TargetFiles.file(targets, "설계 메모.md")
        var ids: (UUID, UUID, UUID, UUID) = (UUID(), UUID(), UUID(), UUID())
        try await seedStore(in: directory, at: harness.url) { seed in
            let project = try await makeBoard(seed, "서비스 A")
            let group = try #require(try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
            let groupID = try #require(group.snapshot.node(named: "개발")).id
            let linked = try #require(try await seed.linking.link(LinkRequest(projectID: project, parentID: groupID, position: nil, urls: [legacy, note])).committed)
            ids = (project, groupID, try #require(linked.snapshot.node(named: "legacy-api")).id, try #require(linked.snapshot.node(named: "설계 메모.md")).id)
            if archived { try await seed.store.setArchived(project, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(ids.0)
        return Opened(harness: harness, targets: targets, project: ids.0, group: ids.1, backend: ids.2, note: ids.3, legacy: legacy)
    }

    private func revisionCount(_ o: Opened) async throws -> Int {
        try await o.harness.model.openedStore!.store.revisionSummaries(projectID: o.project).count
    }

    @Test("[W09-picker-matches-kind] 연결 대상 변경은 선택한 Bishop의 종류에 맞는 대상만 고르게 한다", arguments: [true, false])
    func pickerMatchesKind(folder: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = folder ? o.backend : o.note

            await o.harness.model.beginReplaceTarget()

            #expect(o.harness.picker.replacementKinds == [folder ? .folder : .file])
            let configuration = TargetPicker.replacementConfiguration(for: folder ? .folder : .file)
            #expect(configuration.canChooseDirectories == folder)
            #expect(configuration.canChooseFiles == !folder)
            #expect(!configuration.allowsMultipleSelection)
        }
    }

    @Test("[W09-confirmation-before-change] 대상을 고르면 기존·새 경로를 보여 주는 확인 창을 띄우고, 확정해야 바뀐다")
    func confirmationBeforeChange() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let newAPI = try TargetFiles.folder(o.targets, "new-api")
            o.harness.model.selectedNodeID = o.backend
            o.harness.picker.replacementResults = [newAPI]
            let before = try await revisionCount(o)

            await o.harness.model.beginReplaceTarget()

            let preview = try #require(o.harness.model.replacement)
            #expect(preview.oldPath == o.legacy.standardizedFileURL.path)
            #expect(preview.newPath == newAPI.standardizedFileURL.path)
            #expect(try await revisionCount(o) == before)

            await o.harness.model.confirmReplacement()

            #expect(o.harness.model.replacement == nil)
            #expect(o.harness.model.loadedSnapshot?.node(o.backend)?.recordedPath == newAPI.standardizedFileURL.path)
            #expect(o.harness.model.inspector?.target == newAPI.standardizedFileURL.path)
        }
    }

    enum Pick: String, CaseIterable, Sendable { case different, same, undetermined }

    @Test("[W09-confirmation-by-identity] 확인 창은 판정에 따라 안내와 확정 동작을 다르게 보여 준다", arguments: Pick.allCases)
    func confirmationByIdentity(pick: Pick) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let newAPI = try TargetFiles.folder(o.targets, "new-api")
            if pick == .undetermined { try FileManager.default.removeItem(at: o.legacy) }
            o.harness.model.selectedNodeID = o.backend
            o.harness.picker.replacementResults = [pick == .same ? o.legacy : newAPI]

            await o.harness.model.beginReplaceTarget()

            let preview = try #require(o.harness.model.replacement)
            let presentation = o.harness.model.replacementPresentation(preview)
            switch pick {
            case .different:
                #expect(presentation.canConfirm)
                #expect(presentation.warning == nil)
            case .same:
                #expect(!presentation.canConfirm)
                #expect(presentation.warning == o.harness.model.alreadyLinkedText)
            case .undetermined:
                #expect(presentation.canConfirm)
                #expect(presentation.warning == o.harness.model.undeterminedText)
            }
        }
    }

    @Test("[W09-cancel-records-nothing] 고르기를 취소하거나 확인 창을 닫으면 아무것도 기록하지 않는다", arguments: [true, false])
    func cancelRecordsNothing(cancelPicker: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = o.backend
            o.harness.picker.replacementResults = [cancelPicker ? nil : try TargetFiles.folder(o.targets, "new-api")]
            let before = try await revisionCount(o)
            let node = o.harness.model.loadedSnapshot?.node(o.backend)

            await o.harness.model.beginReplaceTarget()
            o.harness.model.cancelReplacement()

            #expect(o.harness.model.replacement == nil)
            #expect(try await revisionCount(o) == before)
            #expect(o.harness.model.loadedSnapshot?.node(o.backend) == node)
        }
    }

    enum Start: String, CaseIterable, Sendable { case group, nothing, archived }

    @Test("[W09-start-requires-bishop] Bishop이 아니거나 보관된 Board면 연결 대상 변경을 시작하지 않는다", arguments: Start.allCases)
    func startRequiresBishop(start: Start) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: start == .archived)
            o.harness.model.selectedNodeID = switch start {
            case .group: o.group
            case .nothing: nil
            case .archived: o.backend
            }

            await o.harness.model.beginReplaceTarget()

            #expect(o.harness.picker.replacementKinds.isEmpty)
            #expect(o.harness.model.linkNotice?.kind == (start == .archived ? .archived : nil))
        }
    }

    @Test("[W09-failure-notice] 새 대상에 연결할 수 없거나 저장에 실패하면 안내하고 대상은 그대로다", arguments: [true, false])
    func failureNotice(targetGone: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let newAPI = try TargetFiles.folder(o.targets, "new-api")
            o.harness.model.selectedNodeID = o.backend
            o.harness.picker.replacementResults = [newAPI]
            await o.harness.model.beginReplaceTarget()
            let before = try await revisionCount(o)
            let node = o.harness.model.loadedSnapshot?.node(o.backend)
            if targetGone { try FileManager.default.removeItem(at: newAPI) } else { o.harness.fault.failNext() }

            await o.harness.model.confirmReplacement()

            #expect(o.harness.model.linkNotice?.kind == (targetGone ? .unreachable(["new-api"]) : .saveFailed))
            #expect(try await revisionCount(o) == before)
            #expect(o.harness.model.loadedSnapshot?.node(o.backend) == node)
        }
    }

    @Test("[W09-confirmation-by-identity] 확정 시점에 같은 대상이 되면 바꾸지 않았다고 안내한다")
    func confirmBecomesSameTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let newAPI = try TargetFiles.folder(o.targets, "new-api")
            o.harness.model.selectedNodeID = o.backend
            o.harness.picker.replacementResults = [newAPI]
            await o.harness.model.beginReplaceTarget()
            try FileManager.default.removeItem(at: newAPI)
            try FileManager.default.moveItem(at: o.legacy, to: newAPI)

            await o.harness.model.confirmReplacement()

            #expect(o.harness.model.replacement == nil)
            #expect(o.harness.model.linkNotice?.kind == .alreadyLinked)
        }
    }

    @Test("[W09-commands] 연결 대상 변경 명령이 메뉴와 상세 영역에 있다")
    func commandsExist() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.harness.model.selectedNodeID = o.backend
            #expect(o.harness.model.canReplaceSelectedTarget)
            o.harness.model.selectedNodeID = o.group
            #expect(!o.harness.model.canReplaceSelectedTarget)
        }
    }
}
