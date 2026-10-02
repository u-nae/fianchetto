# Fianchetto 디자인 규칙 (초안)

> 상태: **초안**. 디자인 작업 세션이 이 문서를 출발점으로 쓰고, 확정한 항목은 `docs/decisions/NNNN-<slug>.md`에
> 기록한 뒤 이 문서를 같은 변경에서 갱신한다. 색 값·아이콘 모양처럼 "후보"로 적힌 것은 디자인 세션이 결정한다.
> 이 문서는 제품 동작(`PRD.md`)·기술 선택(`TECH_STACK.md`)·프로젝트 규칙(`CLAUDE.md`)을 바꾸지 않는다. 충돌하면 그쪽이 우선한다.

## 1. 원칙

1. **시스템 UI 위에 테마를 얹는다.** 목록·사이드바·툴바·시트·버튼·텍스트 필드·메뉴는 SwiftUI 기본 컨트롤을 그대로 쓴다.
   컨트롤을 직접 그리거나 창 테두리·제목 막대를 바꾸지 않는다. 사이드바 반투명, 키보드 포커스 링, 시스템 강조 색 설정,
   다크 모드, 고대비, 투명도 줄이기가 그대로 동작해야 한다.
2. **체스는 시각 톤으로만 쓴다(0006).** 색·질감·아이콘 모티프로 표현하고, 체스 규칙(말의 이동, 체크, 승패 등)을
   기능·문구·인터랙션에 끌어오지 않는다. 화면 용어는 Board·Bishop과 중립 용어만 쓴다.
3. **정보 영역은 조용하게, 정체성은 가장자리에.** 트리·상세 영역처럼 오래 읽는 곳은 시스템 기본에 가깝게 두고,
   테마는 앱 아이콘·강조 색·Bishop 심볼·빈 화면·Board 제목처럼 정해진 곳에 모은다.
4. **색만으로 구분하지 않는다(CLAUDE.md UI·문구).** 상태·과거/현재·오류는 항상 기호(SF Symbol)와 문구를 함께 쓴다.
   체스판의 흑백 대비를 상태 구분 수단으로 쓰지 않는다.
5. **macOS 15에서 동작해야 한다.** deployment target이 macOS 15.0이다. 더 새로운 OS 전용 API·재질(예: Liquid Glass 전용
   modifier)은 `if #available`로 감싸고, macOS 15에서의 모습을 기준으로 설계한다. 개발 기기(macOS 27) 화면만 보고 확정하지 않는다.

## 2. 테마를 표현하는 곳과 하지 않는 곳

| 영역 | 테마 표현 | 규칙 |
|---|---|---|
| 앱 아이콘 | **주 표현** | 비숍 실루엣, 피앙케토(긴 대각선) 모티프, 체스판 격자 등. 6장 참고 |
| 강조 색(AccentColor) | **주 표현** | 선택 표시·기본 버튼·포커스에 쓰인다. 3장 대비 기준을 지킨다 |
| Bishop 항목 심볼 | **주 표현** | 비숍 말 모양 커스텀 SF Symbol. 5장 참고 |
| 빈 화면(ContentUnavailableView) | 보조 | 체스판 패턴·말 실루엣 일러스트 가능. 내용 없는 곳에서만 |
| Board 제목(상세 영역 머리) | 보조 | 세리프(New York) 시험 가능. 4장 참고 |
| 상세 영역 배경 | 약하게 | 아이보리/에보니 계열 면 색을 아주 약하게. 투명도 줄이기·고대비에서 시스템 배경으로 돌아간다 |
| 트리(목록) 행, 사이드바 | 하지 않음 | 시스템 목록 스타일·선택 색 그대로. 행 배경에 체스판 무늬 금지 |
| 메뉴·툴바·시트·알림 | 하지 않음 | 시스템 그대로. 문구만 String Catalog로 관리 |
| 상태 표시(W15) | 하지 않음 | 시스템 의미 색(`.red`, `.orange` 등) + 기호 + 문구. 7장 참고 |

## 3. 색

### 3.1 토큰 이름과 역할

Asset Catalog(`Fianchetto/Assets.xcassets`)의 Color Set으로 정의한다. 코드에 hex·RGB 값을 직접 쓰지 않는다.
빌드 설정 `ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES`가 이미 켜져 있어 `Color(.themeSurface)`처럼
생성된 심볼로 참조한다(문자열 이름 `Color("...")` 금지). 생성 심볼 이름: `.accent`, `.themeAccentText`, `.themeSurface`,
`.themeBoardGreen`, `.themeLine`.

