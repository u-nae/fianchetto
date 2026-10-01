import Foundation
import Testing
@testable import Fianchetto

@Suite("구성 스냅샷 트리 검증 (W02)")
struct SnapshotValidationTests {
    typealias F = SnapshotFixtures

    private func validate(_ nodes: [ConfigurationNode], projectName: String = "서비스 A") -> Set<SnapshotViolation> {
        SnapshotValidator.violations(in: ConfigurationSnapshot(projectName: projectName, nodes: nodes))
    }

    private func violation(_ id: UUID, _ kind: SnapshotViolationKind) -> SnapshotViolation {
        SnapshotViolation(subject: .node(id), kind: kind)
    }

    @Test("[W02-json-roundtrip] 대표 구성은 유효하다")
    func representativeConfigurationIsValid() {
        #expect(SnapshotValidator.violations(in: F.serviceA()).isEmpty)
    }

    @Test("[W02-empty-configuration-valid] Node가 없는 빈 구성도 유효하다")
    func emptyConfigurationIsValid() {
        #expect(validate([]).isEmpty)
    }

    @Test("[W02-same-name-same-path-not-merged] 같은 부모 아래 같은 표시 이름과 같은 경로의 Node를 병합하지 않는다")
    func sameNameAndPathAreKeptSeparately() throws {
        let snapshot = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            F.group(F.development, "개발", order: 0),
            F.folder(fixedID(10), "backend", parent: F.development, order: 0, reference: fixedID(110), path: "/dev/legacy-api"),
            F.folder(fixedID(11), "backend", parent: F.development, order: 1, reference: fixedID(111), path: "/dev/legacy-api"),
        ])

        #expect(SnapshotValidator.violations(in: snapshot).isEmpty)
        let decoded = try SnapshotCodec.decode(SnapshotCodec.encode(snapshot))
        #expect(Set(decoded.nodes.map(\.id)) == [F.development, fixedID(10), fixedID(11)])
    }

    // MARK: 이름

    @Test("[W02-untrimmed-name-in-json-rejected] 정리되지 않았거나 빈 이름을 담은 JSON은 검증에서 거부한다", arguments: [
        (" backend", "서비스 A", SnapshotViolation(subject: .node(fixedID(2)), kind: .untrimmedName)),
        ("   ", "서비스 A", SnapshotViolation(subject: .node(fixedID(2)), kind: .blankName)),
        ("backend", "서비스 A ", SnapshotViolation(subject: .project, kind: .untrimmedName)),
        ("backend", "", SnapshotViolation(subject: .project, kind: .blankName)),
    ])
    func untrimmedOrBlankNamesInJSONAreRejected(nodeName: String, projectName: String, expected: SnapshotViolation) throws {
        let stored = ConfigurationSnapshot(projectName: projectName, nodes: [
            F.folder(F.backend, nodeName, order: 0, reference: F.backendReference, path: "/dev/legacy-api"),
        ])

        let decoded = try SnapshotCodec.decode(SnapshotCodec.encode(stored))

        #expect(SnapshotValidator.violations(in: decoded) == [expected])
        #expect(decoded.projectName == projectName)
        #expect(decoded.nodes.first?.displayName == nodeName)
    }

    // MARK: 순환 (A14)

    @Test("[W02-self-parent-cycle-rejected] 자기 자신을 부모로 가진 그룹은 순환으로 거부한다", .tags(.A14))
    func selfParentIsCycle() {
        let result = validate([F.group(F.development, "개발", parent: F.development, order: 0)])

        #expect(result == [violation(F.development, .cycle)])
    }

    @Test("[W02-mutual-cycle-rejected] 두 그룹이 서로의 부모인 구성은 순환으로 거부한다", .tags(.A14))
    func mutualParentsAreCycle() {
        let a = fixedID(21), b = fixedID(22)

        let result = validate([F.group(a, "A", parent: b, order: 0), F.group(b, "B", parent: a, order: 0)])

        #expect(result == [violation(a, .cycle), violation(b, .cycle)])
    }

    @Test("[W02-deep-cycle-rejected] 깊은 자손을 거쳐 돌아오는 순환도 거부한다", .tags(.A14))
    func deepCycleIsReportedOnEveryMember() {
        let ids = (31...35).map(fixedID)
        // G1 ← G2 ← G3 ← G4 ← G5, 그리고 G1의 부모가 G5
        let nodes = ids.indices.map { index in
            F.group(ids[index], "G\(index + 1)", parent: index == 0 ? ids[4] : ids[index - 1], order: 0)
        }

        #expect(validate(nodes) == Set(ids.map { violation($0, .cycle) }))
    }

    @Test("[W02-cycle-descendants-not-reported] 순환에 매달린 자손에는 cycle 위반을 보고하지 않는다", .tags(.A14))
    func descendantsOfCycleAreNotReported() {
        let a = fixedID(21), b = fixedID(22), notes = fixedID(23)

        let result = validate([
            F.group(a, "A", parent: b, order: 0),
            F.group(b, "B", parent: a, order: 0),
            F.file(notes, "notes.md", parent: a, order: 1, reference: fixedID(123), path: "/notes.md"),
        ])

        #expect(result == [violation(a, .cycle), violation(b, .cycle)])
    }

    // MARK: 부모와 UUID

    @Test("[W02-missing-parent-rejected] 존재하지 않는 부모를 가리키는 Node는 거부한다")
    func missingParentIsRejected() {
        let result = validate([
            F.file(F.designNote, "설계 메모", parent: fixedID(404), order: 0, reference: F.designNoteReference, path: "/docs/design.md"),
        ])

        #expect(result == [violation(F.designNote, .missingParent)])
    }

    @Test("[W02-duplicate-node-id-rejected] 같은 UUID의 Node가 두 번 나오면 거부한다")
    func duplicateNodeIDIsRejected() {
        let duplicated = fixedID(40)

        let result = validate([
            F.group(F.development, "개발", order: 0),
            F.group(fixedID(41), "문서", order: 1),
            F.group(duplicated, "공통", parent: F.development, order: 0),
            F.group(duplicated, "공통", parent: fixedID(41), order: 0),
        ])

        #expect(result == [violation(duplicated, .duplicateNode)])
    }

    @Test(
        "[W02-parent-must-be-group] Node의 부모는 그룹이거나 프로젝트 최상위여야 한다",
        arguments: [
            (NodeKind?.none, SnapshotViolationKind?.none),
            (NodeKind.group, nil),
            (NodeKind.folder, SnapshotViolationKind.parentNotGroup),
            (NodeKind.file, .parentNotGroup),
            (NodeKind.webLink, .parentNotGroup),
        ]
    )
    func parentEligibility(parentKind: NodeKind?, expected: SnapshotViolationKind?) {
        let parent = fixedID(50), notes = fixedID(51)
        var nodes = [F.file(notes, "notes.md", parent: parentKind == nil ? nil : parent, order: 0, reference: fixedID(151), path: "/notes.md")]
        switch parentKind {
        case .none: break
        case .group: nodes.append(F.group(parent, "부모", order: 0))
        case .folder: nodes.append(F.folder(parent, "부모", order: 0, reference: fixedID(150), path: "/parent"))
        case .file: nodes.append(F.file(parent, "부모", order: 0, reference: fixedID(150), path: "/parent.txt"))
        case .webLink: nodes.append(F.webLink(parent, "부모", order: 0, url: "https://example.com"))
        }

        let expectedViolations = expected.map { Set([violation(notes, $0)]) } ?? []
        #expect(validate(nodes) == expectedViolations)
    }

    @Test("[W02-node-shape-by-kind] Node 종류별 필드 모양 위반을 Node에 보고한다", arguments: [
        (ConfigurationNode(id: fixedID(60), kind: .group, displayName: "x", sortIndex: 0), SnapshotViolationKind?.none),
        (ConfigurationNode(id: fixedID(60), kind: .group, displayName: "x", sortIndex: 0, referenceID: fixedID(160), recordedPath: "/x"), .unexpectedReference),
        (ConfigurationNode(id: fixedID(60), kind: .group, displayName: "x", sortIndex: 0, url: "https://example.com"), .unexpectedURL),
        (ConfigurationNode(id: fixedID(60), kind: .folder, displayName: "x", sortIndex: 0, referenceID: fixedID(160), recordedPath: "/x"), nil),
        (ConfigurationNode(id: fixedID(60), kind: .folder, displayName: "x", sortIndex: 0), .missingReference),
        (ConfigurationNode(id: fixedID(60), kind: .file, displayName: "x", sortIndex: 0, referenceID: fixedID(160)), .incompleteReference),
        (ConfigurationNode(id: fixedID(60), kind: .file, displayName: "x", sortIndex: 0, referenceID: fixedID(160), recordedPath: "/x", url: "https://example.com"), .unexpectedURL),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0, url: "https://example.com/api"), nil),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0, url: "HTTP://Example.com"), nil),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0), .missingURL),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0, url: "ftp://example.com"), .invalidURL),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0, url: "example.com"), .invalidURL),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0, url: "https:///path"), .invalidURL),
        (ConfigurationNode(id: fixedID(60), kind: .webLink, displayName: "x", sortIndex: 0, referenceID: fixedID(160), recordedPath: "/x", url: "https://example.com"), .unexpectedReference),
    ])
    func nodeShapeIsReported(node: ConfigurationNode, expected: SnapshotViolationKind?) {
        let expectedViolations = expected.map { Set([violation(node.id, $0)]) } ?? []
        #expect(validate([node]) == expectedViolations)
    }

    @Test("[W02-recorded-path-must-be-absolute] 기록 당시 경로가 절대 경로가 아니면 참조 필드가 불완전하다", arguments: ["", "dev/legacy-api"])
    func relativeRecordedPathIsIncomplete(path: String) {
        let result = validate([F.folder(F.backend, "backend", order: 0, reference: F.backendReference, path: path)])

        #expect(result == [violation(F.backend, .incompleteReference)])
    }

    // MARK: 정렬 순서

    @Test("[W02-sibling-order-contiguous] 형제의 정렬 순서는 부모마다 0부터 빈틈없이 매긴다")
    func contiguousSiblingOrderIsValid() {
        let result = validate([
            F.group(F.development, "개발", order: 0),
            F.group(fixedID(70), "a", parent: F.development, order: 0),
            F.group(fixedID(71), "b", parent: F.development, order: 1),
            F.group(fixedID(72), "c", parent: F.development, order: 2),
            F.group(fixedID(73), "문서", order: 1),
        ])

        #expect(result.isEmpty)
    }

    @Test("[W02-sibling-order-violations-rejected] 그룹 아래 형제 정렬 순서에 중복·빈칸·음수가 있으면 거부한다", arguments: [
        [0, 0, 1], [0, 2], [1, 2], [-1, 0],
    ])
    func invalidSiblingOrderInGroupIsRejected(orders: [Int]) {
        let children = orders.enumerated().map { index, order in
            F.group(fixedID(80 + index), "child\(index)", parent: F.development, order: order)
        }

        let result = validate([F.group(F.development, "개발", order: 0)] + children)

        #expect(result == [SnapshotViolation(subject: .siblings(parentID: F.development), kind: .siblingOrder)])
    }

    @Test("[W02-sibling-order-violations-rejected] 최상위 형제 정렬 순서가 중복되면 거부한다")
    func invalidSiblingOrderAtRootIsRejected() {
        let result = validate([F.group(fixedID(90), "a", order: 0), F.group(fixedID(91), "b", order: 0)])

        #expect(result == [SnapshotViolation(subject: .siblings(parentID: nil), kind: .siblingOrder)])
    }

    // MARK: 보고

    @Test("[W02-all-violations-reported] 여러 Node가 규칙을 어기면 위반을 모두 보고한다")
    func allViolationsAreReported() {
        let notes = fixedID(95)

        let result = validate([
            F.folder(F.backend, "backend", order: 0, reference: F.backendReference, path: "/dev/legacy-api"),
            F.file(notes, "notes.md", parent: F.backend, order: 0, reference: fixedID(195), path: "/notes.md"),
            F.webLink(F.apiSpec, "API 명세", order: 1, url: "ftp://example.com"),
        ])

        #expect(result == [violation(notes, .parentNotGroup), violation(F.apiSpec, .invalidURL)])
    }

    @Test("[W02-all-violations-reported] 한 Node가 여러 종류의 규칙을 어기면 모두 보고한다")
    func multipleViolationsOnOneNodeAreReported() {
        let file = fixedID(96)

        let result = validate([F.file(file, " notes.md", parent: file, order: 0, reference: fixedID(196), path: "/notes.md")])

        #expect(result == [violation(file, .cycle), violation(file, .parentNotGroup), violation(file, .untrimmedName)])
    }
}
