# AgentBar 프로젝트 작업 지침

Claude Code, OpenAI Codex, Google Gemini, GitHub Copilot, Cursor, Z.ai의 사용량을 표시하는 macOS 메뉴 막대 앱입니다(Swift 6.0, macOS 13.0 이상).

## 언어

사용자와의 대화 및 저장소 문서는 한국어로 작성합니다. 코드와 커밋 메시지는 영어로 유지합니다.

## 작업 절차

### 작업을 시작하기 전

0. **리뷰 확인**: `/roborev-fix`를 실행해 아직 처리하지 않은 리뷰 지적사항을 찾고 수정합니다. 모든 지적사항을 해결한 뒤 요청받은 작업을 진행합니다. 미처리 지적사항이 없으면 바로 진행합니다.

### 모든 변경에서 반드시 지킬 순서

1. 변경사항을 **구현**합니다.
2. **빌드 및 테스트**: `xcodebuild test -project AgentBar.xcodeproj -scheme AgentBar -destination 'platform=macOS' -derivedDataPath build -testPlan AgentBarFull -quiet` — 모든 테스트가 통과해야 합니다.
3. **화면 동작 확인**: `/build-run` 스킬이 설치되어 있으면 실행해 앱을 빌드하고 다시 시작합니다. 스킬을 사용할 수 없으면 다음 명령을 사용합니다: `xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet && (pkill -x AgentBar || true) && open build/Build/Products/Debug/AgentBar.app`. 상세 팝업이 정상적으로 열리는지, 톱니바퀴 아이콘이 있는 헤더·서비스 행·마지막 갱신 시각(Last updated)과 종료(Quit) 버튼이 있는 하단 영역이 모두 잘리지 않고 보이는지 확인합니다.
4. **DEVLOG.md 갱신**: 변경 내용과 이유를 설명하는 새 `## 개발 기록 N:` 항목을 추가합니다. 마지막에 테스트 통과 개수를 기록합니다.
5. **커밋**: `feat:`, `fix:`, `refactor:` 등 Conventional Commits 형식을 사용합니다. 명시적으로 생략하라는 지시가 없다면 커밋과 문서 갱신을 건너뛰지 않습니다.

### 회귀 문제 예방

- 목록이나 컬렉션(서비스, 설정 섹션 등)에 항목을 추가할 때는 팝업 높이, 설정 폼 높이, 스크롤 지원 등 상위 뷰에 충분한 공간이 있는지 확인합니다.
- 모든 내용이 들어가는지 확인하지 않고 고정 크기 프레임을 변경하지 않습니다.
- 서비스 목록처럼 내용이 늘어날 수 있는 컨테이너에는 `ScrollView`를 사용해 이후 항목 추가로 레이아웃이 깨지지 않도록 합니다.

### 커밋 메시지 형식

```
feat: short summary of the change

Longer explanation of what and why (2-3 lines max).

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

첫 줄에는 변경 요약을, 본문에는 변경 이유와 내용을 영어로 2~3줄 이내로 적습니다.

### DEVLOG.md 형식

```markdown
## 개발 기록 N: 짧은 제목

