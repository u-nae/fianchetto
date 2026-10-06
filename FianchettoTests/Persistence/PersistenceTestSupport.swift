import Foundation
import SwiftData
import Testing
@testable import Fianchetto

/// 테스트마다 시스템이 고유하게 만들어 주는 임시 디렉토리. 본문이 끝나면 지운다.
func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = try FileManager.default.url(
        for: .itemReplacementDirectory, in: .userDomainMask,
        appropriateFor: FileManager.default.temporaryDirectory, create: true
    )
    defer {
        restorePermissions(under: directory)
        try? FileManager.default.removeItem(at: directory)
    }
    return try body(directory)
}

/// 비동기 테스트용 임시 디렉토리.
func withTemporaryDirectoryAsync(
    isolation: isolated (any Actor)? = #isolation,
    _ body: (URL) async throws -> Void
) async throws {
    let directory = try FileManager.default.url(
        for: .itemReplacementDirectory, in: .userDomainMask,
        appropriateFor: FileManager.default.temporaryDirectory, create: true
    )
    defer {
        restorePermissions(under: directory)
        try? FileManager.default.removeItem(at: directory)
    }
    try await body(directory)
}

/// 테스트가 막아 둔 권한을 되돌려 지울 수 있게 한다. 폴더는 먼저 열어야 안을 볼 수 있으므로 위에서 아래로 내려가며,
/// 폴더에는 실행 권한을 준다(없으면 안의 항목을 지우지 못한다). 심볼릭 링크는 따라가지 않는다(바깥 대상의 권한을 바꾸지 않는다).
private func restorePermissions(under directory: URL) {
    let fileManager = FileManager.default
    let children = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in children {
        let item = directory.appending(path: name)
        guard let type = (try? fileManager.attributesOfItem(atPath: item.path))?[.type] as? FileAttributeType else { continue }
        switch type {
        case .typeDirectory:
            try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: item.path)
            restorePermissions(under: item)
        case .typeSymbolicLink:
            continue
        default:
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: item.path)
        }
    }
}

func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_790_000_000 + seconds) }

enum RecordFixtures {
    static let project = fixedID(500)
    static let otherProject = fixedID(501)
    static let r1 = fixedID(511)
    static let r2 = fixedID(512)
    static let r3 = fixedID(513)
    static let c1 = fixedID(521)
    static let c2 = fixedID(522)

    static func projectRecord(
        _ id: UUID = project, current: UUID = r2, archivedAt: Date? = nil, origin: ProjectOrigin? = nil
    ) -> ProjectRecord {
        ProjectRecord(id: id, createdAt: date(0), currentRevisionID: current, archivedAt: archivedAt, origin: origin)
    }

    static func snapshot(named name: String = "서비스 A") -> ConfigurationSnapshot {
        var snapshot = SnapshotFixtures.serviceA()
        snapshot.projectName = name
        return snapshot
    }

    static func revision(
        _ id: UUID, project: UUID = project, sequence: Int, at seconds: TimeInterval = 0,
        cause: RevisionCause = .created, snapshot: ConfigurationSnapshot = snapshot()
    ) -> RevisionDraft {
        RevisionDraft(id: id, projectID: project, sequence: sequence, recordedAt: date(seconds), cause: cause, snapshot: snapshot)
    }

    static let backendReference = ResourceReferenceRecord(
        id: SnapshotFixtures.backendReference, initialPath: "/dev/legacy-api", kind: .folder,
        bookmarkData: Data([0xB1, 0x01]), lastResolvedPath: "/dev/legacy-api"
    )

    static func checkpoint(_ id: UUID = c1, revision: UUID = r2, attachments: [AttachmentRecord] = []) -> CheckpointRecord {
        CheckpointRecord(
            id: id, revisionID: revision, title: "인증 리팩토링 1차 완료",
            progressNote: "토큰 갱신까지 끝냄", nextSteps: "권한 화면 연결", createdAt: date(60), attachments: attachments
        )
    }
}

/// 운영 열기 경로로 임시 디렉토리의 저장소를 열어 어댑터로 작업한다.
func withStore<T>(at url: URL, _ body: (StoreAdapter) throws -> T) throws -> T {
    let container = try StoreOpener.open(at: url)
    let adapter = StoreAdapter(context: ModelContext(container))
    return try body(adapter)
}

/// 기본 레코드 묶음: Project P, R1·R2, ref-backend, C1.
func seedBasicRecords(_ store: StoreAdapter) throws {
    try store.insert(RecordFixtures.projectRecord())
    try store.insertRevision(RecordFixtures.revision(RecordFixtures.r1, sequence: 1, at: 0))
    try store.insertRevision(RecordFixtures.revision(
        RecordFixtures.r2, sequence: 2, at: 30, cause: .edited(.renameNode),
        snapshot: SnapshotFixtures.serviceA().updating(SnapshotFixtures.backend) { $0.displayName = "api" }
    ))
    try store.insert(RecordFixtures.backendReference)
    try store.insert(RecordFixtures.checkpoint())
    try store.save()
}

/// 저장소 파일과 -wal·-shm 보조 파일의 현재 바이트. 없는 파일은 nil.
func storeFileBytes(_ url: URL) -> [String: Data?] {
    var result: [String: Data?] = [:]
    for suffix in ["", "-wal", "-shm"] {
        let file = URL(filePath: url.path + suffix)
        result[suffix] = try? Data(contentsOf: file)
    }
    return result
}

/// fixture를 만든 연결이 같은 프로세스에 살아 있으면 보조 파일이 계속 바뀐다.
/// 그래서 다른 위치의 저장소 파일 묶음을 복사해, 열린 연결이 없는 저장소로 검사하거나 "다시 연" 상태를 만든다.
func copyStoreFiles(from source: URL, to destination: URL) throws {
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    for suffix in ["", "-wal", "-shm"] {
        let file = URL(filePath: source.path + suffix)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.copyItem(at: file, to: URL(filePath: destination.path + suffix))
        }
    }
}
