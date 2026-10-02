import Foundation
import Observation

/// 상세 영역에 보여 줄 항목 정보.
struct NodeInspection: Equatable {
    var displayName: String
    var kind: String
    var target: String?
}

/// 트리 한 행. 하위 항목은 펼칠 수 있는 그룹에만 있다.
struct TreeItem: Identifiable, Equatable {
    var node: ConfigurationNode
    var children: [TreeItem]?
    var id: UUID { node.id }
}

/// 기본 창의 화면 상태: Board 목록, 선택한 Board의 현재 구성, 만들기 입력, 저장소 복구.
/// 저장소는 MainActor 밖에서 열고, 열기·선택·복원은 revision을 만들지 않는다(PRD §7).
@MainActor
@Observable
final class BoardBrowserModel {
    struct Dependencies {
        /// 저장소 위치. 구하지 못했으면 nil이고 저장소를 열 수 없는 상태가 된다.
        var storeURL: URL?
        var openStore: @Sendable (URL) throws(StoreOpenError) -> OpenedStore
        var lastBoard: any LastBoardRecord
        var revealInFinder: (URL) -> Void
        var quit: () -> Void
    }

    enum Phase: Equatable {
        case loading
        /// 저장소를 열 수 없다. 빈 저장소로 바꾸지 않고 복구 선택지를 보여 준다(0008).
        case storeUnavailable(StoreOpenError.Category)
        /// 저장소는 열렸지만 Board 목록을 읽지 못했다. 빈 목록으로 대신하지 않는다.
        case listUnavailable
        case ready
    }

    enum CurrentConfiguration: Equatable {
        case none
        case loaded(ConfigurationSnapshot)
        /// 현재 구성을 읽지 못했다. 빈 트리로 대신하지 않는다(불변식 9).
        case unreadable
    }

    enum CreationMessage: Equatable {
        case nameRequired
        case saveFailed
    }

    struct Creation: Equatable {
        var name = ""
        var message: CreationMessage?
        var isSaving = false
    }

    private(set) var phase: Phase = .loading
    private(set) var activeBoards: [ProjectListing] = []
    private(set) var archivedBoards: [ProjectListing] = []
    private(set) var selectedBoardID: UUID?
    private(set) var current: CurrentConfiguration = .none
    var selectedNodeID: UUID?
    var creation: Creation?
    private(set) var openedStore: OpenedStore?

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: 시작과 복구

