import AppKit

/// Bishop 추가용 파일 선택 창. 고른 위치에서 사용자 선택 권한을 얻는다(0001).
@MainActor
enum TargetPicker {
    struct Configuration: Equatable {
        var canChooseFiles: Bool
        var canChooseDirectories: Bool
        var allowsMultipleSelection: Bool
        var canCreateDirectories: Bool
    }

    static let configuration = Configuration(
        canChooseFiles: true, canChooseDirectories: true, allowsMultipleSelection: true, canCreateDirectories: false
    )

    /// 고른 URL 목록. 취소하면 nil.
    static func pick() -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = configuration.canChooseFiles
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.prompt = String(localized: "Bishop 추가")
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
