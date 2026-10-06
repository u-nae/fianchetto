# 0029 UI 테스트를 Tart 가상 머신에서 돌린다

- 상태: 확정 (사용자 결정, 2026-10-06)
- 날짜: 2026-10-06

## 맥락
XCUITest는 실제 키보드·마우스 입력을 합성한다. 호스트에서 `scripts/verify.sh`를 돌리면 테스트가 끝날 때까지 사용자가 키보드·마우스를 쓸 수 없고,
사용자 입력이 섞이면 테스트가 흔들린다. 사용자는 Playwright처럼 테스트를 띄워 두고 컴퓨터를 계속 쓰기를 원했다.

## 결정
- Apple Virtualization 기반 [Tart](https://github.com/cirruslabs/tart)(Cirrus Labs) 2.40.1로 macOS 가상 머신 `fianchetto-ui`를 두고, UI 테스트를 포함한 전체 검증을
  `scripts/vm-verify.sh`로 가상 머신 안에서 돌린다. 저장소의 앱·테스트 target은 바뀌지 않는다.
  - 라이선스 Fair Source(FSL-1.1). 개인 사용은 무료다(조직 규모 기준 유료 조건이 있다). GitHub 릴리스 앱을 받아 체크섬·공증을 확인하고 설치했다.
    Homebrew tap이 깨져 있어 쓰지 않는다.
- 가상 머신 준비(사용자 선택, 한 번만 한다):
  - 이미지 `ghcr.io/cirruslabs/macos-tahoe-vanilla:26.6.2`(Xcode 27은 macOS 26.4 이상 필요), CPU 4개, 메모리 6GB, 디스크 70GB, 내장 SSD.
  - Xcode는 호스트의 Xcode 27을 tar로 복사한다(공유 폴더로 ditto 복사하면 심볼릭 링크 순환에 걸린다).
  - 접속은 전용 SSH 키 `~/.ssh/tart_fianchetto`(공개 키만 가상 머신에 둔다). 가상 머신은 부팅마다 로컬 NAT 주소를 받으므로 호스트 키를 저장하지 않는다.
  - 가상 머신 안에서 `sudo automationmodetool enable-automationmode-without-authentication`으로 UI 테스트 자동화 모드를 승인 없이 켠다.
- 가상 머신은 **창을 띄워** 실행한다. `--no-graphics`로 화면 없이 실행하면 "Timed out while enabling automation mode"로 UI 테스트가 시작되지 않는다.
  창은 내려 두어도 되고, 호스트의 키보드·마우스는 가상 머신 창 밖에서 그대로 쓸 수 있다.
- `scripts/vm-verify.sh`: 가상 머신이 꺼져 있으면 켜고(끝나면 다시 끈다), 추적 파일과 무시하지 않은 새 파일만 새 폴더로 보낸 뒤 가상 머신 안에서
  `scripts/verify.sh`를 실행하고 로그를 `build/logs/vm/`으로 가져온다. 호스트 `scripts/verify.sh`는 그대로 두며, 가상 머신이 없을 때 쓴다.

## 대안
- 호스트에서 계속 실행: 준비가 없지만 검증 동안 컴퓨터를 쓸 수 없다.
- UI 테스트를 스냅샷·단위 테스트로 대체: 키 입력 흔들림은 줄지만 메뉴·키보드 접근 같은 실제 흐름을 검증하지 못한다.
- 원격 CI(GitHub Actions macOS): macOS·Xcode 버전을 고르기 어렵고, 개인 저장소에서 사용량 제한이 있다.

## 영향
- 가상 머신 macOS는 26.6이다. 가상 머신 통과는 macOS 15 실기 확인을 대신하지 않는다(보고 때 구분).
  다만 호스트(macOS 27)와 다른 OS에서 돌기 때문에 OS별 차이를 일찍 잡는다. 첫 실행에서 이력 탭·비교가 사이드바를 바로 접을 때
  macOS 26의 NSSplitView 안전 영역 제약이 충돌하는 경고(W17·W18·W19 UI 테스트 4건)를 찾았다. 툴바 버튼으로 접을 때는 생기지 않았고,
  모델이 바꾼 사이드바 표시를 애니메이션으로 따라가게 해서 없앴다.
- 가상 머신 디스크는 복구 파티션 때문에 늘릴 수 없어 남는 공간이 약 12GB다. Xcode를 올리면 이미지를 새로 받는다.
- 호스트 디스크를 약 33GB 쓴다. 가상 머신 실행 중에는 메모리 6GB를 더 쓴다.

## 해결: 가상 머신에서 SwiftData 저장 중 프로세스 종료 (0031)
- 2026-10-06 14:31:42–14:35:48(KST)에 가상 머신에서 단위 테스트 호스트가 SwiftData 저장 중 잡히지 않은 예외로 종료되었다
  (크래시 보고서 8건). 그 뒤에도 V1·V2 테스트를 함께 돌린 실행 12번 중 7번에서 났다.
- 원인: xcresult 진단 로그의 `NSUnknownKeyException`(RevisionModel, key "note"). 테스트 전용 `TestSchemaV2`가 앱 V1과 같은 엔티티 이름을 써서,
  병렬로 겹친 V1 저장이 V2 정의를 따라갔다. 앱은 V2 테스트 스키마를 불러오지 않으므로 배포된 앱의 버그는 아니다.
- 해결: 0031(V2 테스트를 별도 실행으로 분리). 수정 뒤 가상 머신 단위 테스트 5회 반복에서 크래시 0건.
- 교훈: 크래시 보고서에 예외 메시지가 없으면 `xcrun xcresulttool export diagnostics`로 받은 진단 로그의
  `StandardOutputAndStandardError.txt`에서 `Terminating app due to uncaught exception`을 찾는다.
