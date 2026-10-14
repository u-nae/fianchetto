import SwiftUI

/// 기본 창: 저장소 상태에 따라 복구 화면, 목록 오류, 또는 Board 목록·현재 구성·상세 영역을 보여 준다.
struct BoardBrowserView: View {
    @Bindable var model: BoardBrowserModel
    /// 분할 뷰에 넘기는 사이드바 표시. 이력 탭·비교가 모델 값을 바꾸면 애니메이션으로 따라간다.
    /// 바로 바꾸면 macOS 26에서 NSSplitView 안전 영역 제약이 충돌한다(0029, 가상 머신 UI 테스트에서 발견).
    /// 동작 줄이기에서도 애니메이션 경로를 타야 제약 충돌이 없으므로, 거의 즉시 끝나는 짧은 애니메이션을 쓴다.
    @State private var shownSidebarVisible: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Observation은 body에서 읽은 값만 추적하므로 Binding 클로저 밖에서 먼저 읽는다.
        let isCreating = model.creation != nil
        let isRenaming = model.rename != nil
        let hasNodeForm = model.nodeForm != nil
        let moveDialog = model.moveDialog
        let removal = model.removal
        let notice = model.linkNotice
        let replacement = model.replacement
        let inspectorPresented = model.isInspectorPresented
        let sidebarVisible = model.isSidebarVisible
        Group {
            switch model.phase {
            case .loading:
                ProgressView()
            case let .storeUnavailable(category):
                StoreRecoveryView(model: model, category: category)
            case .listUnavailable:
                ContentUnavailableView {
                    Label("Board 목록을 읽지 못했습니다", systemImage: "exclamationmark.triangle")
                } actions: {
                    Button("다시 시도") { Task { await model.retry() } }
                }
            case .ready:
                // 오른쪽 열은 접을 수 있는 인스펙터 하나다(DESIGN.md 16.1). 접으면 구성 영역이 넓어진다.
                // 이력 탭을 열면 Board 사이드바를 접고 닫으면 열기 전 상태로 돌린다(16.1). 사용자가 바꾼 표시도 모델에 알려, 그동안 바꾼 선택은 지킨다(0032).
                NavigationSplitView(columnVisibility: Binding(
                    get: { (shownSidebarVisible ?? sidebarVisible) ? .all : .detailOnly },
                    set: { visibility in
                        let visible = visibility != .detailOnly
                        shownSidebarVisible = visible
                        model.isSidebarVisible = visible
                    }
                )) {
                    BoardListView(model: model)
                } detail: {
                    ConfigurationTreeView(model: model)
                        .inspector(isPresented: Binding(get: { inspectorPresented }, set: { model.isInspectorPresented = $0 })) {
                            InspectorPanel(model: model)
                                .inspectorColumnWidth(min: 220, ideal: 280, max: 420)
                        }
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                // 켜짐 상태로 지금 이력 탭을 보고 있는지 툴바에서도 알린다.
                                Toggle(isOn: Binding(
                                    get: { inspectorPresented && model.inspectorTab == .history },
                                    set: { _ in Task { await model.toggleHistory() } }
                                )) {
                                    Label("이력", systemImage: "clock.arrow.circlepath")
                                }
                                .toggleStyle(.button)
                                .help("이력")
                                .disabled(!model.canShowHistory)
                                .accessibilityIdentifier("history-toggle")
                            }
                            ToolbarItem(placement: .primaryAction) {
                                Button(inspectorPresented ? "인스펙터 가리기" : "인스펙터 보기", systemImage: "sidebar.right") {
                                    model.toggleInspector()
                                }
                                .help(inspectorPresented ? "인스펙터 가리기" : "인스펙터 보기")
                                .accessibilityIdentifier("inspector-toggle")
                            }
                        }
                }
                .onAppear { shownSidebarVisible = sidebarVisible }
                .onChange(of: sidebarVisible) { _, visible in
                    // 툴바 버튼처럼 분할 뷰가 바꾼 값은 이미 반영되어 있다.
                    guard shownSidebarVisible != visible else { return }
                    withAnimation(reduceMotion ? .linear(duration: 0.01) : .default) { shownSidebarVisible = visible }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 480)
        .sheet(isPresented: Binding(get: { isCreating }, set: { if !$0 { model.cancelCreate() } })) {
            CreateBoardSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { isRenaming }, set: { if !$0 { model.cancelRename() } })) {
            RenameBoardSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { hasNodeForm }, set: { if !$0 { model.cancelNodeForm() } })) {
            NodeFormSheet(model: model)
        }
        .sheet(isPresented: Binding(get: { moveDialog != nil }, set: { if !$0 { model.cancelMove() } })) {
            if let moveDialog {
                MoveSheet(model: model, dialog: moveDialog)
            }
        }
        .sheet(isPresented: Binding(get: { removal != nil }, set: { if !$0 { model.cancelRemove() } })) {
            if let removal {
                RemoveSheet(model: model, removal: removal)
            }
        }
        .sheet(item: Binding(get: { replacement.map(PreviewItem.init) }, set: { if $0 == nil { model.cancelReplacement() } })) { item in
            ReplacementSheet(model: model, preview: item.preview)
        }
        .sheet(isPresented: Binding(get: { model.restorePreview != nil }, set: { if !$0 { model.cancelRestore() } })) {
            if let preview = model.restorePreview {
                RestoreSheet(model: model, preview: preview)
            }
        }
        .alert(
            notice.map(model.noticeTitle) ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { model.dismissLinkNotice() } }),
            presenting: notice
        ) { notice in
            if notice.canRetry {
                Button("다시 시도") { Task { await model.retryLink() } }
            }
            Button("닫기", role: .cancel) { model.dismissLinkNotice() }
        } message: { notice in
            Text(model.noticeText(notice))
        }
    }
}

