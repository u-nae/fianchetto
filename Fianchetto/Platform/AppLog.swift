import Foundation
import OSLog

/// 앱 전체의 OSLog 서브시스템과 카테고리.
/// 메모 원문, 이미지 내용, 전체 구성 JSON, 전체 경로 목록은 기록하지 않는다. 경로는 `privacy: .private`로 남긴다.
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.u-nae.Fianchetto"

    enum Category: String, CaseIterable, Sendable {
        case app
        case services
        case persistence
        case fileAccess = "file-access"
    }

    static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
