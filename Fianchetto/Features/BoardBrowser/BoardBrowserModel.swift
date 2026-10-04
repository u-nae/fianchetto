import Foundation
import Observation

/// 상세 영역에 보여 줄 항목 정보.
struct NodeInspection: Equatable {
    var displayName: String
    var kind: String
    var target: String?
    /// 확인한 연결 상태 문구. 정상이거나 확인 전이면 nil.
    var status: String?
    /// Bishop의 용도 문구(모르는 키는 "기본"). Bishop이 아니면 nil.
    var purpose: String?
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
        /// 이력 날짜 구역의 '오늘'과 날짜로 찾기의 처음 값.
        var now: () -> Date = { Date() }
        /// 시스템 시간대가 들어 있는 달력. 바뀐 시간대를 따르도록 부를 때마다 읽는다.
        var calendar: () -> Calendar = { Calendar.autoupdatingCurrent }
        var locale: Locale = .autoupdatingCurrent
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
            /// 과거 구성에서 다른 대상을 골랐다. 같은 대상의 접근 복구만 된다(W18).
            case pastSameTargetOnly
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
    /// 과거 모드에서 확인한 항목의 지금 위치(W18). 모드가 바뀌면 비운다.
    private(set) var pastLocations: [UUID: NodeLocation] = [:]

    private let dependencies: Dependencies

    /// 인스펙터 안의 '항목 | 이력' 탭(W17, DESIGN.md 16.1). 다시 실행하면 항목 탭으로 시작한다.
    enum InspectorTab: Hashable, Sendable {
        case item
        case history
    }

    private(set) var inspectorTab: InspectorTab = .item
    /// Board 사이드바가 보이는지. 화면이 NavigationSplitView 열 표시와 묶는다. 저장하지 않으므로 다시 실행하면 보인다.
    var isSidebarVisible = true
    /// 이력 탭을 열 때의 사이드바 상태. 이력 탭을 닫으면 이 상태로 돌린다(16.1).
    private var sidebarBeforeHistory: Bool?
    /// 이력 탭의 목록·날짜로 찾기·고른 revision.
    let history: HistoryPanelModel

    /// 구성 영역 보기 방식(W28, 0020). Board별로 기억한다.
    enum ViewMode: String, Sendable {
        case list
        case icons
    }

    enum GridDirection: Sendable {
        case left, right, up, down
    }

    private(set) var viewMode: ViewMode = .list
    /// 아이콘 보기 위치: 최상위부터 지금 Wing까지의 UUID 경로(빈 배열 = 최상위). 화면 세션 동안만 둔다.
    private var iconPath: [UUID] = []
    /// 이번 Board 세션에 아이콘 보기를 쓴 적이 있는지(선택 없이 바꿀 때 이어 쓸 위치가 있는지).
    private var hasIconLocation = false
    private var backStack: [[UUID]] = []

    /// 설정의 Bishop 아이콘 방식. 바꾸면 바로 기억한다.
    var bishopIconStyle: BishopIconStyle {
        didSet { dependencies.lastBoard.bishopIconStyle = bishopIconStyle.rawValue }
    }

    /// 오른쪽 열(인스펙터)을 펼쳤는지. 화면 설정이며 바꾸면 바로 기억한다(구성 기록과 무관).
    var isInspectorPresented: Bool {
        didSet {
            dependencies.lastBoard.isInspectorHidden = !isInspectorPresented
            // 인스펙터를 접으면 이력 탭을 닫은 것으로 다룬다(접힘 + 이력 탭 상태는 없다).
            if !isInspectorPresented, inspectorTab == .history { closeHistoryTab() }
        }
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        var openedStore: () -> ProjectStore? = { nil }
        history = HistoryPanelModel(
            environment: .init(now: dependencies.now, calendar: dependencies.calendar, locale: dependencies.locale),
            store: { openedStore() }
        )
        isInspectorPresented = !dependencies.lastBoard.isInspectorHidden
        bishopIconStyle = dependencies.lastBoard.bishopIconStyle.flatMap(BishopIconStyle.init(rawValue:)) ?? .symbol
        openedStore = { [weak self] in self?.openedStore?.store }
        history.selectionChanged = { [weak self] in await self?.viewedConfigurationChanged() }
    }

    // MARK: 이력 탭(W17)

    /// 보기 메뉴 '이력 보기'(⌘Y)와 툴바 이력 버튼이 켜지는 조건.
    var canShowHistory: Bool { selectedBoardID != nil }

