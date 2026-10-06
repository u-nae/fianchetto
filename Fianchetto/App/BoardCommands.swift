import SwiftUI

/// 메뉴 막대의 Board·항목 명령. 지금 실행할 수 없는 명령은 꺼서 흐리게 보인다(AUDIT-1).
/// 예외: Board 만들기(⌘N)는 늘 켜 둔다. 앱 시작 시점(저장소를 여는 중)에 꺼짐으로 굳으면 메뉴를 열기 전까지 ⌘N이 동작하지 않았다(W07).
/// 저장소를 열 수 없거나 여는 중이면 모델이 만들기를 시작하지 않는다. 선택 변화에 따른 꺼짐은 메뉴를 열지 않아도 단축키에 바로 반영된다
/// (NativeCommandUITests가 ⌘⌫로 확인한다).
struct BoardCommands: Commands {
    let model: BoardBrowserModel?

    private func isEnabled(_ capability: KeyPath<BoardBrowserModel, Bool>) -> Bool {
        model?[keyPath: capability] ?? false
    }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("이름 변경…") { model?.beginRenameNode() }
                .disabled(!isEnabled(\.canRenameSelectedNode))
            Button("URL 변경…") { model?.beginChangeURL() }
                .disabled(!isEnabled(\.canChangeURLOfSelected))
            Divider()
            Button("위로 이동") { Task { await model?.moveSelectedUp() } }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!isEnabled(\.canMoveSelectedUp))
            Button("아래로 이동") { Task { await model?.moveSelectedDown() } }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!isEnabled(\.canMoveSelectedDown))
            Button("이동…") { model?.beginMove() }
                .disabled(!isEnabled(\.canMoveSelected))
            // Bishop 용도 아이콘(W29, DESIGN 18.4).
            Menu("아이콘") {
                PurposeMenuItems(current: model?.selectedPurpose, text: { model?.purposeText($0) ?? "" }) { purpose in
                    Task { await model?.setPurposeOfSelected(purpose) }
                }
            }
            .disabled(!isEnabled(\.canSetPurposeOfSelected))
            Divider()
            Button("제거…") { model?.beginRemove() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!isEnabled(\.canRemoveSelected))
        }
        // 보기 메뉴: 보기 방식·탐색, 사이드바·인스펙터 접기, 이력·비교 순서. 시스템 사이드바 그룹(.sidebar)은 비워 두고 앞뒤에 붙인다.
        CommandGroup(before: .sidebar) {
            // 구성 보기 방식과 아이콘 보기 탐색(W28, DESIGN 17장). Finder와 같은 단축키다.
            Button("아이콘으로 보기") { model?.showIcons() }
                .keyboardShortcut("1")
                .disabled(!isEnabled(\.canChangeViewMode))
            Button("목록으로 보기") { model?.showList() }
                .keyboardShortcut("2")
                .disabled(!isEnabled(\.canChangeViewMode))
            Divider()
            Button("들어가기") { Task { await model?.enterSelected() } }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(!isEnabled(\.canEnterSelected))
            Button("상위 Wing으로") { model?.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(!isEnabled(\.canGoUp))
            Button("뒤로") { model?.goBack() }
                .keyboardShortcut("[")
                .disabled(!isEnabled(\.canGoBack))
            Divider()
        }
        CommandGroup(after: .sidebar) {
            // 시스템 '사이드바 가리기/보기'(SidebarCommands)와 같은 이름·단축키. 시스템 항목은 상태와 관계없이 제목이 '사이드바 보기'로
            // 고정되어(macOS 26 확인) 모델 상태로 제목을 정한다. 툴바 버튼·이력 탭과 같은 표시 값을 바꾼다(0032).
            // .sidebar 그룹을 replacing으로 바꾸면 그 앞에 붙인 그룹(보기 방식·탐색)이 메뉴에서 사라지므로 이 그룹 맨 앞에 둔다.
            Button(model?.isSidebarVisible == false ? "사이드바 보기" : "사이드바 가리기") { model?.toggleSidebar() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(!isEnabled(\.canToggleSidebar))
            Button(model?.isInspectorPresented == false ? "인스펙터 보기" : "인스펙터 가리기") { model?.toggleInspector() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(model == nil)
            // 이력 탭(W17, DESIGN.md 16.1). Safari의 방문 기록과 같은 키다.
            Button("이력 보기") { Task { await model?.toggleHistory() } }
                .keyboardShortcut("y")
                .disabled(!isEnabled(\.canShowHistory))
            // 과거 구성에서 현재 구성으로(W18, DESIGN.md 16.4).
            Button("현재 구성으로 돌아가기") { Task { await model?.returnToCurrent() } }
                .disabled(!isEnabled(\.canReturnToCurrent))
            // 구성 비교(W19, 0027). 이력 행의 '이 기록과 비교'는 오른쪽 클릭 지름길이라 여기에 두지 않는다.
            Button("현재와 비교") { Task { await model?.compareWithCurrent() } }
                .disabled(!isEnabled(\.canCompareWithCurrent))
            Button("비교 닫기") { model?.closeComparison() }
                .disabled(!isEnabled(\.canCloseComparison))
        }
        // 첫 버전에는 도움말 문서가 없으므로, 눌러도 "도움말을 사용할 수 없음"만 뜨는 기본 항목을 뺀다(메뉴 검색은 시스템이 유지한다).
        CommandGroup(replacing: .help) {}
        CommandGroup(replacing: .newItem) {
            Button("Board 만들기…") { model?.beginCreate() }
                .keyboardShortcut("n")
            Button("Bishop 추가…") { Task { await model?.addBishops() } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!isEnabled(\.canAddToBoard))
            Button("연결 대상 변경…") { Task { await model?.beginReplaceTarget() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!isEnabled(\.canReplaceSelectedTarget))
            Button("Wing 추가…") { model?.beginAddGroup() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!isEnabled(\.canAddToBoard))
            Button("웹 링크 추가…") { model?.beginAddWebLink() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!isEnabled(\.canAddToBoard))
            Divider()
            Button("열기") { Task { await model?.openSelected() } }
                .keyboardShortcut("o")
                .disabled(!isEnabled(\.canOpenSelected))
            Button("Finder에서 보기") { Task { await model?.revealSelected() } }
                .keyboardShortcut("r")
                .disabled(!isEnabled(\.canRevealSelected))
            Button("다시 선택…") { Task { await model?.reselectSelectedTarget() } }
                .disabled(!isEnabled(\.canReselectSelected))
            Button("상태 새로고침") { Task { await model?.refreshStatuses() } }
                .disabled(!isEnabled(\.canRefreshStatuses))
            Divider()
            Button("Board 이름 변경…") { model?.beginRename() }
                .disabled(!isEnabled(\.canRenameSelectedBoard))
            Button("Board 보관") { Task { await model?.archiveSelected() } }
                .disabled(!isEnabled(\.canArchiveSelected))
            Button("보관 해제") { Task { await model?.unarchiveSelected() } }
                .disabled(!isEnabled(\.canUnarchiveSelected))
        }
    }
}
