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

## 추적 중: 가상 머신에서 SwiftData 저장 중 프로세스 종료 (원인 미확인, 앱 버그 가능성 배제 못함)
- 2026-10-06 14:31:42–14:35:48(KST)에 가상 머신에서 단위 테스트 호스트가 SwiftData 저장 중 잡히지 않은 Objective-C 예외로 종료되었다(크래시 보고서 8건, 실행할 때마다 재현).
  나머지 테스트는 모두 실패로 기록되었다. 그 전 두 번의 가상 머신 실행과 호스트 실행에서는 같은 코드가 통과했고, 14:39 뒤로는 다시 나지 않았다.
- 종료된 지점: 테스트 준비 `seedBasicRecords` → `StoreAdapter.save()`(`StoreOpeningTests.unopenableStoreIsPreserved`, `HistoryModelTests`의 준비),
  그리고 앱 코드 경로 `ProjectStore.appendRevision` → `ProjectStore.commit()`(`ConfigurationServiceTests.addGroup` 준비).
- 예외 스택(사용자 콘텐츠 없음): `NSManagedObjectContext.performAndWait` → SwiftData → `KeyedEncodingContainer.encodeNil(forKey:)` → SwiftData →
  `objc_exception_throw` → XCTest 종료 처리기 → `abort()`. 예외 메시지는 크래시 보고서와 시스템 로그에 남지 않았다.
- 당시 가상 머신 상태: macOS 26.6.2(25G83), 부팅 후 약 40분, 디스크 여유 10GiB, 앱 컨테이너 `tmp/TemporaryItems`에 테스트가 남긴 폴더 약 4,000개.
  같은 가상 머신 안에서 다른 작업은 돌지 않았다(호스트에서는 다른 세션의 정적 검사만).
- 확인한 것: 사이드바 수정 전 코드로도 같은 테스트가 실패했다. 남은 폴더를 옮겨 둔 뒤 통과했지만, 빈 폴더 4,000개를 만들어도 통과했고,
  원래 폴더를 되돌린 뒤에도 통과했다. 그래서 폴더 수만으로는 설명되지 않는다. 테스트 임시 폴더 정리 버그는 #49에서 따로 고쳤다.
- 다시 나면: 크래시 보고서(`~/Library/Logs/DiagnosticReports/Fianchetto-*.ips`의 `lastExceptionBacktrace`)와 실패 테스트 목록을 남기고,
  예외 메시지를 얻기 위해 해당 테스트만 디버거로 실행한다. 저장 중 종료는 '현재 구성과 revision은 함께 커밋되거나 함께 실패' 불변식에 닿으므로
  원인이 나올 때까지 이 항목을 닫지 않는다.
