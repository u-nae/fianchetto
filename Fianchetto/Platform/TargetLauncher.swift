import AppKit

/// 기본 앱으로 열기와 Finder 표시. NSWorkspace는 MainActor에서 부른다.
protocol TargetLauncher: Sendable {
    /// 요청을 넘겼으면 true. 기본 앱이 실제로 문서를 열었는지는 알 수 없다.
    @MainActor func open(_ url: URL) -> Bool
    @MainActor func reveal(_ url: URL)
}

struct WorkspaceLauncher: TargetLauncher {
    @MainActor func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    @MainActor func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
