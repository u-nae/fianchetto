# 0031 테스트 전용 V2 스키마를 쓰는 테스트는 별도 실행에서만 돌린다

- 상태: 확정 (에이전트 결정, 2026-10-06)
- 날짜: 2026-10-06

## 맥락
가상 머신 검증(0029)에서 단위 테스트 호스트가 SwiftData 저장 중 `NSUnknownKeyException`(`the entity RevisionModel is not key value
coding-compliant for the key "note"`)으로 종료되는 일이 여러 번 났다. 이 예외는 xcresult 진단 로그에서 찾았다. 테스트 전용 다음 스키마
`TestSchemaV2.RevisionModel`은 마이그레이션을 시험하려고 앱 V1과 같은 엔티티 이름을 쓴다. Swift Testing이 테스트를 병렬로 돌리다가 V2 저장소를
여는 테스트와 V1 저장소 테스트가 같은 프로세스에서 겹치면, V1 저장이 V2 정의를 따라가다 프로세스가 끝난다. 실행 순서에 따라 나기 때문에
코어 수가 적은 가상 머신에서 더 자주 드러났다. 앱은 V2 테스트 스키마를 불러오지 않으므로 배포된 앱의 버그는 아니다.

## 결정
- V2를 쓰는 테스트 2개(A18 `migrationPreservesV1Data`, 앱보다 새로운 스키마 저장소 `newerSchemaStoreIsPreserved`)를
  `SchemaMigrationTests` 묶음으로 옮기고 `.serialized`로 차례로 돌린다.
- 이 묶음은 환경 변수 `FIANCHETTO_SCHEMA_MIGRATION_TESTS=1`일 때만 켠다. 평소 실행(Xcode ⌘U, '단위 테스트만' 명령)에서는 이유 문구와 함께
  건너뜀으로 보인다.
- `scripts/verify.sh`는 평소 테스트 다음에 `TEST_RUNNER_FIANCHETTO_SCHEMA_MIGRATION_TESTS=1`로 이 묶음만 별도 `xcodebuild test-without-building`
  실행(별도 프로세스)에서 돌린다. 통과 수가 2개가 아니면 실패로 본다. 꺼진 채 0개가 통과하는 것을 막기 위해서다.
  `scripts/vm-verify.sh`는 가상 머신에서 `verify.sh`를 그대로 돌리므로 같은 검사를 거친다.
- `TestSchemaV2`를 다른 테스트에서 쓰지 않는다(파일 주석에 적었다).

## 대안
- 단위 테스트 전체를 `.serialized`로: 충돌은 사라지지만 1,000개가 넘는 테스트가 모두 차례로 돌아 느려진다.
- V1 저장소 테스트 전부와 V2 테스트 사이에 읽기·쓰기 잠금: 동기·비동기 테스트가 섞여 있어 협력 스레드가 막히면 교착될 수 있다.
- 별도 테스트 target: 프로세스가 나뉘지만 target 구성(CLAUDE.md, `check-build-settings.sh`)이 바뀌는 구조 변경이다.
- 새 스키마 저장소를 미리 만든 파일로 두기: `newerSchema`만 해결되고, 마이그레이션 테스트는 여전히 V2가 필요하다.

## 영향
- 평소 단위 테스트 수가 2개 줄고, A18 두 테스트는 `verify.sh`와 `vm-verify.sh`에서만 돈다.
- 0029의 '추적 중' 항목은 이 결정으로 원인이 밝혀져 닫는다.
