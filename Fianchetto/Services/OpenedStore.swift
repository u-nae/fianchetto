import Foundation

/// 열린 저장소와 그 위의 서비스. 화면 상태 모델이 App 조립에서 받는다.
struct OpenedStore: Sendable {
    let store: ProjectStore
    let service: ConfigurationService
    let linking: LinkingService
    let replacement: TargetReplacementService
    let lifecycle: ProjectLifecycleService
    let opening: TargetOpeningService
    let links: LinkStatusService
}
