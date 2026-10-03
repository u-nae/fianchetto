import SwiftUI

/// 목록 행·아이콘 타일의 기호 그리기. 파일 종류 아이콘에는 Bishop 배지를 붙인다(DESIGN 17.3·18.5).
struct TileIconView: View {
    let icon: TileIcon
    var size: CGFloat = 16

    var body: some View {
        switch icon {
        case let .systemSymbol(name):
            Image(systemName: name).resizable().scaledToFit().fontWeight(.light).frame(width: size, height: size)
        case .wing:
            Image(.fianchettoWing).resizable().scaledToFit().frame(width: size, height: size)
        case let .bishop(purpose):
            if let purpose {
                PurposeBadgedBishop(purpose: purpose, size: size)
            } else {
                Image(.fianchettoBishop).resizable().scaledToFit().frame(width: size, height: size)
            }
        case .bishopFolder:
            Image(.fianchettoBishopFolder).resizable().scaledToFit().frame(width: size, height: size)
        case let .fileType(identifier):
            badged(Image(nsImage: FileTypeIcons.image(forTypeIdentifier: identifier)))
        case .genericFolder:
            badged(Image(nsImage: FileTypeIcons.folder))
        }
    }

    /// 파일 종류 아이콘의 Bishop 배지(DESIGN 18.5): 반전 단색. 원은 글자 색, 미트라는 바탕 색이라 강조 색 설정과 상관없이 대비가 높다.
    private func badged(_ image: Image) -> some View {
        let diameter = size * 0.42
        return image.resizable().scaledToFit().frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                Image(.fianchettoBishop)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color(nsColor: .textBackgroundColor))
                    .padding(diameter * 0.18)
                    .frame(width: diameter, height: diameter)
                    .background(Circle().fill(Color.primary))
                    .overlay(Circle().strokeBorder(Color(nsColor: .textBackgroundColor), lineWidth: max(0.5, size / 40)))
            }
    }
}

/// Bishop 심볼 + 용도 배지(DESIGN 18.3). 배지 둘레(0.62배) 원만큼 심볼을 오려 내고 배지(0.38배, .semibold)를 겹친다.
/// 오려 내기가 이 그룹 안에서만 적용되도록 세 층을 하나의 compositingGroup으로 묶는다(선택 바탕을 지우지 않는다).
/// 색은 따로 넣지 않고 바깥 foregroundStyle을 따른다.
private struct PurposeBadgedBishop: View {
    let purpose: BishopPurpose
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(.fianchettoBishop).resizable().scaledToFit().frame(width: size, height: size)
            Circle()
                .frame(width: size * 0.62, height: size * 0.62)
                .offset(x: size * 0.12, y: size * 0.12)
                .blendMode(.destinationOut)
            Image(systemName: PurposePresentation.symbol(for: purpose))
                .resizable().scaledToFit()
                .fontWeight(.semibold)
                .frame(width: size * 0.38, height: size * 0.38)
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

/// 용도 배지 기호(DESIGN 18.2). 저장 키는 바뀌지 않고 기호만 이 표에서 바꾼다.
enum PurposePresentation {
    static func symbol(for purpose: BishopPurpose) -> String {
        switch purpose {
        case .document: "doc.text.fill"
        case .data: "tablecells.fill"
        case .image: "photo.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .reference: "book.closed.fill"
        case .presentation: "play.rectangle.fill"
        case .todo: "checklist"
        case .design: "paintbrush.pointed.fill"
        }
    }
}

/// "아이콘" 고르기 메뉴 항목: 기본 + 8종, 지금 값(모르는 키는 기본)에 체크 표시(DESIGN 18.4). 메뉴 막대·오른쪽 클릭이 같이 쓴다.
struct PurposeMenuItems: View {
    let current: BishopPurpose?
    let text: (BishopPurpose?) -> String
    let choose: (BishopPurpose?) -> Void

    static let choices: [BishopPurpose?] = [nil] + BishopPurpose.allCases.map(Optional.some)

    var body: some View {
        ForEach(Self.choices, id: \.self) { purpose in
            Toggle(isOn: Binding(get: { current == purpose }, set: { _ in choose(purpose) })) {
                if let purpose {
                    Label(text(purpose), systemImage: PurposePresentation.symbol(for: purpose))
                } else {
                    Text(text(nil))
                }
            }
        }
    }
}

/// 아이콘 보기: 지금 위치(최상위 또는 Wing) 한 단계를 구성 순서대로 격자로 보인다(DESIGN 17장, W28).
struct IconGridView: View {
    @Bindable var model: BoardBrowserModel
    @State private var backgroundTargeted = false
    @State private var columns = 1

    private static let tileWidth: CGFloat = 104
    private static let columnSpacing: CGFloat = 12
    private static let margin: CGFloat = 16

