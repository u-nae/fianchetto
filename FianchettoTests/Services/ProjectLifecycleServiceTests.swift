import Foundation
import Testing
@testable import Fianchetto

@Suite("Board 보관·보관 해제 서비스 (W10)")
struct ProjectLifecycleServiceTests {
    @Test("[W10-archive-no-revision] 보관과 보관 해제는 revision을 만들지 않고 저장소를 다시 열어도 유지된다")
    func archiveAndUnarchiveCreateNoRevision() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            let current = try #require(try await harness.store.project(project)).currentRevisionID

            #expect(try await harness.lifecycle.setArchived(project, true) == .changed)
            let archived = try #require(try await harness.store.project(project))
            #expect(archived.archivedAt == date(500))
            #expect(archived.currentRevisionID == current)
            #expect(try await harness.store.revisionSummaries(projectID: project).count == 1)
            try harness.reopened { store throws in
                #expect(try store.project(project)?.archivedAt == date(500))
            }

            #expect(try await harness.lifecycle.setArchived(project, false) == .changed)
            #expect(try await harness.store.project(project)?.archivedAt == nil)
            #expect(try await harness.store.revisionSummaries(projectID: project).count == 1)
        }
    }

    @Test("[W10-archive-idempotent] 보관과 보관 해제를 같은 상태로 다시 요청하면 아무것도 바뀌지 않는다")
    func repeatedRequestsChangeNothing() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory)
            let active = try await makeBoard(harness, "서비스 A")
            let archived = try await makeBoard(harness, "옛 프로젝트")
            _ = try await harness.lifecycle.setArchived(archived, true)

            #expect(try await harness.lifecycle.setArchived(archived, true) == .unchanged)
            #expect(try await harness.store.project(archived)?.archivedAt == date(500))
            #expect(try await harness.lifecycle.setArchived(active, false) == .unchanged)
            #expect(try await harness.store.project(active)?.archivedAt == nil)
        }
    }

    @Test("[W10-archive-save-failure] 보관·보관 해제 저장이 실패하면 상태가 그대로다", arguments: [true, false])
    func saveFailureKeepsState(archiving: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)
            if !archiving { _ = try await harness.lifecycle.setArchived(project, true) }
            let before = try await harness.store.project(project)?.archivedAt
            harness.fault.failNext()

            await #expect(throws: ConfigurationServiceError.saveFailed) { try await harness.lifecycle.setArchived(project, archiving) }

            #expect(try await harness.store.project(project)?.archivedAt == before)
            try harness.reopened { store throws in
                #expect(try store.project(project)?.archivedAt == before)
            }
        }
    }

    @Test("[W10-archive-missing-project] 없는 Board는 보관할 수 없다")
    func missingProject() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory)
            let project = try await makeBoard(harness)

            #expect(try await harness.lifecycle.setArchived(fixedID(404), true) == .rejected(.projectNotFound))
            #expect(try await harness.store.project(project)?.archivedAt == nil)
            #expect(try await harness.store.projects().count == 1)
        }
    }
}
