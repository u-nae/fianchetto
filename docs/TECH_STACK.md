# Fianchetto 기술스택 결정서

작성일: 2026-09-30 (Asia/Seoul)
상태: 첫 구현의 기준. 구현·성능 검증은 아직 수행하지 않음.

## 제품 범위

로컬 파일을 이동하지 않고 프로젝트별로 연결하고, 논리적인 구성의 변화와 작업 맥락을 기록하는 macOS 앱.

- 프로젝트와 중첩 가상 그룹 생성
- 표시 이름을 가진 파일·폴더·웹 링크 연결 항목 생성 및 연결 대상 교체
- 추가·제거·이름 변경·그룹 이동·순서 변경·대상 교체·URL 변경 자동 기록
- 날짜별 구성 조회, 두 구성의 차이 비교, 과거 구성 복원 또는 새 프로젝트로 복제
- 이름 있는 체크포인트, 진행 메모, 다음 할 일 (웹 링크는 체크포인트가 가리키는 구성의 Node로 참조)
- 선택적인 이미지 첨부: 사용자가 이미 찍은 스크린샷을 파일 선택으로 추가

복원은 앱의 연결 구성에만 적용한다. 실제 파일 내용, Git 브랜치, 외부 앱 상태는 변경하지 않는다. 과거 디렉토리 내부의 파일 목록 역시 보존하지 않는다. 연결 대상의 과거 경로는 기록하되, 열 때는 현재 접근 가능한 실제 대상을 연다.

## 확정 기술스택

| 영역 | 선택 | 역할과 이유 |
| --- | --- | --- |
| 플랫폼 | 네이티브 macOS App, 최소 macOS 15.0 | 개인 사용을 우선하고 오래된 OS 대응 범위를 줄인다. 웹 런타임이 필요 없다. |
| CPU | 초기 Apple Silicon(arm64), 공개 배포 시 Intel 포함 여부 재검토 | 현재 개발·사용 기기에서 우선 검증한다. |
| IDE·빌드 | Xcode, 표준 `.xcodeproj`, `xcodebuild` | macOS App 템플릿과 Apple 기본 빌드 도구 사용 |
| 언어 | Swift, Swift 6 language mode | 네이티브 API와 동시성 사용. 컴파일러 버전과 language mode는 구분한다. |
| UI | SwiftUI | 앱 창, 프로젝트 탐색, 구성 이력, 편집 화면 |
| macOS 연동 | AppKit | NSOpenPanel, NSWorkspace, NSImage 등 데스크탑 기능 |
| 화면 상태 | Observation의 `@Observable`, SwiftUI의 `@State`·`@Bindable` | 선택·편집 상태와 화면 갱신. 영구 저장과 구분한다. |
| 영구 저장 | SwiftData의 `@Model`, ModelContainer, ModelContext | 프로젝트·구성 이력·체크포인트·북마크 데이터를 로컬 저장 |
| DB 스키마 변경 | VersionedSchema + SchemaMigrationPlan | 앱 업데이트 후 기존 데이터 유지. 프로젝트 구성 이력과 별도 개념이다. |
| 구조 직렬화 | Foundation의 Codable, JSONEncoder, JSONDecoder | 불변 구성 스냅샷과 버전이 있는 내보내기 형식 |
| 파일 접근 | App Sandbox + app-scoped Security-Scoped Bookmarks | 사용자가 선택한 파일·폴더의 접근 정보를 재실행 후에도 사용 |
| 비동기 작업 | Swift Concurrency: async/await, Task, actor, MainActor | UI 상태는 MainActor, 파일 처리·이미지 처리는 UI를 막지 않도록 분리 |
| 설정 | UserDefaults / `@AppStorage` | 마지막 선택 프로젝트, 표시 옵션 등 소규모 환경 설정 |
| 이미지 | AppKit의 NSImage, ImageIO | 첨부 이미지와 필요 시 크기를 제한한 썸네일 |
| 아이콘 | SF Symbols + 별도 비숍 앱 아이콘 | 시스템 UI 아이콘과 제품 아이콘 |
| 로그·성능 | OSLog의 Logger, Xcode Instruments | 저장 실패·파일 접근 실패 진단, CPU·메모리·UI 반응 측정 |
| 도메인 테스트 | Swift Testing | 구성 비교·복원·직렬화·저장 불변식 검증 |
| UI 테스트 | XCTest / XCUITest | 필요한 핵심 흐름만 검증 |
| 코드 관리 | Git | 앱 소스 관리. 사용자 구성 이력은 앱 자체가 저장한다. |
| 의존성 관리 | Swift Package Manager | 외부 의존성이 필요해질 때 사용. 앱 target의 외부 패키지는 0개다. 테스트 target에만 화면 스냅샷 도구 swift-snapshot-testing을 둔다(0028). |

