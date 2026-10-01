import Foundation
import Testing
@testable import Fianchetto

@Suite("구성 편집 연산 (W03)")
struct ConfigurationEditorTests {
    typealias F = SnapshotFixtures
    let s = SnapshotFixtures.serviceA()
    let missing = fixedID(404)

    // MARK: 프로젝트 이름

    @Test("[W03-rename-project] 프로젝트 이름을 바꾸면 이름만 다른 새 스냅샷이 된다")
    func renameProject() throws {
        let result = try #require(apply(.renameProject("  서비스 B "), to: s).snapshot)

        #expect(result.projectName == "서비스 B")
        #expect(result.nodes == s.nodes)
    }

    @Test("[W03-rename-project-unchanged] 같은 프로젝트 이름으로 확정하면 무변경이다", .tags(.A04))
    func renameProjectUnchanged() {
        #expect(apply(.renameProject(" 서비스 A "), to: s) == .unchanged)
    }

    @Test("[W03-rename-project-blank-rejected] 빈 프로젝트 이름은 거부한다")
    func renameProjectBlank() {
        #expect(apply(.renameProject("   "), to: s) == .rejected(.blankName))
    }

    // MARK: 그룹 추가

    @Test("[W03-add-group-appends] 위치를 지정하지 않은 그룹은 부모의 마지막에 추가한다")
    func addGroupAppends() throws {
        let result = try #require(apply(.addGroup(name: "에셋", parentID: nil, position: nil), to: s).snapshot)

        let added = try #require(result.node(SequentialIDs.new(1)))
        #expect(added.kind == .group)
        #expect(added.displayName == "에셋")
        #expect(added.parentID == nil)
        #expect(added.sortIndex == 2)
        #expect(added.referenceID == nil && added.recordedPath == nil && added.url == nil)
        #expect(Set(result.nodes.filter { $0.id != added.id }) == Set(s.nodes))
    }

    @Test("[W03-add-group-at-position] 위치를 지정한 그룹 추가는 뒤쪽 형제의 정렬 순서를 하나씩 민다")
    func addGroupAtPosition() throws {
        let result = try #require(apply(.addGroup(name: "공통", parentID: F.development, position: 0), to: s).snapshot)

        #expect(result.children(of: F.development) == ["공통", "backend", "설계 메모"])
    }

    @Test("[W03-add-group-rejected] 그룹 추가를 거부하는 경우", arguments: [
        (fixedID(2) as UUID?, "에셋", nil as Int?, EditRejection.parentNotGroup),
        (fixedID(4), "에셋", nil, .parentNotGroup),
        (fixedID(404), "에셋", nil, .nodeNotFound),
        (nil, "  ", nil, .blankName),
        (nil, "에셋", 3, .invalidPosition),
        (nil, "에셋", -1, .invalidPosition),
    ])
    func addGroupRejected(parent: UUID?, name: String, position: Int?, reason: EditRejection) {
        #expect(apply(.addGroup(name: name, parentID: parent, position: position), to: s) == .rejected(reason))
    }

    // MARK: 연결 파일·폴더 일괄 추가

    @Test("[W03-add-linked-items-batch] 여러 연결 대상을 한 작업으로 선택 순서대로 추가한다")
    func addLinkedItemsInSelectionOrder() throws {
        let targets = [
            LinkedTarget(displayName: "assets", kind: .folder, path: "/design/assets"),
            LinkedTarget(displayName: "회의록", kind: .file, path: "/notes/meeting.md"),
            LinkedTarget(displayName: "docs", kind: .folder, path: "/docs"),
        ]

        let result = try #require(apply(.addLinkedItems(targets, parentID: F.development, position: nil), to: s).snapshot)

        let expected: [(String, NodeKind, Int, Int, String)] = [
            ("assets", .folder, 1, 2, "/design/assets"),
            ("회의록", .file, 3, 3, "/notes/meeting.md"),
            ("docs", .folder, 5, 4, "/docs"),
        ]
        for (name, kind, idNumber, order, path) in expected {
            let node = try #require(result.node(SequentialIDs.new(idNumber)))
            #expect(node.displayName == name)
            #expect(node.kind == kind)
            #expect(node.referenceID == SequentialIDs.new(idNumber + 1))
            #expect(node.sortIndex == order)
            #expect(node.recordedPath == path)
            #expect(node.parentID == F.development)
        }
    }

