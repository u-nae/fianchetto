import Foundation
import Testing
@testable import Fianchetto

/// new-1, new-2 … 순서로 UUID를 내주는 결정적 생성기.
final class SequentialIDs {
    private(set) var issued: [UUID] = []

    func next() -> UUID {
        let id = fixedID(1000 + issued.count + 1)
        issued.append(id)
        return id
    }

    static func new(_ number: Int) -> UUID { fixedID(1000 + number) }
}

/// 편집을 적용하고, 모든 호출에서 W03-results-pass-validation(입력 불변·changed 결과 검증 통과)을 함께 확인한다.
func apply(_ edit: ConfigurationEdit, to snapshot: ConfigurationSnapshot, ids: SequentialIDs = SequentialIDs()) -> EditOutcome {
    let before = snapshot
    let outcome = ConfigurationEditor.apply(edit, to: snapshot, makeID: ids.next)
    #expect(snapshot == before)
    if case let .changed(result) = outcome {
        #expect(SnapshotValidator.violations(in: result).isEmpty)
    }
    return outcome
}

extension EditOutcome {
    var snapshot: ConfigurationSnapshot? {
        if case let .changed(snapshot) = self { snapshot } else { nil }
    }
}

extension ConfigurationSnapshot {
    func node(_ id: UUID) -> ConfigurationNode? { nodes.first { $0.id == id } }

    func node(named name: String) -> ConfigurationNode? { nodes.first { $0.displayName == name } }

    /// 부모 아래 표시 이름을 정렬 순서대로.
    func children(of parentID: UUID?) -> [String] {
        nodes.filter { $0.parentID == parentID }.sorted { $0.sortIndex < $1.sortIndex }.map(\.displayName)
    }
}
