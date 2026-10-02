import SwiftUI

/// 파일 메뉴의 Board 만들기(⌘N).
/// SwiftUI는 메뉴 항목의 꺼짐 상태를 메뉴를 열 때까지 갱신하지 않아, 앱 시작 시점(저장소를 여는 중)에 꺼짐으로 굳으면
/// ⌘N이 동작하지 않는다. 그래서 항목은 켜 두고, 저장소를 열 수 없거나 여는 중이면 모델이 만들기를 시작하지 않는다.
struct BoardCommands: Commands {
    let model: BoardBrowserModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Board 만들기…") { model?.beginCreate() }
                .keyboardShortcut("n")
            Button("Bishop 추가…") { Task { await model?.addBishops() } }
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Button("연결 대상 변경…") { Task { await model?.beginReplaceTarget() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