private struct StoreRecoveryView: View {
    let model: BoardBrowserModel
    let category: StoreOpenError.Category

    var body: some View {
        ContentUnavailableView {
            Label("데이터를 열 수 없습니다", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(model.recoveryMessage(for: category))
        } actions: {
            Button("다시 시도") { Task { await model.retry() } }
            Button("Finder에서 보기") { model.revealStore() }
                .disabled(!model.canRevealStore)
            Button("종료") { model.quit() }
        }
    }
}

private struct BoardListView: View {
    @Bindable var model: BoardBrowserModel

    var body: some View {
        let selected = model.selectedBoardID
        List(selection: Binding(get: { selected }, set: { id in
            if let id { Task { await model.select(id) } }
        })) {
            Section("Board") {
                ForEach(model.activeBoards) { BoardRow(model: model, board: $0) }
            }
            if !model.archivedBoards.isEmpty {
                Section("보관된 Board") {
                    ForEach(model.archivedBoards) { BoardRow(model: model, board: $0) }
                }
            }
        }
        // 오른쪽 클릭 메뉴는 파일 메뉴의 Board 명령과 같은 이름·순서다. 누른 Board를 먼저 고른 뒤 실행한다.
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let board = (model.activeBoards + model.archivedBoards).first(where: { $0.id == id }) {
                BoardContextMenu(model: model, boardID: id, isArchived: board.archivedAt != nil)
            }
        }
        .toolbar {
            Button("Board 만들기", systemImage: "plus") { model.beginCreate() }
                .help("Board 만들기")
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
    }
}

private struct BoardRow: View {
    let model: BoardBrowserModel
    let board: ProjectListing

    var body: some View {
        // Board 심볼(0025). square.grid.2x2는 아이콘 보기 전환 버튼에만 쓴다.
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(board.name)
                    if let status = model.statusText(for: board) {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(model.createdText(for: board)).font(.caption2).foregroundStyle(.secondary)
            }
        } icon: {
            Image(.fianchettoBoard)
        }
        .tag(board.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: board))
        .accessibilityAddTraits(model.selectedBoardID == board.id ? .isSelected : [])
        .accessibilityIdentifier("board-row-\(board.name)")
    }
}