| 토큰 | 역할 | 쓰는 곳 |
|---|---|---|
| `AccentColor` | 앱 강조 색(채움) | 전역 강조. 기본 버튼 채움(흰 글자 위), 선택 표시, 포커스 |
| `ThemeAccentText` | 강조 색의 글자·기호용 변형 | 배경 위에 강조 색으로 쓰는 글자·심볼(링크형 버튼, 강조 기호) |
| `ThemeSurface` | 테마 면 색(라이트=아이보리, 다크=에보니) | 빈 화면·상세 영역 머리의 약한 면. 아이보리·에보니는 이 토큰의 두 값이며 따로 두지 않는다(0011) |
| `ThemeBoardGreen` | 보조 강조(체스판 녹색) | 일러스트·아이콘 보조 색. 글자 색으로 쓰지 않는다 |
| `ThemeLine` | 장식 구분선 | 빈 화면 일러스트·머리 장식. 목록 구분선은 시스템 것을 쓴다 |

글자·기본 배경·구분선·선택 배경은 **시스템 의미 색**을 쓴다: `.primary`, `.secondary`, `Color(nsColor: .windowBackgroundColor)`,
`.separator` 등. 테마 토큰으로 바꾸지 않는다.

### 3.2 팔레트 (0011 확정)

| 토큰 | 라이트 | 다크 | 라이트 고대비 | 다크 고대비 |
|---|---|---|---|---|
| `AccentColor` | `#8A5A2E` 월넛 | `#9D6634` | `#6B4624` | `#A16936` |
| `ThemeAccentText` | `#8A5A2E` | `#D2A06A` | `#6B4624` | `#E6C6A8` |
| `ThemeSurface` | `#F6F1E7` 아이보리 | `#2A2520` 에보니 | `#FFFFFF` | `#1E1E1E` |
| `ThemeBoardGreen` | `#3F6B4A` | `#8DB596` | `#2F5539` | `#B3D4BA` |
| `ThemeLine` | `#D9CDB8` | `#4A4037` | `#8C7A60` | `#9A8A74` |

대비(WCAG 상대 휘도 식, 배경은 개발 기기의 시스템 배경 `#FFFFFF`/`#1E1E1E`):

| 조합 | 라이트 | 다크 | 라이트 고대비 | 다크 고대비 |
|---|---|---|---|---|
| `AccentColor` 위 흰 글자 | 5.86 | 4.79 | 8.31 | 4.58 |
| `AccentColor` 대 배경(UI 요소) | 5.86 | 3.48 | 8.31 | 3.64 |
| `ThemeAccentText` 대 배경 | 5.86 | 7.13 | 8.31 | 10.33 |
| `ThemeAccentText` 대 `ThemeSurface` | 5.21 | 6.49 | — | — |
| `ThemeBoardGreen` 대 배경 | 6.15 | 7.29 | 8.47 | 10.35 |

- 채움용 `AccentColor`와 글자용 `ThemeAccentText`를 나눈다. macOS는 강조 색 채움 위에 흰 글자를 그린다. 다크 모드의 밝은 월넛
  (`#D2A06A`)은 어두운 배경 위 글자로는 좋지만(7.13:1) 흰 글자를 올리면 2.34:1로 부족하기 때문이다.
- `AccentColor` 다크 값은 흰 글자 4.5:1과 `#1E1E1E` 대비 3:1을 함께 만족하는 범위(상대 휘도 0.139–0.183)에서 골랐다.
  `#323232`처럼 더 밝은 배경 위에서는 3:1과 흰 글자 4.5:1을 동시에 만족하는 색이 없다(`#9D6634`는 2.68). 이 경우 흰 글자
  대비를 우선한다.
- 고대비에서 `ThemeSurface`는 시스템 배경 값으로 돌아가고, 나머지는 대비를 높인다.
- 고대비 값과 macOS 15에서의 실제 모습은 실기에서 Accessibility Inspector로 다시 잰다(W27).

### 3.3 대비·변형 기준

- 본문 글자 4.5:1 이상, 큰 글자(제목 18pt 이상 또는 14pt 굵게)와 UI 요소·기호 3:1 이상(WCAG 2.x AA).
- 모든 Color Set은 **Any(라이트)·Dark** 두 값과 **High Contrast** 변형을 둔다(Asset Catalog의 Appearances: Any, Dark +
  High Contrast 체크). 고대비 값은 대비를 더 높이거나 시스템 색에 가깝게 한다.
- 사용자가 시스템 설정에서 강조 색을 바꾸면 그 설정이 우선한다(macOS 기본 동작). 앱 강조 색은 "다중 색상"일 때만 보인다.
  이것을 막지 않는다.

