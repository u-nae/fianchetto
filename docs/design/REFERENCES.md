# 디자인 레퍼런스

> 디자인 세션이 관리하는 참고 앱 목록이다. 무엇을 가져오고 무엇을 가져오지 않을지를 작업 항목(W)과 연결해 둔다.
> 규칙은 `docs/DESIGN.md`가 정한다. 이 문서는 판단 근거이고, 여기 적힌 것만으로 화면을 바꾸지 않는다.
> 작성: 2026-10-02. 앱 화면의 세부 묘사 일부는 공개 자료와 리뷰를 바탕으로 했으며 직접 사용해 확인하지 않았다(아래 표의 '확인').

## 1. 목적이 가까운 앱

| 앱 | 겹치는 점 | 가져올 것 | 가져오지 않을 것 | 확인 |
|---|---|---|---|---|
| Hookmark | 파일·폴더·웹·메일을 서로 연결하고 로컬에만 저장한다. 연구·문서 작업자 사용자층 | 연결 대상이 사라지거나 바뀔 때의 안내, "원본은 그대로 두고 연결만 한다"는 신뢰 문구 | 패널 중심 유틸리티 UI(Fianchetto는 창 앱) | 미확인 |
| Workspaces 2 | 프로젝트마다 파일·폴더·앱·웹을 모아 한 번에 연다. Board와 개념이 거의 같다 | 항목 종류 구분, 열기 동작의 비중 | 런처 성격(Fianchetto의 중심은 이력과 체크포인트) | 미확인 |
| Eagle | 로컬 자료를 보드 단위로 정리한다 | 미리보기 중심 정리 경험 | 비네이티브의 무거운 화면. 반면교사 | 미확인 |

## 2. 앞으로 만들 화면의 레퍼런스

| 앱 | 대상 작업 | 가져올 것 | 가져오지 않을 것 |
|---|---|---|---|
| Fork(Git 클라이언트) | W16 차이, W17 이력 | 목록 → 바뀐 항목 → 차이의 3단 구조, 검색으로 바로 이동, 항목별 이력 | 브랜치 그래프 같은 Git 전용 개념 |
| Kaleidoscope | W16 차이 표시 | 나란히 비교, 덜 중요한 차이 숨기기, 메타데이터 패널 | 추가·삭제를 빨강·초록 색만으로 구분하는 관례(기호와 문구를 함께 쓴다) |
| Time Machine, 문서 버전 브라우저(Apple) | W18 과거 구성 | "과거를 보는 중"을 화면 전체 맥락으로 드러내기, 읽기 전용과 "지금으로 돌아가기" | 공간 연출 효과 |
| Mela | W22 체크포인트 작성 | 지금 단계에 필요 없는 정보를 흐리게 처리해 집중을 돕는 방식 | 요리 모드 같은 전용 화면 연출 |

## 3. 분위기·완성도 레퍼런스

- Things 3: 넓은 여백, 절제된 색, 오래 다듬은 세부. macOS 26에 맞춘 사이드바 유리 효과와 모서리 정리. "정보 영역은 조용하게"(DESIGN.md 1장)의 기준.
- Bear 2: 일관된 모서리 반경 체계와 빠른 Liquid Glass 적용. 자체 서체는 가져오지 않는다(외부 서체 없음, 0016).
- Mimestream, NetNewsWire, Panic의 Nova·Transmit: 시스템 컨트롤과 관례를 충실히 따르면서 OS 기능과 맞물리는 "Mac다운 Mac 앱" 계열. 메뉴·키보드·창 동작의 기준.

## 4. 네이티브 macOS 점검 범위

새 기능이 아니라 이미 있는 기능의 완성도를 본다. 점검 결과는 `docs/design/AUDIT-<날짜>.md`에 남긴다.

1. 메뉴·키보드: 명령의 메뉴 위치와 단축키 체계, 쓸 수 없는 항목의 꺼짐, 포커스 링, 화살표·Return·Delete·Space 같은 목록 키
2. 선택·드래그 피드백: 오른쪽 클릭 메뉴의 내용, 끌고 있는 항목과 놓을 위치 표시
3. 창 동작: 창 크기·위치·열 너비 복원, 전체 화면, 창 개수
4. 시스템 설정 존중: 강조 색 "다중 색상", 사이드바 아이콘 크기, 대비 증가, 투명도 줄이기, 동작 줄이기, 다크 모드
5. Liquid Glass: macOS 26 이상은 시스템 재질을 그대로 받고, macOS 15에서도 깨지지 않는다. `.icon` 다크·틴트 변형
6. VoiceOver: 트리 읽기 순서, 상태 문구, 장식 숨김
7. 문구: 오류 문구의 구조(무엇이 일어났는지, 원인, 할 수 있는 일)

Quick Look(스페이스 키 미리보기), 공유 메뉴, Spotlight 연동은 기능 범위와 맞닿아 있으므로 디자인 세션은 제안만 하고, 도입은 사용자가 정한다.

## 출처

- Apple Design Awards 2025: https://developer.apple.com/design/awards/2025/
- Apple Design Awards 2026: https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/
- Hookmark: https://hookproductivity.com/benefits/transcend-finder-folders-spotlight-and-tags
- Workspaces: https://apptorium.com/workspaces
- Fork: https://fork.dev/releasenotes
- Kaleidoscope 4: https://9to5mac.com/2023/05/25/kaleidoscope-4-file-comparison/
- Things 3: https://thesweetsetup.com/cultured-code-releases-things-3/
- Bear(macOS Tahoe): https://alternativeto.net/news/2025/9/bear-unveils-redesigned-ui-and-icons-for-macos-tahoe-and-ios-26
- SwiftUI로 Mac다운 앱 만들기의 한계: https://pfandrade.me/blog/mac-assed-swiftui-app/
