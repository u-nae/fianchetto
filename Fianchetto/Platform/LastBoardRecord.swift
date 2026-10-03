import Foundation

/// 화면 설정: 마지막으로 선택한 Board UUID(PRD §6 기본 창)와 오른쪽 열(인스펙터)을 접었는지. 구성 이력과 무관하다.
@MainActor
protocol LastBoardRecord: AnyObject {
    var lastBoardID: UUID? { get set }
    /// 기본은 펼침이라, 접었을 때만 true로 기록한다.
    var isInspectorHidden: Bool { get set }
}

@MainActor
final class UserDefaultsLastBoard: LastBoardRecord {
    private let defaults: UserDefaults
    private let key = "lastBoardID"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var lastBoardID: UUID? {
        get { defaults.string(forKey: key).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: key) }
    }

    var isInspectorHidden: Bool {
        get { defaults.bool(forKey: "inspectorHidden") }
        set { defaults.set(newValue, forKey: "inspectorHidden") }
    }
}

/// UI 테스트 전용: 테스트 폴더 안의 파일에 기록해, 폴더를 지우면 함께 정리되게 한다.
@MainActor
final class FileLastBoard: LastBoardRecord {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    var lastBoardID: UUID? {
        get { (try? String(contentsOf: url, encoding: .utf8)).flatMap(UUID.init(uuidString:)) }
        set {
            if let newValue {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? newValue.uuidString.write(to: url, atomically: true, encoding: .utf8)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// 같은 테스트 폴더의 표시 파일이 있으면 접힘이다.
    var isInspectorHidden: Bool {
        get { FileManager.default.fileExists(atPath: inspectorURL.path) }
        set {
            if newValue {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: inspectorURL.path, contents: Data())
            } else {
                try? FileManager.default.removeItem(at: inspectorURL)
            }
        }
    }

    private var inspectorURL: URL { url.deletingLastPathComponent().appending(path: "inspectorHidden") }
}
