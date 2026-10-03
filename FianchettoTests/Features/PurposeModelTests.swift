import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("Bishop 용도 고르기 화면 (W29)")
struct PurposeModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        var model: BoardBrowserModel { harness.model }

        func id(_ name: String) throws -> UUID { try #require(model.loadedSnapshot?.node(named: name)).id }
        func node(_ name: String) throws -> ConfigurationNode { try #require(model.loadedSnapshot?.node(named: name)) }
        func summaries() async throws -> [RevisionSummary] {
            try await model.openedStore!.store.revisionSummaries(projectID: project)
        }
    }

    nonisolated static let purposeRevisionID = UUID(uuidString: "00000000-0000-0000-0000-00000000AB29")!

    /// 최상위: Bishop 파일 "README.md", Bishop 폴더 "backend", 웹 링크 "API 명세", Wing "개발".
    private func opened(_ directory: URL, archived: Bool = false, readmePurpose: String? = nil) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let readme = try TargetFiles.file(directory, "targets/README.md")
        let backend = try TargetFiles.folder(directory, "targets/backend")
        var project = UUID()
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            project = board
            let linked = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [readme, backend]))
            _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: board)
            _ = try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board)
            if let readmePurpose, case let .committed(_, snapshot) = linked, let node = snapshot.node(named: "README.md") {
                // 모르는 키도 넣을 수 있게 편집 연산을 거치지 않고 다음 revision으로 직접 기록한다.
                var next = try await seed.store.currentSnapshot(projectID: board)
                let index = try #require(next.nodes.firstIndex { $0.id == node.id })
                next.nodes[index].purpose = readmePurpose
                let recorded = next
                _ = try await seed.store.appendRevision(to: board) { _ -> AppendDecision<Bool> in
                    .append(RevisionAppend(id: Self.purposeRevisionID, recordedAt: date(50), cause: .edited(.changePurpose), snapshot: recorded, references: []))
                }
            }
            if archived { try await seed.store.setArchived(board, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(project)
        return Opened(harness: harness, project: project)
    }

    // MARK: 고르기와 기록

    @Test("[W29-pick-purpose] 용도를 고르면 changePurpose revision 하나가 남고 기호·접근성 라벨이 바뀐다", .tags(.A04), arguments: [
        BishopPurpose.data, .document, .code,
    ])
    func pickPurpose(purpose: BishopPurpose) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("README.md")
            #expect(o.model.canSetPurposeOfSelected)
            let before = try await o.summaries().count

            await o.model.setPurposeOfSelected(purpose)

            let summaries = try await o.summaries()
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(.changePurpose))
            let node = try o.node("README.md")
            #expect(node.purpose == purpose.rawValue)
            #expect(o.model.selectedPurpose == purpose)
            #expect(TileIcon.of(node, style: .symbol) == .bishop(purpose: purpose))
            #expect(o.model.accessibilityLabel(for: node).contains(o.model.purposeText(purpose)))
        }
    }

    @Test("[W29-history-keeps-old-purpose] 용도를 바꿔도 직전 revision은 이전 용도를 그대로 가진다", .tags(.A04))
    func historyKeepsOldPurpose() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, readmePurpose: "document")
            o.model.selectedNodeID = try o.id("README.md")
            let previous = try #require(try await o.summaries().last)

            await o.model.setPurposeOfSelected(.presentation)

            #expect(try o.node("README.md").purpose == "presentation")
            let old = try await o.model.openedStore!.store.snapshot(revisionID: previous.id)
            #expect(old.node(named: "README.md")?.purpose == "document")
        }
    }

    @Test("[W29-pick-default] 기본을 고르면 용도가 없어지고 revision이 남는다")
    func pickDefault() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, readmePurpose: "document")
            o.model.selectedNodeID = try o.id("README.md")
            let before = try await o.summaries().count

            await o.model.setPurposeOfSelected(nil)

            #expect(try await o.summaries().count == before + 1)
            #expect(try o.node("README.md").purpose == nil)
            #expect(TileIcon.of(try o.node("README.md"), style: .symbol) == .bishop(purpose: nil))
        }
    }

    @Test("[W29-pick-same] 같은 용도를 다시 고르면 기록하지 않는다")
    func pickSame() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, readmePurpose: "document")
            o.model.selectedNodeID = try o.id("README.md")
            let before = try await o.summaries().count
            await o.model.setPurposeOfSelected(.document)
            #expect(try await o.summaries().count == before)
        }
    }

    @Test("[W29-pick-cancel] 고르는 곳을 열었다 닫기만 하면 기록하지 않는다", .tags(.A04))
    func pickCancel() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("README.md")
            let before = try await o.summaries().count
            // 메뉴를 여는 것만으로는 모델에 아무 요청도 가지 않는다(체크 표시를 읽기만 한다).
            _ = o.model.selectedPurpose
            _ = o.model.canSetPurposeOfSelected
            #expect(try await o.summaries().count == before)
            #expect(try o.node("README.md").purpose == nil)
        }
    }

    @Test("[W29-save-failure] 용도 저장 실패는 안내하고 값·체크·기호를 이전 그대로 둔다")
    func saveFailure() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("README.md")
            let before = try await o.summaries().count
            o.harness.fault.failNext()

            await o.model.setPurposeOfSelected(.image)

            #expect(o.model.linkNotice?.kind == .saveFailed)
            #expect(try await o.summaries().count == before)
            #expect(try o.node("README.md").purpose == nil)
            #expect(o.model.selectedPurpose == nil)
            #expect(TileIcon.of(try o.node("README.md"), style: .symbol) == .bishop(purpose: nil))
        }
    }

    @Test("[W29-archived-service-reject] 보관된 Board의 용도 변경 요청은 archived로 거부되고 안내한다")
    func archivedServiceReject() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            let readme = try o.id("README.md")
            let before = try await o.summaries().count

            await o.model.requestPurpose(readme, "document")

            #expect(o.model.linkNotice?.kind == .archived)
            #expect(try await o.summaries().count == before)
        }
    }

    enum Disabled: String, CaseIterable, Sendable { case archived, wing, webLink, none }

    @Test("[W29-pick-disabled] 보관된 Board·Wing·웹 링크·선택 없음에서는 고르는 곳이 꺼진다", arguments: Disabled.allCases)
    func pickDisabled(state: Disabled) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: state == .archived)
            o.model.selectedNodeID = switch state {
            case .archived: try o.id("README.md")
            case .wing: try o.id("개발")
            case .webLink: try o.id("API 명세")
            case .none: nil
            }
            #expect(!o.model.canSetPurposeOfSelected)
            let before = try await o.summaries().count
            await o.model.setPurposeOfSelected(.document)
            #expect(try await o.summaries().count == before)
        }
    }

    @Test("[W29-pick-checkmark] 고르는 곳은 지금 용도에 체크 표시를 한다")
    func checkmark() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, readmePurpose: "reference")
            o.model.selectedNodeID = try o.id("README.md")
            #expect(o.model.selectedPurpose == .reference)
            #expect(o.model.inspector?.purpose == "참고")
        }
    }

    @Test("[W29-unknown-key-display] 모르는 용도 키는 기본으로 보이고 기본을 고르면 키가 없어지며 revision이 남는다")
    func unknownKeyDisplay() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, readmePurpose: "music")
            let node = try o.node("README.md")
            o.model.selectedNodeID = node.id
            #expect(TileIcon.of(node, style: .symbol) == .bishop(purpose: nil))
            #expect(o.model.selectedPurpose == nil)
            #expect(o.model.inspector?.purpose == "기본")
            #expect(o.model.accessibilityLabel(for: node) == "README.md, Bishop")
            let before = try await o.summaries().count

            await o.model.setPurposeOfSelected(nil)

            #expect(try o.node("README.md").purpose == nil)
            let summaries = try await o.summaries()
            #expect(summaries.count == before + 1)
            #expect(summaries.last?.cause == .edited(.changePurpose))
        }
    }

    // MARK: 기호와 문구

    @Test("[W29-tile-icon] 기호 설정에서는 용도 배지를 그리고, 폴더는 용도가 폴더 배지를 대신하며, 파일 종류 설정에서는 배지를 그리지 않는다")
    func tileIcon() {
        let file = ConfigurationNode(id: UUID(), kind: .file, displayName: "README.md", sortIndex: 0, recordedPath: "/README.md", purpose: "document")
        let plainFile = ConfigurationNode(id: UUID(), kind: .file, displayName: "README.md", sortIndex: 0, recordedPath: "/README.md")
        let folder = ConfigurationNode(id: UUID(), kind: .folder, displayName: "backend", sortIndex: 0, recordedPath: "/backend")
        let codeFolder = ConfigurationNode(id: UUID(), kind: .folder, displayName: "backend", sortIndex: 0, recordedPath: "/backend", purpose: "code")
        #expect(TileIcon.of(plainFile, style: .symbol) == .bishop(purpose: nil))
        #expect(TileIcon.of(file, style: .symbol) == .bishop(purpose: .document))
        #expect(TileIcon.of(folder, style: .symbol) == .bishopFolder)
        #expect(TileIcon.of(codeFolder, style: .symbol) == .bishop(purpose: .code))
        #expect(TileIcon.of(file, style: .fileType) == .fileType(identifier: TileIcon.typeIdentifier(forExtension: "md")))
    }

    @Test("[W29-kind-text] 파일 Bishop은 Bishop, 폴더 Bishop은 Bishop · 폴더다")
    func kindText() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(o.model.kindText(for: try o.node("README.md")) == "Bishop")
            #expect(o.model.kindText(for: try o.node("backend")) == "Bishop · 폴더")
            o.model.selectedNodeID = try o.id("backend")
            #expect(o.model.inspector?.kind == "Bishop · 폴더")
        }
    }

    @Test("[W29-purpose-visible-in-file-type] 파일 종류 아이콘 설정에서도 용도는 인스펙터와 접근성 라벨에 보인다")
    func purposeVisibleInFileType() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, readmePurpose: "document")
            o.model.bishopIconStyle = .fileType
            let node = try o.node("README.md")
            o.model.selectedNodeID = node.id
            #expect(o.model.inspector?.purpose == "문서")
            #expect(o.model.accessibilityLabel(for: node).contains("문서"))
        }
    }

    @Test("[W29-catalog] 용도 문구는 18.2 표 순서와 같다")
    func purposeTexts() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            #expect(([nil] + BishopPurpose.allCases).map(o.model.purposeText) == ["기본", "문서", "데이터", "이미지", "코드", "참고", "발표", "할 일", "디자인"])
        }
    }
}