## 4. 글자

- 기본은 시스템 서체(SF Pro)와 SwiftUI 텍스트 스타일(`.body`, `.headline`, `.caption` 등)이다. 크기를 pt로 고정하지 않는다.
- **세리프 시험 범위:** Board 제목(상세 영역 머리), 빈 화면 제목에 한해 `.fontDesign(.serif)`(시스템 세리프 New York)를
  시험할 수 있다. 목록·메뉴·버튼·본문에는 쓰지 않는다. 외부 서체 파일은 넣지 않는다(외부 의존 0개, 라이선스 관리 회피).
- 숫자가 정렬돼야 하는 곳(포함 항목 수, 날짜 목록·이력 W17)은 `.monospacedDigit()`을 쓴다.
- 문구는 모두 String Catalog에 있다. 디자인 작업에서 문구를 바꾸면 `scripts/check-terms.sh` 금지 표현(DB·JSON·bookmark·북마크·
  파일 삭제)과 필수 용어 목록을 지킨다.

## 5. 기호(SF Symbols)

### 5.1 현재 쓰는 기호

| 쓰임 | 현재 기호 | 위치 |
|---|---|---|
| 그룹 | `folder` | 트리 행(`NodeRow`) |
| Bishop(파일) | `fianchetto.bishop`(커스텀, 0012) | 트리 행 |
| Bishop(폴더) | `fianchetto.bishop.folder`(커스텀, 0012) | 트리 행 |
| 웹 링크 | `link` | 트리 행 |
| 최상위(이동 창) | `square.stack` | 이동 창 |
| 보관된 Board 표시 | `archivebox` | 읽기 전용 띠 |
| Board 없음 | `square.grid.2x2` | 빈 화면 |
| 구성 비어 있음 | `tray` | 빈 화면 |
| 항목 선택 안내 | `sidebar.right` | 상세 영역 빈 화면 |
| 저장소 복구 | `externaldrive.badge.exclamationmark` | 복구 화면 |
| 오류 일반 | `exclamationmark.triangle` | 목록 오류·경고 |

### 5.2 Bishop 커스텀 심볼 (0012 확정)

- 모양: 비숍의 머리(미트라)를 크게 그린다. 위에 구슬, 몸통에 대각선 홈(피앙케토의 긴 대각선), 아래에 받침띠가 있다.
  폴더 Bishop은 미트라를 줄이고 오른쪽 아래에 폴더 배지를 붙인다. 파일과 폴더는 색이 아닌 배지 모양으로 구분한다.
- 이름: `fianchetto.bishop`(파일), `fianchetto.bishop.folder`(폴더). 참조는 `Image(.fianchettoBishop)`, `Image(.fianchettoBishopFolder)`
  (생성 심볼). 문자열 이름 금지.
- 자산: `Fianchetto/Assets.xcassets`의 Symbol Image Set. 템플릿은 `scripts/design/generate-bishop-symbols.swift`가 만든다.
  24 격자의 선 디자인(선 굵기 1.6)을 채운 윤곽선으로 바꿔 넣는다. 모양을 고칠 때는 SVG를 직접 고치지 않고 스크립트를 고쳐 다시 만든다.
- 한계: 템플릿에는 Regular-M 하나만 있다. 그래서 굵기(weight)를 바꿔도 모양이 같고, 크기(scale)는 시스템이 비율로만 조정한다.
  트리 행은 기본 굵기만 쓰므로 지금은 문제가 없다. 굵기 대응이 필요해지면 Ultralight·Black 기준 굵기를 같은 점 구조로 추가한다.
- 렌더링: 한 레이어(Monochrome)다. 색은 넣지 않고 사용처의 `foregroundStyle`을 따른다.

## 6. 앱 아이콘

- 도구: Apple **Icon Composer**(Xcode 26 시대의 레이어드 아이콘 도구). 결과 `.icon` 파일을 프로젝트에 넣고 앱 target의
  아이콘 이름으로 지정한다. macOS 15에서 보일 이전 형식 이미지가 함께 만들어지는지 반드시 확인하고, 안 되면 Asset Catalog의
  `AppIcon` 세트(16–1024px, @1x/@2x)를 따로 둔다.
- 모양: macOS 표준 둥근 사각형 격자를 따른다(Apple Design Resources의 macOS 아이콘 템플릿). 아이콘 안에 글자를 넣지 않는다.
- 모티프 후보: (a) 비숍 실루엣 + 대각선, (b) 체스판 일부를 대각선으로 가로지르는 경로, (c) 월넛·아이보리 두 색 면 분할.
- 16px·32px에서 알아볼 수 있는지 확인한다(Finder 목록·Spotlight 크기).

