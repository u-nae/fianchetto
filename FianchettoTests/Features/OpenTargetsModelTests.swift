import Foundation
import Testing
@testable import Fianchetto

@MainActor
@Suite("현재 대상 열기와 Finder에서 보기 화면 (W14)")
struct OpenTargetsModelTests {
    @MainActor
    struct Opened {
        let harness: BrowserHarness
        let project: UUID
        let directory: URL
        let memoURL: URL
        let backendURL: URL
        var model: BoardBrowserModel { harness.model }
        var launcher: RecordingLauncher { harness.launcher }

        func id(_ name: String) throws -> UUID {
            try #require(model.loadedSnapshot?.node(named: name)).id
        }
    }

    /// 최상위: Bishop 파일 "설계 메모", Bishop 폴더 "backend", 웹 링크 "API 명세", 그룹 "개발".
    private func opened(_ directory: URL, archived: Bool = false) async throws -> Opened {
        let harness = BrowserHarness(directory: directory.appending(path: "browser"))
        let memo = try TargetFiles.file(directory, "targets/설계 메모.md", contents: "memo")
        let backend = try TargetFiles.folder(directory, "targets/backend")
        _ = try TargetFiles.file(directory, "targets/backend/main.swift", contents: "print(1)")
        var project = UUID()
        try await seedStore(in: directory, at: harness.url) { seed in
            let board = try await makeBoard(seed, "서비스 A")
            project = board
            _ = try await seed.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [memo, backend]))
            _ = try await seed.service.apply(.addWebLink(name: "API 명세", url: "https://example.com/api", parentID: nil, position: nil), to: board)
            _ = try await seed.service.apply(.addGroup(name: "개발", parentID: nil, position: nil), to: board)
            if archived { try await seed.store.setArchived(board, at: date(100)) }
        }
        await harness.model.start()
        await harness.model.select(project)
        return Opened(harness: harness, project: project, directory: directory, memoURL: memo, backendURL: backend)
    }

    private func revisionCount(_ o: Opened) async throws -> Int {
        try await o.model.openedStore!.store.revisionSummaries(projectID: o.project).count
    }

    private func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func targetState(_ directory: URL) throws -> [String: String] {
        let targets = directory.appending(path: "targets")
        var result: [String: String] = [:]
        for path in FileManager.default.enumerator(atPath: targets.path)?.compactMap({ $0 as? String }) ?? [] {
            let url = targets.appending(path: path)
            let modified = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? "<dir>"
            result[path] = "\(contents)|\(modified?.timeIntervalSinceReferenceDate ?? -1)"
        }
        return result
    }

    // MARK: 열기

    enum OpenCase: String, CaseIterable, Sendable { case fileByMenu, folderByDoubleClick, webLinkByMenu, webLinkByDoubleClick }

    @Test("[W14-open-current-target] 열기는 현재 대상을 기본 앱에 정확히 한 번 넘기고 기록하지 않는다", .tags(.A02), arguments: OpenCase.allCases)
    func openCurrentTarget(openCase: OpenCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisionCount(o)
            let files = try targetState(directory)

            switch openCase {
            case .fileByMenu:
                o.model.selectedNodeID = try o.id("설계 메모.md")
                await o.model.openSelected()
            case .folderByDoubleClick:
                await o.model.open(try o.id("backend"))
            case .webLinkByMenu:
                o.model.selectedNodeID = try o.id("API 명세")
                await o.model.openSelected()
            case .webLinkByDoubleClick:
                await o.model.open(try o.id("API 명세"))
            }

            #expect(o.launcher.opened.count == 1)
            #expect(o.launcher.revealed.isEmpty)
            let opened = try #require(o.launcher.opened.first)
            switch openCase {
            case .fileByMenu: #expect(canonical(opened) == canonical(o.memoURL))
            case .folderByDoubleClick: #expect(canonical(opened) == canonical(o.backendURL))
            case .webLinkByMenu, .webLinkByDoubleClick: #expect(opened.absoluteString == "https://example.com/api")
            }
            #expect(o.model.linkNotice == nil)
            #expect(try await revisionCount(o) == before)
            #expect(try targetState(directory) == files)
        }
    }

    enum ScopeCase: String, CaseIterable, Sendable { case openSucceeds, openFails, reveal, startFails }

    /// 시작이 실패해도 요청은 한 번 보낸다(접근 범위 없이도 열 수 있는 위치가 있다). 종료는 시작이 성공했을 때만 한다.
    @Test("[W14-access-scope-paired] 요청은 접근 범위 시작 뒤에 나가고 범위는 정확히 한 번 닫힌다", .tags(.A02), arguments: ScopeCase.allCases)
    func accessScopePaired(scopeCase: ScopeCase) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let events = o.launcher.events
            o.launcher.openSucceeds = scopeCase != .openFails
            events.startSucceeds = scopeCase != .startFails
            o.model.selectedNodeID = try o.id("설계 메모.md")

            if scopeCase == .reveal {
                await o.model.revealSelected()
            } else {
                await o.model.openSelected()
            }

            let expected = switch scopeCase {
            case .openSucceeds, .openFails: ["start", "open", "stop"]
            case .reveal: ["start", "reveal", "stop"]
            case .startFails: ["start", "open"]
            }
            #expect(events.events == expected)
            #expect((o.model.linkNotice != nil) == (scopeCase == .openFails))
        }
    }

    @Test("[W14-no-scope-when-unreachable] 대상을 찾지 못하면 접근 범위를 열지 않는다")
    func noScopeWhenUnreachable() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            try FileManager.default.removeItem(at: o.memoURL)
            o.model.selectedNodeID = try o.id("설계 메모.md")

            await o.model.openSelected()

            #expect(o.launcher.events.events.isEmpty)
            #expect(o.model.linkNotice != nil)
        }
    }

    @Test("[W14-open-moved-target] 옮겨진 대상은 지금 위치로 열고 기록 당시 경로는 그대로다", .tags(.A02))
    func openMovedTarget() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let moved = directory.appending(path: "targets/moved/설계 메모.md")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: o.memoURL, to: moved)
            let recorded = try #require(o.model.loadedSnapshot?.node(named: "설계 메모.md")).recordedPath
            let before = try await revisionCount(o)

            o.model.selectedNodeID = try o.id("설계 메모.md")
            await o.model.openSelected()

            #expect(o.launcher.opened.map(canonical) == [canonical(moved)])
            #expect(o.model.linkNotice == nil)
            let stored = try await o.model.openedStore!.store.currentSnapshot(projectID: o.project)
            #expect(stored.node(named: "설계 메모.md")?.recordedPath == recorded)
            #expect(try await revisionCount(o) == before)
        }
    }

    @Test("[W14-open-after-reopen] 저장소를 다시 열어도 저장된 접근 정보로 연다", .tags(.A02))
    func openAfterReopen() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let first = try await opened(directory)
            let reopened = BrowserHarness(directory: directory.appending(path: "browser"))
            await reopened.model.start()
            await reopened.model.select(first.project)

            reopened.model.selectedNodeID = try #require(reopened.model.loadedSnapshot?.node(named: "backend")).id
            await reopened.model.openSelected()

            #expect(reopened.launcher.opened.map(canonical) == [canonical(first.backendURL)])
            #expect(reopened.model.linkNotice == nil)
        }
    }

    @Test("[W14-open-archived] 보관된 Board의 항목도 열고 Finder에서 보며 보관 안내를 띄우지 않는다", arguments: [false, true])
    func openArchived(reveal: Bool) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory, archived: true)
            let before = try await revisionCount(o)
            o.model.selectedNodeID = try o.id("설계 메모.md")

            if reveal {
                await o.model.revealSelected()
            } else {
                await o.model.openSelected()
            }

            #expect((reveal ? o.launcher.revealed : o.launcher.opened).count == 1)
            #expect(o.model.linkNotice == nil)
            #expect(try await revisionCount(o) == before)
        }
    }

    // MARK: Finder에서 보기

    @Test("[W14-reveal-in-finder] Finder에서 보기는 Bishop 현재 위치를 한 번 보여 주고 열지 않으며 기록하지 않는다", .tags(.A02), arguments: [
        "설계 메모.md", "backend",
    ])
    func revealInFinder(item: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let before = try await revisionCount(o)
            o.model.selectedNodeID = try o.id(item)

            await o.model.revealSelected()

            let expected = item == "backend" ? o.backendURL : o.memoURL
            #expect(o.launcher.revealed.map(canonical) == [canonical(expected)])
            #expect(o.launcher.opened.isEmpty)
            #expect(try await revisionCount(o) == before)
        }
    }

    // MARK: 열 수 없는 경우

    enum Unreachable: String, CaseIterable, Sendable { case deletedOpen, deletedReveal, denied, volumeDetached, noEvidence }

    @Test("[W14-unreachable-target] 대상을 찾지 못하면 원인을 안내하고 아무것도 열지 않는다", arguments: Unreachable.allCases)
    func unreachableTarget(situation: Unreachable) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let memo = try o.id("설계 메모.md")
            switch situation {
            case .deletedOpen, .deletedReveal:
                try FileManager.default.removeItem(at: o.memoURL)
            case .denied:
                o.harness.bookmarks.failResolution(with: NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError))
            case .volumeDetached:
                o.harness.bookmarks.failResolution(with: NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError), volumeUnmounted: true)
            case .noEvidence:
                o.harness.bookmarks.failResolution(with: NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError))
            }
            let before = try await revisionCount(o)
            o.model.selectedNodeID = memo

            if situation == .deletedReveal {
                await o.model.revealSelected()
            } else {
                await o.model.openSelected()
            }

            #expect(o.launcher.opened.isEmpty)
            #expect(o.launcher.revealed.isEmpty)
            let notice = try #require(o.model.linkNotice)
            let expected = switch situation {
            case .deletedOpen, .deletedReveal: "열지 못했습니다. 상태: 대상 없음"
            case .denied: "열지 못했습니다. 상태: 권한 필요"
            case .volumeDetached: "열지 못했습니다. 상태: 볼륨 연결 필요"
            case .noEvidence: "열지 못했습니다. 상태: 확인 실패"
            }
            #expect(o.model.noticeText(notice) == expected)
            #expect(o.model.noticeTitle(notice) == "열기")
            #expect(o.model.loadedSnapshot?.nodes.contains { $0.id == memo } == true)
            #expect(try await revisionCount(o) == before)
        }
    }

    @Test("[W14-open-rejected] 기본 앱 열기 요청이 실패하면 안내한다", arguments: ["설계 메모.md", "API 명세"])
    func openRejected(item: String) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.launcher.openSucceeds = false
            let before = try await revisionCount(o)
            o.model.selectedNodeID = try o.id(item)

            await o.model.openSelected()

            let notice = try #require(o.model.linkNotice)
            #expect(notice.kind == .openFailed(.launchFailed))
            #expect(o.model.noticeText(notice) == "열지 못했습니다.")
            #expect(try await revisionCount(o) == before)
        }
    }

    enum Nothing: String, CaseIterable, Sendable { case noSelectionOpen, noSelectionReveal, groupOpen, groupReveal, groupDoubleClick, webLinkReveal }

    @Test("[W14-nothing-to-open] 열 대상이 없는 선택에서는 요청과 안내가 없다", arguments: Nothing.allCases)
    func nothingToOpen(selection: Nothing) async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            switch selection {
            case .noSelectionOpen:
                o.model.selectedNodeID = nil
                #expect(!o.model.canOpenSelected)
                await o.model.openSelected()
            case .noSelectionReveal:
                o.model.selectedNodeID = nil
                #expect(!o.model.canRevealSelected)
                await o.model.revealSelected()
            case .groupOpen:
                o.model.selectedNodeID = try o.id("개발")
                #expect(!o.model.canOpenSelected)
                await o.model.openSelected()
            case .groupReveal:
                o.model.selectedNodeID = try o.id("개발")
                #expect(!o.model.canRevealSelected)
                await o.model.revealSelected()
            case .groupDoubleClick:
                await o.model.open(try o.id("개발"))
            case .webLinkReveal:
                o.model.selectedNodeID = try o.id("API 명세")
                #expect(o.model.canOpenSelected)
                #expect(!o.model.canRevealSelected)
                await o.model.revealSelected()
            }
            #expect(o.launcher.opened.isEmpty)
            #expect(o.launcher.revealed.isEmpty)
            #expect(o.model.linkNotice == nil)
        }
    }

    @Test("[W14-nothing-to-open] 서비스도 그룹과 웹 링크의 Finder 보기·없는 항목에는 아무것도 하지 않는다")
    func serviceNotApplicable() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            let opening = o.model.openedStore!.opening
            let foreign = try #require(UUID(uuidString: "00000000-0000-0000-0000-00000000F00D"))
            #expect(await opening.perform(.reveal, projectID: o.project, nodeID: try o.id("API 명세")) == .notApplicable)
            #expect(await opening.perform(.open, projectID: o.project, nodeID: try o.id("개발")) == .notApplicable)
            #expect(await opening.perform(.open, projectID: o.project, nodeID: foreign) == .notApplicable)
            #expect(o.launcher.events.events.isEmpty)
        }
    }

    @Test("[W14-commands] 상세 영역 버튼은 Bishop이면 열기·Finder에서 보기, 웹 링크면 열기만 보인다")
    func inspectorButtons() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let o = try await opened(directory)
            o.model.selectedNodeID = try o.id("backend")
            #expect(o.model.canOpenSelected && o.model.canRevealSelected)
            o.model.selectedNodeID = try o.id("API 명세")
            #expect(o.model.canOpenSelected && !o.model.canRevealSelected)
            o.model.selectedNodeID = try o.id("개발")
            #expect(!o.model.canOpenSelected && !o.model.canRevealSelected)
        }
    }
}
