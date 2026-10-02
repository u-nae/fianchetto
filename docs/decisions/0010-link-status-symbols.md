# 0010 연결 상태 기호: 종류와 무관한 뒤쪽 배지, 확정 상태는 ×, 불확실은 ?

- 상태: 확정 (디자인 세션)
- 날짜: 2026-10-02

## 맥락
W15는 연결 상태(권한 필요, 대상 없음, 볼륨 연결 필요, 확인 실패)를 트리에 표시한다. DESIGN.md 7장의 후보 기호에는 문제가 두 가지
있었다. `questionmark.folder`는 파일 Bishop에도 폴더 모양을 보여 행 앞의 종류 기호(`doc`, `folder.badge.gearshape`)와 겹치고, 물음표가
"대상 없음"이라는 확정 판정과 맞지 않는다. 또 확인 실패의 `exclamationmark.triangle`은 앱의 일반 오류·경고 기호와 같아 구분되지 않는다.
PRD §6-H는 판정 근거가 부족하면 확인 실패로 표시하고 존재 여부를 단정하지 않도록 한다.

## 결정
상태 기호는 행 앞의 종류 기호를 바꾸지 않고, 이름 뒤에 문구와 함께 붙이는 배지로 쓴다. 기호는 Bishop 종류와 관계없이 같다.

| 상태 | 기호 | 기호 색 | 문구 색 |
|---|---|---|---|
| 정상 | 표시 없음 | — | — |
| 권한 필요 | `lock` | `.orange` | `.secondary` |
| 대상 없음 | `xmark.circle` | `.red` | `.secondary` |
| 볼륨 연결 필요 | `externaldrive.badge.xmark` | `.orange` | `.secondary` |
| 확인 실패 | `questionmark.circle` | `.secondary` | `.secondary` |

- 판정이 확정된 상태에는 ×를, 단정하지 않는 확인 실패에는 ?를 쓴다. 사용자가 복구할 수 있는 상태(권한, 볼륨)는 주황, 대상이 없는
  상태는 빨강으로 둔다.
- 네 기호는 모두 macOS 11 이하에서 도입됐다(CoreGlyphs `name_availability.plist` 확인). 따라서 macOS 15에서 쓸 수 있다.
- 기호 색은 보조 수단이다. 의미는 문구와 기호 모양이 전달한다. 라이트 모드에서 시스템 주황은 행 배경 대비 약 2.3:1로 3:1에
  못 미친다. 그래서 문구에는 주황을 쓰지 않고 시스템 `.secondary`를 쓴다. 측정 근거는 아래 영향 항목에 적었다.
- VoiceOver에서는 행 라벨에 상태 문구가 들어가야 한다. 정상 상태에서는 넣지 않는다. 행의 접근성 요소 구조와 식별자는 바꾸지 않는다.

## 대안
- 종류별 기호(`questionmark.folder`, `doc.questionmark`): 행 앞의 종류 기호와 같은 정보를 반복한다. 또 `doc.questionmark`는 macOS 14부터
  쓸 수 있다.
- 확인 실패에 `exclamationmark.triangle`: 일반 오류·경고 기호와 겹친다. 경고 모양이 문제가 있다고 단정하는 것처럼 읽힌다.
- 행 앞 기호를 상태 기호로 바꾸기: 종류를 알 수 없게 된다. 정상 행과 오류 행의 정렬도 달라진다.
- 주황 대신 진한 맞춤 색: 시스템 의미 색 원칙(DESIGN.md 2장)과 사용자 강조 색 설정에 맞지 않는다.

## 영향
- `Features/BoardBrowser/LinkStatusPresentation.swift`(W15)가 위 표의 기호 이름과 색 역할을 쓴다. 문구는 W14 문구를 그대로 쓴다.
- 대비 측정(개발 기기 macOS 27, NSColor sRGB, `controlBackgroundColor` 위, WCAG 식):
  - 라이트: 주황 2.31, 빨강 3.57, secondary 3.95
  - 다크: 주황 7.47, 빨강 4.86, secondary 5.89
  - 고대비 모드의 값과 macOS 15에서의 값은 측정하지 못했다. W27 실제 환경 확인 목록에 넣는다.
- DESIGN.md 7장과 15장을 같은 변경에서 갱신한다.
