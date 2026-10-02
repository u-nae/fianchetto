import Foundation

struct BookmarkCreation: Equatable, Sendable {
    var bookmarkData: Data
    var kind: LinkedTarget.Kind
    /// 사용자가 고른 표기에서 "."·".."만 정리한 절대 경로. 심볼릭 링크는 풀지 않는다.
    var path: String
}

struct BookmarkResolution: Equatable, Sendable {
    var url: URL
    /// stale이거나 해석 위치가 북마크 기록 위치와 다를 때 새 위치로 만든 북마크. 저장은 호출자가 한다(불변식 8).
    var refreshedBookmark: Data?
    /// 갱신이 필요했지만 새 북마크를 만들지 못했다. 해석 자체는 성공이다.
    var refreshFailed: Bool
}

enum BookmarkFailureCause: Error, Equatable, Sendable {
    case volumeUnavailable
    case missing
    case accessDenied
    case checkFailed
}

enum BookmarkError: Error, Equatable, Sendable {
    case creationFailed
    case resolutionFailed(BookmarkFailureCause)
}

/// Foundation 북마크·리소스 값 호출을 감싼 얇은 계층. 테스트에서 OS 동작을 재현하려고 분리한다.
protocol BookmarkSystem: Sendable {
    func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data
    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> (url: URL, isStale: Bool)
    /// 북마크가 기록한 대상 경로.
    func bookmarkedPath(of data: Data) -> String?
    /// 북마크가 기록한 볼륨 경로. 읽지 못하면 오류.
    func volumePath(of data: Data) throws -> String?
    func itemKind(at url: URL) throws -> LinkedTarget.Kind
    func fileExists(atPath path: String) -> Bool
}

protocol SecurityScopedResource {
    func startAccessingSecurityScopedResource() -> Bool
    func stopAccessingSecurityScopedResource()
}

extension URL: SecurityScopedResource {}

