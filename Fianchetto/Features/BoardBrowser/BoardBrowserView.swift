import SwiftUI

/// 기본 창: 저장소 상태에 따라 복구 화면, 목록 오류, 또는 Board 목록·현재 구성·상세 영역을 보여 준다.
struct BoardBrowserView: View {
    @Bindable var model: BoardBrowserModel

    var body: some View {
        // Observation은 body에서 읽은 값만 추적하므로 Binding 클로저 밖에서 먼저 읽는다.
        let isCreating = model.creation != nil
        let isRenaming = model.rename != nil
        let hasNodeForm = model.nodeForm != nil
        let notice = model.linkNotice
        let replacement = model.replacement
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
                NavigationSplitView {
                    BoardListView(model: model)
                } content: {
                    ConfigurationTreeView(model: model)
                } detail: {
                    NodeInspectorView(model: model)
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
        .sheet(item: Binding(get: { replacement.map(PreviewItem.init) }, set: { if $0 == nil { model.cancelReplacement() } })) { item in
            ReplacementSheet(model: model, preview: item.preview)
        }
        .alert(
            "Bishop 추가",
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(board.name)
                if let status = model.statusText(for: board) {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(model.createdText(for: board)).font(.caption2).foregroundStyle(.secondary)
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

    var body: some View {
        VStack(spacing: 0) {
            if let readOnly = model.readOnlyText {
                Label(readOnly, systemImage: "archivebox")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary)
            }
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.current {
        case .none:
            ContentUnavailableView {
                Label("Board가 없습니다", systemImage: "square.grid.2x2")
            } description: {
                Text("Board를 만들거나 목록에서 고르세요.")
            } actions: {
                Button("Board 만들기") { model.beginCreate() }
            }
        case .unreadable:
            ContentUnavailableView("현재 구성을 읽지 못했습니다", systemImage: "exclamationmark.triangle")
        case let .loaded(snapshot) where snapshot.nodes.isEmpty:
            ContentUnavailableView("구성이 비어 있습니다", systemImage: "tray")
                .dropDestination(for: URL.self) { urls, _ in
                    accept(urls, on: nil)
                }
        case .loaded:
            let selectedNode = model.selectedNodeID
            List(selection: Binding(get: { selectedNode }, set: { model.selectedNodeID = $0 })) {
                OutlineGroup(model.tree, children: \.children) { item in
                    NodeRow(model: model, node: item.node)
                        .dropDestination(for: URL.self) { urls, _ in
                            accept(urls, on: item.node.id)
                        }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                accept(urls, on: nil)
            }
        }
    }
}

private extension ConfigurationTreeView {
    /// 드롭은 받을 수 있는 곳에서만 받아들이고, 연결은 비동기로 진행한다.
    func accept(_ urls: [URL], on nodeID: UUID?) -> Bool {
        guard model.canAcceptDrop(on: nodeID), !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return false }
        Task { await model.drop(urls, on: nodeID) }
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
            }
        } icon: {
            Image(systemName: icon)
        }
        .tag(node.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: node))
        .accessibilityIdentifier("node-row-\(node.displayName)")
        .accessibilityAddTraits(model.selectedNodeID == node.id ? .isSelected : [])
    }

    private var icon: String {
        switch node.kind {
        case .group: "folder"
        case .file: "doc"
        case .folder: "folder.badge.gearshape"
        case .webLink: "link"
        }
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

private struct NodeInspectorView: View {
    let model: BoardBrowserModel

    var body: some View {
        if let inspection = model.inspector {
            Form {
                LabeledContent("표시 이름", value: inspection.displayName)
                LabeledContent("종류", value: inspection.kind)
                if let target = inspection.target {
                    LabeledContent("대상", value: target)
                }
                if model.canReplaceSelectedTarget {
                    Button("연결 대상 변경") { Task { await model.beginReplaceTarget() } }
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
        case .addGroup: String(localized: "그룹 추가")
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