    var body: some View {
        let items = model.iconItems
        VStack(spacing: 0) {
            Group {
                if items.isEmpty {
                    ContentUnavailableView {
                        Label { Text("Wing이 비어 있습니다") } icon: { ChessboardIllustration() }
                    } description: {
                        Text("Bishop이나 웹 링크를 추가하거나 이곳으로 끌어 놓으세요.")
                    }
                } else {
                    grid(items)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            // 빈 곳 오른쪽 클릭: 지금 위치에 추가한다(Finder의 '새로운 폴더' 관례). 보관된 Board에서는 꺼진다.
            .contextMenu {
                Group {
                    Button("Bishop 추가…") { Task { await model.addBishops() } }
                    Button("Wing 추가…") { model.beginAddGroup() }
                    Button("웹 링크 추가…") { model.beginAddWebLink() }
                }
                .disabled(!model.canAddToBoard)
            }
            .dropDestination(for: TreeDropItem.self) { dropped, _ in
                acceptBackground(dropped)
            } isTargeted: { backgroundTargeted = $0 }
            .overlay { DropHighlight(isActive: backgroundTargeted && model.canAcceptIconFileDrop(onTile: nil)) }
            PathBar(model: model)
        }
        .navigationTitle(model.iconTitle)
        .navigationSubtitle(model.iconSubtitle ?? "")
    }

    private func grid(_ items: [ConfigurationNode]) -> some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: Self.columnSpacing)],
                    spacing: 18
                ) {
                    ForEach(items, id: \.id) { node in
                        IconTile(model: model, node: node)
                    }
                }
                .padding(Self.margin)
            }
            .onAppear { columns = Self.columnCount(width: geometry.size.width) }
            .onChange(of: geometry.size.width) { _, width in columns = Self.columnCount(width: width) }
        }
        // 방향키·Delete는 포커스 가능한 격자의 시스템 명령으로 받는다(onKeyPress는 쓰지 않는다, 0018).
        .focusable()
        .onMoveCommand { direction in
            let mapped: BoardBrowserModel.GridDirection? = switch direction {
            case .left: .left
            case .right: .right
            case .up: .up
            case .down: .down
            @unknown default: nil
            }
            if let mapped { Task { await model.selectNeighbor(mapped, columns: columns) } }
        }
        .onDeleteCommand { model.beginRemove() }
    }

    static func columnCount(width: CGFloat) -> Int {
        max(1, Int((width - margin * 2 + columnSpacing) / (tileWidth + columnSpacing)))
    }

    /// 빈 곳: Finder 파일만 지금 위치 끝에 연결한다. 같은 층 타일은 받지 않는다(DESIGN 17.4).
    private func acceptBackground(_ items: [TreeDropItem]) -> Bool {
        let urls = items.compactMap(\.fileURL)
        guard !urls.isEmpty, urls.count == items.count, model.canAcceptIconFileDrop(onTile: nil) else { return false }
        Task { await model.dropFilesInIconView(urls, onTile: nil) }
        return true
    }
}

/// 타일 하나: 기호, 이름 두 줄, 상태가 정상이 아니면 기호 배지와 셋째 줄 문구.
private struct IconTile: View {
    let model: BoardBrowserModel
    let node: ConfigurationNode
    @State private var targeted = false

    var body: some View {
        let selected = model.selectedNodeID == node.id
        let status = model.displayedStatus(of: node.id)
        VStack(spacing: 4) {
            TileIconView(icon: TileIcon.of(node, style: model.bishopIconStyle), size: 40)
                .frame(width: 64, height: 56)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
                .overlay(alignment: .bottomTrailing) {
                    if let status, let presentation = LinkStatusPresentation.of(status) {
                        Image(systemName: presentation.systemImage)
                            .foregroundStyle(presentation.symbolColor)
                            .background(Circle().fill(.background))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(targeted && node.kind == .group ? 1 : 0)
                }
            Text(node.displayName)
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.accentColor : .clear))
                .foregroundStyle(selected ? .white : .primary)
            if let status {
                Text(model.statusText(status)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 104)
        .contentShape(Rectangle())
        .help(node.displayName)
        .onTapGesture(count: 2) { Task { await model.activateTile(node.id) } }
        .onTapGesture { Task { await model.selectNode(node.id) } }
        .contextMenu { NodeContextMenu(model: model, node: node, inIconView: true) }
        .draggable(NodeDragItem(nodeID: node.id))
        .dropDestination(for: TreeDropItem.self) { items, _ in
            accept(items)
        } isTargeted: { targeted = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel(for: node))
        .accessibilityIdentifier("icon-tile-\(node.displayName)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Wing 타일만 받는다: 앱 안 항목은 그 안으로 옮기고, Finder 파일은 그 안에 연결한다.
    private func accept(_ items: [TreeDropItem]) -> Bool {
        let urls = items.compactMap(\.fileURL)
        if !urls.isEmpty, urls.count == items.count {
            guard model.canAcceptIconFileDrop(onTile: node.id) else { return false }
            Task { await model.dropFilesInIconView(urls, onTile: node.id) }
            return true
        }
        guard items.count == 1, let moved = items.first?.nodeID, model.canAcceptIconNodeDrop(moved, onTile: node.id) else { return false }
        Task { await model.dropNodeInIconView(moved, onTile: node.id) }
        return true
    }
}

/// 경로 막대: 'Board › Wing › …' 칸을 누르면 그곳으로 간다. 오른쪽에 항목 수(DESIGN 17.5).
private struct PathBar: View {
    let model: BoardBrowserModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.pathBarEntries.enumerated()), id: \.offset) { index, entry in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button {
                    model.goTo(entry.id)
                } label: {
                    // 최상위는 Board, 그 아래는 Wing 심볼이다(0025).
                    Label { Text(entry.name) } icon: { Image(entry.id == nil ? .fianchettoBoard : .fianchettoWing) }
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(model.iconItemCountText).font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("path-bar")
    }
}
