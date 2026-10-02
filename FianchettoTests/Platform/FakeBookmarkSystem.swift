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

/// 실제 Foundation 북마크 호출을 쓰되, 지정한 이름의 대상은 북마크 생성을 실패시키고 호출 스레드를 기록한다.
final class ScriptedBookmarkSystem: BookmarkSystem {
    private let real = FoundationBookmarkSystem()
    private let state = Mutex((failNames: Set<String>(), failuresLeft: Int.max, onMain: [Bool]()))

    /// names의 대상 생성을 times번까지 실패시킨다.
    func fail(_ names: Set<String>, times: Int = .max) {
        state.withLock { $0.failNames = names; $0.failuresLeft = times }
    }

    var creationOnMainThread: [Bool] { state.withLock { $0.onMain } }

    func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        let fails = state.withLock { state -> Bool in
            state.onMain.append(Thread.isMainThread)
            guard state.failNames.contains(url.lastPathComponent), state.failuresLeft > 0 else { return false }
            state.failuresLeft -= 1
            return true
        }
        if fails { throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError) }
        return try real.bookmarkData(for: url, options: options)
    }

    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> (url: URL, isStale: Bool) {
        try real.resolve(data, options: options)
    }

    func bookmarkedPath(of data: Data) -> String? { real.bookmarkedPath(of: data) }
    func volumePath(of data: Data) throws -> String? { try real.volumePath(of: data) }
    func itemKind(at url: URL) throws -> LinkedTarget.Kind { try real.itemKind(at: url) }
    func fileExists(atPath path: String) -> Bool { real.fileExists(atPath: path) }
}

/// 임시 디렉토리에 파일·폴더를 만든다.
enum TargetFiles {
    static func file(_ directory: URL, _ relative: String, contents: String? = nil) throws -> URL {
        let url = directory.appending(path: relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((contents ?? "내용 \(relative)").utf8).write(to: url)
        return url
    }

    static func folder(_ directory: URL, _ relative: String) throws -> URL {
        let url = directory.appending(path: relative, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
