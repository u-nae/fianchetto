import Foundation
import Testing
@testable import Fianchetto

@Suite("복원 확인 내용 (W20)")
struct RestorePreviewTests {
    private let wording = ChangeWording(purposeText: { $0?.rawValue ?? "기본" })
    private let target = RevisionSummary(
        id: fixedID(9002), projectID: fixedID(900), sequence: 2, recordedAt: Date(timeIntervalSince1970: 0),
        cause: .created, projectName: "서비스 알파"
    )

    private func makePreview(target snapshot: ConfigurationSnapshot, current: ConfigurationSnapshot) -> RestorePreview {
        RestorePreview.make(target: target, targetSnapshot: snapshot, current: current, wording: wording, dateTimeText: { _ in "T" })
    }

    @Test("[W20-sheet-shows-diff] 현재 구성에서 복원 결과로의 변화를 요약과 변경 목록으로 만든다", .tags(.A08))
    func showsDiffFromCurrentToTarget() {
        let current = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
            SnapshotFixtures.folder(fixedID(2), "backend", parent: fixedID(1), order: 0, reference: fixedID(202), path: "/dev/api-v2"),
            SnapshotFixtures.group(fixedID(5), "문서", order: 1),
        ])
        let restored = ConfigurationSnapshot(projectName: "서비스 알파", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
            SnapshotFixtures.folder(fixedID(2), "backend", parent: fixedID(1), order: 0, reference: fixedID(201), path: "/dev/legacy-api"),
        ])
        let preview = makePreview(target: restored, current: current)
        #expect(preview.title == "#2 구성으로 복원")
        #expect(preview.beforeText == "현재 구성")
        #expect(preview.afterText == "#2 · T")
        #expect(preview.isIdentical == false)
        #expect(preview.summaryText == "변화 2개 · Board 이름 변경")
        #expect(preview.boardNameText == "서비스 A → 서비스 알파")
        #expect(preview.rows.map(\.name) == ["backend", "문서"])
        #expect(preview.rows.map(\.changeText) == ["대상 교체 /dev/api-v2 → /dev/legacy-api", "제거됨"])
        #expect(preview.rows.map(\.symbol) == ["arrow.triangle.swap", "minus.circle"])
        #expect(preview.rows.map(\.accessibilityLabel) == ["backend, 대상 교체 /dev/api-v2 → /dev/legacy-api", "문서, 제거됨"])
    }

    @Test("현재와 같은 구성이면 같다고 표시하고 변경 목록이 비어 있다")
    func identicalConfiguration() {
        let snapshot = SnapshotFixtures.serviceA()
        let preview = makePreview(target: snapshot, current: snapshot)
        #expect(preview.isIdentical)
        #expect(preview.rows.isEmpty)
        #expect(preview.boardNameText == nil)
    }

    @Test("한 항목의 여러 변화는 19.3 순서로 ' · '로 잇고 값을 붙인다")
    func multipleKindsAreJoinedWithValues() {
        let note = fixedID(7)
        let current = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
            SnapshotFixtures.file(note, "notes.md", parent: fixedID(1), order: 0, reference: fixedID(207), path: "/docs/notes.md"),
        ])
        let restored = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
            SnapshotFixtures.file(note, "memo.md", order: 1, reference: fixedID(207), path: "/docs/notes.md"),
        ])
        let preview = makePreview(target: restored, current: current)
        #expect(preview.rows.count == 1)
        #expect(preview.rows.first?.changeText == "이름 변경 notes.md → memo.md · ‘개발’에서 이동")
        #expect(preview.rows.first?.symbol == "pencil")
    }

    @Test("순서만 바뀐 항목도 세고 보인다")
    func reorderOnlyIsCountedAndShown() {
        let current = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
            SnapshotFixtures.group(fixedID(2), "문서", order: 1),
        ])
        let restored = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 1),
            SnapshotFixtures.group(fixedID(2), "문서", order: 0),
        ])
        let preview = makePreview(target: restored, current: current)
        #expect(preview.summaryText == "변화 1개")
        #expect(preview.rows.count == 1)
        #expect(preview.rows.first?.changeText == "순서 변경")
    }

    @Test("URL과 아이콘 변화는 이전 → 이후 값을 붙인다")
    func urlAndPurposeCarryValues() {
        let link = fixedID(8), file = fixedID(9)
        let current = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.webLink(link, "명세", order: 0, url: "https://new.example.com"),
            ConfigurationNode(id: file, kind: .file, displayName: "a.md", sortIndex: 1, referenceID: fixedID(209),
                              recordedPath: "/a.md", purpose: "data"),
        ])
        let restored = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.webLink(link, "명세", order: 0, url: "https://old.example.com"),
            ConfigurationNode(id: file, kind: .file, displayName: "a.md", sortIndex: 1, referenceID: fixedID(209),
                              recordedPath: "/a.md", purpose: "code"),
        ])
        let preview = makePreview(target: restored, current: current)
        #expect(preview.rows.map(\.changeText) == [
            "URL 변경 https://new.example.com → https://old.example.com",
            "아이콘 변경 data → code",
        ])
    }

    @Test("추가되는 항목은 '추가됨'이다")
    func addedItem() {
        let current = ConfigurationSnapshot(projectName: "서비스 A", nodes: [])
        let restored = ConfigurationSnapshot(projectName: "서비스 A", nodes: [
            SnapshotFixtures.group(fixedID(1), "개발", order: 0),
        ])
        let preview = makePreview(target: restored, current: current)
        #expect(preview.rows.map(\.changeText) == ["추가됨"])
        #expect(preview.rows.map(\.symbol) == ["plus.circle"])
    }
}