## 현재 로컬 도구 기준

2026-09-30에 직접 확인한 값:

- Xcode 26.3, build 17C529
- Apple Swift compiler 6.2.4
- 호스트 macOS 27.0, build 26A428
- 호스트 아키텍처 arm64

위 값은 현재 환경 기록이며 최신 버전이라는 의미는 아니다. 첫 프로젝트를 생성할 때 이 도구로 빌드 기준을 고정하고, deployment target은 macOS 15.0으로 설정한다. macOS 15에서의 실제 실행 호환성은 별도로 검증해야 한다.

## UI 구성

기본 UI는 자유로운 캔버스 대신 계층형 목록으로 시작한다. 여기서 '배치'는 부모 그룹과 형제 항목 순서를 의미한다. 구성 영역은 계층형 목록과, Wing 한 단계씩 보는 아이콘 보기 중에서 고를 수 있다([0020](decisions/0020-icon-view.md)). 두 보기 모두 같은 배치(부모·형제 순서)를 보여 줄 뿐이며 자유 배치 캔버스가 아니다.

- `WindowGroup`: 기본 앱 창
- `NavigationSplitView`: 프로젝트 목록과 프로젝트 상세 화면
- `List` + `OutlineGroup` 또는 `DisclosureGroup`: 가상 그룹·연결 항목 트리
- `LazyVGrid` 등 격자: 아이콘 보기(현재 Wing 한 단계)
- `Inspector` 또는 상세 패널: 연결 경로·메모·대상 상태
- `Settings`: 환경 설정
- `Commands`: 메뉴와 키보드 단축키
- SwiftUI drag/drop API: 앱 내부 항목 이동과 외부 파일 연결 추가
- `NSOpenPanel`: 파일·폴더 선택
- `NSWorkspace.open`: 기본 앱으로 연결 대상·웹 링크 열기
- `NSWorkspace.activateFileViewerSelecting`: Finder에서 대상 표시

SwiftUI를 기본으로 사용한다. 계층형 목록의 드래그·선택 동작이 요구에 맞지 않을 때만 `NSOutlineView`를 `NSViewRepresentable`로 감싼다. 첫 구현부터 전체 UI를 AppKit으로 작성하지 않는다.

## 데이터와 구성 이력

SwiftData가 프로젝트 구성 이력을 자동으로 만들어 주는 것은 아니다. 이력은 앱의 저장 규칙으로 구현한다.

### 주요 개념

- `Project`: 안정적인 UUID, 생성일, 현재 revision ID, 보관 시각(선택), 출처(선택: 복제/가져오기의 원본 프로젝트·revision ID) — [0005](decisions/0005-provenance-and-archive-fields.md). 이름은 현재 revision이 가진다 — [0007](decisions/0007-current-configuration-is-revision-pointer.md)
- `Node`: 안정적인 UUID, 종류(group/file/folder/webLink), 표시 이름, 부모 ID, 정렬 순서, 연결 참조 ID(file/folder), URL(webLink) — [0002](decisions/0002-web-links-are-nodes.md). 별도 레코드가 아니라 revision 스냅샷 안의 값이다 — [0007](decisions/0007-current-configuration-is-revision-pointer.md)
- `ResourceReference`: 특정 연결 대상을 가리키는 UUID, 최초 경로, 파일·폴더 종류, 북마크 데이터, 마지막 해석 경로
- `Revision`: 프로젝트 ID, 증가하는 순번, 기록 시간, 원인, 복원 출처 revision ID(선택), 그 시점의 프로젝트 이름, 구성 JSON, JSON schema version
- `Checkpoint`: 특정 revision ID, 제목, 진행 메모, 다음 할 일, 이미지 첨부 참조

Node는 독립적인 논리 항목이다. 이름 변경이나 대상 교체 후에도 UUID를 유지한다. ResourceReference는 대상 교체 시 새로 생성하고, 이전 reference는 과거 revision에서 참조하는 동안 보존한다.

