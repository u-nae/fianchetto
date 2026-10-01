# Fianchetto

실제 파일을 옮기지 않고, 흩어진 로컬 파일·폴더·웹 링크를 논리적인 프로젝트로 연결하고 그 구성의 변화와
작업 체크포인트를 기억하는 macOS 앱입니다.

> 상태: 구현 전. 기준 문서와 개발 절차를 준비한 단계입니다.

## 문서

| 문서 | 내용 |
| --- | --- |
| [docs/PRD.md](docs/PRD.md) | 제품 동작, 데이터 불변식, 수용 기준(A01~A18) |
| [docs/TECH_STACK.md](docs/TECH_STACK.md) | 기술 선택 |
| [docs/decisions/](docs/decisions/) | 기준 문서의 공백·모순 해소와 이후 결정 기록 |
| [docs/work-items.yaml](docs/work-items.yaml) | 구현 작업 항목 |
| [CLAUDE.md](CLAUDE.md) | 개발 규칙 |

## 개발 절차

작업 항목마다 명세 게이트(`fianchetto-spec-gate`)를 통과한 뒤, 인계된 test obligation 기준으로 TDD를 진행합니다.

- 기술: Swift 6, SwiftUI, SwiftData, App Sandbox. 최소 macOS 15, arm64. 외부 패키지 없음.
- 빌드: Xcode 표준 프로젝트, `xcodebuild`.
