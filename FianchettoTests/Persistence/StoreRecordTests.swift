import Foundation
import SwiftData
import Testing
@testable import Fianchetto

@Suite("저장소 레코드 (W04)")
struct StoreRecordTests {
    typealias R = RecordFixtures

    @Test("[W04-records-survive-reopen] 저장한 레코드는 저장소를 닫았다 다시 열어도 같은 값으로 읽힌다")
    func recordsSurviveReopen() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            try withStore(at: url, seedBasicRecords)

            try withStore(at: url) { store throws in
                #expect(try store.project(R.project) == R.projectRecord())
                let summaries = try store.revisionSummaries(projectID: R.project)
                #expect(summaries.map(\.id) == [R.r1, R.r2])
                #expect(summaries.map(\.cause) == [.created, .edited(.renameNode)])
                #expect(summaries.map(\.recordedAt) == [date(0), date(30)])
                #expect(summaries.map(\.projectName) == ["서비스 A", "서비스 A"])
                #expect(try store.reference(SnapshotFixtures.backendReference) == R.backendReference)
                #expect(try store.checkpoints(revisionID: R.r2) == [R.checkpoint()])
                let expected = SnapshotFixtures.serviceA().updating(SnapshotFixtures.backend) { $0.displayName = "api" }
                #expect(try store.snapshot(revisionID: R.r2) == expected)
            }
        }
    }

    @Test("[W04-revision-summaries-without-decoding] revision 목록 정보는 스냅샷을 디코딩하지 않고 읽는다")
    func summariesDoNotDecodeSnapshots() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            try withStore(at: url) { store throws in
                try store.insert(R.projectRecord())
                try store.insertRevision(R.revision(R.r1, sequence: 1))
                try store.insertRevision(R.revision(R.r2, sequence: 2, at: 30))
                try store.save()
                try corruptSnapshot(of: R.r2, in: store.context)
            }

            try withStore(at: url) { store throws in
                #expect(try store.revisionSummaries(projectID: R.project).map(\.sequence) == [1, 2])
                #expect(try store.snapshot(revisionID: R.r1) == R.snapshot())
                #expect(throws: StoreReadError.snapshot(.malformed)) { try store.snapshot(revisionID: R.r2) }
            }
        }
    }

    @Test("[W04-revision-list-by-project-sequence] revision 목록은 프로젝트별로 순번 순서다")
    func summariesAreFilteredAndOrdered() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try store.insert(R.projectRecord(current: R.r3))
                try store.insert(R.projectRecord(R.otherProject, current: fixedID(519)))
                try store.insertRevision(R.revision(R.r3, sequence: 3, at: 0))
                try store.insertRevision(R.revision(R.r1, sequence: 1, at: 50))
                try store.insertRevision(R.revision(R.r2, sequence: 2, at: 40))
                try store.insertRevision(R.revision(fixedID(519), project: R.otherProject, sequence: 1))
                try store.save()

                let summaries = try store.revisionSummaries(projectID: R.project)

                #expect(summaries.map(\.id) == [R.r1, R.r2, R.r3])
                #expect(summaries.allSatisfy { $0.projectID == R.project })
            }
        }
    }

    @Test("[W04-revision-columns-from-snapshot] revision의 프로젝트 이름과 스냅샷 schema version은 저장하는 스냅샷에서 만든다")
    func columnsComeFromSnapshot() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            try withStore(at: url) { store throws in
                try store.insert(R.projectRecord(current: R.r1))
                try store.insertRevision(R.revision(R.r1, sequence: 1, snapshot: R.snapshot(named: "서비스 B")))
                try store.save()
            }

            try withStore(at: url) { store throws in
                let summary = try #require(try store.revisionSummaries(projectID: R.project).first)
                #expect(summary.projectName == "서비스 B")
                #expect(try store.snapshot(revisionID: R.r1).projectName == summary.projectName)
                let model = try #require(try rawRevision(R.r1, in: store.context))
                #expect(model.snapshotSchemaVersion == SnapshotCodec.currentSchemaVersion)
            }
        }
    }

    static let causes: [RevisionCause] = [.created] + RevisionCause.EditKind.allCases.map { .edited($0) }
        + [.restored(from: RecordFixtures.r1), .duplicated, .imported]

    @Test("[W04-revision-cause-preserved] revision 원인과 복원 출처를 그대로 보존한다", arguments: causes)
    func causeIsPreserved(cause: RevisionCause) throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            try withStore(at: url) { store throws in
                try store.insert(R.projectRecord(current: R.r2))
                try store.insertRevision(R.revision(R.r2, sequence: 1, cause: cause))
                try store.save()
            }

            try withStore(at: url) { store throws in
                #expect(try store.revisionSummaries(projectID: R.project).first?.cause == cause)
            }
        }
    }

    @Test("[W04-project-archive-and-origin-preserved] 프로젝트의 보관 시각과 출처를 그대로 보존한다", arguments: [
        (nil as Date?, nil as ProjectOrigin?),
        (date(500), nil),
        (nil, ProjectOrigin(kind: .duplicate, sourceProjectID: fixedID(600), sourceRevisionID: fixedID(609))),
        (date(500), ProjectOrigin(kind: .import, sourceProjectID: fixedID(600), sourceRevisionID: fixedID(609))),
    ])
    func archiveAndOriginArePreserved(archivedAt: Date?, origin: ProjectOrigin?) throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let record = R.projectRecord(archivedAt: archivedAt, origin: origin)
            try withStore(at: url) { store throws in
                try store.insert(record)
                try store.save()
            }

            try withStore(at: url) { store throws in
                #expect(try store.project(R.project) == record)
            }
        }
    }

    enum DamagedShape: String, CaseIterable, Sendable {
        case restoredWithoutSource, sourceWithoutRestored, unknownCause, partialOrigin, unknownOriginKind
    }

    @Test("[W04-provenance-shape-enforced] 0005 형태 규칙을 어긴 저장 레코드는 손상 레코드로 읽는다", arguments: DamagedShape.allCases)
    func damagedRecordsAreReported(shape: DamagedShape) throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try seedBasicRecords(store)
                let bad = fixedID(599)
                switch shape {
                case .restoredWithoutSource, .sourceWithoutRestored, .unknownCause:
                    let model = SchemaV1.RevisionModel(
                        id: bad, projectID: R.project, sequence: 9, recordedAt: date(90),
                        cause: shape == .unknownCause ? "rollback" : (shape == .restoredWithoutSource ? "restored" : "renameNode"),
                        restoredFromRevisionID: shape == .sourceWithoutRestored ? R.r1 : nil,
                        projectName: "서비스 A", snapshotSchemaVersion: 1, snapshotData: Data()
                    )
                    store.context.insert(model)
                    try store.save()
                    #expect(throws: StoreReadError.damagedRecord(bad)) { try store.revisionSummary(bad) }
                    #expect(try store.revisionSummary(R.r1)?.sequence == 1)
                case .partialOrigin, .unknownOriginKind:
                    let model = SchemaV1.ProjectModel(
                        id: bad, createdAt: date(0), currentRevisionID: R.r1, archivedAt: nil,
                        originKind: shape == .partialOrigin ? "duplicate" : "fork",
                        originProjectID: fixedID(600), originRevisionID: shape == .partialOrigin ? nil : fixedID(609)
                    )
                    store.context.insert(model)
                    try store.save()
                    #expect(throws: StoreReadError.damagedRecord(bad)) { try store.project(bad) }
                    #expect(try store.project(R.project) == R.projectRecord())
                }
            }
        }
    }

    @Test("[W04-checkpoints-and-attachments-preserved] 한 revision에 체크포인트 여러 개와 첨부 참조를 저장한다")
    func checkpointsAndAttachmentsArePreserved() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let attachments = [
                AttachmentRecord(id: fixedID(531), relativePath: "attachments/A1.png", mediaType: "image/png", byteCount: 1024),
                AttachmentRecord(id: fixedID(532), relativePath: "attachments/A2.jpg", mediaType: "image/jpeg", byteCount: 2048),
            ]
            var empty = R.checkpoint()
            empty.progressNote = ""
            empty.nextSteps = ""
            let c2 = R.checkpoint(R.c2, attachments: attachments)
            try withStore(at: url) { store throws in
                try store.insert(R.projectRecord())
                try store.insertRevision(R.revision(R.r2, sequence: 1))
                try store.insert(empty)
                try store.insert(c2)
                try store.save()
            }

            try withStore(at: url) { store throws in
                let checkpoints = try store.checkpoints(revisionID: R.r2)
                #expect(Set(checkpoints) == [empty, c2])
                #expect(checkpoints.first { $0.id == R.c2 }?.attachments == attachments)
            }
        }
    }

    @Test("[W04-reference-update-leaves-revisions] 연결 참조의 북마크와 해석 경로를 갱신해도 revision 스냅샷은 바뀌지 않는다")
    func referenceUpdateLeavesRevisions() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let before = try withStore(at: url) { store throws in
                try seedBasicRecords(store)
                return try #require(try rawRevision(R.r2, in: store.context)).snapshotData
            }

            try withStore(at: url) { store throws in
                try store.updateReference(
                    SnapshotFixtures.backendReference, bookmarkData: Data([0xB2]), lastResolvedPath: "/Volumes/ext/legacy-api"
                )
                try store.save()
            }

            try withStore(at: url) { store throws in
                let reference = try #require(try store.reference(SnapshotFixtures.backendReference))
                #expect(reference.bookmarkData == Data([0xB2]))
                #expect(reference.lastResolvedPath == "/Volumes/ext/legacy-api")
                #expect(reference.initialPath == "/dev/legacy-api")
                #expect(try rawRevision(R.r2, in: store.context)?.snapshotData == before)
            }
        }
    }

    @Test("[W04-revision-bytes-stable] 저장된 revision 스냅샷 바이트는 읽고 다시 저장해도 바뀌지 않는다")
    func revisionBytesAreStable() throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let before = try withStore(at: url) { store throws in
                try seedBasicRecords(store)
                return try #require(try rawRevision(R.r1, in: store.context)).snapshotData
            }

            try withStore(at: url) { store throws in
                _ = try store.snapshot(revisionID: R.r1)
                try store.insertRevision(R.revision(R.r3, sequence: 3, at: 90))
                try store.updateProject(R.project, currentRevisionID: R.r3, archivedAt: nil)
                try store.save()
            }

            try withStore(at: url) { store throws in
                #expect(try rawRevision(R.r1, in: store.context)?.snapshotData == before)
            }
        }
    }

    enum Duplicate: String, CaseIterable, Sendable {
        case revisionID, projectSequence, projectID, referenceID, checkpointID
    }

    @Test("[W04-existing-records-not-overwritten] 이미 있는 레코드는 덮어쓰지 않는다", arguments: Duplicate.allCases)
    func existingRecordsAreNotOverwritten(duplicate: Duplicate) throws {
        try withTemporaryDirectory { directory throws in
            let url = directory.appending(path: "Fianchetto.store")
            let r1Bytes = try withStore(at: url) { store throws in
                try seedBasicRecords(store)
                return try #require(try rawRevision(R.r1, in: store.context)).snapshotData
            }

            try withStore(at: url) { store throws in
                switch duplicate {
                case .revisionID:
                    #expect(throws: StoreWriteError.duplicateRevision(R.r1)) {
                        try store.insertRevision(R.revision(R.r1, sequence: 7, cause: .imported, snapshot: R.snapshot(named: "다른 이름")))
                    }
                case .projectSequence:
                    #expect(throws: StoreWriteError.duplicateSequence(projectID: R.project, sequence: 1)) {
                        try store.insertRevision(R.revision(fixedID(598), sequence: 1))
                    }
                case .projectID:
                    #expect(throws: StoreWriteError.duplicateProject(R.project)) {
                        try store.insert(R.projectRecord(current: R.r1, archivedAt: date(1)))
                    }
                case .referenceID:
                    var other = R.backendReference
                    other.initialPath = "/other"
                    #expect(throws: StoreWriteError.duplicateReference(other.id)) { try store.insert(other) }
                case .checkpointID:
                    var other = R.checkpoint()
                    other.title = "다른 제목"
                    #expect(throws: StoreWriteError.duplicateCheckpoint(R.c1)) { try store.insert(other) }
                }
                try store.save()
            }

            try withStore(at: url) { store throws in
                #expect(try store.context.fetchCount(FetchDescriptor<SchemaV1.ProjectModel>()) == 1)
                #expect(try store.context.fetchCount(FetchDescriptor<SchemaV1.RevisionModel>()) == 2)
                #expect(try store.context.fetchCount(FetchDescriptor<SchemaV1.ResourceReferenceModel>()) == 1)
                #expect(try store.context.fetchCount(FetchDescriptor<SchemaV1.CheckpointModel>()) == 1)
                #expect(try store.project(R.project) == R.projectRecord())
                #expect(try store.reference(R.backendReference.id) == R.backendReference)
                #expect(try store.checkpoints(revisionID: R.r2) == [R.checkpoint()])
                #expect(try store.revisionSummary(R.r1)?.cause == .created)
                #expect(try rawRevision(R.r1, in: store.context)?.snapshotData == r1Bytes)
            }
        }
    }

    @Test("[W04-same-sequence-other-project-allowed] 다른 Project의 같은 순번은 허용한다")
    func sameSequenceInOtherProjectIsAllowed() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                try store.insert(R.projectRecord(current: R.r1))
                try store.insert(R.projectRecord(R.otherProject, current: fixedID(519)))
                try store.insertRevision(R.revision(R.r1, sequence: 1))
                try store.insertRevision(R.revision(fixedID(519), project: R.otherProject, sequence: 1))
                try store.save()

                #expect(try store.revisionSummaries(projectID: R.project).map(\.sequence) == [1])
                #expect(try store.revisionSummaries(projectID: R.otherProject).map(\.sequence) == [1])
            }
        }
    }

    @Test("[W04-existing-records-not-overwritten] 없는 Project의 revision과 없는 revision의 체크포인트는 거부한다")
    func ownersMustExist() throws {
        try withTemporaryDirectory { directory throws in
            try withStore(at: directory.appending(path: "Fianchetto.store")) { store throws in
                #expect(throws: StoreWriteError.missingProject(R.project)) {
                    try store.insertRevision(R.revision(R.r1, sequence: 1))
                }
                #expect(throws: StoreWriteError.missingRevision(R.r2)) { try store.insert(R.checkpoint()) }
            }
        }
    }

    // MARK: 도우미

    private func rawRevision(_ id: UUID, in context: ModelContext) throws -> SchemaV1.RevisionModel? {
        try context.fetch(FetchDescriptor<SchemaV1.RevisionModel>(predicate: #Predicate { $0.id == id })).first
    }

    private func corruptSnapshot(of id: UUID, in context: ModelContext) throws {
        let model = try #require(try rawRevision(id, in: context))
        model.snapshotData = Data("{\"schemaVersion\":1,".utf8)
        try context.save()
    }
}