- **핵심 변경사항**: 변경 내용과 이유
- **다른 변경사항**: 모델·구조체·필드 이름 등을 포함한 설명
- 테스트 N개 모두 통과
```

## 빌드 및 실행

- **빌드 및 실행(권장)**: `/build-run` 스킬(Debug 빌드, 기존 프로세스 종료, 새 빌드 실행)
- 스킬 설치 위치: `/build-run`은 `$CODEX_HOME/skills`의 외부 Codex 스킬이며 이 저장소에 정의되어 있지 않습니다.
- **빌드 및 실행(스킬이 없을 때)**: `xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet && (pkill -x AgentBar || true) && open build/Build/Products/Debug/AgentBar.app`
- 빌드만 실행: `xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet`
- 빠른 기본 테스트: `xcodebuild test -project AgentBar.xcodeproj -scheme AgentBar -destination 'platform=macOS' -derivedDataPath build -testPlan AgentBar -quiet`
- 전체 테스트(커밋 전): `xcodebuild test -project AgentBar.xcodeproj -scheme AgentBar -destination 'platform=macOS' -derivedDataPath build -testPlan AgentBarFull -quiet`
- 단일 클래스 테스트: `xcodebuild test -project AgentBar.xcodeproj -scheme AgentBar -destination 'platform=macOS' -derivedDataPath build -only-testing:AgentBarTests/<ClassName>`
- 릴리스 서명 검증: `DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/verify-release-signing.sh`
- DMG 생성: `hdiutil create -volname AgentBar -srcfolder build/Build/Products/Release/AgentBar.app -ov -format UDZO AgentBar.dmg`

## 프로젝트 구조

```
AgentBar/
  Models/          ServiceType, UsageData, UsageMetric, SubscriptionPlan
  Services/        UsageProviderProtocol 및 서비스별 제공자(Claude, Codex, Gemini, Copilot, Cursor, Zai)
  ViewModels/      UsageViewModel (@MainActor, TaskGroup을 이용한 병렬 조회)
  Views/
    StatusBar/     StackedBarView (메뉴 막대 아이콘)
    Popover/       DetailPopoverView, ServiceDetailRow, MetricRow, MiniBarView
    Settings/      SettingsView, SettingsWindowController
  Networking/      APIClient, APIError
  Infrastructure/  KeychainManager, LoginItemManager
  Utilities/       DateUtils, JSONLParser
AgentBarTests/   서비스별 제공자·뷰 모델·유틸리티 단위 테스트
```

## 서비스별 사용량 제공자

| 서비스 | 데이터 출처 | 단위 | 참고 |
|---------|-----------|------|-------|
| Claude Code | Anthropic OAuth API (`/api/oauth/usage`) | 백분율 | macOS 키체인의 "Claude Code-credentials"에서 토큰 조회 |
| OpenAI Codex | Codex App Server (`account/rateLimits/read`) | 백분율 | Codex CLI 로그인 사용, 서버의 실제 한도 기간에 따른 라벨 표시, 초기화권 포함 |
| Google Gemini | 로컬 로그(`~/.gemini/tmp/`) | 요청 수 | 일일 한도만 사용, weeklyUsage=nil |
| GitHub Copilot | GitHub API (`/copilot_internal/user`) | 요청 수 | 키체인의 PAT 사용, 월간 프리미엄 요청, weeklyUsage=nil |
| Cursor | Cursor API (`/api/usage`) 및 로컬 SQLite | 요청 수 | `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`에서 JWT 조회, weeklyUsage=nil |
| Z.ai | REST API (`/api/monitor/usage/quota/limit`) | 백분율(5h) / 요청 수(MCP) | TOKENS_LIMIT=5h, TIME_LIMIT=월간 MCP |

## 주요 규칙

- Swift 6의 엄격한 동시성 검사 사용: 모든 모델은 `Sendable`, 제공자는 `@unchecked Sendable`입니다.
- `weeklyUsage`는 선택적 값(`UsageMetric?`)이며, 한도 기간이 하나뿐인 서비스는 nil로 설정합니다.
- `UsageUnit`은 `.tokens`, `.requests`, `.dollars`, `.percent`를 지원하며, MetricRow는 단위별로 다르게 표시합니다.
- 제공자의 조회가 실패하면 뷰 모델은 사용량 0인 데이터를 반환합니다(막대는 계속 표시).
- 서비스 표시 순서는 Claude, Codex, Gemini, Copilot, Cursor, Z.ai입니다.
- API 키는 `KeychainManager`를 통해 키체인에 저장합니다(서비스: "com.agentbar.apikeys").
- 외부 데이터나 주장에 의존하는 구현은 실제 API 응답과 대조해 확인한 뒤 진행합니다.
