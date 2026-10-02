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
        /// 파일 선택 창. 취소하면 nil.
        var pickTargets: () -> [URL]?
        /// 연결 대상 변경 선택 창(종류에 맞는 것 하나). 취소하면 nil.
        var pickReplacement: (LinkedTarget.Kind) -> URL?
    }

    /// Bishop 연결 결과 안내. 다시 시도는 처음 요청 그대로 실행한다.
    struct LinkNotice: Equatable {
        enum Kind: Equatable {
            case unreachable([String])
            case saveFailed
            case archived
            /// 확정 시점에 같은 대상이라 바꾸지 않았다.
            case alreadyLinked
            /// 그 밖의 이유로 바꾸지 못했다(항목이 없어졌거나 종류가 다름).
            case changeFailed
        }

        var kind: Kind
        var request: LinkRequest?
        var canRetry: Bool { request != nil }
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
    private(set) var linkNotice: LinkNotice?
    /// 연결 대상 변경 확인 창.
    private(set) var replacement: ReplacementPreview?

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

    // MARK: Bishop 추가와 드롭

    /// 선택한 항목에 따른 연결 위치: 그룹이면 그 안, 그 밖의 항목이면 그 부모, 선택이 없으면 최상위. 모두 끝에 넣는다.
    private var insertionParent: UUID? {
        guard case let .loaded(snapshot) = current,
              let id = selectedNodeID, let node = snapshot.nodes.first(where: { $0.id == id })
        else { return nil }
        return node.kind == .group ? node.id : node.parentID
    }

    private var selectedBoardIsArchived: Bool {
        selectedBoardID.flatMap(board)?.archivedAt != nil
    }

    func addBishops() async {
        guard let boardID = selectedBoardID, openedStore != nil else { return }
        guard !selectedBoardIsArchived else {
            linkNotice = LinkNotice(kind: .archived, request: nil)
            return
        }
        let parent = insertionParent
        guard let urls = dependencies.pickTargets(), !urls.isEmpty else { return }
        await link(LinkRequest(projectID: boardID, parentID: parent, position: nil, urls: urls))
    }

    /// 놓은 곳이 최상위(nil)나 그룹이고, 보관되지 않은 Board가 선택돼 있을 때만 받는다.
    func canAcceptDrop(on nodeID: UUID?) -> Bool {
        guard selectedBoardID != nil, !selectedBoardIsArchived, case let .loaded(snapshot) = current else { return false }
        guard let nodeID else { return true }
        return snapshot.nodes.first { $0.id == nodeID }?.kind == .group
    }

    /// Finder에서 끌어온 파일·폴더를 연결한다. 파일 URL이 아니거나 받을 수 없는 곳이면 false.
    @discardableResult
    func drop(_ urls: [URL], on nodeID: UUID?) async -> Bool {
        guard canAcceptDrop(on: nodeID), let boardID = selectedBoardID, !urls.isEmpty, urls.allSatisfy(\.isFileURL) else {
            return false
        }
        await link(LinkRequest(projectID: boardID, parentID: nodeID, position: nil, urls: urls))
        return true
    }

    func retryLink() async {
        guard let request = linkNotice?.request else { return }
        await link(request)
    }

    func dismissLinkNotice() {
        linkNotice = nil
    }

    func noticeText(_ notice: LinkNotice) -> String {
        switch notice.kind {
        case let .unreachable(names):
            String(localized: "연결하지 못한 항목이 있어 아무것도 추가하지 않았습니다: \(names.joined(separator: ", "))")
        case .saveFailed:
            String(localized: "저장하지 못했습니다. 다시 시도하세요.")
        case .archived:
            String(localized: "보관된 Board는 바꿀 수 없습니다.")
        case .alreadyLinked:
            String(localized: "이미 연결된 대상이라 바꾸지 않았습니다.")
        case .changeFailed:
            String(localized: "연결 대상을 바꾸지 못했습니다.")
        }
    }

    // MARK: 연결 대상 변경

    struct ReplacementPresentation: Equatable {
        var canConfirm: Bool
        var warning: String?
    }

    var alreadyLinkedText: String { String(localized: "이미 연결된 대상입니다.") }
    var undeterminedText: String {
        String(localized: "같은 대상인지 확인할 수 없어 연결 대상 변경으로 기록됩니다.")
    }

    var canReplaceSelectedTarget: Bool {
        guard case let .loaded(snapshot) = current, let id = selectedNodeID,
              let node = snapshot.nodes.first(where: { $0.id == id })
        else { return false }
        return node.kind == .file || node.kind == .folder
    }

    func beginReplaceTarget() async {
        guard let boardID = selectedBoardID, let service = openedStore?.replacement,
              canReplaceSelectedTarget, case let .loaded(snapshot) = current,
              let node = snapshot.nodes.first(where: { $0.id == selectedNodeID })
        else { return }
        guard !selectedBoardIsArchived else {
            linkNotice = LinkNotice(kind: .archived, request: nil)
            return
        }
        let kind: LinkedTarget.Kind = node.kind == .folder ? .folder : .file
        guard let url = dependencies.pickReplacement(kind) else { return }
        do {
            switch try await service.preview(projectID: boardID, nodeID: node.id, newURL: url) {
            case let .success(preview): replacement = preview
            case let .failure(rejection): linkNotice = notice(for: rejection, url: url)
            }
        } catch {
            linkNotice = LinkNotice(kind: .changeFailed, request: nil)
        }
    }

    func replacementPresentation(_ preview: ReplacementPreview) -> ReplacementPresentation {
        switch preview.identity {
        case .sameTarget: ReplacementPresentation(canConfirm: false, warning: alreadyLinkedText)
        case .undetermined: ReplacementPresentation(canConfirm: true, warning: undeterminedText)
        case .differentTarget: ReplacementPresentation(canConfirm: true, warning: nil)
        }
    }

    func cancelReplacement() {
        replacement = nil
    }

    func confirmReplacement() async {
        guard let preview = replacement, let service = openedStore?.replacement else { return }
        replacement = nil
        let outcome: ReplacementOutcome
        do {
            outcome = try await service.confirm(preview)
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil)
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            if selectedBoardID == preview.projectID { current = .loaded(snapshot) }
        case .unchanged:
            linkNotice = LinkNotice(kind: .alreadyLinked, request: nil)
        case let .rejected(rejection):
            linkNotice = notice(for: rejection, url: preview.newURL)
        }
    }

    private func notice(for rejection: ReplacementRejection, url: URL) -> LinkNotice {
        switch rejection {
        case .unreachableTarget: LinkNotice(kind: .unreachable([url.lastPathComponent]), request: nil)
        case .commit(.archived): LinkNotice(kind: .archived, request: nil)
        case .commit: LinkNotice(kind: .changeFailed, request: nil)
        }
    }

    private func link(_ request: LinkRequest) async {
        guard let linking = openedStore?.linking else { return }
        linkNotice = nil
        let outcome: LinkOutcome
        do {
            outcome = try await linking.link(request)
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: request)
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            if selectedBoardID == request.projectID { current = .loaded(snapshot) }
        case .unchanged:
            break
        case let .rejected(.unreachableTargets(names)):
            linkNotice = LinkNotice(kind: .unreachable(names), request: request)
        case .rejected(.commit(.archived)):
            linkNotice = LinkNotice(kind: .archived, request: nil)
        case .rejected:
            linkNotice = LinkNotice(kind: .saveFailed, request: request)
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
