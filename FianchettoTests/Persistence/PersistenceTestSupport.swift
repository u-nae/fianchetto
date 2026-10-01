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

private func restorePermissions(under directory: URL) {
    let paths = FileManager.default.enumerator(atPath: directory.path)?.compactMap { $0 as? String } ?? []
    for path in paths {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: directory.appending(path: path).path)
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
