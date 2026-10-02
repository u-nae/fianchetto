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

    /// 연결 대상 변경: Bishop 종류와 같은 것 하나만 고른다(종류 전환은 새 항목, PRD §5).
    static func replacementConfiguration(for kind: LinkedTarget.Kind) -> Configuration {
        Configuration(
            canChooseFiles: kind == .file, canChooseDirectories: kind == .folder,
            allowsMultipleSelection: false, canCreateDirectories: false
        )
    }

    /// 고른 URL 목록. 취소하면 nil.
    static func pick() -> [URL]? {
        run(configuration, prompt: String(localized: "Bishop 추가"))
    }

    static func pickReplacement(_ kind: LinkedTarget.Kind) -> URL? {
        run(replacementConfiguration(for: kind), prompt: String(localized: "연결 대상 변경"))?.first
    }

    private static func run(_ configuration: Configuration, prompt: String) -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = configuration.canChooseFiles
        panel.canChooseDirectories = configuration.canChooseDirectories
        panel.allowsMultipleSelection = configuration.allowsMultipleSelection
        panel.canCreateDirectories = configuration.canCreateDirectories
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.urls : nil
    }
}