Revision의 Node 목록은 Codable 값 타입을 복사한 불변 JSON으로 저장한다. 현재 구성은 현재 revision의 스냅샷이며 수정 가능한 Node 레코드를 따로 두지 않으므로, 과거 revision이 현재 구성과 객체를 공유하지 않는다 — [0007](decisions/0007-current-configuration-is-revision-pointer.md). 과거 표시 이름·배치·참조 ID·당시 경로(`recordedPath`)·URL을 보존한다 — [0003](decisions/0003-snapshot-records-paths.md).

북마크 데이터 갱신은 운영상 접근 정보 갱신이다. 과거 revision에 기록된 경로나 표시 정보를 덮어쓰지 않는다.

### 저장 방식

첫 버전에서는 변경 이벤트를 재생해서 과거를 만드는 방식 대신, 의미 있는 변경마다 전체 구성 메타데이터 스냅샷을 저장한다.

- 추가·제거·대상 교체·드롭 완료·이름 편집 확정 등 논리적인 작업 단위로 revision 생성
- 드래그 중간 좌표나 키 입력마다 revision을 만들지 않음
- 메모 입력은 묶어서 저장하고, 명명된 체크포인트는 명시적으로 확정
- 현재 구성 변경과 revision 추가는 단일 저장 단위로 처리
- 구성 변경 서비스에서 명시적으로 저장하고, 실패 시 현재 구성을 되돌림
- 성공하기 전에는 사용자에게 저장 완료로 표시하지 않음
- 순서 판정은 시간만이 아니라 프로젝트별 revision 순번을 사용
- 복원은 과거 revision을 수정하지 않고 새 revision을 생성
- Undo가 필요할 때도 이전 기록 삭제 대신 역변경을 새 revision으로 기록
- 날짜 조회는 해당 시점 이전의 마지막 revision을 선택하고 실제 기록 시각을 표시
- 변경 전 첫 구성도 기록

전체 스냅샷은 최초 구현을 단순하게 하고 과거 구성을 바로 조회하기 쉽다. 저장하는 것은 경로·이름·그룹·순서 등 메타데이터이므로 파일 원본 복제보다 작다. 실제 크기·저장 지연은 revision 수를 늘려 측정한다. 델타 저장이나 압축은 측정 결과가 필요성을 보여 줄 때 도입한다.

### 차이 비교

Node UUID를 기준으로 두 스냅샷을 비교하는 순수 Swift 함수를 작성한다. 추가·제거·이름 변경·부모 변경·순서 변경·연결 대상 교체를 각각 분류한다. 비교 자체에는 디스크 접근이나 Git 실행이 필요하지 않다.

## 파일 접근과 권한

첫 버전은 연결 대상 원본을 편집하지 않는다. entitlement는 내보내기 위치 쓰기를 위해 user-selected read-write와 app-scoped bookmarks를 쓰고, 연결 대상 북마크는 `securityScopeAllowOnlyReadAccess` 로 만들어 읽기 전용으로 제한한다 — [0001](decisions/0001-sandbox-file-access.md). 앱 자신의 데이터 저장은 샌드박스 내부에서 처리한다.

경로 문자열만 저장하지 않는다. 선택 시 북마크 데이터를 생성하고, 재실행 후 북마크를 해석해 접근한다. 접근하는 동안 `startAccessingSecurityScopedResource()`와 `stopAccessingSecurityScopedResource()`를 대응시킨다.

- 북마크가 stale이면 접근 가능한 URL로 북마크를 갱신
- 이동·이름 변경을 항상 추적할 수 있다고 약속하지 않음
- 접근 실패 시 '권한 필요', '대상 없음', '볼륨 연결 필요' 등의 상태를 구분
- 접근 실패로 과거 연결 기록을 자동 삭제하지 않음
- 사용자가 재선택한 대상이 새로운 파일·폴더라면 명시적인 연결 교체로 기록. 같은 대상인지는 파일 시스템 식별자로 판정한다 — [0004](decisions/0004-same-target-identity.md)
- 앱 내부 드래그는 북마크 배치만 변경하며 실제 파일을 이동하지 않음

Security-Scoped Bookmark는 파일 백업도, 다른 Mac에서 사용할 수 있는 영구적인 권한 토큰도 아니다. 내보낸 구성은 다른 환경에서 대상 재연결을 요구할 수 있다.

## 저장 위치와 내보내기

- SwiftData store와 이미지는 샌드박스 내부 Application Support 아래 저장
- 설정만 UserDefaults에 저장하고, 구성 이력은 넣지 않음
- 이미지는 JSON에 base64로 넣지 않고 별도 파일로 저장
- 내보내기는 schema version이 있는 JSON과 선택적인 첨부 이미지 묶음
- 내보내기에는 경로 정보가 포함될 수 있음을 사용자에게 설명
- import는 경로를 복구하고 필요한 대상 접근은 사용자에게 다시 요청
- 실행 중 DB 파일 복사 대신 앱 데이터 모델 기반 export를 기본 백업 경로로 사용
- 이미지 첨부와 DB 저장 실패 사이에 고아 파일이 남지 않도록 정리 규칙 마련