    @Test("[W03-add-linked-items-all-or-nothing] 일괄 추가 중 하나라도 유효하지 않으면 아무것도 추가하지 않는다")
    func addLinkedItemsAllOrNothing() {
        let targets = [
            LinkedTarget(displayName: "assets", kind: .folder, path: "/design/assets"),
            LinkedTarget(displayName: "   ", kind: .file, path: "/notes/meeting.md"),
        ]

        #expect(apply(.addLinkedItems(targets, parentID: F.development, position: nil), to: s) == .rejected(.blankName))
    }

    @Test("[W03-add-linked-items-invalid-path] 일괄 추가 대상의 경로가 절대 경로가 아니면 아무것도 추가하지 않는다")
    func addLinkedItemsInvalidPath() {
        let targets = [
            LinkedTarget(displayName: "assets", kind: .folder, path: "/design/assets"),
            LinkedTarget(displayName: "회의록", kind: .file, path: "notes/meeting.md"),
        ]

        #expect(apply(.addLinkedItems(targets, parentID: F.development, position: nil), to: s) == .rejected(.invalidPath))
    }

    @Test("[W03-add-linked-items-rejected] 일괄 추가는 선택 순서상 첫 대상의 사유를 돌려준다")
    func addLinkedItemsFirstTargetReasonWins() {
        let targets = [
            LinkedTarget(displayName: "assets", kind: .folder, path: "design/assets"),
            LinkedTarget(displayName: "   ", kind: .file, path: "/notes/meeting.md"),
        ]

        #expect(apply(.addLinkedItems(targets, parentID: F.development, position: nil), to: s) == .rejected(.invalidPath))
    }

    @Test("[W03-add-linked-items-rejected] 일괄 추가를 거부하는 경우", arguments: [
        (fixedID(2) as UUID?, nil as Int?, EditRejection.parentNotGroup),
        (fixedID(4), nil, .parentNotGroup),
        (fixedID(404), nil, .nodeNotFound),
        (fixedID(1), 3, .invalidPosition),
    ])
    func addLinkedItemsRejected(parent: UUID?, position: Int?, reason: EditRejection) {
        let targets = [LinkedTarget(displayName: "assets", kind: .folder, path: "/design/assets")]

        #expect(apply(.addLinkedItems(targets, parentID: parent, position: position), to: s) == .rejected(reason))
    }

    @Test("[W03-add-linked-items-empty-unchanged] 추가할 대상이 없으면 무변경이다", .tags(.A04))
    func addNoLinkedItems() {
        #expect(apply(.addLinkedItems([], parentID: F.development, position: nil), to: s) == .unchanged)
    }

    @Test("[W03-add-linked-items-no-merge] 기존 항목과 같은 이름·같은 경로의 대상도 별도 Node로 추가한다")
    func addLinkedItemDoesNotMerge() throws {
        let target = LinkedTarget(displayName: "backend", kind: .folder, path: "/dev/legacy-api")

        let result = try #require(apply(.addLinkedItems([target], parentID: F.development, position: nil), to: s).snapshot)

        let backends = result.nodes.filter { $0.parentID == F.development && $0.displayName == "backend" }
        #expect(backends.count == 2)
        #expect(Set(backends.map(\.id)).count == 2)
        #expect(Set(backends.compactMap(\.referenceID)).count == 2)
    }

    // MARK: 웹 링크

    @Test("[W03-add-web-link] 웹 링크를 추가한다")
    func addWebLink() throws {
        let result = try #require(
            apply(.addWebLink(name: "디자인 시안", url: " https://figma.com/file/1 ", parentID: nil, position: nil), to: s).snapshot
        )

