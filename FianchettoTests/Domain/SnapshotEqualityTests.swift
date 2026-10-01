import Foundation
import Testing
@testable import Fianchetto

@Suite("구성 스냅샷 동등성 (W02)")
struct SnapshotEqualityTests {
    typealias F = SnapshotFixtures

    @Test("[W02-equality-ignores-list-order] Node 목록의 저장 순서가 달라도 같은 구성은 같은 스냅샷이다")
    func listOrderDoesNotMatter() {
        let snapshot = F.serviceA()
        let reordered = ConfigurationSnapshot(projectName: snapshot.projectName, nodes: snapshot.nodes.reversed())

        #expect(snapshot == reordered)
        #expect(snapshot.hashValue == reordered.hashValue)
    }

    /// 각 변경은 S와 정확히 한 가지만 다른 T를 만든다. 이 비교가 W03 무변경 판정의 기준이다.
    static let singleChanges: [(String, @Sendable (ConfigurationSnapshot) -> ConfigurationSnapshot)] = [
        ("프로젝트 이름", { var s = $0; s.projectName = "서비스 B"; return s }),
        ("표시 이름", { $0.updating(F.designNote) { $0.displayName = "설계" } }),
        ("부모", {
            $0.updating(F.designNote) { $0.parentID = nil; $0.sortIndex = 1 }
              .updating(F.apiSpec) { $0.sortIndex = 2 }
        }),
        ("정렬 순서", {
            $0.updating(F.backend) { $0.sortIndex = 1 }.updating(F.designNote) { $0.sortIndex = 0 }
        }),
        ("종류", { $0.updating(F.designNote) { $0.kind = .folder } }),
        ("referenceID", { $0.updating(F.backend) { $0.referenceID = fixedID(999) } }),
        ("기록 당시 경로", { $0.updating(F.backend) { $0.recordedPath = "/dev/new-api" } }),
        ("URL", { $0.updating(F.apiSpec) { $0.url = "https://example.com/v2" } }),
        ("Node 추가", { var s = $0; s.nodes.append(F.group(fixedID(5), "에셋", order: 2)); return s }),
        ("Node 제거", { var s = $0; s.nodes.removeAll { $0.id == F.apiSpec }; return s }),
    ]

    @Test("[W02-different-snapshots-not-equal] 한 가지라도 다른 두 스냅샷은 같지 않다", arguments: singleChanges.indices)
    func singleDifferenceMakesSnapshotsUnequal(index: Int) {
        let (_, change) = Self.singleChanges[index]
        let original = F.serviceA()

        #expect(change(original) != original)
    }

    @Test("[W02-copy-does-not-affect-original] 스냅샷을 복사해 바꿔도 원래 스냅샷은 바뀌지 않는다")
    func copyIsIndependent() {
        let original = F.serviceA()

        let copy = original.updating(F.backend) { $0.displayName = "api" }

        #expect(copy.nodes.first { $0.id == F.backend }?.displayName == "api")
        #expect(original.nodes.first { $0.id == F.backend }?.displayName == "backend")
    }
}