private struct ConfigurationTreeView: View {
    @Bindable var model: BoardBrowserModel
    @State private var listTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            if let readOnly = model.readOnlyText {
                Label(readOnly, systemImage: "archivebox")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
            }
            if model.isComparing {
                // 비교 중에는 과거 구성 띠 대신 비교 띠만 보인다(0027). 비교는 목록 형태로만 보인다(19.1).
                ComparisonView(model: model)
            } else {
                if model.isViewingPast {
                    PastConfigurationBanner(model: model)
                }
                content
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if model.viewMode == .icons {
                    Button("뒤로", systemImage: "chevron.left") { model.goBack() }
                        .help("뒤로")
                        .disabled(!model.canGoBack)
                }
            }
            ToolbarItem {
                // 보기 전환(DESIGN 17.1): 아이콘 | 목록. Board마다 기억한다.
                Picker("보기", selection: Binding(get: { model.viewMode }, set: { mode in
                    mode == .icons ? model.showIcons() : model.showList()
                })) {
                    Label("아이콘으로 보기", systemImage: "square.grid.2x2").tag(BoardBrowserModel.ViewMode.icons)
                    Label("목록으로 보기", systemImage: "list.bullet").tag(BoardBrowserModel.ViewMode.list)
                }
                .pickerStyle(.segmented)
                .help("보기")
                .disabled(!model.canChangeViewMode)
                .accessibilityIdentifier("view-mode")
            }
            ToolbarItemGroup {
                Button { Task { await model.addBishops() } } label: {
                    Label("Bishop 추가", image: .fianchettoBishop)
                }
                .help("Bishop 추가")
                .disabled(!model.canAddToBoard)
                Button { model.beginAddGroup() } label: { Label("Wing 추가", image: .fianchettoWing) }
                    .help("Wing 추가")
                    .disabled(!model.canAddToBoard)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.current {
        case .none:
            ContentUnavailableView {
                Label { Text("Board가 없습니다") } icon: { ChessboardIllustration() }
            } description: {
                Text("Board를 만들거나 목록에서 고르세요.")
            } actions: {
                Button("Board 만들기") { model.beginCreate() }
            }
        case .unreadable:
            ContentUnavailableView("현재 구성을 읽지 못했습니다", systemImage: "exclamationmark.triangle")
        case let .loaded(snapshot) where snapshot.nodes.isEmpty:
            ContentUnavailableView {
                Label { Text("구성이 비어 있습니다") } icon: { ChessboardIllustration() }
            }
                .dropDestination(for: TreeDropItem.self) { items, _ in
                    accept(items, on: nil)
                }
        case .loaded where model.viewMode == .icons:
            IconGridView(model: model)
        case .loaded:
            let selectedNode = model.selectedNodeID
            // 선택은 바로 반영하고, Bishop이면 연결 상태를 확인한다(W15).
            List(selection: Binding(get: { selectedNode }, set: { id in
                model.selectedNodeID = id
                Task { await model.selectNode(id) }
            })) {
                // 펼침 상태는 모델이 가진다. 그룹 안에 항목을 넣으면 모델이 그 그룹을 펼쳐 새 항목이 보이게 한다.
                ForEach(model.tree) { item in
                    TreeBranch(model: model, item: item, accept: accept)
                }
            }
            // 이중 클릭은 열기다. 오른쪽 클릭 메뉴는 항목 종류에 맞는 메뉴 막대 명령을 같은 이름·순서로 보여 준다.
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let node = TreeItem.node(id, in: model.tree) {
                    NodeContextMenu(model: model, node: node)
                }
            } primaryAction: { ids in
                if let id = ids.first { Task { await model.open(id) } }
            }
            // Delete 키는 편집 메뉴의 '제거…'와 같다. 확인 창을 열고, 화면에 '삭제' 표현을 쓰지 않는다.
            // onKeyPress는 목록의 키보드 포커스를 빼앗아 방향키까지 막으므로, 시스템 Delete 명령에 연결한다.
            .onDeleteCommand { model.beginRemove() }
            .dropDestination(for: TreeDropItem.self) { items, _ in
                accept(items, on: nil)
            } isTargeted: { listTargeted = $0 }
            .overlay {
                DropHighlight(isActive: listTargeted && model.canAcceptDrop(on: nil))
            }
        }
    }
}

/// 트리 한 갈래: 하위 항목이 있는 그룹은 모델의 펼침 상태에 묶인 DisclosureGroup, 나머지는 행 하나.
private struct TreeBranch: View {
    let model: BoardBrowserModel
    let item: TreeItem
    let accept: ([TreeDropItem], UUID?) -> Bool
    @State private var isTargeted = false

    var body: some View {
        if let children = item.children {
            // Observation은 body에서 읽은 값만 추적하므로 Binding 클로저 밖에서 먼저 읽는다.
            let expanded = model.isExpanded(item.id)
            DisclosureGroup(isExpanded: Binding(get: { expanded }, set: { model.setExpanded(item.id, $0) })) {
                ForEach(children) { child in
                    TreeBranch(model: model, item: child, accept: accept)
                }
            } label: {
                row
            }
        } else {
            row
        }
    }

