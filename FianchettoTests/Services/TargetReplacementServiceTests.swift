import Foundation
import Testing
@testable import Fianchetto

@Suite("연결 대상 변경 서비스 (W09)")
struct TargetReplacementServiceTests {
    struct Fixture {
        let harness: ServiceHarness
        let targets: URL
        let project: UUID
        let group: UUID
        let backend: UUID
        let legacy: URL
        var replacement: TargetReplacementService {
            TargetReplacementService(bookmarks: BookmarkAdapter(system: harness.bookmarks), configuration: harness.service)
        }
    }

    /// 그룹 "개발" 안에 폴더 "legacy-api"를 연결한 Bishop "backend".
    private func fixture(_ directory: URL) async throws -> Fixture {
        let harness = try ServiceHarness(directory: directory.appending(path: "store"))
        let targets = directory.appending(path: "targets")
        let legacy = try TargetFiles.folder(targets, "legacy-api")
        let project = try await makeBoard(harness)
        let group = try #require(try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
        let groupID = try #require(group.snapshot.node(named: "개발")).id
        let linked = try #require(try await harness.linking.link(LinkRequest(projectID: project, parentID: groupID, position: nil, urls: [legacy])).committed)
        let backend = try #require(linked.snapshot.node(named: "legacy-api")).id
        _ = try await harness.service.apply(.renameNode(backend, "backend"), to: project)
        return Fixture(harness: harness, targets: targets, project: project, group: groupID, backend: backend, legacy: legacy)
    }

