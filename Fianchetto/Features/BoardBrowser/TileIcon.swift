import Foundation
import UniformTypeIdentifiers

/// 설정의 Bishop 아이콘 방식(DESIGN 18.5). 화면 설정이며 revision을 만들지 않는다.
enum BishopIconStyle: String, Sendable {
    /// Bishop 심볼(기본).
    case symbol
    /// 기록 당시 경로의 확장자로 정한 일반 파일 종류 아이콘 + Bishop 배지.
    case fileType
}

/// 목록 행·아이콘 타일의 기호. 대상 파일에 접근하지 않고 Node 값만으로 정한다(0020, PRD §8).
enum TileIcon: Equatable, Sendable {
    case systemSymbol(String)
    case bishop
    case bishopFolder
    /// 확장자 기준 UTType 식별자의 일반 아이콘 + Bishop 배지.
    case fileType(identifier: String)
    /// 일반 폴더 아이콘 + Bishop 배지.
    case genericFolder

    /// 확장자가 없거나 알 수 없을 때의 일반 문서.
    static let genericDocumentIdentifier = UTType.data.identifier

    static func of(_ node: ConfigurationNode, style: BishopIconStyle) -> TileIcon {
        switch (node.kind, style) {
        case (.group, _): .systemSymbol("folder")
        case (.webLink, _): .systemSymbol("link")
        case (.file, .symbol): .bishop
        case (.folder, .symbol): .bishopFolder
        case (.folder, .fileType): .genericFolder
        case (.file, .fileType):
            .fileType(identifier: typeIdentifier(forExtension: URL(filePath: node.recordedPath ?? node.displayName).pathExtension))
        }
    }

    static func typeIdentifier(forExtension ext: String) -> String {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return genericDocumentIdentifier }
        return type.identifier
    }
}
