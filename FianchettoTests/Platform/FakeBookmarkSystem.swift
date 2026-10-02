import Foundation
import Synchronization
@testable import Fianchetto

/// OS 북마크 동작을 재현하는 가짜 시스템 어댑터. 호출 옵션을 기록한다.
final class FakeBookmarkSystem: BookmarkSystem {
    struct Behavior: Sendable {
        var resolvedURL = URL(filePath: "/tmp/design.md")
        var bookmarkedPath: String? = "/tmp/design.md"
        var isStale = false
        var resolveError: NSError?
        /// 보안 범위 없이 해석할 때의 결과. nil이면 resolveError와 같다. .success면 범위 없는 해석은 성공한다.
        var unscopedResolve: Result<Void, NSError>?
        var volumePath: Result<String?, NSError> = .success("/")
        var existingPaths: Set<String> = ["/"]
        var creationFails = false
        var kind: LinkedTarget.Kind = .file
    }

    private let state: Mutex<(behavior: Behavior, creationOptions: [URL.BookmarkCreationOptions], resolutionOptions: [URL.BookmarkResolutionOptions])>

    init(_ behavior: Behavior = Behavior()) {
        state = Mutex((behavior, [], []))
    }

    var creationOptions: [URL.BookmarkCreationOptions] { state.withLock { $0.creationOptions } }
    var resolutionOptions: [URL.BookmarkResolutionOptions] { state.withLock { $0.resolutionOptions } }

    func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        let fails = state.withLock { state in
            state.creationOptions.append(options)
            return state.behavior.creationFails
        }
        if fails { throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError) }
        return Data("bookmark:\(url.path)".utf8)
    }

    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> (url: URL, isStale: Bool) {
        let behavior = state.withLock { state in
            state.resolutionOptions.append(options)
            return state.behavior
        }
        if !options.contains(.withSecurityScope), let unscoped = behavior.unscopedResolve {
            try unscoped.get()
            return (behavior.resolvedURL, behavior.isStale)
        }
        if let error = behavior.resolveError { throw error }
        return (behavior.resolvedURL, behavior.isStale)
    }

    func bookmarkedPath(of data: Data) -> String? { state.withLock { $0.behavior.bookmarkedPath } }

    func volumePath(of data: Data) throws -> String? { try state.withLock { $0.behavior.volumePath }.get() }

    func itemKind(at url: URL) throws -> LinkedTarget.Kind { state.withLock { $0.behavior.kind } }

    func fileExists(atPath path: String) -> Bool { state.withLock { $0.behavior.existingPaths.contains(path) } }
}

/// 접근 시작 결과를 정하고 시작·종료 호출 수를 센다.
final class FakeScopedResource: SecurityScopedResource, Sendable {
    private let counts = Mutex((starts: 0, stops: 0))
    let startSucceeds: Bool

    init(startSucceeds: Bool) { self.startSucceeds = startSucceeds }

    var starts: Int { counts.withLock { $0.starts } }
    var stops: Int { counts.withLock { $0.stops } }

    func startAccessingSecurityScopedResource() -> Bool {
        counts.withLock { $0.starts += 1 }
        return startSucceeds
    }

    func stopAccessingSecurityScopedResource() {
        counts.withLock { $0.stops += 1 }
    }
}
