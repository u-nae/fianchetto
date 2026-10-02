import AppKit

/// 복구 화면의 Finder·종료 동작(0008).
@MainActor
enum WorkspaceActions {
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func quit() {
        NSApplication.shared.terminate(nil)
    }
}
