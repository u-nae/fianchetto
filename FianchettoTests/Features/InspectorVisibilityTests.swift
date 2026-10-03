import Foundation
import Testing
@testable import Fianchetto

/// 오른쪽 열(인스펙터)을 접고 펴는 화면 설정. 구성 기록과 무관하며 마지막 상태를 기억한다.
@MainActor
@Suite("인스펙터 접기")
struct InspectorVisibilityTests {
    @Test("인스펙터는 처음에 보이고, 접고 펴면 화면 설정에 기억된다")
    func toggleRemembers() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let lastBoard = InMemoryLastBoard()
            let harness = BrowserHarness(directory: directory.appending(path: "browser"), lastBoard: lastBoard)
            await harness.model.start()
            #expect(harness.model.isInspectorPresented)

            harness.model.toggleInspector()
            #expect(!harness.model.isInspectorPresented)
            #expect(lastBoard.isInspectorHidden)

            harness.model.toggleInspector()
            #expect(harness.model.isInspectorPresented)
            #expect(!lastBoard.isInspectorHidden)
        }
    }

    @Test("기억된 설정이 접힘이면 다음 실행에서도 접혀 있다")
    func restoresHidden() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let lastBoard = InMemoryLastBoard()
            lastBoard.isInspectorHidden = true
            let harness = BrowserHarness(directory: directory.appending(path: "browser"), lastBoard: lastBoard)
            #expect(!harness.model.isInspectorPresented)
        }
    }

    @Test("화면에서 직접 닫아도(바인딩) 같은 설정에 기억된다")
    func bindingSetRemembers() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let lastBoard = InMemoryLastBoard()
            let harness = BrowserHarness(directory: directory.appending(path: "browser"), lastBoard: lastBoard)
            harness.model.isInspectorPresented = false
            #expect(lastBoard.isInspectorHidden)
        }
    }

    @Test("파일 기록과 UserDefaults 기록 모두 인스펙터 설정을 저장하고 지울 수 있다")
    func records() throws {
        try withTemporaryDirectory { directory in
            let file = FileLastBoard(url: directory.appending(path: "ui/lastBoard"))
            #expect(!file.isInspectorHidden)
            file.isInspectorHidden = true
            #expect(FileLastBoard(url: directory.appending(path: "ui/lastBoard")).isInspectorHidden)
            file.isInspectorHidden = false
            #expect(!file.isInspectorHidden)

            let suite = "fianchetto-test-\(directory.lastPathComponent)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let stored = UserDefaultsLastBoard(defaults: defaults)
            #expect(!stored.isInspectorHidden)
            stored.isInspectorHidden = true
            #expect(UserDefaultsLastBoard(defaults: defaults).isInspectorHidden)
        }
    }
}
