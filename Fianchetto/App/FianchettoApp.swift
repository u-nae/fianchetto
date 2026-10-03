import SwiftUI

@main
struct FianchettoApp: App {
    @State private var model: BoardBrowserModel?

    init() {
        switch AppComposition.launchMode() {
        case .unitTestHost:
            _model = State(initialValue: nil)
        case let .app(storeURL, lastBoard):
            _model = State(initialValue: AppComposition.makeModel(storeURL: storeURL, lastBoard: lastBoard))
        }
    }

    var body: some Scene {
        WindowGroup("Fianchetto") {
            RootView(model: model)
        }
        .commands {
            BoardCommands(model: model)
        }
        Settings {
            AppSettingsView(model: model)
        }
    }
}