    func start() async {
        phase = .loading
        openedStore = nil
        guard let url = dependencies.storeURL else {
            phase = .storeUnavailable(.unavailable)
            return
        }
        let open = dependencies.openStore
        let result = await Task.detached { () -> Result<OpenedStore, StoreOpenError> in
            do throws(StoreOpenError) {
                return .success(try open(url))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case let .failure(error):
            phase = .storeUnavailable(error.category)
        case let .success(opened):
            openedStore = opened
            await reloadBoards()
            if phase == .ready, let last = dependencies.lastBoard.lastBoardID, board(last) != nil {
                await loadCurrent(of: last)
            }
        }
    }

    /// 저장소를 다시 열거나, 열려 있으면 Board 목록을 다시 읽는다.
    func retry() async {
        if openedStore == nil {
            await start()
        } else {
            await reloadBoards()
        }
    }

    var canRevealStore: Bool { dependencies.storeURL != nil }

    func revealStore() {
        guard let url = dependencies.storeURL else { return }
        dependencies.revealInFinder(url)
    }

    func quit() {
        dependencies.quit()
    }

    func recoveryMessage(for category: StoreOpenError.Category) -> String {
        switch category {
        case .damaged: String(localized: "데이터를 읽을 수 없습니다. 파일이 손상되었을 수 있습니다.")
        case .incompatible: String(localized: "이 버전의 앱이 읽을 수 없는 형식입니다. 더 새로운 버전의 앱이 만들었을 수 있습니다.")
        case .accessDenied: String(localized: "데이터에 접근할 권한이 없습니다.")
        case .unavailable: String(localized: "데이터를 열지 못했습니다.")
        }
    }

    // MARK: 목록과 선택

    func select(_ boardID: UUID) async {
        dependencies.lastBoard.lastBoardID = boardID
        await loadCurrent(of: boardID)
    }

    func statusText(for board: ProjectListing) -> String? {
        board.archivedAt == nil ? nil : String(localized: "보관됨")
    }

    func createdText(for board: ProjectListing) -> String {
        board.createdAt.formatted(date: .abbreviated, time: .standard)
    }

    func accessibilityLabel(for board: ProjectListing) -> String {
        [board.name, statusText(for: board), createdText(for: board)].compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: 현재 구성 트리

    func children(of parentID: UUID?) -> [ConfigurationNode] {
        guard case let .loaded(snapshot) = current else { return [] }
        return snapshot.nodes.filter { $0.parentID == parentID }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// 펼칠 수 있는 항목의 하위 목록. 그룹만 하위 항목을 가지며, 비어 있거나 그룹이 아니면 nil이다.
    func childrenIfExpandable(_ node: ConfigurationNode) -> [ConfigurationNode]? {
        guard node.kind == .group else { return nil }
        let children = children(of: node.id)
        return children.isEmpty ? nil : children
    }

    /// 현재 구성 전체를 정렬 순서대로 중첩한 트리.
    var tree: [TreeItem] { treeItems(under: nil) }

    private func treeItems(under parentID: UUID?) -> [TreeItem] {
        children(of: parentID).map { node in
            TreeItem(node: node, children: childrenIfExpandable(node).map { _ in treeItems(under: node.id) })
        }
    }

    func kindText(for node: ConfigurationNode) -> String {
        switch node.kind {
        case .group: String(localized: "그룹")
        case .file, .folder: String(localized: "Bishop")
        case .webLink: String(localized: "웹 링크")
        }
    }

    func accessibilityLabel(for node: ConfigurationNode) -> String {
        "\(node.displayName), \(kindText(for: node))"
    }

    var inspector: NodeInspection? {
        guard case let .loaded(snapshot) = current,
              let id = selectedNodeID, let node = snapshot.nodes.first(where: { $0.id == id })
        else { return nil }
        let kind = switch node.kind {
        case .group: String(localized: "그룹")
        case .file: String(localized: "Bishop(파일)")
        case .folder: String(localized: "Bishop(폴더)")
        case .webLink: String(localized: "웹 링크")
        }
        return NodeInspection(displayName: node.displayName, kind: kind, target: node.recordedPath ?? node.url)
    }

    // MARK: Board 만들기

    var canCreateBoard: Bool { phase == .ready }

    var canConfirmCreate: Bool { creation.map { !$0.isSaving } ?? false }

    func beginCreate() {
        guard canCreateBoard else { return }
        creation = Creation()
    }

    func cancelCreate() {
        guard creation?.isSaving != true else { return }
        creation = nil
    }

    func confirmCreate() async {
        guard var draft = creation, !draft.isSaving, let service = openedStore?.service else { return }
        draft.isSaving = true
        draft.message = nil
        creation = draft
        let outcome: ConfigurationCommitOutcome
        do {
            outcome = try await service.createProject(named: draft.name)
        } catch {
            finishCreate(with: .saveFailed)
            return
        }
        switch outcome {
        case let .committed(summary, _):
            creation = nil
            await reloadBoards()
            await select(summary.projectID)
        case .rejected(.blankName):
            finishCreate(with: .nameRequired)
        case .rejected, .unchanged:
            finishCreate(with: .saveFailed)
        }
    }

    // MARK: 내부

    private func finishCreate(with message: CreationMessage) {
        creation?.isSaving = false
        creation?.message = message
    }

    private func board(_ id: UUID) -> ProjectListing? {
        (activeBoards + archivedBoards).first { $0.id == id }
    }

    private func reloadBoards() async {
        guard let store = openedStore?.store else { return }
        do {
            let listings = try await store.projectListings().sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            activeBoards = listings.filter { $0.archivedAt == nil }
            archivedBoards = listings.filter { $0.archivedAt != nil }
            phase = .ready
        } catch {
            activeBoards = []
            archivedBoards = []
            phase = .listUnavailable
        }
    }

    private func loadCurrent(of boardID: UUID) async {
        selectedBoardID = boardID
        selectedNodeID = nil
        guard let store = openedStore?.store else { return }
        do {
            current = .loaded(try await store.currentSnapshot(projectID: boardID))
        } catch {
            current = .unreadable
        }
    }
}