## 7. 상태 표현 (W15, 0010 확정)

W15에서 연결 상태를 트리에 표시한다. 상태 이름은 W14 안내 문구와 같다. 표현은 **기호 + 문구 + 시스템 의미 색** 셋을 함께 쓴다.
상태 기호는 행 앞의 종류 기호를 바꾸지 않는다. 이름 뒤에 문구와 함께 붙이는 배지로 쓰며, Bishop 종류와 관계없이 같다.

| 상태 | 문구 | 기호 | 기호 색 | 문구 색 |
|---|---|---|---|---|
| 정상 | (표시 없음) | — | — | — |
| 권한 필요 | 권한 필요 | `lock` | `.orange` | `.secondary` |
| 대상 없음 | 대상 없음 | `xmark.circle` | `.red` | `.secondary` |
| 볼륨 연결 필요 | 볼륨 연결 필요 | `externaldrive.badge.xmark` | `.orange` | `.secondary` |
| 확인 실패 | 확인 실패 | `questionmark.circle` | `.secondary` | `.secondary` |

- 확정 판정에는 ×를, 단정하지 않는 확인 실패에는 ?를 쓴다. 확인 실패에 일반 오류 기호(`exclamationmark.triangle`)를 쓰지 않는다.
- 기호 색은 보조 수단이다. 라이트 모드의 시스템 주황은 3:1에 못 미치므로(0010 측정) 문구에는 주황을 쓰지 않는다.
- VoiceOver 행 라벨에는 상태 문구를 넣는다. 정상 상태에서는 넣지 않는다.
- 값은 `Features/BoardBrowser/LinkStatusPresentation.swift` 한 곳에 둔다.
- 오류 항목도 트리에 남긴다. 행을 흐리게(투명도) 만드는 것만으로 표현하지 않는다.
- 과거 구성 보기(W18)는 "과거 구성" 띠 + 기호(`clock.arrow.circlepath`) + 문구로 현재와 구분한다. 배경 색만 바꾸지 않는다.

## 8. 배치와 간격

- 창 구조(TECH_STACK UI 구성): `NavigationSplitView` 3단(Board 목록 · 구성 트리 · 상세). 최소 창 크기 820×480,
  Board 목록 열 min 200 / ideal 240. 크기를 바꿀 때 UI 테스트가 같은 창 크기에서 통과하는지 확인한다.
- 간격 단위: 4의 배수(4·8·12·16·20). 시트 내부 여백은 시스템 `.padding()`, 요소 사이 12.
- 시트 폭: 입력 360, 확인·목록 380–460. 내용에 맞춰 늘리되 화면 절반을 넘기지 않는다.
- 툴바·제목 막대는 시스템 스타일. 사용자 정의 배경을 넣지 않는다.

## 9. 빈 화면·일러스트

- `ContentUnavailableView`를 유지한다. 테마는 그 안의 이미지(기호 또는 일러스트)와 제목 서체에만 쓴다.
- 일러스트 자산: 벡터(PDF 또는 SVG, Single Scale, Preserve Vector Data). 라이트/다크 변형을 둔다. 크기 64–96pt.
- 일러스트에 글자를 넣지 않는다(현지화·접근성). 설명은 `Text`로 둔다.
- 장식 이미지는 VoiceOver에서 숨긴다(`.accessibilityHidden(true)`). 의미가 있는 이미지만 라벨을 준다.

## 10. 움직임

- 시스템 기본 전환(시트, 펼치기, 목록 갱신)을 쓴다. 장식 애니메이션을 넣지 않는다.
- 새 애니메이션을 넣으면 `@Environment(\.accessibilityReduceMotion)`일 때 끈다.

## 11. 접근성·테스트가 의존하는 것

- **바꾸면 안 되는 접근성 식별자**(UI 테스트가 쓴다): `board-row-<이름>`, `node-row-<이름>`, `board-name-field`,
  `node-name-field`, `node-url-field`, `move-destination-<이름>`, `removal-message`(W13). 행의 `accessibilityElement(children: .ignore)`와
  `accessibilityLabel`, 선택 행의 `.isSelected` trait도 유지한다.
- 메뉴 항목 제목과 단축키를 바꾸지 않는다. 바꾸려면 `BoardBrowserUITests`의 메뉴 검사도 같은 변경에서 고친다.
- 확인 항목: 라이트·다크·고대비(시스템 설정 > 손쉬운 사용 > 디스플레이 > 대비 증가)·투명도 줄이기·VoiceOver로 트리 읽기·
  키보드만으로 모든 명령 실행.

