import Foundation
import Testing
@testable import Fianchetto

/// 과거 항목의 현재 위치와 당시 경로 비교(W18, 0003).
@Suite("과거 항목 위치 확인(W18)")
struct NodeLocationTests {
    @Test("[W18-location-card] 심볼릭 링크를 거친 당시 경로와 실제 위치는 같은 위치로 본다")
    func symlinkedRecordedPathIsSameLocation() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let real = try TargetFiles.folder(directory, "real/backend")
            let link = directory.appending(path: "link")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real.deletingLastPathComponent())
            let board = try await makeBoard(harness)
            _ = try await harness.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [link.appending(path: "backend")]))
            let node = try #require(try await harness.store.currentSnapshot(projectID: board).node(named: "backend"))
            let links = LinkStatusService(store: harness.store, bookmarks: BookmarkAdapter(system: harness.bookmarks))

            guard case let .resolved(_, differs) = await links.location(of: node) else {
                Issue.record("위치를 해석하지 못했다")
                return
            }
            #expect(!differs)
        }
    }

    @Test("[W18-location-card] 대상을 옮기면 다른 위치로 보고 표준화한 현재 위치를 준다")
    func movedTargetDiffers() async throws {
        try await withTemporaryDirectoryAsync { directory async throws in
            let harness = try ServiceHarness(directory: directory.appending(path: "store"))
            let original = try TargetFiles.folder(directory, "a/backend")
            let board = try await makeBoard(harness)
            _ = try await harness.linking.link(LinkRequest(projectID: board, parentID: nil, position: nil, urls: [original]))
            let node = try #require(try await harness.store.currentSnapshot(projectID: board).node(named: "backend"))
            let moved = directory.appending(path: "b/backend")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: original, to: moved)
            let links = LinkStatusService(store: harness.store, bookmarks: BookmarkAdapter(system: harness.bookmarks))

            guard case let .resolved(path, differs) = await links.location(of: node) else {
                Issue.record("위치를 해석하지 못했다")
                return
            }
            #expect(differs)
            #expect(!path.hasSuffix("/"))
            #expect(URL(filePath: path).resolvingSymlinksInPath().path == moved.resolvingSymlinksInPath().path)
        }
    }
}
