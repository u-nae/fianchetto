# 0028 테스트 target에 화면 스냅샷 도구 swift-snapshot-testing을 둔다

- 상태: 확정 (사용자 결정, 2026-10-06)
- 날짜: 2026-10-06

## 맥락
디자인 부품(Bishop 타일·용도 배지·상태 기호 등)의 렌더링은 디자인 세션이 앱 창을 손으로 캡처해 확인해 왔다. 확인할 때마다 UI 테스트를 띄워야 하고,
배지 대비 같은 회귀를 자동으로 잡지 못했다. TECH_STACK은 외부 패키지 0개로 시작했고, 필요가 드러날 때 도입하기로 했다.

## 결정
- 화면 스냅샷 도구 [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)(Point-Free)을 **FianchettoTests target에만** 넣는다.
  앱 target은 외부 패키지 0개를 유지한다. `scripts/check-build-settings.sh`가 허용 목록 밖의 패키지와 앱 target 의존을 막는다.
  - 라이선스 MIT, 1.19.6(2026-09-21) 기준 활발히 유지된다. SwiftPM 해석 때 swift-syntax·swift-custom-dump·swift-issue-reporting을 함께 받지만
    링크하는 것은 SnapshotTesting 모듈뿐이다. 버전 범위는 1.19.x(upToNextMinor)이며 Package.resolved를 커밋한다.
- 그리기: SwiftUI `ImageRenderer`로 그린다. NSView cacheDisplay 계열은 배지의 compositingGroup·blendMode(.destinationOut) 합성을 무시한다(디자인 세션 확인).
- 고정 조건: 2배율, 한국어, 라이트·다크, 창 배경 위. 비교 정밀도는 perceptualPrecision 0.98이다.
- 기준 이미지는 개발 기기(macOS 27)에서 기록했다. macOS 15 화면 확인을 대신하지 않고 회귀 방지용이다. 실제 앱 창으로 하는 최종 확인은 디자인 세션이 그대로 한다.
- 샌드박스: 단위 테스트 호스트 앱은 샌드박스라 저장소에 쓰고 읽을 수 없다. 기준 이미지는 `FianchettoTests/Snapshots/References`에 두어
  테스트 번들 리소스로 들어가게 하고, 비교·기록은 앱 컨테이너 임시 폴더에서 한다. 새 기준 이미지는 `scripts/record-snapshots.sh`로 저장소에 옮긴다.
- 대상 순서(디자인 세션 의견): Bishop 타일·배지 → 상태 기호 → 빈 화면 체스판·Board/Wing 심볼 → 비교 행. 창 전체와 시스템 컨트롤이 많은 화면은 OS 업데이트마다
  그리기가 바뀌므로 뒤로 미룬다. 기준 이미지가 바뀌는 PR은 디자인 세션이 이미지를 보고 확인한다.

## 대안
- 도입하지 않음: 의존성은 늘지 않지만 렌더링 회귀를 사람이 매번 확인해야 한다.
- ViewInspector: 뷰 구조는 볼 수 있지만 그려진 모양(배지 대비)은 보지 못하고, macOS 목록·메뉴 지원이 제한적이다.
- XCUITest 캡처 비교: 앱을 띄워야 하고 키 입력 흔들림의 영향을 받는다.

## 영향
- CLAUDE.md, TECH_STACK.md, README.md의 '외부 패키지 0개' 문장을 '앱 target 0개, 테스트 전용 허용 목록'으로 바꿨다.
- 처음 클론하거나 캐시가 없으면 패키지 해석에 네트워크가 필요하다.