    /// '이력 보기': 인스펙터가 접혀 있으면 펴며 이력 탭을 열고, 이력 탭에서 다시 하면 항목 탭으로 돌아간다(16.1).
    func toggleHistory() async {
        guard canShowHistory else { return }
        if isInspectorPresented, inspectorTab == .history {
            closeHistoryTab()
        } else {
            isInspectorPresented = true
            await openHistoryTab()
        }
    }

    /// 인스펙터 안 세그먼트로 탭을 바꾼다.
    func selectInspectorTab(_ tab: InspectorTab) async {
        switch tab {
        case .history where inspectorTab != .history && canShowHistory: await openHistoryTab()
        case .item where inspectorTab == .history: closeHistoryTab()
        default: break
        }
    }

    private func openHistoryTab() async {
        inspectorTab = .history
        if sidebarBeforeHistory == nil {
            sidebarBeforeHistory = isSidebarVisible
            isSidebarVisible = false
        }
        await history.open()
    }

    private func closeHistoryTab() {
        inspectorTab = .item
        if let before = sidebarBeforeHistory {
            isSidebarVisible = before
            sidebarBeforeHistory = nil
        }
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
        guard case let .loaded(snapshot) = shown else { return }
        var next = groupID
        var seen: Set<UUID> = []
        while let id = next, seen.insert(id).inserted, let node = snapshot.nodes.first(where: { $0.id == id }) {
            expandedGroupIDs.insert(id)
            next = node.parentID
        }
    }

