import Foundation
import SwiftData
import Testing
@testable import Fianchetto

@Suite("Bishop 연결 서비스 (W08)")
struct LinkingServiceTests {
    @Test("[W08-link-multiple-one-revision] 여러 위치의 파일·폴더를 한 작업으로 선택 순서대로 연결한다", .tags(.A02))
    func linkMultipleTargets() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let targets = directory.appending(path: "targets")
            let urls = [
                try TargetFiles.file(targets, "docs/design.md"),
                try TargetFiles.folder(targets, "media/assets"),
                try TargetFiles.file(targets, "misc/notes.txt"),
            ]
            let project = try await makeBoard(harness)
            let group = try await addGroup(harness, project)
            let before = try await harness.store.revisionSummaries(projectID: project).count

            let outcome = try await harness.linking.link(LinkRequest(projectID: project, parentID: group, position: nil, urls: urls))

            let (_, snapshot) = try #require(outcome.committed)
            #expect(try await harness.store.revisionSummaries(projectID: project).count == before + 1)
            let children = snapshot.nodes.filter { $0.parentID == group }.sorted { $0.sortIndex < $1.sortIndex }
            #expect(children.map(\.displayName) == ["design.md", "assets", "notes.txt"])
            #expect(children.map(\.kind) == [.file, .folder, .file])
            #expect(children.map(\.recordedPath) == urls.map { $0.standardizedFileURL.path })
            let adapter = BookmarkAdapter(system: FoundationBookmarkSystem())
            for (node, url) in zip(children, urls) {
                let referenceID = try #require(node.referenceID)
                let reference = try #require(try await harness.store.reference(referenceID))
                #expect(canonical(try adapter.resolve(reference.bookmarkData).url) == canonical(url))
            }
            try harness.reopened { store throws in
                for (node, url) in zip(children, urls) {
                    let referenceID = try #require(node.referenceID)
                    let reference = try #require(try store.reference(referenceID))
                    #expect(canonical(try adapter.resolve(reference.bookmarkData).url) == canonical(url))
                }
            }
        }
    }

    @Test("[W08-package-as-file] 패키지 폴더는 Bishop 파일로 연결한다")
    func packageIsLinkedAsFile() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let package = try TargetFiles.folder(directory, "targets/Deck.key")
            let project = try await makeBoard(harness)

            let outcome = try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [package]))

            #expect(try #require(outcome.committed).snapshot.node(named: "Deck.key")?.kind == .file)
        }
    }

    @Test("[W08-same-target-twice-no-merge] 같은 대상을 한 번에 두 번 고르면 서로 다른 Bishop 두 개가 된다")
    func sameTargetTwice() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let file = try TargetFiles.file(directory, "targets/design.md")
            let project = try await makeBoard(harness)

            let outcome = try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [file, file]))

            let nodes = try #require(outcome.committed).snapshot.nodes.filter { $0.displayName == "design.md" }
            #expect(nodes.count == 2)
            #expect(Set(nodes.map(\.id)).count == 2)
            #expect(Set(nodes.compactMap(\.referenceID)).count == 2)
        }
    }

    @Test("[W08-relink-creates-new-bishop] 이미 연결된 대상을 다시 연결하면 별도 Bishop을 만든다")
    func relinkCreatesNewBishop() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let file = try TargetFiles.file(directory, "targets/design.md")
            let project = try await makeBoard(harness)
            let group = try await addGroup(harness, project)
            let first = try #require(try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [file])).committed)
            let existing = try #require(first.snapshot.node(named: "design.md"))

            let second = try #require(try await harness.linking.link(LinkRequest(projectID: project, parentID: group, position: nil, urls: [file])).committed)

            let linked = second.snapshot.nodes.filter { $0.displayName == "design.md" }
            #expect(linked.count == 2)
            let added = try #require(linked.first { $0.id != existing.id })
            #expect(added.parentID == group)
            #expect(added.referenceID != existing.referenceID)
            #expect(second.snapshot.node(existing.id) == existing)
        }
    }

    @Test("[W08-empty-selection-unchanged] 고른 대상이 없으면 아무것도 기록하지 않는다")
    func emptySelection() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let project = try await makeBoard(harness)

            #expect(try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [])) == .unchanged)
            #expect(try await harness.store.revisionSummaries(projectID: project).count == 1)
            #expect(try await harness.store.referenceCount() == 0)
        }
    }

    enum Failure: String, CaseIterable, Sendable { case injected, deleted }

    @Test("[W08-bookmark-failure-all-or-nothing] 대상 하나라도 북마크를 만들지 못하면 아무것도 연결하지 않고 다시 시도할 수 있다", arguments: Failure.allCases)
    func bookmarkFailureIsAllOrNothing(failure: Failure) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let design = try TargetFiles.file(directory, "targets/design.md")
            let notes = try TargetFiles.file(directory, "targets/notes.txt")
            let project = try await makeBoard(harness)
            switch failure {
            case .injected: harness.bookmarks.fail(["notes.txt"], times: 1)
            case .deleted: try FileManager.default.removeItem(at: notes)
            }
            let request = LinkRequest(projectID: project, parentID: nil, position: nil, urls: [design, notes])

            #expect(try await harness.linking.link(request) == .rejected(.unreachableTargets(["notes.txt"])))
            #expect(try await harness.store.revisionSummaries(projectID: project).count == 1)
            #expect(try await harness.store.referenceCount() == 0)
            #expect(try await harness.store.currentSnapshot(projectID: project).nodes.isEmpty)

            if failure == .deleted { _ = try TargetFiles.file(directory, "targets/notes.txt") }
            let retried = try #require(try await harness.linking.link(request).committed)
            #expect(retried.summary.sequence == 2)
            #expect(retried.snapshot.nodes.map(\.displayName).sorted() == ["design.md", "notes.txt"])
        }
    }

    @Test("[W08-multiple-failures-reported] 여러 대상이 실패하면 실패한 대상을 모두 알려 준다")
    func multipleFailuresAreReported() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let urls = try ["a.md", "b.md", "c.md"].map { try TargetFiles.file(directory, "targets/\($0)") }
            try FileManager.default.removeItem(at: urls[0])
            try FileManager.default.removeItem(at: urls[2])
            let project = try await makeBoard(harness)

            let outcome = try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: urls))

            #expect(outcome == .rejected(.unreachableTargets(["a.md", "c.md"])))
            #expect(try await harness.store.revisionSummaries(projectID: project).count == 1)
            #expect(try await harness.store.referenceCount() == 0)
        }
    }

    @Test("[W08-targets-untouched] 연결은 대상 파일과 폴더를 바꾸지 않는다", .tags(.A02))
    func targetsAreUntouched() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let targets = directory.appending(path: "targets")
            let file = try TargetFiles.file(targets, "design.md")
            let folder = try TargetFiles.folder(targets, "assets")
            _ = try TargetFiles.file(folder, "inner.png")
            let before = try fingerprint(targets)
            let project = try await makeBoard(harness)

            _ = try #require(try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [file, folder])).committed)

            #expect(try fingerprint(targets) == before)
        }
    }

    @Test("[W08-save-failure-nothing-left] 저장이 실패하면 연결이 하나도 남지 않는다", .tags(.A13))
    func saveFailureLeavesNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let file = try TargetFiles.file(directory, "targets/design.md")
            let project = try await makeBoard(harness)
            harness.fault.failNext()

            await #expect(throws: ConfigurationServiceError.saveFailed) {
                try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [file]))
            }
            #expect(try await harness.store.revisionSummaries(projectID: project).count == 1)
            #expect(try await harness.store.referenceCount() == 0)
            #expect(try await harness.store.currentSnapshot(projectID: project).nodes.isEmpty)
        }
    }

    @Test("[W08-archived-rejected] 보관된 Board에는 연결할 수 없다")
    func archivedBoardIsRejected() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let file = try TargetFiles.file(directory, "targets/design.md")
            let project = try await makeBoard(harness, "옛 프로젝트")
            try await harness.store.setArchived(project, at: date(100))

            let outcome = try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [file]))

            #expect(outcome == .rejected(.commit(.archived)))
            #expect(harness.bookmarks.creationOnMainThread.isEmpty)
        }
    }

    @Test("[W08-bookmarks-off-main] 북마크 생성은 메인 스레드 밖에서 한다")
    @MainActor
    func bookmarksAreCreatedOffMain() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let file = try TargetFiles.file(directory, "targets/design.md")
            let project = try await makeBoard(harness)

            _ = try await harness.linking.link(LinkRequest(projectID: project, parentID: nil, position: nil, urls: [file]))

            #expect(harness.bookmarks.creationOnMainThread == [false])
        }
    }

    // MARK: 도우미

    private func addGroup(_ harness: ServiceHarness, _ project: UUID) async throws -> UUID {
        let committed = try #require(try await harness.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: project).committed)
        return try #require(committed.snapshot.node(named: "개발")).id
    }

    private func canonical(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    struct Entry: Equatable {
        var path: String
        var contents: Data?
        var modified: Date?
        var permissions: Int?
    }

    private func fingerprint(_ root: URL) throws -> [Entry] {
        let paths = (FileManager.default.enumerator(atPath: root.path)?.compactMap { $0 as? String } ?? []).sorted()
        return try paths.map { path in
            let url = root.appending(path: path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let isFile = (attributes[.type] as? FileAttributeType) == .typeRegular
            return Entry(
                path: path, contents: isFile ? try Data(contentsOf: url) : nil,
                modified: attributes[.modificationDate] as? Date, permissions: attributes[.posixPermissions] as? Int
            )
        }
    }
}

extension LinkOutcome {
    var committed: (summary: RevisionSummary, snapshot: ConfigurationSnapshot)? {
        if case let .committed(summary, snapshot) = self { (summary, snapshot) } else { nil }
    }
}
