import AppKit
import UniformTypeIdentifiers

/// 파일 종류(UTType)의 macOS 일반 아이콘. 대상 파일에 접근하지 않는다(icon(forFile:)을 쓰지 않는다, 0020·DESIGN 18.5).
@MainActor
enum FileTypeIcons {
    static func image(forTypeIdentifier identifier: String) -> NSImage {
        NSWorkspace.shared.icon(for: UTType(identifier) ?? .data)
    }

    static var folder: NSImage { NSWorkspace.shared.icon(for: .folder) }
}