    private var row: some View {
        NodeRow(model: model, node: item.node)
            .draggable(NodeDragItem(nodeID: item.node.id))
            .dropDestination(for: TreeDropItem.self) { items, _ in
                accept(items, item.node.id)
            } isTargeted: { isTargeted = $0 }
            // 놓을 수 있는 Wing만 강조한다. 놓을 수 없는 곳은 강조하지 않는다.
            .background {
                DropHighlight(isActive: isTargeted && model.canAcceptDrop(on: item.node.id))
            }
    }
}

/// 끌어 놓을 위치 표시. 시스템 강조 색 테두리라 사용자의 강조 색 설정을 따른다.
struct DropHighlight: View {
    let isActive: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// 트리 항목의 오른쪽 클릭 메뉴. 누른 항목을 먼저 고른 뒤 메뉴 막대와 같은 명령을 실행한다.
struct NodeContextMenu: View {
    let model: BoardBrowserModel
    let node: ConfigurationNode
    /// 아이콘 보기의 Wing 타일은 Finder처럼 항목 명령만 보이고, 추가는 빈 곳 메뉴에 둔다(현재 위치에 추가).
    var inIconView = false

    var body: some View {
        if model.isViewingPast {
            pastItems
        } else {
            currentItems
        }
    }

    /// 과거 구성(16.4): 열기·Finder에서 보기·다시 선택(같은 대상만)과 아이콘 보기의 Wing 들어가기만 둔다.
    @ViewBuilder private var pastItems: some View {
        switch node.kind {
        case .file, .folder:
            Button("열기") { run { await model.openSelected() } }
            Button("Finder에서 보기") { run { await model.revealSelected() } }
            Divider()
            Button("다시 선택…") { run { await model.reselectSelectedTarget() } }
        case .webLink:
            Button("열기") { run { await model.openSelected() } }
        case .group where inIconView:
            Button("들어가기") { run { await model.activateTile(node.id) } }
        case .group:
            EmptyView()
        }
    }

    @ViewBuilder private var currentItems: some View {
        switch node.kind {
        case .file, .folder:
            Button("열기") { run { await model.openSelected() } }
            Button("Finder에서 보기") { run { await model.revealSelected() } }
            Divider()
            Button("다시 선택…") { run { await model.reselectSelectedTarget() } }
            Button("연결 대상 변경…") { run { await model.beginReplaceTarget() } }
                .disabled(!model.canAddToBoard)
            Menu("아이콘") {
                PurposeMenuItems(current: node.knownPurpose, text: model.purposeText) { purpose in
                    run { await model.setPurposeOfSelected(purpose) }
                }
            }
            .disabled(!model.canAddToBoard)
        case .webLink:
            Button("열기") { run { await model.openSelected() } }
            Divider()
            Button("URL 변경…") { run { model.beginChangeURL() } }
                .disabled(!model.canAddToBoard)
        case .group where inIconView:
            Button("들어가기") { run { await model.activateTile(node.id) } }
        case .group:
            Group {
                Button("Bishop 추가…") { run { await model.addBishops() } }
                Button("Wing 추가…") { run { model.beginAddGroup() } }
                Button("웹 링크 추가…") { run { model.beginAddWebLink() } }
            }
            .disabled(!model.canAddToBoard)
        }
        Divider()
        // 편집 명령은 Board를 편집할 수 있을 때만 켠다(보관된 Board는 읽기 전용).
        Group {
            Button("이름 변경…") { run { model.beginRenameNode() } }
            Button("이동…") { run { model.beginMove() } }
            Divider()
            Button("제거…") { run { model.beginRemove() } }
        }
        .disabled(!model.canAddToBoard)
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        model.selectedNodeID = node.id
        Task {
            await model.selectNode(node.id)
            await action()
        }
    }
}

/// Board 목록의 오른쪽 클릭 메뉴. 보관 여부에 따라 보관 또는 보관 해제 하나만 보여 준다.
private struct BoardContextMenu: View {
    let model: BoardBrowserModel
    let boardID: UUID
    let isArchived: Bool

