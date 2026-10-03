import Foundation
import Observation

/// 상세 영역에 보여 줄 항목 정보.
struct NodeInspection: Equatable {
    var displayName: String
    var kind: String
    var target: String?
    /// 확인한 연결 상태 문구. 정상이거나 확인 전이면 nil.
    var status: String?
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
            /// 그룹을 자기 자신이나 자손 안으로 옮기려 했다.
            case moveIntoItself
            /// 그룹이 아닌 항목 안으로 옮기려 했다.
            case moveIntoNonGroup
            /// 대상을 열거나 Finder에서 보여 주지 못했다.
            case openFailed(OpenFailure)
        }

        /// 안내를 띄운 동작. 알림 제목을 정한다.
        enum Action: Equatable {
            case link
            case move
            case remove
            case open
        }

        var kind: Kind
        var request: LinkRequest?
        var action: Action = .link
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

    enum FormMessage: Equatable {
        case nameRequired
        case invalidURL
        case saveFailed
    }

    /// 그룹 추가·웹 링크 추가·항목 이름 변경·URL 변경 입력 창.
    struct NodeForm: Equatable {
        enum Purpose: Equatable {
            case addGroup(parentID: UUID?)
            case addWebLink(parentID: UUID?)
            case rename(UUID)
            case changeURL(UUID)
        }

        var purpose: Purpose
        var name = ""
        var url = ""
        var message: FormMessage?
        var isSaving = false
        var boardID: UUID
    }

    /// 이동 창의 목적지.
    enum MoveTarget: Hashable {
        case root
        case group(UUID)

        var parentID: UUID? {
            if case let .group(id) = self { id } else { nil }
        }
    }

    struct MoveDestination: Identifiable, Equatable {
        var target: MoveTarget
        var name: String
        /// 트리 깊이. 최상위는 0, 최상위의 그룹은 1이다.
        var depth: Int
        var id: MoveTarget { target }
    }

    /// "이동…" 창. 목적지는 최상위와, 옮길 항목 자신·자손을 뺀 그룹이다.
    struct MoveDialog: Equatable {
        var nodeID: UUID
        var currentParent: MoveTarget
        var destinations: [MoveDestination]
    }

    /// 제거 확인 창. 포함 항목 수는 창을 연 시점의 현재 구성 기준이다.
    struct Removal: Equatable {
        var nodeID: UUID
        var boardID: UUID
        var kind: NodeKind
        var name: String
        /// 함께 제거될 모든 자손 수.
        var descendantCount: Int
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
    /// Board 이름 변경 입력. Board 만들기 입력과 같은 모양이다.
    var rename: Creation?
    var nodeForm: NodeForm?
    private(set) var moveDialog: MoveDialog?
    private(set) var removal: Removal?
    /// 이번 화면 세션에서 확인한 연결 상태. 저장하지 않고 Board를 바꾸면 비운다.
    private(set) var linkStatuses: [UUID: LinkStatus] = [:]
    /// 트리에서 펼친 그룹. 그룹 안에 항목을 넣거나 옮기면 그 그룹과 상위 그룹을 펼쳐 새 항목이 보이게 한다. Board를 바꾸면 비운다.
    private(set) var expandedGroupIDs: Set<UUID> = []
    /// Board 전환·다시 선택·대상 변경 때 올린다. 확인을 시작할 때의 값과 다르면 늦게 온 결과를 버린다.
    private var statusEpoch = 0
    /// 이동을 저장하는 중이다. 그동안 들어온 이동은 옛 구성 기준이라 무시한다.
    private var isMoving = false
    private(set) var openedStore: OpenedStore?
    private(set) var linkNotice: LinkNotice?
    /// 연결 대상 변경 확인 창.
    private(set) var replacement: ReplacementPreview?

    private let dependencies: Dependencies

    /// 오른쪽 열(인스펙터)을 펼쳤는지. 화면 설정이며 바꾸면 바로 기억한다(구성 기록과 무관).
    var isInspectorPresented: Bool {
        didSet { dependencies.lastBoard.isInspectorHidden = !isInspectorPresented }
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        isInspectorPresented = !dependencies.lastBoard.isInspectorHidden
    }

    /// 보기 메뉴 "인스펙터 보기/가리기"(⌥⌘I)와 툴바 버튼.
    func toggleInspector() {
        isInspectorPresented.toggle()
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

    func isExpanded(_ groupID: UUID) -> Bool { expandedGroupIDs.contains(groupID) }

    /// 사용자가 펼침 삼각형으로 펼치거나 접는다.
    func setExpanded(_ groupID: UUID, _ expanded: Bool) {
        if expanded { expandedGroupIDs.insert(groupID) } else { expandedGroupIDs.remove(groupID) }
    }

    /// 지금 트리에 보이는 항목: 최상위와, 모든 상위 그룹이 펼쳐진 항목.
    var visibleNodeIDs: Set<UUID> {
        var result: Set<UUID> = []
        func walk(_ parentID: UUID?) {
            for node in children(of: parentID) {
                result.insert(node.id)
                if node.kind == .group, isExpanded(node.id) { walk(node.id) }
            }
        }
        walk(nil)
        return result
    }

    /// 그룹과 그 상위 그룹을 모두 펼친다. 최상위(nil)면 아무것도 하지 않는다.
    private func reveal(_ groupID: UUID?) {
        guard case let .loaded(snapshot) = current else { return }
        var next = groupID
        var seen: Set<UUID> = []
        while let id = next, seen.insert(id).inserted, let node = snapshot.nodes.first(where: { $0.id == id }) {
            expandedGroupIDs.insert(id)
            next = node.parentID
        }
    }

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
        case .group: String(localized: "Wing")
        case .file, .folder: String(localized: "Bishop")
        case .webLink: String(localized: "웹 링크")
        }
    }

    func accessibilityLabel(for node: ConfigurationNode) -> String {
        let base = "\(node.displayName), \(kindText(for: node))"
        guard let status = displayedStatus(of: node.id) else { return base }
        return "\(base), \(statusText(status))"
    }

    var inspector: NodeInspection? {
        guard case let .loaded(snapshot) = current,
              let id = selectedNodeID, let node = snapshot.nodes.first(where: { $0.id == id })
        else { return nil }
        let kind = switch node.kind {
        case .group: String(localized: "Wing")
        case .file: String(localized: "Bishop(파일)")
        case .folder: String(localized: "Bishop(폴더)")
        case .webLink: String(localized: "웹 링크")
        }
        return NodeInspection(
            displayName: node.displayName, kind: kind, target: node.recordedPath ?? node.url,
            status: displayedStatus(of: node.id).map(statusText)
        )
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

    // MARK: 그룹·웹 링크·이름·URL 편집

    /// 편집을 시작할 수 있는 Board. 선택한 Board가 없으면 nil, 보관돼 있으면 안내하고 nil(보관 안내가 다른 조건보다 먼저다).
    // MARK: 메뉴 켜짐 판단 값
    // 각 값은 해당 동작이 실제로 창을 열거나 기록하는 조건과 같다(MenuCapabilityModelTests). 보관된 Board는 편집 동작이 모두 거짓이다(0009).

    private var canEditSelectedBoard: Bool { selectedBoardID != nil && openedStore != nil && !selectedBoardIsArchived }

    /// Bishop 추가·Wing 추가·웹 링크 추가.
    var canAddToBoard: Bool { canEditSelectedBoard }
    var canRenameSelectedNode: Bool { canEditSelectedBoard && selectedNode != nil }
    var canChangeURLOfSelected: Bool { canEditSelectedBoard && selectedNode?.kind == .webLink }
    var canMoveSelected: Bool { canEditSelectedBoard && selectedNode != nil }
    var canRemoveSelected: Bool { canEditSelectedBoard && selectedNode != nil }
    var canMoveSelectedUp: Bool { canEditSelectedBoard && siblingPosition.map { $0.index > 0 } == true }
    var canMoveSelectedDown: Bool { canEditSelectedBoard && siblingPosition.map { $0.index < $0.count - 1 } == true }
    /// 상태 확인은 조회라 보관된 Board에서도 한다.
    var canRefreshStatuses: Bool { selectedBoardID != nil && openedStore != nil }
    var canRenameSelectedBoard: Bool { canEditSelectedBoard }

    /// 선택한 항목의 형제 안 위치.
    private var siblingPosition: (index: Int, count: Int)? {
        guard let node = selectedNode else { return nil }
        let siblings = children(of: node.parentID)
        guard let index = siblings.firstIndex(where: { $0.id == node.id }) else { return nil }
        return (index, siblings.count)
    }

    private func editableBoard() -> UUID? {
        guard let boardID = selectedBoardID, openedStore != nil else { return nil }
        guard !selectedBoardIsArchived else {
            linkNotice = LinkNotice(kind: .archived, request: nil)
            return nil
        }
        return boardID
    }

    private var selectedNode: ConfigurationNode? {
        guard case let .loaded(snapshot) = current, let id = selectedNodeID else { return nil }
        return snapshot.nodes.first { $0.id == id }
    }

    func beginAddGroup() {
        guard let boardID = editableBoard() else { return }
        nodeForm = NodeForm(purpose: .addGroup(parentID: insertionParent), boardID: boardID)
    }

    func beginAddWebLink() {
        guard let boardID = editableBoard() else { return }
        nodeForm = NodeForm(purpose: .addWebLink(parentID: insertionParent), boardID: boardID)
    }

    func beginRenameNode() {
        guard let boardID = editableBoard(), let node = selectedNode else { return }
        nodeForm = NodeForm(purpose: .rename(node.id), name: node.displayName, boardID: boardID)
    }

    func beginChangeURL() {
        guard let boardID = editableBoard(), let node = selectedNode, node.kind == .webLink else { return }
        nodeForm = NodeForm(purpose: .changeURL(node.id), url: node.url ?? "", boardID: boardID)
    }

    func cancelNodeForm() {
        guard nodeForm?.isSaving != true else { return }
        nodeForm = nil
    }

    func confirmNodeForm() async {
        guard var form = nodeForm, !form.isSaving, let service = openedStore?.service else { return }
        form.isSaving = true
        form.message = nil
        nodeForm = form
        let edit: ConfigurationEdit = switch form.purpose {
        case let .addGroup(parentID): .addGroup(name: form.name, parentID: parentID, position: nil)
        case let .addWebLink(parentID): .addWebLink(name: form.name, url: form.url, parentID: parentID, position: nil)
        case let .rename(id): .renameNode(id, form.name)
        case let .changeURL(id): .changeURL(id, form.url)
        }
        let outcome: ConfigurationCommitOutcome
        do {
            outcome = try await service.apply(edit, to: form.boardID)
        } catch {
            finishNodeForm(with: .saveFailed)
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            nodeForm = nil
            if selectedBoardID == form.boardID {
                current = .loaded(snapshot)
                switch form.purpose {
                case let .addGroup(parentID), let .addWebLink(parentID): reveal(parentID)
                case .rename, .changeURL: break
                }
            }
        case .unchanged:
            nodeForm = nil
        case .rejected(.edit(.blankName)):
            finishNodeForm(with: .nameRequired)
        case .rejected(.edit(.invalidURL)):
            finishNodeForm(with: .invalidURL)
        case .rejected(.archived):
            nodeForm = nil
            linkNotice = LinkNotice(kind: .archived, request: nil)
        case .rejected:
            finishNodeForm(with: .saveFailed)
        }
    }

    func formMessageText(_ message: FormMessage) -> String {
        switch message {
        case .nameRequired: String(localized: "이름을 입력하세요.")
        case .invalidURL: String(localized: "http 또는 https로 시작하는 주소를 입력하세요.")
        case .saveFailed: String(localized: "저장하지 못했습니다. 다시 시도하세요.")
        }
    }

    private func finishNodeForm(with message: FormMessage) {
        nodeForm?.isSaving = false
        nodeForm?.message = message
    }

    // MARK: Board 이름 변경·보관

    /// 선택한 Board가 보관돼 있으면 읽기 전용 표시 문구(색만으로 구분하지 않는다).
    var readOnlyText: String? {
        selectedBoardIsArchived ? String(localized: "보관된 Board · 읽기 전용") : nil
    }

    var canArchiveSelected: Bool { selectedBoardID != nil && !selectedBoardIsArchived }
    var canUnarchiveSelected: Bool { selectedBoardID != nil && selectedBoardIsArchived }

    func beginRename() {
        guard let boardID = selectedBoardID, let board = board(boardID) else { return }
        guard board.archivedAt == nil else {
            linkNotice = LinkNotice(kind: .archived, request: nil)
            return
        }
        rename = Creation(name: board.name)
    }

    func cancelRename() {
        guard rename?.isSaving != true else { return }
        rename = nil
    }

    func confirmRename() async {
        guard var draft = rename, !draft.isSaving, let boardID = selectedBoardID, let service = openedStore?.service else { return }
        draft.isSaving = true
        draft.message = nil
        rename = draft
        let outcome: ConfigurationCommitOutcome
        do {
            outcome = try await service.apply(.renameProject(draft.name), to: boardID)
        } catch {
            rename?.isSaving = false
            rename?.message = .saveFailed
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            rename = nil
            await reloadBoards()
            if selectedBoardID == boardID { current = .loaded(snapshot) }
        case .unchanged:
            rename = nil
        case .rejected(.edit(.blankName)):
            rename?.isSaving = false
            rename?.message = .nameRequired
        case .rejected(.archived):
            rename = nil
            linkNotice = LinkNotice(kind: .archived, request: nil)
        case .rejected:
            rename?.isSaving = false
            rename?.message = .saveFailed
        }
    }

    func archiveSelected() async {
        guard canArchiveSelected else { return }
        await setSelectedArchived(true)
    }

    func unarchiveSelected() async {
        guard canUnarchiveSelected else { return }
        await setSelectedArchived(false)
    }

    private func setSelectedArchived(_ archived: Bool) async {
        guard let boardID = selectedBoardID, let lifecycle = openedStore?.lifecycle else { return }
        do {
            _ = try await lifecycle.setArchived(boardID, archived)
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil)
            return
        }
        await reloadBoards()
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

    func noticeTitle(_ notice: LinkNotice) -> String {
        switch notice.action {
        case .link: String(localized: "Bishop 추가")
        case .move: String(localized: "이동")
        case .remove: String(localized: "제거")
        case .open: String(localized: "열기")
        }
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
        case .moveIntoItself:
            String(localized: "Wing을 자기 안으로 옮길 수 없습니다.")
        case .moveIntoNonGroup:
            String(localized: "그 항목 안으로는 옮길 수 없습니다.")
        case let .openFailed(failure):
            openFailureText(failure)
        }
    }

    // MARK: 이동

    var rootDestinationName: String { String(localized: "최상위") }

    func moveSelectedUp() async {
        await moveSelected(by: -1)
    }

    func moveSelectedDown() async {
        await moveSelected(by: 1)
    }

    /// 형제 안에서 한 칸 옮긴다. 이미 끝이면 아무것도 하지 않는다.
    private func moveSelected(by offset: Int) async {
        guard let node = selectedNode, editableBoard() != nil else { return }
        let others = children(of: node.parentID).map(\.id).filter { $0 != node.id }
        let current = children(of: node.parentID).firstIndex { $0.id == node.id } ?? 0
        let position = current + offset
        guard (0...others.count).contains(position) else { return }
        await requestMove(node.id, toParent: node.parentID, position: position)
    }

    func beginMove() {
        guard let node = selectedNode, editableBoard() != nil else { return }
        var destinations = [MoveDestination(target: .root, name: rootDestinationName, depth: 0)]
        func collect(under parentID: UUID?, depth: Int) {
            for child in children(of: parentID) where child.kind == .group && child.id != node.id {
                destinations.append(MoveDestination(target: .group(child.id), name: child.displayName, depth: depth))
                collect(under: child.id, depth: depth + 1)
            }
        }
        collect(under: nil, depth: 1)
        moveDialog = MoveDialog(
            nodeID: node.id,
            currentParent: node.parentID.map(MoveTarget.group) ?? .root,
            destinations: destinations
        )
    }

    func cancelMove() {
        moveDialog = nil
    }

    /// 고른 목적지의 끝으로 옮긴다. 현재 부모를 고르면 기록하지 않고 닫는다.
    func confirmMove(to target: MoveTarget) async {
        guard let dialog = moveDialog else { return }
        moveDialog = nil
        guard target != dialog.currentParent, dialog.destinations.contains(where: { $0.target == target }) else { return }
        await requestMove(dialog.nodeID, toParent: target.parentID, position: nil)
    }

    /// 앱 안에서 끌어온 항목을 받을 수 있는지: 보관되지 않은 Board의 현재 구성에 있는 항목이고,
    /// 놓은 곳이 빈 곳(nil)이거나 연결 폴더가 아닌 이 Board의 항목이어야 한다(PRD §6-C).
    func canAcceptNodeDrop(_ nodeID: UUID, on targetID: UUID?) -> Bool {
        guard selectedBoardID != nil, !selectedBoardIsArchived, case let .loaded(snapshot) = current,
              snapshot.nodes.contains(where: { $0.id == nodeID })
        else { return false }
        guard let targetID else { return true }
        guard let target = snapshot.nodes.first(where: { $0.id == targetID }) else { return false }
        return target.kind != .folder
    }

    /// 그룹 위면 그 안 끝, Bishop 파일·웹 링크 위면 그 앞, 빈 곳이면 최상위 끝으로 옮긴다. 자기 자신 위는 무변경이다.
    @discardableResult
    func dropNode(_ nodeID: UUID, on targetID: UUID?) async -> Bool {
        guard canAcceptNodeDrop(nodeID, on: targetID), case let .loaded(snapshot) = current else { return false }
        guard targetID != nodeID else { return true }
        guard let targetID, let target = snapshot.nodes.first(where: { $0.id == targetID }) else {
            await requestMove(nodeID, toParent: nil, position: nil)
            return true
        }
        if target.kind == .group {
            await requestMove(nodeID, toParent: target.id, position: nil)
        } else {
            let others = children(of: target.parentID).map(\.id).filter { $0 != nodeID }
            await requestMove(nodeID, toParent: target.parentID, position: others.firstIndex(of: target.id))
        }
        return true
    }

    /// 이동 요청 하나를 저장한다. 성공하면 옮긴 항목을 선택한다.
    func requestMove(_ nodeID: UUID, toParent parentID: UUID?, position: Int?) async {
        guard !isMoving, let boardID = editableBoard(), let service = openedStore?.service else { return }
        isMoving = true
        defer { isMoving = false }
        let outcome: ConfigurationCommitOutcome
        do {
            outcome = try await service.apply(.move(nodeID, toParent: parentID, position: position), to: boardID)
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil, action: .move)
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            guard selectedBoardID == boardID else { return }
            current = .loaded(snapshot)
            selectedNodeID = nodeID
            reveal(parentID)
        case .unchanged:
            break
        case .rejected(.edit(.cycle)):
            linkNotice = LinkNotice(kind: .moveIntoItself, request: nil, action: .move)
        case .rejected(.edit(.parentNotGroup)):
            linkNotice = LinkNotice(kind: .moveIntoNonGroup, request: nil, action: .move)
        case .rejected(.archived):
            linkNotice = LinkNotice(kind: .archived, request: nil, action: .move)
        case .rejected:
            linkNotice = LinkNotice(kind: .saveFailed, request: nil, action: .move)
        }
    }

    // MARK: 열기와 Finder에서 보기

    /// 기본 앱으로 열 수 있는 선택: Bishop과 웹 링크.
    var canOpenSelected: Bool { selectedNode.map { $0.kind != .group } ?? false }

    /// Finder에서 보여 줄 수 있는 선택: Bishop.
    var canRevealSelected: Bool { selectedNode.map { $0.kind == .file || $0.kind == .folder } ?? false }

    func openSelected() async {
        guard canOpenSelected, let id = selectedNodeID else { return }
        await perform(.open, on: id)
    }

    func revealSelected() async {
        guard canRevealSelected, let id = selectedNodeID else { return }
        await perform(.reveal, on: id)
    }

    /// 트리 행 이중 클릭.
    func open(_ nodeID: UUID) async {
        selectedNodeID = nodeID
        await openSelected()
    }

    /// 열기는 조회라 보관된 Board에서도 한다(0009는 편집만 막는다).
    private func perform(_ command: OpenCommand, on nodeID: UUID) async {
        guard let boardID = selectedBoardID, let opening = openedStore?.opening else { return }
        let isLinked = selectedNode.map { $0.kind == .file || $0.kind == .folder } ?? false
        let epoch = statusEpoch
        let outcome = await opening.perform(command, projectID: boardID, nodeID: nodeID)
        // 열기도 상태 확인이다(W15): 해석 결과를 그 항목의 상태로 남긴다.
        if isLinked, epoch == statusEpoch {
            switch outcome {
            case .opened: linkStatuses[nodeID] = .healthy
            case let .failed(.unreachable(cause)): linkStatuses[nodeID] = LinkStatus(cause)
            case .failed, .notApplicable: break
            }
        }
        if case let .failed(failure) = outcome {
            linkNotice = LinkNotice(kind: .openFailed(failure), request: nil, action: .open)
        }
    }

    private func openFailureText(_ failure: OpenFailure) -> String {
        switch failure {
        // 상태 이름은 W15의 연결 상태 표시와 같다.
        case .unreachable(.missing): String(localized: "열지 못했습니다. 상태: 대상 없음")
        case .unreachable(.accessDenied): String(localized: "열지 못했습니다. 상태: 권한 필요")
        case .unreachable(.volumeUnavailable): String(localized: "열지 못했습니다. 상태: 볼륨 연결 필요")
        case .unreachable(.checkFailed): String(localized: "열지 못했습니다. 상태: 확인 실패")
        case .launchFailed, .unreadable: String(localized: "열지 못했습니다.")
        }
    }

    // MARK: 연결 상태와 다시 선택

    /// 화면에 보일 상태. 정상이거나 확인 전이면 nil이다.
    func displayedStatus(of nodeID: UUID) -> LinkStatus? {
        guard let status = linkStatuses[nodeID], status != .healthy else { return nil }
        return status
    }

    func statusText(_ status: LinkStatus) -> String {
        switch status {
        case .healthy: String(localized: "정상")
        case .accessRequired: String(localized: "권한 필요")
        case .missing: String(localized: "대상 없음")
        case .volumeUnavailable: String(localized: "볼륨 연결 필요")
        case .checkFailed: String(localized: "확인 실패")
        }
    }

    /// 트리에서 항목을 고른다. Bishop이면 그 항목의 상태를 확인한다(선택 때만, PRD §8).
    func selectNode(_ nodeID: UUID?) async {
        selectedNodeID = nodeID
        guard let nodeID, let node = selectedNode, node.kind == .file || node.kind == .folder,
              let boardID = selectedBoardID, let links = openedStore?.links
        else { return }
        let epoch = statusEpoch
        let status = await links.check(projectID: boardID, nodeID: nodeID)
        guard epoch == statusEpoch, selectedBoardID == boardID, let status else { return }
        linkStatuses[nodeID] = status
    }

    /// Board의 모든 Bishop을 한 번씩 다시 확인한다. 기록하지 않는다.
    func refreshStatuses() async {
        guard let boardID = selectedBoardID, let links = openedStore?.links else { return }
        let epoch = statusEpoch
        let statuses = await links.checkAll(projectID: boardID)
        guard epoch == statusEpoch, selectedBoardID == boardID else { return }
        linkStatuses.merge(statuses) { _, new in new }
    }

    var canReselectSelected: Bool { selectedNode.map { $0.kind == .file || $0.kind == .folder } ?? false }

    /// 다시 선택: 같은 대상이면 접근을 복구하고, 아니면 연결 대상 변경 확인 창을 연다.
    func reselectSelectedTarget() async {
        guard canReselectSelected, let node = selectedNode, let boardID = selectedBoardID,
              let service = openedStore?.replacement
        else { return }
        let kind: LinkedTarget.Kind = node.kind == .folder ? .folder : .file
        guard let url = dependencies.pickReplacement(kind) else { return }
        do {
            switch try await service.reselect(projectID: boardID, nodeID: node.id, newURL: url) {
            case .recovered:
                statusEpoch += 1
                if selectedBoardID == boardID { linkStatuses[node.id] = .healthy }
            case let .needsConfirmation(preview):
                replacement = preview
            case let .rejected(rejection):
                linkNotice = notice(for: rejection, url: url)
            }
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil)
        }
    }

    // MARK: 제거

    /// 첫 버전에는 Undo가 없으므로 종류와 상관없이 확인 창을 연다.
    func beginRemove() {
        guard let node = selectedNode, let boardID = editableBoard() else { return }
        func count(under parentID: UUID) -> Int {
            children(of: parentID).reduce(0) { $0 + 1 + count(under: $1.id) }
        }
        removal = Removal(
            nodeID: node.id, boardID: boardID, kind: node.kind, name: node.displayName,
            descendantCount: node.kind == .group ? count(under: node.id) : 0
        )
    }

    func cancelRemove() {
        removal = nil
    }

    func confirmRemove() async {
        guard let pending = removal, let service = openedStore?.service else { return }
        removal = nil
        let outcome: ConfigurationCommitOutcome
        do {
            outcome = try await service.apply(.remove(pending.nodeID), to: pending.boardID)
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil, action: .remove)
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            guard selectedBoardID == pending.boardID else { return }
            current = .loaded(snapshot)
            selectedNodeID = nil
        case .unchanged:
            break
        case .rejected(.archived):
            linkNotice = LinkNotice(kind: .archived, request: nil, action: .remove)
        case .rejected:
            linkNotice = LinkNotice(kind: .saveFailed, request: nil, action: .remove)
        }
    }

    func removalTitle(_ removal: Removal) -> String {
        switch removal.kind {
        case .group: String(localized: "Wing 제거")
        case .file, .folder: String(localized: "Bishop 제거")
        case .webLink: String(localized: "웹 링크 제거")
        }
    }

    func removalMessage(_ removal: Removal) -> String {
        let target = switch removal.kind {
        case .group where removal.descendantCount == 0:
            String(localized: "Wing \"\(removal.name)\"(포함된 항목 없음)")
        case .group:
            String(localized: "Wing \"\(removal.name)\"(포함된 항목 \(removal.descendantCount)개)")
        case .file, .folder:
            String(localized: "Bishop \"\(removal.name)\"")
        case .webLink:
            String(localized: "웹 링크 \"\(removal.name)\"")
        }
        return String(localized: "현재 구성에서 제거합니다: \(target). 연결된 파일과 폴더는 그대로 남습니다.")
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
            statusEpoch += 1
            if selectedBoardID == preview.projectID {
                current = .loaded(snapshot)
                linkStatuses[preview.nodeID] = nil
            }
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
            if selectedBoardID == request.projectID {
                current = .loaded(snapshot)
                reveal(request.parentID)
            }
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
        linkStatuses = [:]
        expandedGroupIDs = []
        statusEpoch += 1
        guard let store = openedStore?.store else { return }
        do {
            current = .loaded(try await store.currentSnapshot(projectID: boardID))
        } catch {
            current = .unreadable
        }
    }
}

#if DEBUG
extension BoardBrowserModel {
    /// Xcode Preview 전용: 저장소를 열지 않고 화면 상태를 채운다. 실제 저장소·파일에 접근하지 않는다.
    func loadPreview(boards: [ProjectListing], selectedBoardID: UUID?, snapshot: ConfigurationSnapshot?, statuses: [UUID: LinkStatus]) {
        phase = .ready
        activeBoards = boards.filter { $0.archivedAt == nil }
        archivedBoards = boards.filter { $0.archivedAt != nil }
        self.selectedBoardID = selectedBoardID
        current = snapshot.map(CurrentConfiguration.loaded) ?? .none
        linkStatuses = statuses
    }
}
#endif