/// 읽기 전용 보안 범위 북마크 어댑터(0001). 대상 파일을 쓰거나 옮기지 않는다.
/// 동기 함수이며 MainActor에 묶이지 않는다. 파일 I/O이므로 호출자가 MainActor 밖에서 부른다.
struct BookmarkAdapter: Sendable {
    static let creationOptions: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
    /// 해석 중 UI를 띄우거나 볼륨을 자동 마운트하지 않는다. 분리된 볼륨은 volumeUnavailable로 드러난다.
    static let resolutionOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI, .withoutMounting]

    let system: any BookmarkSystem

    func createBookmark(for url: URL) throws(BookmarkError) -> BookmarkCreation {
        let standardized = url.standardizedFileURL
        do {
            let kind = try system.itemKind(at: standardized)
            let data = try system.bookmarkData(for: standardized, options: Self.creationOptions)
            return BookmarkCreation(bookmarkData: data, kind: kind, path: standardized.path)
        } catch {
            throw .creationFailed
        }
    }

    /// 대상의 종류(패키지는 파일). 대상이 없거나 읽을 수 없으면 생성 실패로 본다.
    func kind(of url: URL) throws(BookmarkError) -> LinkedTarget.Kind {
        do {
            return try system.itemKind(at: url.standardizedFileURL)
        } catch {
            throw .creationFailed
        }
    }

    func resolve(_ data: Data) throws(BookmarkError) -> BookmarkResolution {
        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try system.resolve(data, options: Self.resolutionOptions)
        } catch {
            let cause = BookmarkFailureRule.classify(volume: volumeState(of: data), error: failureEvidence(data, scopedError: error))
            throw .resolutionFailed(cause)
        }
        let moved = system.bookmarkedPath(of: data).map { Self.canonical($0) != Self.canonical(resolved.url.path) } ?? false
        guard resolved.isStale || moved else {
            return BookmarkResolution(url: resolved.url, refreshedBookmark: nil, refreshFailed: false)
        }
        let refreshed = withAccess(to: resolved.url) {
            try? system.bookmarkData(for: resolved.url, options: Self.creationOptions)
        }
        return BookmarkResolution(url: resolved.url, refreshedBookmark: refreshed, refreshFailed: refreshed == nil)
    }

    /// 원인 분류에 쓸 오류 범주. sandbox에서는 보안 범위 해석이 원인과 상관없이 형식 오류로 실패할 수 있어(삭제된 대상 등),
    /// 그때는 분류용으로만 범위 없이 다시 해석해 OS가 파일 ID로 찾은 결과의 오류를 쓴다. 다시 해석한 URL은 쓰지 않는다.
    /// 경로 존재 확인은 근거로 쓰지 않는다. sandbox에서는 권한 없는 파일도 없는 것처럼 보이기 때문이다.
    private func failureEvidence(_ data: Data, scopedError: any Error) -> BookmarkFailureRule.ErrorKind {
        let scoped = BookmarkFailureRule.errorKind(scopedError)
        guard scoped == .other else { return scoped }
        var options = Self.resolutionOptions
        options.remove(.withSecurityScope)
        do {
            _ = try system.resolve(data, options: options)
            return scoped
        } catch {
            return BookmarkFailureRule.errorKind(error)
        }
    }

    /// 같은 대상 판정(0004)에 쓸 위치. 보안 범위 해석이 실패하면 식별자 확인용으로만 범위 없이 다시 해석한다.
    /// 이 위치로 파일에 접근하지 않는다. 둘 다 실패하면 nil(식별자 없음 → 판정 불가).
    func identityURL(of data: Data) -> URL? {
        if let resolved = try? system.resolve(data, options: Self.resolutionOptions) { return resolved.url }
        var options = Self.resolutionOptions
        options.remove(.withSecurityScope)
        return try? system.resolve(data, options: options).url
    }

    func volumeState(of data: Data) -> BookmarkFailureRule.VolumeState {
        guard let path = try? system.volumePath(of: data) else { return .unknown }
        return system.fileExists(atPath: path) ? .mounted : .unmounted
    }

    /// 작업은 접근 시작 결과와 상관없이 한 번 실행한다. 종료는 시작이 성공했을 때만 정확히 한 번 한다.
    func withAccess<Value, Failure: Error>(
        to resource: some SecurityScopedResource,
        _ body: () throws(Failure) -> Value
    ) throws(Failure) -> Value {
        let started = resource.startAccessingSecurityScopedResource()
        defer {
            if started { resource.stopAccessingSecurityScopedResource() }
        }
        return try body()
    }

    /// 심볼릭 링크를 푼 실제 대상의 파일·볼륨 식별자(0004). 확정 시점에만 구하고 저장하지 않는다.
    func identity(of url: URL) -> FileSystemIdentity {
        let target = url.standardizedFileURL.resolvingSymlinksInPath()
        guard let values = try? target.resourceValues(forKeys: [.fileResourceIdentifierKey, .volumeIdentifierKey]) else {
            return FileSystemIdentity(file: nil, volume: nil)
        }
        return FileSystemIdentity(file: Self.archive(values.fileResourceIdentifier), volume: Self.archive(values.volumeIdentifier))
    }

    private static func archive(_ object: (any NSCopying & NSSecureCoding & NSObjectProtocol)?) -> Data? {
        guard let object else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
    }

    private static func canonical(_ path: String) -> String {
        URL(filePath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

/// 결정표 bookmark_failure_cause와 그 입력 매핑. 화면 상태 문구로 바꾸는 일은 W15가 한다.
enum BookmarkFailureRule {
    enum VolumeState: Sendable {
        case mounted
        case unmounted
        /// 북마크에서 볼륨 경로를 읽지 못했다.
        case unknown
    }

    enum ErrorKind: Sendable {
        case noSuchFile
        case noPermission
        case other
    }

    static func classify(volume: VolumeState, error: ErrorKind) -> BookmarkFailureCause {
        if volume == .unmounted { return .volumeUnavailable } // R1
        switch (volume, error) {
        case (_, .noPermission): return .accessDenied // R2
        case (.mounted, .noSuchFile): return .missing // R3
        default: return .checkFailed // R4·R5: 근거가 부족하면 존재 여부를 단정하지 않는다
        }
    }

    static func errorKind(_ error: any Error) -> ErrorKind {
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError),
             (NSPOSIXErrorDomain, Int(ENOENT)):
            return .noSuchFile
        case (NSCocoaErrorDomain, NSFileReadNoPermissionError),
             (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return .noPermission
        default:
            return .other
        }
    }
}

/// 실제 Foundation 호출.
struct FoundationBookmarkSystem: BookmarkSystem {
    func bookmarkData(for url: URL, options: URL.BookmarkCreationOptions) throws -> Data {
        try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func resolve(_ data: Data, options: URL.BookmarkResolutionOptions) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }

    func bookmarkedPath(of data: Data) -> String? {
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: data)?.path
    }

    func volumePath(of data: Data) throws -> String? {
        guard let values = URL.resourceValues(forKeys: [.volumeURLKey], fromBookmarkData: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return values.volume?.path
    }

    func itemKind(at url: URL) throws -> LinkedTarget.Kind {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        // 패키지(.app·.key 등 번들 폴더)는 Finder처럼 파일로 본다.
        return values.isDirectory == true && values.isPackage != true ? .folder : .file
    }

    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