## 구조와 경량화 원칙

한 앱 target에서 기능별 폴더로 구성한다. UI → 기능별 상태 모델 → 구성/북마크 서비스 → 저장소 어댑터 순서로 의존한다. 작은 순수 Swift 도메인 타입과 함수를 먼저 분리하고, 별도 패키지·복잡한 DI 프레임워크는 필요해질 때 도입한다.

- 전체 디스크 인덱싱·폴더 하위 내용의 상시 스캔을 하지 않음
- 선택·열기·명시적 새로고침 시 대상 상태를 확인
- 앱 자체에서 일어난 구성 변경만 자동 기록
- 과거 revision은 목록에서 필요한 만큼 조회하고 선택한 구성만 디코딩
- 파일 시스템 I/O는 MainActor를 막지 않도록 분리
- SwiftData 모델을 임의의 Task 사이에 공유하지 않고 actor/context 경계를 지킴
- 디버그 빌드가 아닌 Release 빌드로 유휴 CPU·메모리·큰 구성의 반응 측정
- 성능 목표 수치는 최초 프로토타입 측정 후 확정

SwiftData를 선택한 이유는 Apple 기본 도구만으로 작은 로컬 앱을 시작하기 쉽기 때문이다. DB 크기나 조회 비용이 실제 병목이면 SQLite 직접 사용 또는 GRDB를 별도 결정서로 재평가한다. SwiftData store의 내부 형식을 외부 데이터 계약으로 사용하지 않는다.

## 첫 버전에서 제외하는 기술

Electron/Tauri/웹 UI, 서버/API, CloudKit/iCloud 동기화, 앱 내부 Git 실행, 전체 파일 내용 버전 관리, 실시간 Git 상태 조회, 전체 화면 상시 기록, 다른 앱의 열린 문서·탭·창 배치 자동 복원, Accessibility 권한, ScreenCaptureKit 기반 자동 캡처, 자동 업데이트 프레임워크는 초기 의존성에 포함하지 않는다.

스크린샷 첨부는 사용자가 기존 이미지를 선택하는 방식으로 제공한다. 앱에서 직접 촬영하는 기능과 외부 앱 상태 복원은 별도 후속 결정이다.

## 검증과 배포

의미 있는 단위 테스트: 대상 교체 후 이전 revision 유지, Node 이름 변경 후 동일성 유지, 구성 비교, 복원 후 새 revision 생성, 저장 실패 시 부분 변경 방지, JSON 왕복, DB 스키마 이전.

실제 macOS 검증: 앱 재실행 후 파일 접근, 파일 이동·삭제, 외장 볼륨 분리, 권한 재요청, Finder 열기, 대규모 구성에서 UI 응답. 개발 기기의 최신 OS에서 통과했다고 최소 지원 OS에서 통과한 것으로 간주하지 않는다.

개인 사용은 Xcode에서 로컬 실행하고 Release 앱을 수동으로 사용한다. Debug와 Release는 번들 ID와 저장소가 다르고, 개인 Apple Development 서명은 git에 넣지 않는 `Config/Local.xcconfig`로 한다(0033). 외부 배포가 필요해질 때 Developer ID 서명·notarization·배포 형식·업데이트 경로를 결정한다. App Sandbox는 첫 버전부터 적용한다.

## 공식 참고 자료

- [Swift 6 language mode와 동시성](https://www.swift.org/blog/announcing-swift-6/)
- [SwiftUI Navigation](https://developer.apple.com/documentation/swiftui/navigation)
- [OutlineGroup](https://developer.apple.com/documentation/swiftui/outlinegroup)
- [Observation](https://developer.apple.com/documentation/observation)
- [SwiftData 영구 저장](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches)
- [SwiftData SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [App Sandbox 파일 접근](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)
- [Security-Scoped Bookmark 설정](https://developer.apple.com/documentation/professional-video-applications/enabling-security-scoped-bookmark-and-url-access)
- [NSWorkspace에서 Finder 표시](https://developer.apple.com/documentation/appkit/nsworkspace/activatefileviewerselecting(_:))
- [Swift Testing](https://developer.apple.com/xcode/swift-testing)
