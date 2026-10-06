# 0033 Debug 번들 ID를 나누고 개인 서명은 git 밖 설정으로 둔다

- 상태: 확정 (사용자 결정: 로컬 설치 준비 진행, 2026-10-06)
- 날짜: 2026-10-06

## 맥락
사용자가 앱을 로컬에 설치해 개인적으로 쓰기로 했다. 지금까지 Debug와 Release가 같은 번들 ID(`io.github.u-nae.Fianchetto`)를 써서,
설치한 앱과 Xcode로 띄운 개발용 앱·테스트가 같은 sandbox 컨테이너(같은 저장소)를 썼다. 설치한 앱을 켜 둔 채 호스트에서 테스트하면
같은 번들의 앱이 겹친다. 또 모든 target이 pbxproj에 ad-hoc 서명(`CODE_SIGN_IDENTITY = "-"`)을 박아 두어 개인 인증서로 서명할 자리가 없었다.
저장소는 공개할 예정이라 개인 팀 ID를 커밋하지 않아야 한다.

## 결정
- 앱의 Debug 번들 ID를 `io.github.u-nae.Fianchetto.debug`로 바꾼다. Release는 `io.github.u-nae.Fianchetto` 그대로다.
  Debug(Xcode 실행·단위·UI 테스트)와 Release(설치한 앱)의 컨테이너와 저장소가 나뉜다. 테스트 target 번들 ID는 그대로 둔다.
  - 번들 ID를 쓰던 곳: UI 테스트 도우미는 테스트 대상 앱 번들에서 ID를 읽는다. `record-snapshots.sh`는 Debug 컨테이너를 본다.
    로그 서브시스템은 지금처럼 실행 중인 번들 ID라 Debug 로그가 `.debug` 서브시스템으로 나뉜다.
- 서명 설정을 `Config/Signing.xcconfig`(커밋)로 옮겨 프로젝트 수준 구성에 연결한다. 기본값은 ad-hoc(`-`), 팀 없음이다.
  이 파일은 `#include? "Local.xcconfig"`로 git에 넣지 않는 `Config/Local.xcconfig`를 읽는다. 사용자가 거기에 `DEVELOPMENT_TEAM`과
  `CODE_SIGN_IDENTITY = Apple Development`를 두면 모든 target이 개인 인증서로 서명된다. 파일이 없으면(가상 머신, 다른 Mac) ad-hoc 그대로다.
  `Config/Local.xcconfig.example`을 둔다.
- `check-build-settings.sh`가 확인하는 것:
  - 구성별 앱 번들 ID.
  - Local.xcconfig가 없을 때 모든 target의 ad-hoc 서명.
  - Local.xcconfig가 `.gitignore`에 있는지.
  - pbxproj에 서명 값이 다시 박히지 않았는지.

## 대안
- 번들 ID를 그대로 두고 저장소 경로만 Debug에서 바꾸기: 컨테이너가 같아 설치한 앱과 테스트 실행이 여전히 겹친다.
- 팀 ID를 pbxproj에 커밋: 설정은 단순하지만 공개 저장소에 개인 팀 ID가 남고, 인증서가 없는 가상 머신·다른 Mac에서 빌드가 깨진다.

## 영향
- 기존 Debug 실행으로 만든 데이터는 `io.github.u-nae.Fianchetto` 컨테이너에 남아 있어, 설치한 Release 앱에서 보인다.
  Debug 앱은 빈 저장소로 시작한다. 데이터를 옮기거나 지우는 일은 하지 않았다.
- 스냅샷 기준 이미지 기록 위치가 Debug 컨테이너로 바뀌었다(`record-snapshots.sh`).
- 개인 서명은 사용자가 Xcode 계정 설정 뒤 Local.xcconfig를 만들어야 쓴다. `verify.sh`와 `vm-verify.sh`는 Local.xcconfig 유무와 관계없이 돈다.
