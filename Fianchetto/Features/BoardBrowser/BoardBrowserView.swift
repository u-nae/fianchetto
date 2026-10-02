import SwiftUI

/// 기본 창: 저장소 상태에 따라 복구 화면, 목록 오류, 또는 Board 목록·현재 구성·상세 영역을 보여 준다.
struct BoardBrowserView: View {
    @Bindable var model: BoardBrowserModel

    var body: some View {
        // Observation은 body에서 읽은 값만 추적하므로 Binding 클로저 밖에서 먼저 읽는다.
        let isCreating = model.creation != nil
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
        case .loaded:
            let selectedNode = model.selectedNodeID
            List(selection: Binding(get: { selectedNode }, set: { model.selectedNodeID = $0 })) {
                OutlineGroup(model.tree, children: \.children) { item in
                    NodeRow(model: model, node: item.node)
                }
            }
        }
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
            }
            .padding()
        } else {
            ContentUnavailableView("항목을 고르세요", systemImage: "sidebar.right")
        }
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