    var body: some View {
        Button("Board 이름 변경…") { run { model.beginRename() } }
        if isArchived {
            Button("보관 해제") { run { await model.unarchiveSelected() } }
        } else {
            Button("Board 보관") { run { await model.archiveSelected() } }
        }
    }

    private func run(_ action: @escaping @MainActor () async -> Void) {
        Task {
            await model.select(boardID)
            await action()
        }
    }
}

private extension TreeItem {
    /// 트리에서 id로 항목을 찾는다(오른쪽 클릭 메뉴용 조회. 상태를 바꾸지 않는다).
    static func node(_ id: UUID, in items: [TreeItem]) -> ConfigurationNode? {
        for item in items {
            if item.id == id { return item.node }
            if let found = node(id, in: item.children ?? []) { return found }
        }
        return nil
    }
}

private extension ConfigurationTreeView {
    /// 드롭은 받을 수 있는 곳에서만 받아들이고, 연결·이동은 비동기로 진행한다.
    /// Finder의 파일은 연결하고, 앱 안에서 끈 항목 하나는 옮긴다. 둘이 섞이거나 알 수 없는 것은 받지 않는다.
    func accept(_ items: [TreeDropItem], on nodeID: UUID?) -> Bool {
        let urls = items.compactMap(\.fileURL)
        if !urls.isEmpty, urls.count == items.count {
            guard model.canAcceptDrop(on: nodeID), urls.allSatisfy(\.isFileURL) else { return false }
            Task { await model.drop(urls, on: nodeID) }
            return true
        }
        guard items.count == 1, let moved = items.first?.nodeID, model.canAcceptNodeDrop(moved, on: nodeID) else { return false }
        Task { await model.dropNode(moved, on: nodeID) }
        return true
    }
}

private struct NodeRow: View {
    let model: BoardBrowserModel
    let node: ConfigurationNode

    var body: some View {
        Label {
            HStack {
                Text(node.displayName)
                Text(model.kindText(for: node)).font(.caption).foregroundStyle(.secondary)
                if let status = model.displayedStatus(of: node.id), let presentation = LinkStatusPresentation.of(status) {
                    LinkStatusLabel(text: model.statusText(status), presentation: presentation)
                }
            }
        } icon: {
            // 설정의 Bishop 아이콘 방식을 목록에도 같이 쓴다(DESIGN 18.5).
            TileIconView(icon: TileIcon.of(node, style: model.bishopIconStyle))
        }
        .tag(node.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: node))
        .accessibilityIdentifier("node-row-\(node.displayName)")
        .accessibilityAddTraits(model.selectedNodeID == node.id ? .isSelected : [])
    }

}