    @Test("[W09-replace-keeps-identity] 다른 폴더로 교체하면 이름·UUID·배치는 유지하고 새 참조를 쓴다", .tags(.A03))
    func replaceKeepsIdentity() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let newAPI = try TargetFiles.folder(f.targets, "new-api")
            let before = try await f.harness.store.currentSnapshot(projectID: f.project).node(f.backend)
            let revisions = try await revisionCount(f)

            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: newAPI).get()
            #expect(preview.oldPath == f.legacy.standardizedFileURL.path)
            #expect(preview.newPath == newAPI.standardizedFileURL.path)
            #expect(preview.identity == .differentTarget)

            let (summary, snapshot) = try #require(try await f.replacement.confirm(preview).committed)
            #expect(summary.cause == .edited(.replaceTarget))
            #expect(try await revisionCount(f) == revisions + 1)
            let after = try #require(snapshot.node(f.backend))
            let original = try #require(before)
            #expect(after.displayName == original.displayName && after.parentID == original.parentID && after.sortIndex == original.sortIndex)
            #expect(after.referenceID != original.referenceID)
            #expect(after.recordedPath == newAPI.standardizedFileURL.path)
            let afterReference = try #require(after.referenceID)
            let reference = try #require(try await f.harness.store.reference(afterReference))
            #expect(reference.initialPath == newAPI.standardizedFileURL.path)
            #expect(canonical(try BookmarkAdapter(system: FoundationBookmarkSystem()).resolve(reference.bookmarkData).url) == canonical(newAPI))
        }
    }

    @Test("[W09-previous-revision-keeps-target] 교체 전 revision은 기존 대상을 그대로 가진다", .tags(.A03))
    func previousRevisionKeepsTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let previous = try #require(try await f.harness.store.revisionSummaries(projectID: f.project).last)
            let old = try #require(try await f.harness.store.currentSnapshot(projectID: f.project).node(f.backend))
            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: try TargetFiles.folder(f.targets, "new-api")).get()
            _ = try #require(try await f.replacement.confirm(preview).committed)

            let past = try #require(try await f.harness.store.snapshot(revisionID: previous.id).node(f.backend))
            #expect(past.referenceID == old.referenceID)
            #expect(past.recordedPath == f.legacy.standardizedFileURL.path)
            let oldReferenceID = try #require(old.referenceID)
            let oldReference = try #require(try await f.harness.store.reference(oldReferenceID))
            #expect(canonical(try BookmarkAdapter(system: FoundationBookmarkSystem()).resolve(oldReference.bookmarkData).url) == canonical(f.legacy))
        }
    }

    @Test("[W09-same-target-unchanged] 같은 대상을 다시 고르면 같은 대상이라고 알리고 아무것도 기록하지 않는다", .tags(.A03))
    func sameTargetUnchanged() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let state = try await counts(f)

            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: f.legacy).get()
            #expect(preview.identity == .sameTarget)
            #expect(try await f.replacement.confirm(preview) == .unchanged)
            #expect(try await counts(f) == state)
        }
    }

    @Test("[W09-renamed-original-same-target] 같은 볼륨 안에서 이름을 바꾼 기존 대상을 고르면 같은 대상이다", .tags(.A03))
    func renamedOriginalIsSameTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let renamed = f.targets.appending(path: "legacy-api-renamed")
            try FileManager.default.moveItem(at: f.legacy, to: renamed)

            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: renamed).get()

            #expect(preview.identity == .sameTarget)
        }
    }

    @Test("[W09-undetermined-warns-then-replaces] 기존 대상을 찾을 수 없으면 판정 불가로 알리고, 확정하면 교체로 기록한다", .tags(.A03))
    func undeterminedWarnsThenReplaces() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            try FileManager.default.removeItem(at: f.legacy)
            let newAPI = try TargetFiles.folder(f.targets, "new-api")
            let old = try #require(try await f.harness.store.currentSnapshot(projectID: f.project).node(f.backend))

            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: newAPI).get()
            #expect(preview.identity == .undetermined)
            #expect(preview.willRecordAsReplacement)

            let (_, snapshot) = try #require(try await f.replacement.confirm(preview).committed)
            #expect(snapshot.node(f.backend)?.referenceID != old.referenceID)
        }
    }

    enum Invalid: String, CaseIterable, Sendable { case kindMismatch, group, newTargetGone, archived, nodeRemoved }

    @Test("[W09-invalid-requests-record-nothing] 교체할 수 없는 요청은 아무것도 기록하지 않는다", arguments: Invalid.allCases)
    func invalidRequestsRecordNothing(invalid: Invalid) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let newAPI = try TargetFiles.folder(f.targets, "new-api")
            let apiFile = try TargetFiles.file(f.targets, "api.md")
            let state = try await counts(f)

            switch invalid {
            case .kindMismatch:
                let result = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: apiFile)
                #expect(result == .failure(.commit(.edit(.targetKindMismatch))))
            case .group:
                let result = try await f.replacement.preview(projectID: f.project, nodeID: f.group, newURL: newAPI)
                #expect(result == .failure(.commit(.edit(.notLinkedItem))))
            case .newTargetGone, .archived, .nodeRemoved:
                let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: newAPI).get()
                let expected: ReplacementRejection
                switch invalid {
                case .newTargetGone:
                    try FileManager.default.removeItem(at: newAPI)
                    expected = .unreachableTarget
                case .archived:
                    try await f.harness.store.setArchived(f.project, at: date(100))
                    expected = .commit(.archived)
                default:
                    _ = try await f.harness.service.apply(.remove(f.backend), to: f.project)
                    expected = .commit(.edit(.nodeNotFound))
                }
                let base = try await counts(f)
                #expect(try await f.replacement.confirm(preview) == .rejected(expected))
                #expect(try await counts(f) == base)
                return
            }
            #expect(try await counts(f) == state)
        }
    }

    @Test("[W09-identity-rechecked-on-confirm] 확정할 때 같은 대상인지 다시 판정한다")
    func identityRecheckedOnConfirm() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let newAPI = try TargetFiles.folder(f.targets, "new-api")
            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: newAPI).get()
            #expect(preview.identity == .differentTarget)
            try FileManager.default.removeItem(at: newAPI)
            try FileManager.default.moveItem(at: f.legacy, to: newAPI)
            let state = try await counts(f)

            #expect(try await f.replacement.confirm(preview) == .unchanged)
            #expect(try await counts(f) == state)
        }
    }

    @Test("[W09-save-failure-no-change] 저장이 실패하면 교체가 남지 않는다", .tags(.A13))
    func saveFailureLeavesNoChange() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: try TargetFiles.folder(f.targets, "new-api")).get()
            let state = try await counts(f)
            let node = try await f.harness.store.currentSnapshot(projectID: f.project).node(f.backend)
            f.harness.fault.failNext()

            await #expect(throws: ConfigurationServiceError.saveFailed) { try await f.replacement.confirm(preview) }
            #expect(try await counts(f) == state)
            #expect(try await f.harness.store.currentSnapshot(projectID: f.project).node(f.backend) == node)
        }
    }

    @Test("[W09-replace-with-target-linked-elsewhere] 다른 Bishop이 이미 연결한 대상으로도 교체할 수 있고 서로 영향을 주지 않는다")
    func replaceWithTargetLinkedElsewhere() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let newAPI = try TargetFiles.folder(f.targets, "new-api")
            let linked = try #require(try await f.harness.linking.link(LinkRequest(projectID: f.project, parentID: nil, position: nil, urls: [newAPI])).committed)
            let api = try #require(linked.snapshot.node(named: "new-api"))
            let apiReferenceID = try #require(api.referenceID)
            let apiReference = try await f.harness.store.reference(apiReferenceID)

            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: newAPI).get()
            let (_, snapshot) = try #require(try await f.replacement.confirm(preview).committed)

            #expect(snapshot.node(f.backend)?.referenceID != api.referenceID)
            #expect(snapshot.node(api.id) == api)
            #expect(try await f.harness.store.reference(apiReferenceID) == apiReference)
        }
    }

    @Test("[W09-targets-untouched] 교체는 기존 대상과 새 대상 파일을 바꾸지 않는다")
    func targetsUntouched() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let f = try await fixture(directory)
            let newAPI = try TargetFiles.folder(f.targets, "new-api")
            _ = try TargetFiles.file(newAPI, "inner.swift")
            let before = try fingerprint(f.targets)

            let preview = try await f.replacement.preview(projectID: f.project, nodeID: f.backend, newURL: newAPI).get()
            _ = try #require(try await f.replacement.confirm(preview).committed)

            #expect(try fingerprint(f.targets) == before)
        }
    }

    // MARK: 도우미

    struct Counts: Equatable {
        var revisions: Int
        var references: Int
    }

    private func counts(_ f: Fixture) async throws -> Counts {
        Counts(revisions: try await revisionCount(f), references: try await f.harness.store.referenceCount())
    }

    private func revisionCount(_ f: Fixture) async throws -> Int {
        try await f.harness.store.revisionSummaries(projectID: f.project).count
    }

    private func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    private func fingerprint(_ root: URL) throws -> [String] {
        let paths = (FileManager.default.enumerator(atPath: root.path)?.compactMap { $0 as? String } ?? []).sorted()
        return try paths.map { path in
            let attributes = try FileManager.default.attributesOfItem(atPath: root.appending(path: path).path)
            return "\(path)|\(attributes[.modificationDate] ?? "")|\(attributes[.posixPermissions] ?? "")"
        }
    }
}

extension ReplacementOutcome {
    var committed: (summary: RevisionSummary, snapshot: ConfigurationSnapshot)? {
        if case let .committed(summary, snapshot) = self { (summary, snapshot) } else { nil }
    }
}
