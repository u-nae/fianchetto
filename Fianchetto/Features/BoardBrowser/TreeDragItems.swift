import CoreTransferable
import Foundation

/// 앱 안에서 끄는 트리 항목. 항목 식별자만 담은 문자열로 내보내며, 받는 쪽은 현재 구성에 있는지 다시 확인한다.
struct NodeDragItem: Transferable {
    static let prefix = "fianchetto-node:"

    var nodeID: UUID

    var text: String { Self.prefix + nodeID.uuidString }

    /// 앱 안 항목 형식의 문자열이면 식별자를, 아니면 nil.
    static func nodeID(from text: String) -> UUID? {
        guard text.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(text.dropFirst(prefix.count)))
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.text)
    }
}

/// 트리에 놓인 것: Finder에서 끈 파일, 앱 안에서 끈 항목, 또는 알 수 없는 것.
enum TreeDropItem: Transferable {
    case file(URL)
    case node(UUID)
    case unknown

    var fileURL: URL? {
        if case let .file(url) = self { url } else { nil }
    }

    var nodeID: UUID? {
        if case let .node(id) = self { id } else { nil }
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in TreeDropItem.file(url) })
        ProxyRepresentation(importing: { (text: String) in
            NodeDragItem.nodeID(from: text).map(TreeDropItem.node) ?? .unknown
        })
    }
}
