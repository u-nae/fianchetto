import Foundation

/// 결정표 node_shape_validity: Node 종류별 필드 모양과 부모 자격.
/// 위에서 아래로 처음 맞는 규칙 하나를 적용한다(FIRST). 부모 위반을 Node 자체 필드보다 먼저 판정한다.
enum NodeShapeRule {
    enum ParentKind: Sendable {
        case root
        case group
        case file
        case folder
        case webLink

        init(_ kind: NodeKind) {
            switch kind {
            case .group: self = .group
            case .file: self = .file
            case .folder: self = .folder
            case .webLink: self = .webLink
            }
        }
    }

    enum ReferenceFields: Sendable {
        /// referenceID가 있고 기록 당시 경로가 "/"로 시작한다.
        case complete
        case none
        case incomplete
    }

    enum URLShape: Sendable {
        case absent
        /// scheme이 http/https(대소문자 무관)이고 host가 비어 있지 않은 절대 URL.
        case httpOrHTTPS
        case other
    }

    static func evaluate(
        parent: ParentKind,
        kind: NodeKind,
        reference: ReferenceFields,
        url: URLShape,
        hasPurpose: Bool = false
    ) -> SnapshotViolationKind? {
        switch parent {
        case .file, .folder, .webLink: return .parentNotGroup // R1~R3
        case .root, .group: break
        }
        switch kind {
        case .group:
            if reference != .none { return .unexpectedReference } // R4·R5
            if url != .absent { return .unexpectedURL } // R6·R7
            return hasPurpose ? .purposeNotAllowed : nil // R8 (용도는 Bishop만, 0021)
        case .file, .folder:
            switch reference {
            case .none: return .missingReference // R9·R10
            case .incomplete: return .incompleteReference // R11·R12
            case .complete: return url == .absent ? nil : .unexpectedURL // R13~R18
            }
        case .webLink:
            if reference != .none { return .unexpectedReference } // R19·R20
            switch url {
            case .absent: return .missingURL // R21
            case .other: return .invalidURL // R22
            case .httpOrHTTPS: return hasPurpose ? .purposeNotAllowed : nil // R23 (용도는 Bishop만, 0021)
            }
        }
    }

    static func referenceFields(referenceID: UUID?, recordedPath: String?) -> ReferenceFields {
        switch (referenceID, recordedPath) {
        case (nil, nil): return .none
        case let (.some, .some(path)) where path.hasPrefix("/"): return .complete
        default: return .incomplete
        }
    }

    static func urlShape(_ string: String?) -> URLShape {
        guard let string else { return .absent }
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty
        else { return .other }
        return .httpOrHTTPS
    }
}