/// "이동…" 창: 최상위와 옮길 수 있는 그룹을 트리 순서로 보여 준다.
private struct MoveSheet: View {
    let model: BoardBrowserModel
    let dialog: BoardBrowserModel.MoveDialog
    @State private var selection: BoardBrowserModel.MoveTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이동할 위치").font(.headline)
            List(dialog.destinations, selection: $selection) { destination in
                Label { Text(destination.name) } icon: { Image(destination.target == .root ? .fianchettoBoard : .fianchettoWing) }
                    .padding(.leading, CGFloat(max(destination.depth - 1, 0)) * 16)
                    .accessibilityIdentifier("move-destination-\(destination.name)")
            }
            .frame(minHeight: 200)
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelMove() }
                    .keyboardShortcut(.cancelAction)
                Button("이동") {
                    guard let selection else { return }
                    Task { await model.confirmMove(to: selection) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

/// 제거 확인 창: 종류별 제목과 함께 제거될 범위. 연결 대상은 지우지 않는다.
private struct RemoveSheet: View {
    let model: BoardBrowserModel
    let removal: BoardBrowserModel.Removal

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.removalTitle(removal)).font(.headline)
            Text(model.removalMessage(removal))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("removal-message")
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelRemove() }
                    .keyboardShortcut(.cancelAction)
                Button("제거", role: .destructive) { Task { await model.confirmRemove() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

private struct PreviewItem: Identifiable {
    var preview: ReplacementPreview
    var id: String { "\(preview.nodeID)-\(preview.newPath)" }
}

/// 연결 대상 변경 확인 창: 기존·새 경로와 판정에 따른 안내.
private struct ReplacementSheet: View {
    let model: BoardBrowserModel
    let preview: ReplacementPreview

    var body: some View {
        let presentation = model.replacementPresentation(preview)
        VStack(alignment: .leading, spacing: 12) {
            Text("연결 대상 변경").font(.headline)
            LabeledContent("기존", value: preview.oldPath)
            LabeledContent("새 대상", value: preview.newPath)
            if let warning = presentation.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
            }
            HStack {
                Spacer()
                if presentation.canConfirm {
                    Button("취소", role: .cancel) { model.cancelReplacement() }
                        .keyboardShortcut(.cancelAction)
                    Button("변경") { Task { await model.confirmReplacement() } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("닫기") { model.cancelReplacement() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding()
        .frame(width: 460)
    }
}

/// 과거 구성 띠(DESIGN.md 16.3): 기호 + '과거 구성 · 읽기 전용'과 '현재로 돌아가기', 둘째 줄에 순번과 실제 기록 시각.
/// '현재와 비교'(W19)와 '이 구성으로…' 메뉴의 '복원…'(W20)이 있다. '새 Board 만들기…'는 W21이 동작과 함께 더한다. VoiceOver는 문구를 한 요소로 읽는다.
private struct PastConfigurationBanner: View {
    let model: BoardBrowserModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(model.pastBannerTitle, systemImage: "clock.arrow.circlepath")
                    .font(.callout.bold())
                if let detail = model.pastBannerDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.pastBannerAccessibilityLabel ?? model.pastBannerTitle)
            .accessibilityIdentifier("past-banner")
            Spacer()
            Button("현재와 비교") { Task { await model.compareWithCurrent() } }
                .disabled(!model.canCompareWithCurrent)
                .accessibilityIdentifier("compare-with-current")
            Menu("이 구성으로…") {
                Button("복원…") { model.beginRestore() }
                    .disabled(!model.canRestoreShown)
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityIdentifier("restore-menu")
            Button("현재로 돌아가기") { Task { await model.returnToCurrent() } }
                .accessibilityIdentifier("return-to-current")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.quaternary)
    }
}

/// 오른쪽 열(인스펙터): 맨 위 '항목 | 이력' 세그먼트로 항목 상세와 이력을 같은 자리에서 바꾼다(DESIGN.md 16.1).
private struct InspectorPanel: View {
    let model: BoardBrowserModel

    var body: some View {
        let tab = model.inspectorTab
        VStack(spacing: 0) {
            Picker("인스펙터", selection: Binding(get: { tab }, set: { next in Task { await model.selectInspectorTab(next) } })) {
                Text("항목").tag(BoardBrowserModel.InspectorTab.item)
                Text("이력").tag(BoardBrowserModel.InspectorTab.history)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!model.canShowHistory && tab == .item)
            .padding([.horizontal, .top])
            switch tab {
            case .item:
                NodeInspectorView(model: model)
                    .frame(maxHeight: .infinity, alignment: .top)
            case .history:
                HistoryTabView(history: model.history, model: model)
            }
        }
        // 날짜나 시스템 시간대가 바뀌면 날짜 구역 머리글과 행 시각을 다시 계산한다.
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            model.history.clockChanged()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
            model.history.clockChanged()
        }
    }
}

private struct NodeInspectorView: View {
    let model: BoardBrowserModel

    var body: some View {
        if model.isComparing {
            ComparisonDetailView(model: model)
        } else if let inspection = model.inspector {
            Form {
                LabeledContent("표시 이름", value: inspection.displayName)
                LabeledContent("종류", value: inspection.kind)
                if let target = inspection.target {
                    LabeledContent("대상", value: target)
                }
                if let id = model.selectedNodeID, let status = model.displayedStatus(of: id),
                   let presentation = LinkStatusPresentation.of(status) {
                    LabeledContent("상태") {
                        LinkStatusLabel(text: model.statusText(status), presentation: presentation)
                    }
                    HStack {
                        Button("다시 선택…") { Task { await model.reselectSelectedTarget() } }
                        Button("상태 새로고침") { Task { await model.refreshStatuses() } }
                    }
                }
                HStack {
                    if model.canOpenSelected {
                        Button("열기") { Task { await model.openSelected() } }
                    }
                    if model.canRevealSelected {
                        Button("Finder에서 보기") { Task { await model.revealSelected() } }
                    }
                }
                if model.canReplaceSelectedTarget {
                    Button("연결 대상 변경") { Task { await model.beginReplaceTarget() } }
                }
                if let id = model.selectedNodeID, model.isBishopSelected {
                    Picker("아이콘", selection: Binding(get: { model.selectedPurpose }, set: { purpose in
                        Task { await model.setPurposeOfSelected(purpose) }
                    })) {
                        ForEach(PurposeMenuItems.choices, id: \.self) { purpose in
                            if let purpose {
                                Label(model.purposeText(purpose), systemImage: PurposePresentation.symbol(for: purpose)).tag(purpose)
                            } else {
                                Text(model.purposeText(nil)).tag(purpose)
                            }
                        }
                    }
                    .disabled(!model.canSetPurposeOfSelected)
                    .id(id)
                }
            }
            .padding()
        } else {
            ContentUnavailableView("항목을 고르세요", systemImage: "sidebar.right")
        }
    }
}

/// 그룹 추가·웹 링크 추가·이름 변경·URL 변경 입력 창.
private struct NodeFormSheet: View {
    @Bindable var model: BoardBrowserModel

    var body: some View {
        let form = model.nodeForm
        VStack(alignment: .leading, spacing: 12) {
            Text(title(form?.purpose)).font(.headline)
            if showsName(form?.purpose) {
                TextField("이름", text: Binding(get: { model.nodeForm?.name ?? "" }, set: { model.nodeForm?.name = $0 }))
                    .accessibilityIdentifier("node-name-field")
                    .onSubmit { confirm() }
            }
            if showsURL(form?.purpose) {
                TextField("https://", text: Binding(get: { model.nodeForm?.url ?? "" }, set: { model.nodeForm?.url = $0 }))
                    .accessibilityIdentifier("node-url-field")
                    .onSubmit { confirm() }
            }
            if let message = form?.message {
                Text(model.formMessageText(message)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelNodeForm() }
                    .keyboardShortcut(.cancelAction)
                Button("확인") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(form?.isSaving == true)
            }
        }
        .padding()
        .frame(width: 380)
    }

    private func title(_ purpose: BoardBrowserModel.NodeForm.Purpose?) -> String {
        switch purpose {
        case .addGroup: String(localized: "Wing 추가")
        case .addWebLink: String(localized: "웹 링크 추가")
        case .rename: String(localized: "이름 변경")
        case .changeURL: String(localized: "URL 변경")
        case nil: ""
        }
    }

    private func showsName(_ purpose: BoardBrowserModel.NodeForm.Purpose?) -> Bool {
        if case .changeURL = purpose { return false }
        return true
    }

    private func showsURL(_ purpose: BoardBrowserModel.NodeForm.Purpose?) -> Bool {
        switch purpose {
        case .addWebLink, .changeURL: true
        default: false
        }
    }

    private func confirm() {
        Task { await model.confirmNodeForm() }
    }
}

private struct RenameBoardSheet: View {
    @Bindable var model: BoardBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board 이름 변경").font(.headline)
            TextField("Board 이름", text: Binding(get: { model.rename?.name ?? "" }, set: { model.rename?.name = $0 }))
                .onSubmit { confirm() }
            if let message = model.rename?.message {
                Text(message == .nameRequired ? "이름을 입력하세요." : "저장하지 못했습니다. 다시 시도하세요.")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelRename() }
                    .keyboardShortcut(.cancelAction)
                Button("이름 변경") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.rename?.isSaving == true)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func confirm() {
        Task { await model.confirmRename() }
    }
}

private struct CreateBoardSheet: View {
    @Bindable var model: BoardBrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Board 만들기").font(.headline)
            TextField("Board 이름", text: Binding(
                get: { model.creation?.name ?? "" }, set: { model.creation?.name = $0 }
            ))
            .accessibilityIdentifier("board-name-field")
            .onSubmit { confirm() }
            if let message = model.creation?.message {
                Text(message == .nameRequired ? "이름을 입력하세요." : "저장하지 못했습니다. 다시 시도하세요.")
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("취소", role: .cancel) { model.cancelCreate() }
                    .keyboardShortcut(.cancelAction)
                Button("만들기") { confirm() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConfirmCreate)
            }
        }
        .padding()
        .frame(width: 360)
    }

    private func confirm() {
        Task { await model.confirmCreate() }
    }
}