## 12. 코드 구조

- 자산: `Fianchetto/Assets.xcassets`(0011에서 만듦). 소스 폴더가 폴더 동기화 그룹이라 폴더를 만들면
  target에 자동 포함된다. pbxproj의 파일 목록은 고치지 않는다.
- 빌드 설정(앱 target Debug·Release 모두): 강조 색을 쓰면 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`,
  아이콘을 쓰면 `ASSETCATALOG_COMPILER_APPICON_NAME = <아이콘 이름>`. pbxproj를 직접 고치거나 Xcode에서 설정한다.
  `scripts/check-build-settings.sh`가 검사하는 값(Swift 6, strict concurrency, macOS 15.0, arm64)은 건드리지 않는다.
- 공용 스타일 코드: `Fianchetto/Features/Shared/`에 둔다(예: `Theme.swift`의 간격 상수, 빈 화면 공용 View, ViewModifier).
  Domain·Services·Persistence에 색·글자 코드를 넣지 않는다(CLAUDE.md 의존 방향).
- View 파일에서는 스타일 부분만 바꾼다. 화면 상태 모델(`BoardBrowserModel`)·서비스·저장소는 디자인 작업에서 고치지 않는다.
  기능 작업(W15 이후)이 같은 View 파일을 계속 고치므로, 디자인 변경은 작게 나눠 자주 병합한다.
- 모든 화면은 Xcode Preview를 둔다: 라이트, 다크, 빈 상태, 긴 이름. 미리보기 데이터는 실제 저장소를 열지 않는 값으로 만든다.

## 13. 작업 절차

1. 브랜치: `feature/design-<주제>`(예: `feature/design-palette`, `feature/design-app-icon`). 주제 하나에 PR 하나.
2. 결정 기록: 팔레트·아이콘·Bishop 심볼처럼 되돌리기 어려운 결정은 `docs/decisions/NNNN-<slug>.md`(맥락·결정·대안·영향)로 남기고
   이 문서의 "후보"를 확정 값으로 바꾼다. 번호는 `docs/decisions`의 마지막 번호 다음부터.
3. 검증: `scripts/verify.sh` 전체 통과(경고 0개 포함). 보고할 때 빌드 성공·테스트 통과·실제 화면 확인을 구분한다.
4. 화면 캡처: **앱 창만** 캡처한다(`screencapture -l <windowID>` 또는 Xcode Preview 내보내기). 전체 화면 캡처는 다른 앱의 개인
   정보가 찍히므로 하지 않는다. 캡처에 실제 사용자 파일 이름이 보이면 테스트용 Board로 다시 찍는다.
5. macOS 15 확인: 개발 기기에서만 본 결과를 macOS 15 결과로 보고하지 않는다. 15 전용 확인이 필요한 항목은 W27 목록에 넣는다.

## 14. 도구

| 도구 | 쓰임 | 비고 |
|---|---|---|
| Apple Design Resources (macOS UI Kit, Figma/Sketch) | 실제 컨트롤 크기로 시안 | developer.apple.com/design/resources |
| Figma MCP 서버(Figma 공식 Dev Mode MCP) | Claude Code가 Figma 프레임의 색·간격·구조를 읽어 SwiftUI로 옮김 | 요금제·좌석 조건은 Figma에서 확인 |
| SF Symbols 앱 | 기호 검색, 커스텀 심볼 템플릿 | 무료 |
| Icon Composer | 앱 아이콘 | 무료, Xcode와 함께 배포 |
| Xcode Previews | 라이트/다크/고대비 비교 | 반복 작업의 기본 루프 |
| Accessibility Inspector | 대비·VoiceOver 확인 | Xcode > Open Developer Tool |
| Claude HTML 아티팩트 | 팔레트·무드보드 비교 | 웹 렌더링이라 최종 화면 판단에는 쓰지 않는다 |

## 15. 디자인 세션이 정할 것

- [x] `AccentColor` 라이트·다크·고대비 값(3.2의 긴장 해소) — 0011
- [ ] `ThemeSurface`를 상세 영역에 쓸지, 빈 화면에만 쓸지
- [x] Bishop 커스텀 심볼 채택 여부와 모양(파일/폴더 구분 방식) — 0012
- [ ] 앱 아이콘 모티프와 macOS 15 이전 형식 처리
- [ ] Board 제목 세리프 사용 여부
- [ ] 빈 화면 일러스트 사용 여부와 범위
- [x] W15 상태 기호(7장) 확정 — 0010
