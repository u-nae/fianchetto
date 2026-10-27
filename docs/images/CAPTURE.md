# README 이미지 촬영 절차

README의 스크린샷은 UI 테스트 `FianchettoUITests/ReadmeScreenshotTests.swift`가 만든다. 샘플 Board를 UI 테스트 전용
저장소(Debug 컨테이너 안 `FianchettoUITests/readme-…`)에 만들고, 창 영역만 PNG로 저장한다. 실사용 저장소와 설치한 앱의
데이터는 건드리지 않는다. 전체 화면은 찍지 않는다(다른 앱의 개인 정보가 찍힐 수 있다).

## 다시 찍기

```sh
scripts/vm-capture-readme-screenshots.sh     # Tart 가상 머신에서 찍고 docs/images/ 로 가져온다(권장, 0029)
scripts/capture-readme-screenshots.sh        # 호스트에서 직접(UI 테스트 자동화 모드가 켜져야 한다. 실행 중 키보드·마우스 금지)
```

- 환경 변수 `FIANCHETTO_README_SHOTS=1`이 아니면 테스트는 건너뛴다. `scripts/verify.sh`는 이 테스트를 실행하지 않는 것과 같다.
- 테스트 러너는 앱과 같은 샌드박스라 PNG를 테스트 첨부로 남기고, 스크립트가 결과 번들(`build/readme-shots.xcresult`)에서 꺼낸다.
- 시스템 외관은 **라이트 모드**, 언어는 한국어(앱 기본)로 찍는다. 가상 머신은 이 설정이 고정되어 있다.
- 창은 테스트가 윈도우 메뉴 "채우기"로 화면에 맞춘다. 가상 머신 화면은 1024×768pt(Retina 2배)라 PNG는 약 2048×1490px이다.
  크기 조절에 실패하면 로그에 "창 크기 조절 실패"가 남고 기본 창 크기(962×598pt)로 찍힌다.
- 알림 배너가 창 위에 찍힐 수 있다. 가상 머신에는 Tips 데몬을 꺼 두었다(`launchctl disable gui/$(id -u)/com.apple.tipsd`).
  배너가 남아 있으면 알림 저장소를 비우고 알림 센터를 재시작한다:
  `killall usernoted; sqlite3 "$HOME/Library/Group Containers/group.com.apple.usernoted/db2/db" "delete from record"; killall NotificationCenter`
  (usernoted가 저장소를 잠그고 있어 먼저 끈다). 2026-10-21 1차 이미지 6장은 이 배너가 찍힌 채라 재촬영이 필요하다.
- 찍은 뒤 이미지를 열어 확인하고(잘림·애니메이션 중간 상태·오타·알림 배너), 바뀐 PNG만 커밋한다.
- 테스트 도중 앱이 사라지며 `Application … is not running`으로 실패하면 가상 머신의 소프트웨어 업데이트가 원인일 수 있다.
  macOS가 새 업데이트를 자동 다운로드하려고 `cache_delete`로 공간을 확보하면서(목표 약 15GB, 가상 머신 여유 약 9GB) 앱 컨테이너
  캐시를 비우려 앱을 종료시킨다(`log show --predicate 'process == "deleted"'`에 `Purge: goal`, runningboard에
  `CacheDeleteAppContainerCaches`). 2026-10-27에 자동 다운로드·자동 확인을 꺼 두었다
  (`sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false`, `AutomaticCheckEnabled` 동일).
  APFS 컨테이너(44GB) 뒤에 Recovery 파티션이 있어 디스크(70GB)에 맞춰 키우지는 못한다.

## 장면

| 파일 | 장면 | 테스트에서 만드는 상태 |
| --- | --- | --- |
| `app_icon.png` | 앱 아이콘 512px | `Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png` 복사(촬영 아님) |
| `board-tree.png` | 트리 보기, 인스펙터 | Board "서비스 A 리팩토링", Wing 3개, 폴더 Bishop 6개(용도 아이콘), 웹 링크 1개, '회의록' 선택 |
| `icon-view.png` | 아이콘 보기 | '참고 자료' Wing 안으로 들어간 타일 화면, 경로 막대 |
| `link-status.png` | 연결 상태 | 원본 폴더가 사라진 '경쟁 제품 분석'을 고른 상태("대상 없음") |
| `checkpoint.png` | 이력 탭 + 체크포인트 | 체크포인트 "1차 설계 리뷰 완료" 행을 골라 과거 구성 띠와 패널이 보이는 상태 |
| `compare.png` | 구성 비교(통합 트리) | 체크포인트 시점과 현재를 비교. 이름 변경('소스' → '소스 저장소')과 추가('배포')가 보인다 |
| `restore.png` | 복원 시트 | 과거 구성에서 '이 구성으로 복원…'을 연 상태(바뀌는 내용 미리 보기) |

샘플 이름은 모두 가공한 것이다. 연결 대상은 임시 폴더이며 테스트가 끝나면 지운다.

## GIF (아직 없음)

핵심 흐름(이력에서 과거 구성 보기 → 현재와 비교 → 복원)을 담은 `history-compare.gif` 자리를 README에 비워 두었다.
촬영은 QuickTime 화면 기록(앱 창만 선택) 후 GIF로 변환한다. 너비 1200px 이하, 15fps, 10초 이내, 2MB 이하를 목표로 한다.
파일을 넣은 뒤 README의 주석 처리된 `<img>`를 되살린다.
