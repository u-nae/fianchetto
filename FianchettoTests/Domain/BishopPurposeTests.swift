import Foundation
import Testing
@testable import Fianchetto

@Suite("Bishop 용도 (W29 Domain)")
struct BishopPurposeTests {
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    static let readme = id(1), backend = id(2), api = id(3), dev = id(4)

    static func snapshot(readmePurpose: String? = nil, backendPurpose: String? = nil) -> ConfigurationSnapshot {
        ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            ConfigurationNode(id: readme, kind: .file, displayName: "README.md", sortIndex: 0, referenceID: id(101), recordedPath: "/docs/README.md", purpose: readmePurpose),
            ConfigurationNode(id: backend, kind: .folder, displayName: "backend", sortIndex: 1, referenceID: id(102), recordedPath: "/dev/backend", purpose: backendPurpose),
            ConfigurationNode(id: api, kind: .webLink, displayName: "API 명세", sortIndex: 2, url: "https://example.com/api"),
            ConfigurationNode(id: dev, kind: .group, displayName: "개발", sortIndex: 3),
        ])
    }

    private func apply(_ edit: ConfigurationEdit, to snapshot: ConfigurationSnapshot) -> EditOutcome {
        ConfigurationEditor.apply(edit, to: snapshot, makeID: { Self.id(999) })
    }

    // MARK: 편집 연산

    @Test("[W29-change-purpose] 용도 변경은 그 값만 바꾸고 정체성·배치·참조를 유지한다", .tags(.A04), arguments: [
        (nil as String?, "document" as String?), ("document", "design"), ("code", nil),
    ])
    func changePurpose(before: String?, after: String?) throws {
        let start = Self.snapshot(readmePurpose: before)
        guard case let .changed(result) = apply(.changePurpose(Self.readme, after), to: start) else {
            Issue.record("changed가 아니다")
            return
        }
        var expected = start
        let index = try #require(expected.nodes.firstIndex { $0.id == Self.readme })
        expected.nodes[index].purpose = after
        #expect(result == expected)
    }

    @Test("[W29-change-purpose-unchanged] 같은 용도로 바꾸면 unchanged다", .tags(.A04))
    func unchanged() {
        #expect(apply(.changePurpose(Self.readme, "todo"), to: Self.snapshot(readmePurpose: "todo")) == .unchanged)
    }

    @Test("[W29-change-purpose-rejected] 거부 순서는 node_not_found → not_linked_item → invalid_purpose다", arguments: [
        (dev, "document", EditRejection.notLinkedItem), (api, "reference", .notLinkedItem), (id(77), "document", .nodeNotFound),
        (readme, "music", .invalidPurpose), (dev, "music", .notLinkedItem), (id(77), "music", .nodeNotFound),
    ])
    func rejected(node: UUID, value: String, reason: EditRejection) {
        #expect(apply(.changePurpose(node, value), to: Self.snapshot()) == .rejected(reason))
    }

    @Test("[W29-folder-purpose] 폴더 Bishop도 용도를 가진다")
    func folderPurpose() throws {
        guard case let .changed(result) = apply(.changePurpose(Self.backend, "code"), to: Self.snapshot()) else {
            Issue.record("changed가 아니다")
            return
        }
        #expect(result.nodes.first { $0.id == Self.backend }?.purpose == "code")
    }

    @Test("[W29-purpose-kept-after-move-and-replace] 이동과 연결 대상 변경 뒤에도 용도는 유지된다")
    func keptAfterMoveAndReplace() throws {
        let start = Self.snapshot(readmePurpose: "document")
        guard case let .changed(moved) = apply(.move(Self.readme, toParent: Self.dev, position: nil), to: start),
              case let .changed(replaced) = apply(
                  .replaceTarget(Self.readme, kind: .file, path: "/docs/other.md", identity: .differentTarget), to: moved
              )
        else {
            Issue.record("편집이 changed가 아니다")
            return
        }
        #expect(moved.nodes.first { $0.id == Self.readme }?.purpose == "document")
        #expect(replaced.nodes.first { $0.id == Self.readme }?.purpose == "document")
    }

    // MARK: 저장 형식

    @Test("[W29-codec-roundtrip] 용도는 형식 버전 2로 저장되고 왕복해도 같다")
    func codecRoundTrip() throws {
        let snapshot = Self.snapshot(readmePurpose: "document", backendPurpose: "code")
        let data = try SnapshotCodec.encode(snapshot)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect(try SnapshotCodec.decode(data) == snapshot)
    }

    @Test("[W29-codec-v1] 버전 1 스냅샷은 용도 없음으로 읽고 나머지는 그대로다")
    func codecV1() throws {
        let json = #"{"schemaVersion":1,"projectName":"서비스 A","nodes":[{"id":"00000000-0000-0000-0000-000000000001","kind":"file","displayName":"README.md","sortIndex":0,"referenceID":"00000000-0000-0000-0000-000000000101","recordedPath":"/docs/README.md"}]}"#
        let snapshot = try SnapshotCodec.decode(Data(json.utf8))
        #expect(snapshot.nodes.count == 1)
        #expect(snapshot.nodes[0].purpose == nil)
        #expect(snapshot.nodes[0].recordedPath == "/docs/README.md")
    }

    @Test("[W29-unknown-key-preserved] 모르는 용도 키는 읽고 다시 저장해도 보존된다")
    func unknownKeyPreserved() throws {
        let stored = try SnapshotCodec.encode(Self.snapshot(readmePurpose: "music"))
        var snapshot = try SnapshotCodec.decode(stored)
        guard case let .changed(renamed) = apply(.renameNode(Self.dev, "개발 2"), to: snapshot) else {
            Issue.record("changed가 아니다")
            return
        }
        snapshot = try SnapshotCodec.decode(try SnapshotCodec.encode(renamed))
        #expect(snapshot.nodes.first { $0.id == Self.readme }?.purpose == "music")
        #expect(BishopPurpose(rawValue: "music") == nil)
    }

    // MARK: 형태 검증

    @Test("[W29-validator-shape] Wing·웹 링크의 용도는 purpose_not_allowed이고 부모·기존 필드 위반이 먼저다")
    func validatorShape() {
        func violations(_ nodes: [ConfigurationNode]) -> Set<SnapshotViolationKind> {
            Set(SnapshotValidator.violations(in: ConfigurationSnapshot(projectName: "B", nodes: nodes)).map(\.kind))
        }
        let wing = ConfigurationNode(id: Self.dev, kind: .group, displayName: "개발", sortIndex: 0, purpose: "document")
        #expect(violations([wing]) == [.purposeNotAllowed])
        let link = ConfigurationNode(id: Self.api, kind: .webLink, displayName: "API", sortIndex: 0, url: "https://example.com", purpose: "reference")
        #expect(violations([link]) == [.purposeNotAllowed])
        let noURL = ConfigurationNode(id: Self.api, kind: .webLink, displayName: "API", sortIndex: 0, purpose: "document")
        #expect(violations([noURL]) == [.missingURL])
        let file = ConfigurationNode(id: Self.readme, kind: .file, displayName: "R", sortIndex: 0, referenceID: Self.id(101), recordedPath: "/r", purpose: "code")
        let wingUnderFile = ConfigurationNode(id: Self.dev, kind: .group, displayName: "W", parentID: Self.readme, sortIndex: 0, purpose: "data")
        #expect(violations([file, wingUnderFile]) == [.parentNotGroup])
        #expect(violations([file]).isEmpty)
    }

    // MARK: 차이 비교

    @Test("[W29-diff-purpose] 용도만 바꾸면 그 Node의 purposeChanged 하나이고 전·후 용도를 준다", .tags(.A07), arguments: [
        (nil as String?, "document"), ("music", nil as String?),
    ] as [(String?, String?)])
    func diffPurpose(before: String?, after: String?) throws {
        let result = ConfigurationDiffer.diff(Self.snapshot(readmePurpose: before), Self.snapshot(readmePurpose: after))
        #expect(result.changes.map(\.nodeID) == [Self.readme])
        let change = try #require(result.changes.first)
        #expect(change.kinds == [.purposeChanged])
        #expect(change.before?.purpose == before)
        #expect(change.after?.purpose == after)
    }

    @Test("[W29-diff-combined] 이름과 용도를 함께 바꾸면 한 항목에 두 분류가 담긴다", .tags(.A07))
    func diffCombined() throws {
        var after = Self.snapshot(readmePurpose: "todo")
        let index = try #require(after.nodes.firstIndex { $0.id == Self.readme })
        after.nodes[index].displayName = "읽어보기"
        let change = try #require(ConfigurationDiffer.diff(Self.snapshot(), after).changes.first)
        #expect(change.kinds == [.renamed, .purposeChanged])
    }
}
