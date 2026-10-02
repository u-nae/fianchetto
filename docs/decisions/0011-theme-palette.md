# 0011 테마 팔레트: 월넛 강조 색, 채움과 글자 변형 분리, 고대비 값

- 상태: 확정 (디자인 세션)
- 날짜: 2026-10-02

## 맥락
DESIGN.md 3.2의 후보 팔레트는 다크 모드 `AccentColor`(`#A06C38`)의 흰 글자 대비가 4.47:1로 4.5:1에 못 미쳤다. 고대비 변형도
정하지 않았다. Asset Catalog가 아직 없어서 W15 이후 화면 작업이 테마 토큰을 참조할 수 없었다.

## 결정
`Fianchetto/Assets.xcassets`에 Color Set 다섯 개를 만든다. 값은 라이트 / 다크 / 라이트 고대비 / 다크 고대비 순서다.

| 토큰 | 값 |
|---|---|
| `AccentColor` | `#8A5A2E` / `#9D6634` / `#6B4624` / `#A16936` |
| `ThemeAccentText` | `#8A5A2E` / `#D2A06A` / `#6B4624` / `#E6C6A8` |
| `ThemeSurface` | `#F6F1E7` / `#2A2520` / `#FFFFFF` / `#1E1E1E` |
| `ThemeBoardGreen` | `#3F6B4A` / `#8DB596` / `#2F5539` / `#B3D4BA` |
| `ThemeLine` | `#D9CDB8` / `#4A4037` / `#8C7A60` / `#9A8A74` |

- 다크 `AccentColor`는 흰 글자 4.5:1 이상과 `#1E1E1E` 배경 대비 3:1 이상을 함께 만족하는 범위(상대 휘도 0.139–0.183) 안에서
  월넛 색상(H 29°)을 유지하는 값으로 고른다. `#9D6634`의 대비는 흰 글자 4.79, 배경 3.48이다.
- 앱 target의 Debug와 Release에 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor`를 설정한다. 사용자가 시스템 강조 색을
  "다중 색상"으로 둔 경우에만 앱 강조 색이 보인다.
- `ThemeIvory`와 `ThemeEbony`는 따로 만들지 않는다. 두 색은 `ThemeSurface`의 라이트·다크 값이다. 쓰지 않는 토큰이 생성 심볼로
  노출되는 것을 피한다.
- 고대비에서 `ThemeSurface`는 시스템 배경으로 돌아가고, 나머지 토큰은 대비를 높인다.

## 대안
- 다크 `AccentColor`를 `#A06C38`로 유지: 흰 글자가 4.47:1로 기준 미달이다.
- 다크에서 밝은 월넛(`#D2A06A`) 하나로 채움과 글자를 함께 쓰기: 흰 글자 대비가 2.34:1이다.
- 고대비 변형 없음: DESIGN.md 3.3 기준(모든 Color Set에 고대비 변형)과 맞지 않는다.

## 영향
- 화면 코드는 `Color(.accent)`, `Color(.themeAccentText)`, `Color(.themeSurface)`, `Color(.themeBoardGreen)`, `Color(.themeLine)`로
  참조한다. 이번 변경은 View를 고치지 않는다. 토큰 적용은 이후 디자인 PR이 화면별로 한다.
- 더 밝은 배경(`#323232`) 위에서는 `AccentColor`가 3:1에 못 미친다(2.68). 이 경우 흰 글자 대비를 우선한다.
- 컴파일된 `Assets.car`에 네 가지 외관 변형이 모두 들어간 것을 `assetutil`로 확인했다. 고대비 화면에서의 실제 모습과
  macOS 15에서의 결과는 실기 확인(W27)으로 넘긴다.
- ThemeSurface를 상세 영역에도 쓸지 빈 화면에만 쓸지는 이번 결정에 포함하지 않는다(DESIGN.md 15장의 별도 항목).
