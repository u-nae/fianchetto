import Foundation

/// 화면 설정: 마지막으로 선택한 Board UUID(PRD §6 기본 창)와 오른쪽 열(인스펙터)을 접었는지. 구성 이력과 무관하다.
@MainActor
protocol LastBoardRecord: AnyObject {
    var lastBoardID: UUID? { get set }
    /// 기본은 펼침이라, 접었을 때만 true로 기록한다.
    var isInspectorHidden: Bool { get set }
    /// Board별 구성 보기 방식(W28). 값은 화면 쪽이 정한 문자열이다. 없으면 nil.
    func viewMode(for boardID: UUID) -> String?
    func setViewMode(_ mode: String, for boardID: UUID)
    /// 설정의 Bishop 아이콘 방식(W28). 없으면 nil(기본).
    var bishopIconStyle: String? { get set }
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

    func viewMode(for boardID: UUID) -> String? {
        (defaults.dictionary(forKey: "viewModes") as? [String: String])?[boardID.uuidString]
    }

    func setViewMode(_ mode: String, for boardID: UUID) {
        var modes = defaults.dictionary(forKey: "viewModes") as? [String: String] ?? [:]
        modes[boardID.uuidString] = mode
        defaults.set(modes, forKey: "viewModes")
    }

    var bishopIconStyle: String? {
        get { defaults.string(forKey: "bishopIconStyle") }
        set { defaults.set(newValue, forKey: "bishopIconStyle") }
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

    /// 같은 테스트 폴더의 "viewModes" 파일에 "UUID=값" 줄로 기록한다.
    func viewMode(for boardID: UUID) -> String? { viewModes[boardID.uuidString] }

    func setViewMode(_ mode: String, for boardID: UUID) {
        var modes = viewModes
        modes[boardID.uuidString] = mode
        write(modes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "\n"), to: "viewModes")
    }

    var bishopIconStyle: String? {
        get { read("bishopIconStyle") }
        set { write(newValue, to: "bishopIconStyle") }
    }

    private var viewModes: [String: String] {
        let lines = read("viewModes")?.split(separator: "\n") ?? []
        return Dictionary(lines.compactMap { line -> (String, String)? in
            let parts = line.split(separator: "=", maxSplits: 1)
            return parts.count == 2 ? (String(parts[0]), String(parts[1])) : nil
        }, uniquingKeysWith: { _, last in last })
    }

    private func read(_ name: String) -> String? {
        try? String(contentsOf: url.deletingLastPathComponent().appending(path: name), encoding: .utf8)
    }

    private func write(_ text: String?, to name: String) {
        let file = url.deletingLastPathComponent().appending(path: name)
        guard let text else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
}