        let link = try #require(result.node(SequentialIDs.new(1)))
        #expect(link.kind == .webLink)
        #expect(link.url == "https://figma.com/file/1")
        #expect(link.sortIndex == 2)
    }

    @Test("[W03-add-web-link-rejected] 웹 링크 추가를 거부하는 경우", arguments: [
        (nil as UUID?, "디자인 시안", "ftp://example.com", nil as Int?, EditRejection.invalidURL),
        (nil, "디자인 시안", "", nil, .invalidURL),
        (nil, "디자인 시안", "example.com", nil, .invalidURL),
        (nil, "   ", "https://figma.com", nil, .blankName),
        (fixedID(2), "디자인 시안", "https://figma.com", nil, .parentNotGroup),
        (fixedID(4), "디자인 시안", "https://figma.com", nil, .parentNotGroup),
        (fixedID(404), "디자인 시안", "https://figma.com", nil, .nodeNotFound),
        (fixedID(2), "   ", "ftp://example.com", nil, .parentNotGroup),
        (nil, "   ", "ftp://example.com", nil, .blankName),
        (nil, "디자인 시안", "https://figma.com", 3, .invalidPosition),
    ])
    func addWebLinkRejected(parent: UUID?, name: String, url: String, position: Int?, reason: EditRejection) {
        #expect(apply(.addWebLink(name: name, url: url, parentID: parent, position: position), to: s) == .rejected(reason))
    }

    @Test("[W03-change-url] 웹 링크 URL을 바꾼다", .tags(.A04))
    func changeURL() throws {
        let result = try #require(apply(.changeURL(F.apiSpec, "https://example.com/v2"), to: s).snapshot)

        #expect(result.node(F.apiSpec)?.url == "https://example.com/v2")
        #expect(result.node(F.apiSpec)?.displayName == "API 명세")
    }

    @Test("[W03-change-url] URL 변경의 무변경과 거부", .tags(.A04), arguments: [
        (fixedID(4), " https://example.com/api ", EditOutcome.unchanged),
        (fixedID(4), "ftp://example.com", .rejected(.invalidURL)),
        (fixedID(4), "", .rejected(.invalidURL)),
        (fixedID(2), "https://example.com", .rejected(.notWebLink)),
        (fixedID(404), "https://example.com", .rejected(.nodeNotFound)),
    ])
    func changeURLUnchangedOrRejected(node: UUID, url: String, expected: EditOutcome) {
        #expect(apply(.changeURL(node, url), to: s) == expected)
    }

    // MARK: 표시 이름

    @Test("[W03-rename-node-keeps-identity] 표시 이름을 바꾸면 UUID와 배치·대상은 유지된다", .tags(.A04))
    func renameNodeKeepsIdentity() throws {
        let result = try #require(apply(.renameNode(F.backend, "api"), to: s).snapshot)

        let renamed = try #require(result.node(F.backend))
        let original = try #require(s.node(F.backend))
        #expect(renamed.displayName == "api")
        #expect(renamed.parentID == original.parentID)
        #expect(renamed.sortIndex == original.sortIndex)
        #expect(renamed.referenceID == original.referenceID)
        #expect(renamed.recordedPath == original.recordedPath)
        #expect(original.displayName == "backend")
    }

    @Test("[W03-rename-node-unchanged-or-rejected] 같은 이름으로 확정하거나 빈 이름이면 기록할 변경이 없다", .tags(.A04), arguments: [
        ("backend", EditOutcome.unchanged),
        ("  backend ", .unchanged),
        ("   ", .rejected(.blankName)),
    ])
    func renameNodeUnchangedOrRejected(name: String, expected: EditOutcome) {
        #expect(apply(.renameNode(F.backend, name), to: s) == expected)
    }

    @Test("[W03-rename-node-missing-rejected] 없는 Node의 표시 이름은 바꿀 수 없다")
    func renameMissingNode() {
        #expect(apply(.renameNode(missing, "api"), to: s) == .rejected(.nodeNotFound))
    }

    // MARK: 이동과 형제 순서

    @Test("[W03-move-renumbers-siblings] 다른 그룹으로 옮기면 양쪽 형제의 정렬 순서를 빈틈없이 다시 매긴다", .tags(.A04))
    func moveRenumbersBothSides() throws {
        let result = try #require(apply(.move(F.backend, toParent: nil, position: nil), to: s).snapshot)

        #expect(result.children(of: F.development) == ["설계 메모"])
        #expect(result.children(of: nil) == ["개발", "API 명세", "backend"])
        #expect(result.node(F.backend)?.referenceID == F.backendReference)
        #expect(result.node(F.backend)?.recordedPath == "/dev/legacy-api")
    }

    @Test("[W03-move-group-keeps-descendants] 그룹을 옮기면 자손은 그 그룹과 함께 옮겨진다", .tags(.A04))
    func moveGroupKeepsDescendants() throws {
        let archive = fixedID(30)
        var base = s
        base.nodes.append(F.group(archive, "보관", order: 2))

        let result = try #require(apply(.move(F.development, toParent: archive, position: nil), to: base).snapshot)

        #expect(result.node(F.development)?.parentID == archive)
        #expect(result.node(F.backend)?.parentID == F.development)
        #expect(result.node(F.backend)?.sortIndex == 0)
        #expect(result.node(F.designNote)?.parentID == F.development)
        #expect(result.node(F.designNote)?.sortIndex == 1)
    }

    @Test("[W03-move-same-position-unchanged] 같은 부모의 같은 위치로 옮기면 무변경이다", .tags(.A04))
    func moveToSamePosition() {
        #expect(apply(.move(F.designNote, toParent: F.development, position: 1), to: s) == .unchanged)
    }

    @Test("[W03-move-rejected] 이동을 거부하는 경우", arguments: [
        (fixedID(1), fixedID(1) as UUID?, nil as Int?, EditRejection.cycle),
        (fixedID(1), fixedID(31), nil, .cycle),
        (fixedID(3), fixedID(2), nil, .parentNotGroup),
        (fixedID(3), fixedID(4), nil, .parentNotGroup),
        (fixedID(404), nil, nil, .nodeNotFound),
        (fixedID(3), nil, 5, .invalidPosition),
        (fixedID(3), fixedID(405), 9, .nodeNotFound),
        (fixedID(3), fixedID(3), nil, .parentNotGroup),
    ])
    func moveRejected(node: UUID, destination: UUID?, position: Int?, reason: EditRejection) {
        var base = s
        base.nodes.append(F.group(fixedID(31), "하위", parent: F.development, order: 2))

        #expect(apply(.move(node, toParent: destination, position: position), to: base) == .rejected(reason))
    }

    @Test("[W03-reorder-siblings] 형제 안에서 순서를 바꾸면 사이의 형제만 밀린다", .tags(.A04))
    func reorderSiblings() throws {
        let result = try #require(apply(.move(F.designNote, toParent: F.development, position: 0), to: s).snapshot)

        #expect(result.children(of: F.development) == ["설계 메모", "backend"])
        #expect(result.children(of: nil) == s.children(of: nil))
    }

    @Test("[W03-reorder-unchanged-or-rejected] 형제 순서 변경의 무변경과 거부", .tags(.A04), arguments: [
        (1, EditOutcome.unchanged),
        (2, .rejected(.invalidPosition)),
        (-1, .rejected(.invalidPosition)),
    ])
    func reorderUnchangedOrRejected(position: Int, expected: EditOutcome) {
        #expect(apply(.move(F.designNote, toParent: F.development, position: position), to: s) == expected)
    }

    // MARK: 제거

    @Test("[W03-remove-group-with-descendants] 그룹을 제거하면 자손도 함께 제거하고 남은 형제의 순서를 다시 매긴다")
    func removeGroupWithDescendants() throws {
        let result = try #require(apply(.remove(F.development), to: s).snapshot)

        #expect(Set(result.nodes.map(\.id)) == [F.apiSpec])
        #expect(result.children(of: nil) == ["API 명세"])
        #expect(Set(s.nodes.map(\.id)).isSuperset(of: [F.development, F.backend, F.designNote]))
    }

    @Test("[W03-remove-missing-rejected] 없는 Node는 제거할 수 없다")
    func removeMissing() {
        #expect(apply(.remove(missing), to: s) == .rejected(.nodeNotFound))
    }

    // MARK: 연결 대상 교체

    @Test("[W03-replace-target-new-reference] 다른 대상으로 교체하면 새 referenceID를 만들고 이름·UUID·배치는 유지한다", .tags(.A03))
    func replaceTargetCreatesNewReference() throws {
        let edit = ConfigurationEdit.replaceTarget(F.backend, kind: .folder, path: "/dev/new-api", identity: .differentTarget)

        let result = try #require(apply(edit, to: s).snapshot)

        let replaced = try #require(result.node(F.backend))
        let original = try #require(s.node(F.backend))
        #expect(replaced.referenceID == SequentialIDs.new(1))
        #expect(replaced.recordedPath == "/dev/new-api")
        #expect(replaced.displayName == original.displayName)
        #expect(replaced.parentID == original.parentID)
        #expect(replaced.sortIndex == original.sortIndex)
        #expect(replaced.kind == original.kind)
        #expect(original.referenceID == F.backendReference)
        #expect(original.recordedPath == "/dev/legacy-api")
    }

    @Test("[W03-replace-target-same-unchanged] 같은 실제 대상을 다시 고르면 무변경이다", .tags(.A03))
    func replaceWithSameTarget() {
        let edit = ConfigurationEdit.replaceTarget(F.backend, kind: .folder, path: "/dev/legacy-api-moved", identity: .sameTarget)

        #expect(apply(edit, to: s) == .unchanged)
    }

    @Test("[W03-replace-target-undetermined-changed] 같은 대상인지 판정할 수 없으면 교체로 기록한다", .tags(.A03))
    func replaceWithUndeterminedTarget() throws {
        let edit = ConfigurationEdit.replaceTarget(F.backend, kind: .folder, path: "/dev/legacy-api", identity: .undetermined)

        let result = try #require(apply(edit, to: s).snapshot)

        #expect(result.node(F.backend)?.referenceID == SequentialIDs.new(1))
    }

    @Test("[W03-rejection-before-unchanged] 거부 사유가 있으면 같은 대상이어도 거부한다", .tags(.A03))
    func rejectionBeforeUnchanged() {
        let edit = ConfigurationEdit.replaceTarget(F.backend, kind: .file, path: "/dev/legacy-api", identity: .sameTarget)

        #expect(apply(edit, to: s) == .rejected(.targetKindMismatch))
    }

    @Test("[W03-replace-target-rejected] 대상 교체를 거부하는 경우", arguments: [
        (fixedID(2), LinkedTarget.Kind.file, "/dev/api.md", EditRejection.targetKindMismatch),
        (fixedID(3), .folder, "/docs", .targetKindMismatch),
        (fixedID(1), .folder, "/dev", .notLinkedItem),
        (fixedID(4), .file, "/api.md", .notLinkedItem),
        (fixedID(404), .folder, "/dev", .nodeNotFound),
        (fixedID(2), .folder, "dev/relative", .invalidPath),
        (fixedID(2), .file, "dev/relative", .targetKindMismatch),
    ])
    func replaceTargetRejected(node: UUID, kind: LinkedTarget.Kind, path: String, reason: EditRejection) {
        let edit = ConfigurationEdit.replaceTarget(node, kind: kind, path: path, identity: .differentTarget)

        #expect(apply(edit, to: s) == .rejected(reason))
    }

    // MARK: 공통 속성

    @Test("[W03-results-pass-validation] 모든 changed 결과는 W02 검증을 통과하고 입력 스냅샷은 바뀌지 않는다", .tags(.A04))
    func everyChangedResultIsValid() {
        let edits: [ConfigurationEdit] = [
            .renameProject("서비스 B"),
            .addGroup(name: "에셋", parentID: F.development, position: 1),
            .addLinkedItems([LinkedTarget(displayName: "x", kind: .file, path: "/x")], parentID: nil, position: 0),
            .addWebLink(name: "링크", url: "https://example.com", parentID: F.development, position: nil),
            .renameNode(F.designNote, "설계"),
            .changeURL(F.apiSpec, "https://example.com/v2"),
            .move(F.apiSpec, toParent: F.development, position: 1),
            .move(F.backend, toParent: F.development, position: 1),
            .remove(F.backend),
            .replaceTarget(F.designNote, kind: .file, path: "/docs/v2.md", identity: .differentTarget),
        ]
        for edit in edits {
            // apply()가 입력 불변과 결과 검증을 확인한다.
            #expect(apply(edit, to: s).snapshot != nil)
        }
    }
}