    func children(of parentID: UUID?) -> [ConfigurationNode] {
        guard case let .loaded(snapshot) = shown else { return [] }
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
        case .file: String(localized: "Bishop")
        case .folder: String(localized: "Bishop · 폴더")
        case .webLink: String(localized: "웹 링크")
        }
    }

    func accessibilityLabel(for node: ConfigurationNode) -> String {
        // 이름, 종류, (상태), (용도) 순서다(DESIGN 17.7). 모르는 용도 키는 붙이지 않는다.
        var parts = [node.displayName, kindText(for: node)]
        if let status = displayedStatus(of: node.id) { parts.append(statusText(status)) }
        if let purpose = node.knownPurpose { parts.append(purposeText(purpose)) }
        return parts.joined(separator: ", ")
    }

    var inspector: NodeInspection? {
        guard case let .loaded(snapshot) = shown,
              let id = selectedNodeID, let node = snapshot.nodes.first(where: { $0.id == id })
        else { return nil }
        let kind = switch node.kind {
        case .group: String(localized: "Wing")
        case .file: String(localized: "Bishop")
        case .folder: String(localized: "Bishop · 폴더")
        case .webLink: String(localized: "웹 링크")
        }
        return NodeInspection(
            displayName: node.displayName, kind: kind, target: node.recordedPath ?? node.url,
            status: displayedStatus(of: node.id).map(statusText),
            purpose: node.kind == .file || node.kind == .folder ? purposeText(node.knownPurpose) : nil
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

    /// 과거 구성을 보는 동안에도 편집 동작은 모두 거짓이다(W18, DESIGN 16.4).
    private var canEditSelectedBoard: Bool { selectedBoardID != nil && openedStore != nil && !selectedBoardIsArchived && !isViewingPast }

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
        guard let boardID = selectedBoardID, openedStore != nil, !isViewingPast else { return nil }
        guard !selectedBoardIsArchived else {
            linkNotice = LinkNotice(kind: .archived, request: nil)
            return nil
        }
        return boardID
    }

    private var selectedNode: ConfigurationNode? {
        guard case let .loaded(snapshot) = shown, let id = selectedNodeID else { return nil }
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
                await adopt(snapshot)
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
            if selectedBoardID == boardID { await adopt(snapshot) }
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
    /// 아이콘 보기에서는 선택과 상관없이 지금 위치다(Finder의 새 폴더 관례, DESIGN 17.5).
    private var insertionParent: UUID? {
        if viewMode == .icons { return iconLocationID }
        return listInsertionParent
    }

    private var listInsertionParent: UUID? {
        guard case let .loaded(snapshot) = shown,
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
        guard selectedBoardID != nil, !selectedBoardIsArchived, !isViewingPast, case let .loaded(snapshot) = shown else { return false }
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
        case .pastSameTargetOnly:
            String(localized: "과거 구성에서는 같은 대상의 접근만 복구할 수 있습니다.")
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
        guard selectedBoardID != nil, !selectedBoardIsArchived, !isViewingPast, case let .loaded(snapshot) = shown,
              snapshot.nodes.contains(where: { $0.id == nodeID })
        else { return false }
        guard let targetID else { return true }
        guard let target = snapshot.nodes.first(where: { $0.id == targetID }) else { return false }
        return target.kind != .folder
    }

    /// 그룹 위면 그 안 끝, Bishop 파일·웹 링크 위면 그 앞, 빈 곳이면 최상위 끝으로 옮긴다. 자기 자신 위는 무변경이다.
    @discardableResult
    func dropNode(_ nodeID: UUID, on targetID: UUID?) async -> Bool {
        guard canAcceptNodeDrop(nodeID, on: targetID), case let .loaded(snapshot) = shown else { return false }
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
            await adopt(snapshot)
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
        let outcome: OpenOutcome
        if isViewingPast, let node = selectedNode, node.id == nodeID {
            // 과거 항목은 그 revision의 Node를 그대로 넘긴다(그 참조의 지금 대상, 당시 URL).
            outcome = await opening.perform(command, node: node)
        } else {
            outcome = await opening.perform(command, projectID: boardID, nodeID: nodeID)
        }
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

    // MARK: Bishop 용도(W29)

    /// 메뉴 막대·인스펙터·오른쪽 클릭의 "아이콘" 고르기가 켜지는 조건: 편집할 수 있는 Board에서 Bishop을 골랐을 때.
    var canSetPurposeOfSelected: Bool { canEditSelectedBoard && isBishopSelected }

    /// 인스펙터 "아이콘" 줄을 보이는 조건. 보관된 Board에서도 보이되 꺼진다.
    var isBishopSelected: Bool { selectedNode.map { $0.kind == .file || $0.kind == .folder } == true }

    /// 체크 표시할 지금 용도. 없거나 모르는 키면 nil(기본).
    var selectedPurpose: BishopPurpose? { selectedNode?.knownPurpose }

    func purposeText(_ purpose: BishopPurpose?) -> String {
        switch purpose {
        case nil: String(localized: "기본")
        case .document: String(localized: "문서")
        case .data: String(localized: "데이터")
        case .image: String(localized: "이미지")
        case .code: String(localized: "코드")
        case .reference: String(localized: "참고")
        case .presentation: String(localized: "발표")
        case .todo: String(localized: "할 일")
        case .design: String(localized: "디자인")
        }
    }

    func setPurposeOfSelected(_ purpose: BishopPurpose?) async {
        guard canSetPurposeOfSelected, let node = selectedNode else { return }
        await requestPurpose(node.id, purpose?.rawValue)
    }

    /// 용도 변경 요청 하나를 저장한다. 같은 값이면 서비스가 무변경으로 돌려준다.
    func requestPurpose(_ nodeID: UUID, _ key: String?) async {
        guard let boardID = selectedBoardID, let service = openedStore?.service else { return }
        let outcome: ConfigurationCommitOutcome
        do {
            outcome = try await service.apply(.changePurpose(nodeID, key), to: boardID)
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil)
            return
        }
        switch outcome {
        case let .committed(_, snapshot):
            if selectedBoardID == boardID { await adopt(snapshot) }
        case .unchanged:
            break
        case .rejected(.archived):
            linkNotice = LinkNotice(kind: .archived, request: nil)
        case .rejected:
            linkNotice = LinkNotice(kind: .saveFailed, request: nil)
        }
    }

    // MARK: 아이콘 보기(W28)

    func showIcons() {
        guard selectedBoardID != nil else { return }
        if let node = selectedNode {
            iconPath = path(to: node.parentID)
        } else if hasIconLocation {
            iconPath = resolvedIconPath
        } else {
            iconPath = []
        }
        hasIconLocation = true
        setViewMode(.icons)
    }

    func showList() {
        guard selectedBoardID != nil else { return }
        setViewMode(.list)
    }

    private func setViewMode(_ mode: ViewMode) {
        viewMode = mode
        if let boardID = selectedBoardID { dependencies.lastBoard.setViewMode(mode.rawValue, for: boardID) }
    }

    /// 지금 보고 있는 Wing. 최상위면 nil. 보던 Wing이 없어졌으면 남은 가장 가까운 상위다.
    var iconLocationID: UUID? { resolvedIconPath.last }

    private var resolvedIconPath: [UUID] { resolve(iconPath) }

    /// 경로에서 아직 있는 Wing까지만 남긴다(없어진 Wing부터 아래는 버린다).
    private func resolve(_ path: [UUID]) -> [UUID] {
        guard case let .loaded(snapshot) = shown else { return [] }
        var result: [UUID] = []
        for id in path {
            guard let node = snapshot.nodes.first(where: { $0.id == id }), node.kind == .group, node.parentID == result.last else { break }
            result.append(id)
        }
        return result
    }

    /// 최상위부터 그 Wing까지의 경로.
    private func path(to groupID: UUID?) -> [UUID] {
        guard case let .loaded(snapshot) = shown else { return [] }
        var result: [UUID] = []
        var next = groupID
        var seen: Set<UUID> = []
        while let id = next, seen.insert(id).inserted, let node = snapshot.nodes.first(where: { $0.id == id }) {
            result.insert(id, at: 0)
            next = node.parentID
        }
        return result
    }

    /// 아이콘 보기 현재 위치 한 단계의 항목(구성 순서).
    var iconItems: [ConfigurationNode] { children(of: iconLocationID) }

    var pathBarNames: [String] {
        guard case let .loaded(snapshot) = shown else { return [] }
        let wings = resolvedIconPath.compactMap { id in snapshot.nodes.first { $0.id == id }?.displayName }
        return [snapshot.projectName] + wings
    }

    /// 경로 막대 칸: 최상위(id nil)부터 지금 Wing까지.
    var pathBarEntries: [(id: UUID?, name: String)] {
        let names = pathBarNames
        let ids: [UUID?] = [nil] + resolvedIconPath.map(Optional.some)
        return Array(zip(ids, names)).map { (id: $0.0, name: $0.1) }
    }

    var iconItemCountText: String { String(localized: "항목 \(iconItems.count)개") }

    var iconTitle: String { pathBarNames.last ?? "" }
    var iconSubtitle: String? { resolvedIconPath.isEmpty ? nil : pathBarNames.first }

    var canGoUp: Bool { viewMode == .icons && !resolvedIconPath.isEmpty }
    var canGoBack: Bool { viewMode == .icons && !backStack.isEmpty }
    var canEnterSelected: Bool { viewMode == .icons && selectedNode != nil }

    /// Wing 안으로 들어간다. 선택은 비운다.
    func enter(_ wingID: UUID) {
        guard case let .loaded(snapshot) = shown, snapshot.nodes.first(where: { $0.id == wingID })?.kind == .group else { return }
        navigate(to: path(to: wingID))
    }

    /// 보기 메뉴 "들어가기"(⌘↓): Wing이면 들어가고 Bishop·웹 링크면 연다.
    func enterSelected() async {
        guard canEnterSelected, let node = selectedNode else { return }
        await activateTile(node.id)
    }

    /// 타일 이중 클릭.
    func activateTile(_ nodeID: UUID) async {
        guard case let .loaded(snapshot) = shown, let node = snapshot.nodes.first(where: { $0.id == nodeID }) else { return }
        if node.kind == .group {
            enter(nodeID)
        } else {
            await open(nodeID)
        }
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: Array(resolvedIconPath.dropLast()))
    }

    /// 경로 막대의 칸. nil이면 최상위.
    func goTo(_ wingID: UUID?) {
        guard viewMode == .icons else { return }
        navigate(to: path(to: wingID))
    }

    func goBack() {
        guard canGoBack, let previous = backStack.popLast() else { return }
        move(to: resolve(previous))
    }

    /// 뒤로 기록에 지금 위치를 쌓고 옮긴다(뒤로 자체는 쌓지 않는다).
    private func navigate(to newPath: [UUID]) {
        let old = resolvedIconPath
        guard newPath != old else { return }
        backStack.append(old)
        move(to: newPath)
    }

    /// 위치를 바꾼다. 상위로 가면 방금 있던 자식 Wing을 선택하고, 그 밖에는 선택을 비운다.
    private func move(to newPath: [UUID]) {
        let old = resolvedIconPath
        iconPath = newPath
        hasIconLocation = true
        if old.count > newPath.count, Array(old.prefix(newPath.count)) == newPath {
            selectedNodeID = old[newPath.count]
        } else {
            selectedNodeID = nil
        }
    }

    /// 방향키: 열 수 기준으로 이웃을 고른다. 경계에서는 그대로이고, 선택이 없으면 첫 타일을 고른다. Bishop이면 상태를 확인한다.
    func selectNeighbor(_ direction: GridDirection, columns: Int) async {
        let items = iconItems
        guard !items.isEmpty, columns > 0 else { return }
        guard let current = selectedNodeID, let index = items.firstIndex(where: { $0.id == current }) else {
            await selectNode(items[0].id)
            return
        }
        let next: Int = switch direction {
        case .left: index % columns == 0 ? index : index - 1
        case .right: (index % columns == columns - 1 || index + 1 >= items.count) ? index : index + 1
        case .up: index - columns >= 0 ? index - columns : index
        case .down: index + columns < items.count ? index + columns : index
        }
        guard next != index else { return }
        await selectNode(items[next].id)
    }

    /// 앱 안 항목 드롭(아이콘 보기): Wing 타일 위만 받는다. 빈 곳(같은 층)·Bishop·웹 링크·자기 자신은 받지 않는다(DESIGN 17.4).
    func canAcceptIconNodeDrop(_ nodeID: UUID, onTile tileID: UUID?) -> Bool {
        guard let tileID, tileID != nodeID, case let .loaded(snapshot) = shown,
              snapshot.nodes.first(where: { $0.id == tileID })?.kind == .group
        else { return false }
        return canAcceptNodeDrop(nodeID, on: tileID)
    }

    @discardableResult
    func dropNodeInIconView(_ nodeID: UUID, onTile tileID: UUID?) async -> Bool {
        guard canAcceptIconNodeDrop(nodeID, onTile: tileID) else { return false }
        return await dropNode(nodeID, on: tileID)
    }

    /// Finder 파일 드롭(아이콘 보기): Wing 타일 위는 그 안, 빈 곳은 지금 위치. Bishop·웹 링크 타일은 받지 않는다.
    func canAcceptIconFileDrop(onTile tileID: UUID?) -> Bool {
        canAcceptDrop(on: tileID ?? iconLocationID)
    }

    @discardableResult
    func dropFilesInIconView(_ urls: [URL], onTile tileID: UUID?) async -> Bool {
        guard canAcceptIconFileDrop(onTile: tileID) else { return false }
        return await drop(urls, on: tileID ?? iconLocationID)
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
        if isViewingPast {
            // 과거 항목은 그 revision의 참조로 확인하고, 카드에 보일 현재 위치도 함께 구한다(W18).
            let location = await links.location(of: node)
            guard epoch == statusEpoch, selectedBoardID == boardID else { return }
            pastLocations[nodeID] = location
            switch location {
            case .resolved: linkStatuses[nodeID] = .healthy
            case let .unresolved(status): linkStatuses[nodeID] = status
            }
            return
        }
        let status = await links.check(projectID: boardID, nodeID: nodeID)
        guard epoch == statusEpoch, selectedBoardID == boardID, let status else { return }
        linkStatuses[nodeID] = status
    }

    /// Board의 모든 Bishop을 한 번씩 다시 확인한다. 기록하지 않는다.
    func refreshStatuses() async {
        guard let boardID = selectedBoardID, let links = openedStore?.links else { return }
        let epoch = statusEpoch
        let statuses: [UUID: LinkStatus]
        if isViewingPast, case let .loaded(snapshot) = shown {
            statuses = await links.checkAll(snapshot.nodes)
        } else {
            statuses = await links.checkAll(projectID: boardID)
        }
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
        if isViewingPast {
            await reselectPast(node, url: url, boardID: boardID, service: service)
            return
        }
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

    /// 과거 화면의 다시 선택: 같은 대상의 접근 복구만 하고 다른 대상으로 덮어쓰지 않는다(PRD §6-H, 0012).
    private func reselectPast(_ node: ConfigurationNode, url: URL, boardID: UUID, service: TargetReplacementService) async {
        do {
            switch try await service.reselectPast(node: node, newURL: url) {
            case .recovered:
                guard selectedBoardID == boardID else { return }
                await selectNode(node.id)
            case .notSameTarget:
                linkNotice = LinkNotice(kind: .pastSameTargetOnly, request: nil)
            case let .rejected(rejection):
                linkNotice = notice(for: rejection, url: url)
            }
        } catch {
            linkNotice = LinkNotice(kind: .saveFailed, request: nil)
        }
    }

    // MARK: 과거 구성(W18)

    /// 이력 탭에서 revision을 골라 그 구성을 보고 있다. 가운데 영역·선택·인스펙터가 그 구성을 보이고 편집은 모두 꺼진다.
    var isViewingPast: Bool { history.selectedSnapshot != nil }

    /// 화면에 보이는 구성: 과거 모드면 고른 revision, 아니면 현재 구성.
    var shownSnapshot: ConfigurationSnapshot? {
        if case let .loaded(snapshot) = shown { snapshot } else { nil }
    }

    private var shown: CurrentConfiguration {
        history.selectedSnapshot.map(CurrentConfiguration.loaded) ?? current
    }

    var canReturnToCurrent: Bool { isViewingPast }

    /// 띠의 '현재로 돌아가기', 보기 메뉴 '현재 구성으로 돌아가기'. 이력 탭 '현재 구성' 행과 같은 동작이다.
    func returnToCurrent() async {
        await history.select(.current)
    }

    var pastBannerTitle: String { String(localized: "과거 구성 · 읽기 전용") }

    /// 띠 둘째 줄: '#순번 · 날짜 시각 기록'(실제 기록 시각).
    var pastBannerDetail: String? {
        guard isViewingPast, let summary = history.selectedSummary else { return nil }
        return String(localized: "#\(summary.sequence) · \(history.dateTimeText(summary.recordedAt)) 기록")
    }

    /// VoiceOver는 띠를 한 요소로 읽는다(16.3).
    var pastBannerAccessibilityLabel: String? {
        guard isViewingPast, let summary = history.selectedSummary else { return nil }
        return String(localized: "과거 구성, 읽기 전용, #\(summary.sequence), \(history.dateTimeText(summary.recordedAt)) 기록")
    }

    /// 이력 탭 아래쪽 '고른 항목' 카드(16.2). 과거 모드에서 항목을 골랐을 때만 있다.
    struct PastItemCard: Equatable {
        var name: String
        var kind: NodeKind
        var recordedPath: String?
        /// 고른 Bishop의 지금 위치. 확인 전이면 nil.
        var location: NodeLocation?
        var url: String?
    }

    var pastItemCard: PastItemCard? {
        guard isViewingPast, let node = selectedNode else { return nil }
        let isLinked = node.kind == .file || node.kind == .folder
        return PastItemCard(
            name: node.displayName, kind: node.kind,
            recordedPath: isLinked ? node.recordedPath : nil,
            location: isLinked ? pastLocations[node.id] : nil,
            url: node.kind == .webLink ? node.url : nil
        )
    }

    var recordedPathLabel: String { String(localized: "당시 경로") }
    var currentLocationLabel: String { String(localized: "현재 위치") }
    var movedLocationText: String { String(localized: "당시와 다른 위치") }
    var recordedURLLabel: String { String(localized: "당시 URL") }
    var currentContentNotice: String { String(localized: "열면 지금의 파일이 열립니다. 파일 내용의 과거 버전은 보관하지 않습니다.") }

    /// 과거·현재 모드가 바뀌면: 두 모드의 연결 상태를 섞지 않게 비우고, 고른 항목이 새로 보이는 구성에 없으면 비운다.
    /// 남은 Bishop은 그 구성의 참조로 다시 확인한다.
    private func viewedConfigurationChanged() async {
        statusEpoch += 1
        linkStatuses = [:]
        pastLocations = [:]
        guard let id = selectedNodeID else { return }
        guard shownSnapshot?.nodes.contains(where: { $0.id == id }) == true else {
            selectedNodeID = nil
            return
        }
        await selectNode(id)
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
            await adopt(snapshot)
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
        guard !isViewingPast, case let .loaded(snapshot) = shown, let id = selectedNodeID,
              let node = snapshot.nodes.first(where: { $0.id == id })
        else { return false }
        return node.kind == .file || node.kind == .folder
    }

    func beginReplaceTarget() async {
        guard let boardID = selectedBoardID, let service = openedStore?.replacement,
              canReplaceSelectedTarget, case let .loaded(snapshot) = shown,
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
                await adopt(snapshot)
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
                await adopt(snapshot)
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
        viewMode = dependencies.lastBoard.viewMode(for: boardID).flatMap(ViewMode.init(rawValue:)) ?? .list
        history.reset(boardID: boardID)
        iconPath = []
        hasIconLocation = false
        backStack = []
        linkStatuses = [:]
        pastLocations = [:]
        expandedGroupIDs = []
        statusEpoch += 1
        guard let store = openedStore?.store else { return }
        do {
            current = .loaded(try await store.currentSnapshot(projectID: boardID))
        } catch {
            current = .unreadable
        }
        if inspectorTab == .history { await history.open() }
    }

    /// 저장에 성공한 구성을 현재 구성으로 삼고, 이력 탭이 열려 있었으면 새 revision을 목록 맨 위에 더한다.
    private func adopt(_ snapshot: ConfigurationSnapshot) async {
        current = .loaded(snapshot)
        await history.loadNewer()
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
