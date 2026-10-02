import Foundation

/// 마지막으로 선택한 Board UUID 하나(PRD §6 기본 창). 구성 이력과 무관한 화면 설정이다.
@MainActor
protocol LastBoardRecord: AnyObject {
    var lastBoardID: UUID? { get set }
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
}
