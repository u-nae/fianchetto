# 0001 샌드박스 파일 접근 권한: read-write 권한 + 읽기 전용 북마크

- 상태: 확정 (기준 문서 간 공백 해소, 에이전트 위임)
- 날짜: 2026-10-01

## 맥락
TECH_STACK은 연결 대상 접근을 "user-selected read-only"로 정하고, PRD §6-I는 내보내기 위치 쓰기를
"연결 대상 원본의 read-only 정책과 다른 권한"이라고 적는다. 그러나 App Sandbox의 user-selected 파일 권한
entitlement는 앱 전체에 하나만 선언된다. read-only로 두면 사용자가 고른 내보내기 폴더에 쓸 수 없다.

## 결정
- entitlement는 `com.apple.security.files.user-selected.read-write` 와 `com.apple.security.files.bookmarks.app-scope` 를 쓴다.
- 연결 대상의 북마크는 `.withSecurityScope` + `.securityScopeAllowOnlyReadAccess` 옵션으로 만든다.
  연결 대상에 대한 접근은 북마크 단위에서 읽기 전용으로 제한된다.
- 쓰기는 내보내기 위치 선택(NSSavePanel/NSOpenPanel로 고른 폴더)에서만 하고, 그 접근은 북마크로 저장하지 않는다.
- 첨부 이미지는 읽기 전용으로 열어 앱 컨테이너로 복사한다.

## 대안
- read-only entitlement 유지: 내보내기(F12)를 사용자 선택 위치에 쓸 수 없다. 앱 컨테이너에만 내보내면 사용자가 찾기 어렵다.
- 연결 대상도 read-write 북마크: 원본을 쓰지 않는다는 원칙을 코드 규율에만 의존하게 된다.

## 영향
- TECH_STACK "파일 접근과 권한" 절을 이 결정에 맞게 갱신했다.
- 북마크 생성 코드와 그 테스트는 읽기 전용 옵션 사용을 검증한다.
