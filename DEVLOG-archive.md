# AgentBar 개발 로그 — 보관본

> 반복 1–76(원래 번호). 이 항목들은 초기 뼈대 구성부터 알림 소리까지 프로젝트의
> 기반 개발 과정을 기록합니다. 현재의 DEVLOG.md가 현행 코드와 관련된 반복에 집중하도록
> 이곳으로 옮겼습니다.
>
> 참고: 아래 반복 70–76은 이후 기본 DEVLOG에서 같은 번호로 진행된 작업으로 대체되었습니다.
> 기본 로그의 70–76이 현재 코드베이스 상태를 반영합니다.

## 개발 기록 1: 프로젝트 뼈대 구성 + 빌드 검증

- xcodegen용 `project.yml` 생성(macOS 13.0, LSUIElement, entitlements)
- LSUIElement=true로 `AgentBar/Info.plist` 설정
- network.client 및 파일 읽기 권한으로 `AgentBar/AgentBar.entitlements` 설정
- 최소 구성의 `AgentBarApp.swift`(@main 진입점)와 `AppDelegate.swift` 생성
- 디렉터리 구조 생성: Models, ViewModels, Views, Services, Networking, Infrastructure, Utilities
- Xcode/Swift용 `.gitignore` 추가
- `xcodegen generate` + `xcodebuild build` 성공


## 개발 기록 2: 핵심 모델 + 유틸리티

- DESIGN.md 색상 팔레트에 따른 다크/라이트 색상 확장을 갖춘 `ServiceType` 열거형
- `UsageData`, `UsageMetric`, `UsageUnit` 모델(모두 `Sendable`)
- 5시간/주간 창 감지와 ISO8601 파싱을 제공하는 `DateUtils`
- 메모리 내 및 스트리밍 파일 파서를 제공하는 `JSONLParser`(손상된 줄은 건너뜀)
- 모든 오류 시나리오를 포괄하는 `APIError` 열거형
- 참고: Swift 6 Sendable 요구사항 때문에 공유 정적 인스턴스 대신 인라인 `ISO8601DateFormatter` 인스턴스를 사용


## 개발 기록 3: 인프라 계층

- Security 프레임워크를 통해 API 키를 안전하게 저장/불러오기/삭제하는 `KeychainManager`
- 로그인 시 실행을 위해 `SMAppService`를 감싸는 `LoginItemManager`
- 제네릭 `get<T>()`와 원시 데이터 메서드를 갖춘 `APIClient` actor
- `UsageProviderProtocol` — 모든 공급자를 위한 Sendable 프로토콜


## 개발 기록 4: Claude Code 공급자

- `ClaudeUsageProvider`가 `~/.claude/projects/` 하위 디렉터리를 스캔
- 최근 7일 이내에 수정된 파일만 필터링
- 하위 에이전트의 중첩된 `message.usage`를 포함한 JSONL 레코드 파싱
- 5시간 및 주간 창의 토큰 집계
- 구성 가능한 토큰 한도 사용(기본값 500K / 10M)


## 개발 기록 5: Z.ai + Codex 공급자

- `ZaiUsageProvider` — `/api/monitor/usage/quota/limit` 호출, Bearer/Raw 인증 재시도
- `CodexUsageProvider` — 주간 비용에는 OpenAI Usage API, 정확한 5시간 수치에는 로컬 `~/.codex/sessions/` 사용
- 제네릭 `fetchWithAuthRetry<T: Decodable & Sendable>`의 Swift 6 Sendable 제약 수정


## 개발 기록 6: ViewModel + 데이터 파이프라인

- `@MainActor`, `@Published` 프로퍼티를 갖춘 `UsageViewModel`
- `TaskGroup`으로 모든 공급자에서 병렬 가져오기
- `Timer.publish`를 통한 주기적 새로고침
- 서비스 순서 유지: Claude → Codex → Z.ai

## 개발 기록 7+8: 메뉴 막대 UI + 팝오버

- `StackedBarView` — 메뉴 막대의 3행 누적 막대 차트(64x20px)
- 동적 막대 높이: 서비스 1개=12px, 2개=8px, 3개=5px
- `StatusBarController` — `NSStatusItem` + `NSHostingView` + `Combine` 관찰
- `PopoverController` — 클릭하면 `DetailPopoverView`가 있는 `NSPopover` 표시
- `DetailPopoverView` — 서비스별 사용량 상세 정보, 재설정 시간, 미니 막대, 종료 버튼
- `AppDelegate`가 ViewModel → StatusBarController → 모니터링을 연결


## 개발 기록 9: 설정 창

- 모든 환경설정에 `@AppStorage`를 사용하는 `SettingsView`
- 로그인 시 실행 토글, 새로고침 간격 선택기
- 서비스별 활성화/비활성화, Keychain을 통한 API 키 관리
- Claude(토큰)와 Codex(달러)의 구성 가능한 한도
- API에서 Z.ai 한도 자동 조회
- macOS 13 호환 `onChange(of:)` API 사용


## 개발 기록 10: 테스트

- 단위 테스트 25개, 모두 통과
- `JSONLParserTests` — 유효/손상/빈/스트리밍 파일 파싱
- `DateUtilsTests` — 5시간/주간 창 경계, ISO8601, 경계 사례
- `UsageViewModelTests` — 병렬 가져오기, 오류 처리, 서비스 순서
- `ClaudeUsageProviderTests` — JSONL 파싱, 오래된 파일 필터링, 하위 에이전트 토큰, 누락된 디렉터리
- `MockUsageProvider` + `UsageData.mock()` 팩토리


## 개발 기록 11: 통합 마무리

- 메뉴 막대의 오류 상태 표시기(데이터가 없으면 경고 삼각형)
- `StatusBarController`가 `usageData`와 `lastError`를 모두 관찰
- DEVLOG.md 문서화 완료


## 개발 기록 12: Codex 공급자 재작성 + 플랜 프리셋

- **CodexUsageProvider 전면 재작성**: 실제 `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` 구조 반영
  - 날짜 기반 하위 디렉터리를 재귀적으로 순회
  - 새 데이터 모델: `CodexPayload`, `CodexTokenInfo`, `CodexRateLimits`, `CodexRateWindow`
  - 정확한 사용량 추적에 `rate_limits.primary/secondary.used_percent` 사용
  - `resets_at` 타임스탬프 확인 — 창이 이미 재설정됐으면 사용량 0
  - 대체 경로: `rate_limits`를 사용할 수 없으면 `last_token_usage` 토큰 합산
  - 이제 `CodexTokenUsage`에 `cached_input_tokens`, `reasoning_output_tokens` 포함
  - `UsageUnit.dollars`에서 `UsageUnit.tokens`로 전환
- **SubscriptionPlan.swift**(신규): `ClaudePlan`(Max 5x/20x/Custom), `CodexPlan`(Pro/Custom)
- **SettingsView**: Claude 및 Codex 플랜 Picker, 한도 자동 채우기, Custom이 아니면 필드 비활성화
- **UsageViewModel**: `UserDefaults`에서 플랜/한도를 읽고 `.limitsChanged` 알림 시 `rebuildProviders()` 실행(500ms 디바운스)
- **SettingsWindowController**(신규): 설정용 독립 NSWindow — `showSettingsWindow:` 선택자에 응답자가 없던 LSUIElement 앱 문제 수정
- **CodexUsageProviderTests**(신규): 디렉터리 순회, rate_limits 파싱, 재설정 감지, 이벤트 필터링, 토큰 합산 대체 경로를 다루는 테스트 8개
- 테스트 33개 모두 통과


## 개발 기록 13: Claude 토큰 과다 집계 수정 + Z.ai 새로고침

- **Claude 토큰 과다 집계 수정**: 합계에 `cache_read_input_tokens`가 포함되고 있었음 — 이 토큰은 무료이며 사용량 제한 대상이 아님. `totalTokens`를 `rateLimitTokens`(input + output만)로 변경. 전체 프로젝트의 표시 사용량이 약 1.38B에서 약 2.4M으로 감소
- **스트리밍 중복 제거**: Claude Code는 스트리밍 중 API 호출마다 여러 레코드(동일 메시지 ID)를 기록함. `deduplicateByMessageID()` 추가 — ID별 마지막 레코드만 유지. 중복 레코드 5169개가 이중 집계되고 있었음
- **키 저장 시 Z.ai 새로고침**: 이제 설정에서 API 키를 저장하면 `.limitsChanged` 알림을 게시하여 다음 60초 타이머 틱을 기다리지 않고 즉시 공급자를 재구성하고 가져옴
- 테스트 업데이트: `testExcludesCacheReadTokens`, `testDeduplicatesStreamingRecords`, `testIgnoresNonAssistantRecords` 추가
- 테스트 35개 모두 통과


## 개발 기록 14: Z.ai API 응답 모델 불일치 수정

- **근본 원인**: `ZaiQuotaResponse` 모델이 실제 API 응답 구조와 일치하지 않았음
  - 응답은 `{code, msg, data, success}`로 감싸져 있지만 모델은 `{data}`만 예상
  - `ZaiLimit` 필드: `used`/`total`은 존재하지 않으며 실제 필드는 `usage`(용량), `currentValue`(사용량), `remaining`
  - `TOKENS_LIMIT`에는 사용량 데이터가 없고 `TIME_LIMIT`가 활성 사용량 제한(요청 수)
  - `ZaiUsageDetail`은 `tokens`/`calls`를 사용했지만 실제 필드는 `modelCode`/`usage`
- **주간 API 수정**: epoch ms 타임스탬프를 예상했으나 실제 형식은 `yyyy-MM-dd HH:mm:ss`
  - 응답에 `totalUsage.totalModelCallCount` / `totalTokensUsage`가 있음
- 검증된 API 응답에 맞게 모든 Z.ai Decodable 모델 재작성
- 이제 Z.ai가 올바른 재설정 시간과 함께 요청 기반 사용량(TIME_LIMIT)을 표시
- 테스트 35개 모두 통과


## 개발 기록 15: 메뉴 막대 가시성 + 재설정 시간 표시

- **메뉴 막대 레이블**: 각 막대 앞에 서비스 색상의 짧은 서비스 이름(CC/CX/Z) 추가
- **막대 배경**: 회색 20% 불투명도에서 서비스 색상 15% 불투명도로 변경 — 사용량이 0%여도 막대가 보임
- **최소 막대 너비**: 사용량이 0%보다 크면 막대에 최소 2px를 적용하여 아주 적은 사용량도 표시
- **팝오버 재설정 시간**: 이제 각 지표 행(5h/7d)에 창 재설정까지 남은 시간을 인라인으로 표시(예: 화살표 아이콘과 함께 "4h 23m"), d/h/m 형식 지원
- ServiceDetailRow의 독립 재설정 텍스트 블록을 제거하고 MetricRow에 통합
- `ServiceType.shortName` 추가: CC(Claude Code), CX(Codex), Z(Z.ai)
- 레이블 공간 확보를 위해 상태 막대 너비를 70에서 90px로 증가


## 개발 기록 16: 재설정 시간 수정 + 이름 변경 + Z.ai 단일 창

- **Claude 재설정 시간 수정**: 항상 `now`와 같아지는 잘못된 `nextResetTime(from: windowStart)` 대신 창 안에서 가장 이른 레코드 타임스탬프(`earliestTimestamp + windowDuration`)로 롤링 창 재설정 계산
- **Z.ai 단일 사용량 제한 창**: Z.ai에는 할당량이 하나(월간 TIME_LIMIT)뿐이므로 주간 API 조회를 제거하고 `UsageData.weeklyUsage`를 선택 사항으로 변경. 이제 Z.ai는 두 행 대신 단일 "Quota" 행 표시
- **Z.ai 레이블 수정**: `fiveHourLabel`은 Z.ai에 "Quota", 나머지에는 "5h"를 반환하고 `weeklyLabel`은 "7d"를 반환
- **"Z.ai GLM" → "Z.ai Coding Plan" 이름 변경**
- **AgentBar → AgentBar 이름 변경**: 프로젝트 이름, 디렉터리(`AgentBar/`, `AgentBarTests/`), 번들 ID(`com.agentbar.app`), entitlements, `@main` 구조체, 모든 import, UI 텍스트, 알림 이름
- 사용하지 않는 `ZaiModelUsageResponse`, `ZaiModelUsageData`, `ZaiTotalUsage` 모델과 `fetchWeeklyUsage()` 메서드 제거
- 선택 사항인 `weeklyUsage`를 처리하도록 뷰 업데이트(DetailPopoverView, StackedBarView, MiniBarView)
- 테스트 35개 모두 통과


## 개발 기록 17: 비용 기반 Claude 사용량 + Z.ai 레이블

- **Claude 사용량: 비용 기반 계산**: 원시 토큰 집계가 대시보드와 일치하지 않았음. 대시보드 값(5h=19%, 7d=45%)과 비교하여 공식을 역공학:
  - `cost = input×$15/M + output×$75/M + cache_creation×$18.75/M + cache_read×$1.50/M`(모델별 가격)
  - Opus/Sonnet/Haiku 가격을 담은 `ClaudeModelPricing` 구조체, JSONL 레코드의 `model` 필드로 선택
  - 예산: Max 5x = $103/5h, $1,133/7d; Max 20x = $412/5h, $4,532/7d(창 비율 11:1)
  - 대시보드와 일치: `floor($20.53/$103×100)=19%`, `floor($511/$1133×100)=45%`
- **설정**: Claude 한도를 토큰 필드에서 달러 예산(`claudeFiveHourBudget`/`claudeWeeklyBudget`)으로 변경
- **Z.ai 레이블**: 줄바꿈 방지를 위해 "Quota"를 "Qt"로 축약
- 테스트: `testCostIncludesAllTokenTypes`, `testModelSpecificPricing` 추가; 모든 검증 값을 달러 값으로 업데이트
- 테스트 36개 모두 통과


## 개발 기록 18: CC를 ccusage 호환 토큰 공식으로 전환

- **문제**: 반복 17의 비용 기반 공식은 CC 대시보드와 안정적으로 일치하지 않았음 — Anthropic은 독점 서버 측 공식을 사용함. 오픈 소스 대안(ccusage, tokscale)을 조사하여 어떤 프로젝트도 대시보드 백분율을 정확히 재현할 수 없음을 확인
- **해결책**: 사용자가 구성할 수 있는 토큰 한도와 함께 네 가지 토큰 유형(`input + output + cache_creation + cache_read`)을 모두 합산하는 ccusage 호환 방식 채택
- **ClaudeUsageProvider**: `ClaudeModelPricing`과 비용 계산을 완전히 제거. `fiveHourTokenLimit`/`weeklyTokenLimit`(기본값: 45M/500M)로 복귀. `.dollars` 대신 `.tokens` 단위 사용
- **SubscriptionPlan**: `ClaudePlan`을 달러 예산(`fiveHourBudget`/`weeklyBudget`)에서 토큰 한도(`fiveHourTokenLimit`/`weeklyTokenLimit`)로 변경. Max 5x: 45M/500M, Max 20x: 180M/2B
- **SettingsView**: Claude 필드를 "5h budget:"/"USD"에서 "5h token limit:"/"tokens"로 변경. AppStorage 키를 `claudeFiveHourBudget`/`claudeWeeklyBudget`에서 `claudeFiveHourLimit`/`claudeWeeklyLimit`로 변경
- **UsageViewModel**: 새 AppStorage 키를 읽고 `fiveHourTokenLimit`/`weeklyTokenLimit`를 ClaudeUsageProvider에 전달하도록 업데이트
- **테스트**: 토큰 기반 검증으로 재작성. `testCostIncludesAllTokenTypes` → `testSumsAllTokenTypes`로 이름 변경. `testModelSpecificPricing` 제거(더 이상 해당 없음)
- 테스트 35개 모두 통과


## 개발 기록 19: Claude 5시간 재설정을 대시보드와 정렬

- **세션 시작 기준 Claude 5시간 재설정**: 이제 `ClaudeUsageProvider`가 로컬 JSONL 로그의 `sessionId` 시작 타임스탬프를 사용하고 `earliest assistant in last 5h + 5h` 대신 `DateUtils.nextResetAligned(start, 5h, now)`로 재설정을 계산
- **이유**: 장시간 실행되는 세션에서는 5시간 블록 안에 유휴 구간이 있을 수 있음. 롤링 `earliest-in-window`는 남은 시간을 과대평가하며, 세션 기반 정렬이 대시보드 동작에 더 근접함
- **대체 동작**: `sessionId` 메타데이터가 없으면 공급자는 이전 롤링 창 재설정(`earliest + 5h`)으로 대체
- **ISO8601 파서 강화**: 이제 `DateUtils.parseISO8601`이 Claude 로컬 메타데이터에 쓰이는 마이크로초 타임스탬프(예: `2025-06-05T17:12:37.153082Z`)를 지원
- **테스트**:
  - `DateUtilsTests.testNextResetAlignedUsesAnchorAndWindow` 추가
  - `DateUtilsTests.testParseISO8601WithMicroseconds` 추가
  - `ClaudeUsageProviderTests.testUsesSessionStartForFiveHourReset` 추가


## 개발 기록 20: CC를 Anthropic OAuth Usage API로 전환

- **문제**: 로컬 JSONL 토큰 집계로는 CC 대시보드와 일치할 수 없었음 — Anthropic은 원시 토큰 수가 아닌 계산 비용 기반의 독점 서버 측 공식을 사용함. 토큰 유형별 가중치(cache_read ≠ input ≠ output), 모델별 배수(Opus 대 Sonnet), 공개되지 않은 플랜 한도 때문에 사용량 백분율과 재설정 시간 모두 로컬 추정이 근본적으로 부정확했음
- **해결책**: Claude Code CLI가 macOS Keychain에 저장한 OAuth bearer 토큰으로 `GET https://api.anthropic.com/api/oauth/usage` 호출. 5시간 및 7일 창 모두에 대해 정확한 `utilization` 백분율(0-100)과 `resets_at` ISO 8601 타임스탬프를 반환하며, CC 대시보드와 `/usage` 명령 표시값과 동일함
- **ClaudeUsageProvider 재작성**: 모든 로컬 JSONL 파싱, 세션 스캔, 토큰 집계, 중복 제거 로직 제거. 이제 Keychain(`"Claude Code-credentials"` 서비스)에서 OAuth 토큰을 읽고 API를 호출한 뒤 응답을 `.percent` 단위의 `UsageData`로 직접 매핑
- **`ClaudePlan` 제거**: API가 서버에서 계산한 백분율을 반환하므로 토큰 기반 플랜 한도(Max 5x: 45M/500M, Max 20x: 180M/2B)는 더 이상 필요 없음. 이제 `SubscriptionPlan.swift`에는 `CodexPlan`만 포함
- **SettingsView 단순화**: Claude 플랜 선택기와 토큰 한도 필드 제거. 이제 Claude 섹션에는 활성화 토글과 OAuth API 출처에 대한 설명만 표시
- **UsageViewModel 단순화**: UserDefaults에서 Claude 플랜/한도를 읽는 부분 제거. 구성 매개변수 없이 공급자 생성
- **새 `UsageUnit.percent`**: 백분율 직접 표시를 지원하도록 추가. 백분율 기반 지표에서 `MetricRow`가 "19.0M / 45.0M tokens" 대신 "19%" 표시
- **테스트 재작성**: URLSession 스텁에 `MockURLProtocol`을 사용하는 새 API 기반 테스트 8개: API 응답 파싱, 재설정 시간 파싱, 백분율 계산, null 창 처리, 401 오류 처리, 누락된 자격 증명, 헤더 검증, 추가 필드 허용. 제거된 `ClaudeMessageRecord` 대신 로컬 테스트 구조체를 사용하도록 `JSONLParserTests` 업데이트
- 테스트 41개 모두 통과


## 개발 기록 21: Gemini 단순화 + UI 다듬기

- **Gemini 일간 전용 창**: 1분(RPM) 사용량 제한 창 제거 — 모니터링에는 일간(RPD) 한도만 의미가 있음. 이제 Gemini는 `weeklyUsage: nil`과 함께 Z.ai의 "Qt"처럼 단일 "1d" 행을 표시
- **"Google Gemini CLI" → "Google Gemini" 이름 변경**: `ServiceType.gemini` rawValue와 설정 섹션 헤더 업데이트
- **설정 정리**: `geminiMinuteLimit` AppStorage와 UI 필드 제거. 일간 요청 한도만 구성 가능
- **팝오버 포커스 링 수정**: 팝오버가 열릴 때 파란 포커스 링이 생기지 않도록 설정 톱니바퀴 버튼에 `.focusable(false)` 추가
- 테스트 41개 모두 통과


## 개발 기록 22: Z.ai 이중 창(5시간 프롬프트 + 월간 MCP)

- **Z.ai 이중 사용량 제한 창**: API가 두 한도를 반환 — `TOKENS_LIMIT`(5시간 프롬프트 창, 백분율 기반)와 `TIME_LIMIT`(월간 MCP 할당량, 요청 수). 이전에는 `TIME_LIMIT`만 단일 "Qt" 행으로 표시
  - `TOKENS_LIMIT` → `fiveHourUsage`(백분율 단위, API는 `percentage`와 `nextResetTime`만 제공)
  - `TIME_LIMIT` → `weeklyUsage`(요청 단위, API는 `usage`/`currentValue`/`remaining`/`nextResetTime` 제공)
- **ServiceType 레이블**: Z.ai `fiveHourLabel`을 "Qt"에서 "5h"로, `weeklyLabel`을 "7d"에서 "MCP"로 변경
- **MetricRow 레이블 너비**: "MCP" 레이블이 잘리지 않도록 20px에서 30px로 증가
- **Z.ai 플랜 정보 사실 확인**: API에서 Max 플랜(`level: "max"`) 확인, MCP 합계=4000은 공개된 할당량과 일치, 프롬프트용 5시간 창 존재
- 테스트 41개 모두 통과


## 개발 기록 23: 가져오기 실패 시 막대 유지 + CX 5시간 재설정 시간 수정

- **오류 시 막대 유지**: 이제 구성된 공급자가 오류를 던지면 `UsageViewModel.fetchAllUsage()`가 nil 대신 사용량 0의 `UsageData`를 반환. 이전에는 API 오류나 파싱 실패가 발생하면 메뉴 막대에서 해당 서비스 막대가 완전히 사라졌음
- **CX 5시간 재설정 시간 수정**: 세션 JSONL의 Codex `resets_at`은 세션마다 한 번 설정되어 5시간 창이 넘어가면 오래된 값이 됨. 오래된 `resets_at`을 미래 시점이 될 때까지 `window_minutes` 간격으로 전진시키는 `resolveWindow()` 도우미 추가. 창이 넘어가면 사용량을 올바르게 0으로 만들면서 다음 재설정 시간은 계속 표시
- **테스트 업데이트**: `testProviderFailureDoesNotAffectOthers` → `testProviderFailureReturnsZeroUsage`, `testEmptyResultsSetsError` → `testAllFailuresStillShowBars` — 이제 둘 다 nil 대신 사용량 0 항목을 예상
- 테스트 41개 모두 통과


## 개발 기록 24: GitHub Copilot + Cursor 사용량 공급자

- **ServiceType**: blue-600/green-600 색상, 짧은 이름 CP/CR, `fiveHourLabel`의 월간 레이블 `"Mo"`를 갖춘 `.copilot`(GitHub Copilot)과 `.cursor`(Cursor) 사례 추가
- **SubscriptionPlan**: 월간 요청 한도를 갖춘 `CopilotPlan`(Free/Pro/Pro+/Business/Enterprise/Custom)과 `CursorPlan`(Free/Pro/Business/Custom) 추가
- **CopilotUsageProvider**(신규): Keychain의 GitHub PAT로 `GET https://api.github.com/copilot_internal/user` 호출. `premium_requests` 할당량 스냅샷(`entitlement - remaining = used`) 파싱. `unlimited: true` 사례 처리. 재설정 = 다음 달 1일 UTC. 단일 월간 창(`weeklyUsage: nil`)
- **CursorUsageProvider**(신규): `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`의 SQLite DB에서 JWT를 읽고 사용자 ID에 해당하는 `sub` 클레임을 디코딩한 뒤 세션 쿠키로 `GET https://www.cursor.com/api/usage?user={userId}` 호출. 모든 모델 버킷(gpt-4, gpt-3.5-turbo, cursor-small, claude-3.5-sonnet)의 `numRequests` 합산. `startOfMonth + 1 month`에서 재설정 파싱. `import SQLite3` C API 사용
- **project.yml**: AgentBar와 AgentBarTests 타깃 모두에 `libsqlite3.tbd` 의존성 추가
- **UsageViewModel**: 활성화 토글과 플랜 기반 한도를 사용해 `CopilotUsageProvider`와 `CursorUsageProvider`를 `buildProviders()`에 연결. 정렬 순서 업데이트: claude, codex, gemini, copilot, cursor, zai
- **SettingsView**: GitHub Copilot 섹션(활성화 토글, PAT SecureField)과 Cursor 섹션(활성화 토글, 플랜 선택기, 월간 한도 필드) 추가. 폼 높이를 640에서 800으로 증가
- **CopilotUsageProviderTests**(신규): 프리미엄 요청 파싱, 재설정 시간 계산, 무제한 할당량, 누락된 자격 증명, 401 처리, 헤더 검증을 다루는 테스트 6개
- **CursorUsageProviderTests**(신규): 임시 SQLite DB를 사용한 API 사용량 파싱, startOfMonth 재설정, 누락된 데이터베이스, null maxRequestUsage 대체 처리, JWT 디코딩을 다루는 테스트 5개
- 테스트 52개 모두 통과


## 개발 기록 25: 팝오버 잘림 수정 + CLAUDE.md 회귀 방지 규칙

- **팝오버 높이 수정**: 6개 서비스를 수용하도록 `DetailPopoverView` 프레임 높이를 350에서 480으로 증가. 향후 서비스 추가 시 바닥글(톱니바퀴 아이콘, "Last updated", Quit 버튼)이 잘리지 않도록 서비스 `ForEach`를 `ScrollView`로 감쌈
- **CLAUDE.md 업데이트**: 워크플로에 "Visual smoke test" 단계(3단계) 추가 — 변경할 때마다 빌드+실행하고 팝오버 UI를 검증해야 함. "Regression prevention" 섹션 추가: 항목 추가 시 컨테이너 크기 확인, 검증 없이 고정 프레임을 변경하지 않기, 확장 가능한 목록에는 ScrollView 사용. Copilot/Cursor를 포함하도록 공급자 목록과 서비스 순서 업데이트
- 테스트 52개 모두 통과


## 개발 기록 26: 불필요한 API 키 필드 제거 + Copilot gh CLI + Cursor 크레딧 기반 플랜

- **Codex API 키 제거**: `CodexUsageProvider`는 로컬 JSONL 파일(`~/.codex/sessions/`)만 읽으므로 API 키는 전혀 사용되지 않았음. 설정에서 SecureField + Save 버튼을 제거하고 `openaiAPIKey` 상태 변수 제거. "Usage is derived from local session logs" 설명 추가
- **Copilot gh CLI 자동 읽기**: 이제 `CopilotUsageProvider`가 먼저 `gh auth token`을 (`Process`를 통해) 시도하고 Keychain의 수동 PAT로 대체. `readGHCLIToken()`은 `/usr/bin/env gh auth token`을 실행하고 stdout을 캡처. 설정 업데이트: 기본 설명은 "Token is auto-read from gh CLI", 수동 PAT는 선택적 대체 수단으로 `DisclosureGroup`으로 이동
- **Cursor 크레딧 기반 플랜**: 2025년 6월 가격 개편을 반영하도록 `CursorPlan` 업데이트 — Free/$0, Pro/$20, Pro+/$60, Ultra/$200, Teams/$40, Custom. `monthlyCreditDollars`와 `monthlyRequestEstimate` 추가(근사치이며 모델별로 다름: $20당 Claude Sonnet 약 225회, GPT-5 약 500회). 공급자, ViewModel, 설정 전반에서 `monthlyRequestLimit` → `monthlyRequestEstimate`로 이름 변경. 설정 레이블을 설명과 함께 "Est. monthly requests"로 변경
- 테스트 52개 모두 통과


## 개발 기록 27: 실행할 때마다 나타나는 Keychain 암호 프롬프트 수정

- **근본 원인**: `KeychainManager`가 명시적 ACL 없이 레거시 Keychain(login.keychain)을 사용. Debug 빌드는 빌드할 때마다 달라지는 임시 코드 서명을 사용하므로 macOS가 각 빌드를 "새" 앱으로 취급 → "Always Allow" 후에도 매번 로그인 암호를 요청
- **수정 시도 1**: `kSecUseDataProtectionKeychain: true` — Data Protection Keychain에는 임시 Debug 빌드에서 사용할 수 없는 적절한 코드 서명 entitlements가 필요하므로 `-34018 errSecMissingEntitlement` 발생
- **최종 수정**: 레거시 Keychain으로 되돌리되 `nil` 신뢰 앱 목록과 함께 `SecAccessCreate`를 추가하여 개방형 ACL 생성. 앱별 제한이 제거되어 AgentBar의 어떤 빌드든 암호 프롬프트 없이 항목을 읽을 수 있음
- **SettingsView 컴파일 수정**: `Result<Void, String>`(`String`이 `Error`를 준수하지 않아 유효하지 않음)을 `SaveResult` 열거형으로 교체
- 테스트 72개 모두 통과


## 개발 기록 28: 더 안전한 Keychain 마이그레이션 쓰기 + 저장 알림 통합

- **Keychain 마이그레이션 안전성**: 이제 `KeychainManager`가 Data Protection/레거시 저장소에 추가 또는 업데이트 upsert를 사용하며, 쓰기 성공을 확인하기 전에 레거시 항목을 삭제하지 않음. Data Protection 쓰기가 확인된 뒤에만 레거시 정리를 수행하여 마이그레이션 실패 시 토큰 손실 방지
- **대체 및 삭제 의미론**: 저장은 Data Protection entitlement 실패 시 레거시 저장소로 대체하여 허용. 불러오기는 계속 Data Protection을 우선하고 이후 최선 노력 마이그레이션과 함께 레거시를 사용. 삭제는 이제 두 저장소를 정리하며 예상 상태(`success`, `not found`, Data Protection `missing entitlement`)에서만 성공
- **단일 SwiftUI 알림 경로**: 알림 표시 충돌을 피하도록 `SettingsView`에서 두 개의 `.alert` 수정자를 열거형 기반 `.alert(item:)` 하나로 교체
- **테스트 범위**: 주입된 모의 security API를 사용해 레거시 대체 + 성공적인 마이그레이션, 실패한 마이그레이션 시 레거시 항목 보존, 삭제 정리/오류 동작에 대한 Keychain 테스트 추가
- 테스트 76개 모두 통과


## 개발 기록 29: security CLI를 통해 Claude Code 자격 증명 읽기

- **구현 출처**: 이 반복의 소스 및 테스트 변경은 커밋 `126806a`(`ClaudeUsageProvider.swift`, `ClaudeUsageProviderTests.swift`)에 반영됨. 커밋 `6c80cdf`는 이 개발 로그 항목만 업데이트
- **문제**: `ClaudeUsageProvider`가 `SecItemCopyMatching`으로 Keychain의 `"Claude Code-credentials"`를 읽었음. 이 항목은 앱별 ACL과 함께 Claude Code CLI가 소유하므로 접근할 때마다 macOS가 "AgentBar wants to use your confidential information"을 표시. 임시 코드 서명으로 인해 빌드할 때마다 "Always Allow"가 재설정됨
- **수정**: 직접 Keychain API를 사용하는 대신 `Process`를 통해 `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w` 실행. `security` 바이너리는 앱별 ACL 프롬프트를 우회하는 시스템 신뢰 앱. Copilot의 `gh auth token`과 같은 패턴
- **캐싱**: 앱 새로고침 간격과 일치하는 TTL의 NSLock 보호 토큰 캐시를 추가하여 같은 폴링 주기 내 반복 CLI 호출 방지
- **`import Security` 제거**: 이제 모든 Keychain 접근이 CLI를 통하므로 더 이상 필요 없음
- **테스트 범위**: TTL 내 CLI 캐시, 실패 시 nil 캐시, 유효한 JSON 파싱, 유효하지 않은 JSON 거부를 다루는 테스트 4개 추가
- 테스트 85개 모두 통과


## 개발 기록 30: 여러 limit_id로 인해 Codex 사용량이 잘못 표시되는 문제 수정

- **근본 원인**: Codex 세션 JSONL 파일에는 서로 다른 `limit_id` 값(주 모델의 `"codex"`, GPT-5.3-Codex-Spark의 `"codex_bengalfox"`)을 가진 `rate_limits` 레코드가 뒤섞여 있음. 코드가 `limit_id`와 관계없이 마지막 레코드를 사용하여 `codex`(사용량 14%) 뒤에 `codex_bengalfox`(사용량 0%)가 오면 사용량이 0%로 표시됨. 표시된 재설정 타이머도 두 limit_id의 서로 다른 `resets_at` 값 사이를 오갔음
- **수정**: 이제 `extractLatestRateLimits`가 `limit_id`별 마지막 레코드를 따로 추적한 뒤 모든 limit_id의 `used_percent`를 합하고 가장 이른 `resets_at`을 선택하여 병합. 단일 `limit_id` 세션은 계속 빠른 경로 사용(병합 오버헤드 없음)
- **모델 변경**: 그룹화를 위해 `CodexRateLimits` 구조체에 `limit_id` 필드 추가
- **테스트 범위**: 합계 검증 및 재설정 시간 선택을 포함한 다중 limit_id 병합, 단일 limit_id 그대로 전달을 다루는 테스트 2개 추가
- 테스트 93개 모두 통과


## 개발 기록 31: Developer ID Application 인증서를 사용한 코드 서명

- **project.yml**: AgentBar 타깃에 `DEVELOPMENT_TEAM: <TEAM_ID>`, `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Developer ID Application"` 추가. 테스트 타깃은 호스트 앱과 테스트 번들의 Team ID를 맞추기 위해 동일한 team ID의 `"Apple Development"` 인증 사용
- **이점**: 빌드 간 안정적인 코드 서명 ID로 임시 서명 문제(Keychain ACL 프롬프트, 지속되지 않는 "Always Allow") 제거. 이제 DMG 배포 및 공증을 위해 앱이 올바르게 서명됨
- 테스트 99개 모두 통과


## 개발 기록 32: Developer ID 서명을 Release로 한정 + 서명 검증 추가

- **서명 범위 수정**: 이제 `project.yml`은 `AgentBar`에 기본적으로 자동 서명을 사용하고 `Developer ID Application` 수동 서명은 `Release` 구성에만 제한. 배포 인증서가 없는 머신에서 Debug/CI 실패 방지
- **테스트 타깃 이식성 수정**: 특정 Apple 팀 설정 없이 기여자 및 CI 환경 전반에서 테스트를 실행할 수 있도록 `AgentBarTests`에서 고정된 팀/인증서를 제거하고 자동 서명으로 전환
- **릴리스 검증 자동화**: Release 빌드를 아카이브하고 `codesign --verify`와 `spctl --assess`로 서명을 검증하는 `scripts/verify-release-signing.sh` 추가. 명령을 `CLAUDE.md` Build & Run 섹션에 추가
- 테스트 103개 모두 통과


## 개발 기록 33: 1단계 에이전트 주의 알림(로컬 알림) 추가

- **로드맵 문서**: 이벤트 모델, 아키텍처, 보안 태세, 테스트 전략을 포함한 상세한 1/2/3단계 설계 문서 `docs/AGENT_ALERTING_ROADMAP.md` 추가
- **1단계 알림 파이프라인**: 실시간 에이전트 주의 신호를 위해 정규화된 알림 이벤트 모델(`AgentAlertEvent`, `AgentAlertEventType`), 감지기 프로토콜, Codex JSONL 감지기, 모니터 코디네이터, 로컬 알림 서비스(`UserNotifications`) 추가
- **Codex 이벤트 매핑**: 워터마크 기반 증분 스캔과 함께 `task_complete`(작업 완료), 권한 상승이 필요한 `function_call`(권한 필요), 질문/결정 형태의 `agent_message` 프롬프트(결정 필요)에 대한 Codex 세션 파싱 구현
- **스팸 방지 및 제어**: 같은 세션/이벤트 키의 반복 알림을 피하도록 이벤트별 토글, 전역 활성화 스위치, 폴링 간격 설정, `AgentAlertMonitor`의 쿨다운 중복 제거 추가
- **앱 통합 및 설정 UI**: 모니터 수명 주기를 `AppDelegate`에 연결하고 알림 권한 요청 동작을 포함한 새 "Agent Alerts (Beta)" 섹션을 `SettingsView`에 추가
- **테스트**: 작업 완료, 권한 상승 감지, 결정 프롬프트 감지, 워터마크 필터링에 대한 `CodexAlertEventDetectorTests` 추가
- 테스트 111개 모두 통과


## 개발 기록 34: 1.5단계 Claude 훅 수집 + 소스 토글

- **로드맵을 1.5단계로 확장**: Claude Code 훅 수집(`Notification`/`Stop`/`SubagentStop`)에 대한 새 부록으로 `docs/AGENT_ALERTING_ROADMAP.md`를 업데이트하고 하이브리드 모델(이벤트 구동 소스 + 폴링 대체)을 명확히 설명
- **Claude 훅 감지기**: `~/.claude/agentbar/hook-events.jsonl`의 브리지 JSONL 레코드를 파싱하고 base64 페이로드를 디코딩하여 정규화된 알림 이벤트(`taskCompleted`, `permissionRequired`, `decisionRequired`)로 매핑하는 `ClaudeHookAlertEventDetector` 추가
- **모니터 소스 토글**: 선택 사항인 `settingsEnabledKey`로 `AgentAlertEventDetectorProtocol`을 확장하고 비활성화된 감지기를 건너뛰도록 `AgentAlertMonitor` 업데이트. 이제 기본 감지기에 Codex 세션 폴링과 Claude 훅 수집이 모두 포함됨
- **설정 UX 업데이트**: "Agent Alerts (Beta)" 섹션에 알림 소스 토글(`alertCodexEventsEnabled`, `alertClaudeHookEventsEnabled`)과 설정 안내 추가. 새 컨트롤을 포함한 레이아웃을 유지하도록 설정 창 높이 증가
- **Claude 훅 브리지 스크립트**: 안정적인 UTC 캡처 타임스탬프와 함께 원시 Claude 훅 stdin 페이로드를 캡처하고 브리지 JSONL 파일에 안전하게 추가하는 `scripts/claude-hook-alert-bridge.sh` 추가
- **테스트**: `ClaudeHookAlertEventDetectorTests`(Stop/Notification 매핑 및 경계 동작) 추가, `CodexAlertEventDetectorTests`에 비활성화된 소스 토글에 대한 모니터 범위 추가
- 테스트 127개 모두 통과


## 개발 기록 35: 상위 3개 우선 상태 막대 순환 + Claude 유휴 세션 대체

- **상태 막대 상위 3개 우선 처리**: 사용량(5시간/보조 창 백분율 중 최대값)으로 서비스 순위를 정하고 기본적으로 상위 3개만 표시하며 초과 서비스를 위한 순환 시퀀스를 만드는 `StatusBarDisplayPlanner` 추가
- **초과 항목 순환 UX**: 이제 `StackedBarView`가 페이지 형식의 행을 렌더링하고 수직 슬라이드 전환을 애니메이션으로 처리. 상위 페이지를 더 오래 표시하고 초과 페이지 사이에 끼워 넣어 사용량이 많은 서비스의 우선순위를 유지
- **Claude 사용량 재설정 수정**: 유휴 기간에 API가 `five_hour`/`seven_day`를 null로 반환해도 `ClaudeUsageProvider`가 더 이상 0%로 강제 재설정하지 않음. 이제 마지막 유효 창 지표를 `UserDefaults`에 캐시하고 재설정 시간이 지날 때까지 재사용
- **테스트 범위**: `StatusBarDisplayPlannerTests`(순위, 페이징, 상위 페이지 끼워 넣기, 지속 시간) 추가, 캐시 대체 및 캐시 만료 사례로 `ClaudeUsageProviderTests` 확장. 격리된 `UserDefaults` 스위트를 사용하도록 공급자 테스트 업데이트
- **서명 확인**: Debug/Release 서명 매트릭스가 여전히 올바른지 검증하기 위해 `./scripts/check-signing-matrix.sh` 실행
- 테스트 134개 모두 통과


## 개발 기록 36: 상위 3개 우선 연속 스크롤 + Claude 유휴 창 파싱 강화

- **상태 막대 동작 수정**: 고정 행 높이, 3행 뷰포트, 초과 행을 한 단계씩 아래로 스크롤하는 연속 수직 목록으로 메뉴 막대 렌더링을 재작업. 맨 아래 창에 도달하면 상위 3개로 돌아가 잠시 유지한 뒤 반복
- **호버 상호작용**: 마우스를 올리면 즉시 상위 3개로 이동하고 호버 중에는 스크롤을 일시 정지하도록 처리 추가
- **Claude 유휴 세션 버그 수정**: 집계 키가 없을 때 모델 범위 키(`five_hour_*`, `seven_day_*`)를 지원하도록 OAuth 사용량 디코딩을 확장하고 일시적인 null 창에 대한 캐시 대체를 유지. 활성 세션이 없을 때 잘못된 0%/재설정 누락 회귀 방지
- **테스트 업데이트**: 모델 범위 Claude 창 테스트 범위 추가, 연속 스크롤 의미론(`maxScrollIndex`, 순위, 동률 결정, 가시성 동작)에 맞게 상태 막대 플래너 테스트 업데이트
- 테스트 136개 모두 통과


## 개발 기록 37: 정확한 상단 재설정 + Claude 디코딩 대체 캐시 복원력

- **정확한 상단 재설정 동작**: `StackedBarView`의 암시적 오프셋 애니메이션을 제거하고 명시적 단계 애니메이션만 유지. 이제 아래에서 위로의 전환과 호버 재설정은 항상 애니메이션 없는 트랜잭션에서 오프셋 `0`으로 바로 이동
- **호버 고정 의미론**: 호버 중에는 상태 막대가 상단 위치를 반복해서 강제하고 호버가 끝날 때까지 모든 스크롤 진행을 억제
- **Claude 페이로드 강화**: 이제 `ClaudeUsageProvider`가 예상치 못한 200 응답 페이로드 형태에 디코딩 오류를 던지는 대신 빈 사용량 페이로드로 처리하여, 유휴 상태/일시적인 API 형태 변동 중에도 기존 캐시 대체 로직이 유효한 5h/7d 값을 보존
- **테스트 범위**: `testUsesCachedValuesWhenResponsePayloadIsUnexpected` 추가, 0/null 경계 사례에 대한 유휴 창 캐시 우선 테스트 유지
- 테스트 139개 모두 통과


## 개발 기록 38: 뷰포트와 호스트 정렬을 바로잡아 상단 행 잘림 수정

- **뷰포트 정렬 수정**: 이제 `StackedBarView`가 기본 중앙 정렬 대신 `.top` 정렬로 20px 뷰포트 프레임을 적용하여 `offset 0`이 부분 잘림 없이 상단 가장자리의 첫 행에 정확히 매핑됨
- **상태 버튼 호스트 레이아웃 수정**: `StatusBarController`가 더 이상 시스템 관리 상태 버튼 프레임을 덮어쓰지 않음. 이제 SwiftUI 호스트 뷰를 `button.bounds`에 고정하고(가로 inset 포함) 버튼과 함께 자동 크기 조정하여 메뉴 막대 슬롯의 세로 오정렬 방지
- 테스트 139개 모두 통과


## 개발 기록 39: CCUsageBar를 AgentBar로 이름 변경

- **프로젝트 전체 이름 변경**: pbxproj, project.yml, Swift 소스, 테스트, 스크립트, 문서를 포함한 28개 이상의 파일에서 모든 `CCUsageBar` → `AgentBar`, `ccusagebar` → `agentbar`, `CCUSAGEBAR` → `AGENTBAR` 교체
- **파일 이름 변경**: `CCUsageBarApp.swift` → `AgentBarApp.swift`, `CCUsageBar.entitlements` → `AgentBar.entitlements`
- **디렉터리 이름 변경**: `CCUsageBar/` → `AgentBar/`, `CCUsageBarTests/` → `AgentBarTests/`, `CCUsageBar.xcodeproj/` → `AgentBar.xcodeproj/`
- **데이터 경로 업데이트**: `~/.claude/ccusagebar/` → `~/.claude/agentbar/`, 환경 변수 `CCUSAGEBAR_CLAUDE_HOOK_LOG` → `AGENTBAR_CLAUDE_HOOK_LOG`
- **Keychain 서비스 변경 없음**: `com.agentbar.apikeys`는 이미 올바른 이름이었음
- 테스트 139개 모두 통과


## 개발 기록 40: 소켓 리스너 + 사용자 지정 소리 지원

- **AlertSocketListener**: `~/.agentbar/events.sock`의 Unix 도메인 소켓이 기본 이벤트 소스로서 Timer 기반 폴링을 대체. 정규화된 agent/event/session_id/message/timestamp 필드를 가진 줄바꿈 구분 JSON 수신
- **AlertSoundManager**: `openpeon.json` manifest 파싱, 카테고리별 활성화/비활성화, 반복 없는 선택, 구성 가능한 볼륨의 AVAudioPlayer 재생을 지원하는 CESP 호환 사운드 팩 로더
- **AgentAlertMonitor 리팩터링**: Timer.publish 폴링 루프와 pollingInterval 프로퍼티 제거. 소켓 리스너가 기본 이벤트 소스이며 훅 구성이 없는 사용자를 위한 대체 수단으로 CodexAlertEventDetector 유지. 새 `receive(event:)` 메서드가 동일한 중복 제거/쿨다운/설정 필터링으로 푸시 기반 이벤트 처리
- **AgentAlertNotificationService**: AlertSoundManager 통합 — 사운드 팩이 구성되면 시스템 기본값 대신 사용자 지정 소리 재생
- **훅 스크립트**: `scripts/agentbar-hook.sh`(Claude)와 `scripts/agentbar-codex-hook.sh`(Codex)가 JSONL 파일 대체 경로와 함께 정규화된 JSON을 소켓으로 전송
- **SettingsView**: 폴링 간격 선택기 제거. 팩 디렉터리 탐색기, 볼륨 슬라이더, 카테고리별 토글, 테스트 버튼을 갖춘 Alert Sounds 하위 섹션 추가. 소켓 기반 아키텍처에 맞게 도움말 텍스트 업데이트
- **AgentAlertEvent**: 이벤트 유형을 소리 카테고리에 매핑하는 `cespCategory` 프로퍼티 추가
- 테스트 170개 모두 통과


## 개발 기록 41: 리뷰 수정 — 소켓 재작성, 대체 타이머, 소리 자동 복원

- **AlertSocketListener 재작성**: NWListener/Network 프레임워크를 POSIX 소켓(`socket(AF_UNIX, SOCK_STREAM, 0)`) + `DispatchSource.makeReadSource`로 교체. 런타임 POSIX 오류 22와 경쟁 상태 수정 — 모든 가변 상태는 비공개 `DispatchQueue`에서 직렬화하고 공개 접근자에는 `queue.sync` 사용
- **대체 타이머 복원**: 감지기 기반 폴링(Codex 파일 감시자, Claude JSONL 리더)을 위해 `AgentAlertMonitor`에 10초 대체 `Timer.publish` 재도입. 소켓이 기본이며 훅 구성이 없는 사용자에게 타이머가 보조 수단
- **ClaudeHookAlertEventDetector 복원**: Claude JSONL 대체 브리지 이벤트를 계속 소비하도록 기본 감지기 목록에 다시 추가
- **AlertSoundManager 자동 복원**: 앱 재시작 후 저장된 사운드 팩 경로를 다시 불러오도록 `init()`에 `restorePersistedPack()` 추가
- **훅 스크립트 강화**: 이스케이프되지 않은 session_id 삽입을 막도록 `agentbar-hook.sh`와 `agentbar-codex-hook.sh` 모두 `python3 json.dumps`로 모든 JSON을 구성하도록 재작성
- **새 테스트**: `AlertSoundManagerTests`에 `testAutoRestoresPersistedPackOnInit`와 `testDoesNotCrashOnInitWithInvalidPersistedPath` 추가
- 테스트 172개 모두 통과


## 개발 기록 42: 리뷰 수정 — 소켓 FD 경쟁, 클라이언트 추적, EAGAIN 처리

- **취소 핸들러 FD 경쟁 수정**: 취소 핸들러가 `self.serverFD`를 읽는 대신 생성 시점의 서버 FD 값을 캡처하여 이전 취소 핸들러가 새 리스너의 FD를 닫을 수 있던 재시작 경쟁 방지
- **클라이언트 연결 추적**: 활성 클라이언트 `DispatchSourceRead` 인스턴스를 `clientSources` 딕셔너리에서 추적. `_stop()`은 모든 클라이언트 소스를 취소하고 FD를 닫음. 클라이언트 취소 핸들러가 `close(clientFD)`를 올바르게 호출
- **동기식 `_isListening` 재설정**: 비동기 취소 핸들러를 기다리지 않고 `AgentAlertMonitor`가 올바른 상태를 보도록 `_stop()`에서 `_isListening`을 즉시 `false`로 설정
- **EAGAIN/EWOULDBLOCK 처리**: 이제 비차단 `read()`가 `bytesRead == 0`(EOF), `errno == EAGAIN`인 `bytesRead < 0`(일시적, 재시도), 실제 오류(닫기)를 구분
- **훅 스크립트 python3 대체**: 이제 두 훅 스크립트 모두 `python3`를 사용할 수 없을 때 따옴표를 제거한 값으로 안전한 printf 기반 JSON을 사용
- **수명 주기 테스트**: 소켓 리스너 시작/중지, 빠른 재시작, 이중 중지, 동기식 `isListening` 상태를 다루는 테스트 5개 추가
- 테스트 177개 모두 통과


## 개발 기록 43: Codex 막대 텍스트 색상 밝게 조정

- **Codex darkColor 밝게 조정**: 메뉴 막대의 "CX" 레이블과 막대 채움 가독성을 높이기 위해 emerald-600 `(0.020, 0.588, 0.412)`에서 emerald-500 `(0.063, 0.725, 0.506)`으로 변경
- 테스트 183개 모두 통과


## 개발 기록 44: 코드베이스 정리 — 사용하지 않는 코드 제거, 중복 통합

- **사용하지 않는 코드 제거**: `APIClient.getRawData`, `APIError.timeout`/`.networkError`, `UsageViewModel.consecutiveFailures`, `DateUtils.isWithinFiveHourWindow`/`isWithinWeeklyWindow`/`nextResetTime`/`nextResetAligned`, `CopilotPlan.monthlyPremiumRequests`, `CursorPlan.monthlyCreditDollars`
- **공유 UserDefaultsExtensions.swift**: 동일한 `bool(forKey:defaultValue:)` 정의 3개(AgentAlertMonitor, UsageViewModel, AgentAlertNotificationService)를 하나의 `internal` 확장으로 통합
- **공유 DynamicCodingKey.swift**: ClaudeUsageProvider와 CursorUsageProvider의 동일한 `DynamicCodingKey` 구조체를 공유 유틸리티로 추출
- **프로토콜 수준 passesBoundary**: ClaudeHookAlertEventDetector와 CodexAlertEventDetector의 중복 `passesBoundary`를 `AgentAlertEventDetectorProtocol` 확장으로 이동
- **AlertSoundManager 중복 제거**: 이제 `cespCategory(for:)`가 `AgentAlertEventType.cespCategory`에 위임. 볼륨 읽기를 `currentVolume` 계산 프로퍼티로 추출
- **테스트 정리**: 제거된 DateUtils 함수에 대한 테스트 메서드 6개 제거
- 테스트 179개 모두 통과


## 개발 기록 45: 팝오버 Quit 버튼의 포커스 링 제거

- **포커스 링 제거**: `DetailPopoverView`의 Quit 버튼에 `.focusable(false)` 추가. 팝오버가 열릴 때 macOS가 마지막으로 포커스 가능한 버튼에 자동 포커스하여 Quit(또는 때때로 톱니바퀴 아이콘) 주위에 파란 테두리가 나타났음. 톱니바퀴 버튼에는 이미 `.focusable(false)`가 있었음
- 테스트 183개 모두 통과

## 개발 기록 46: 설정 탭 분리, 사운드 팩 도움말, 팝오버 플랜 표시

- **SettingsView TabView**: 단일 8개 섹션 Form을 "Usage"(General + 서비스 섹션 6개)와 "Alerts"(알림 토글 + 사운드 팩) 두 탭으로 분리. 프레임을 450×920에서 450×750으로 축소
- **ClaudePlan 열거형**: Claude Code 설정 섹션의 `@AppStorage("claudePlan")` 선택기와 함께 `SubscriptionPlan.swift`에 `ClaudePlan`(Free/Pro/Max/Team) 추가
- **CodexPlan.plus**: `pro` 앞에 1M/5h 및 10M/7d 토큰 한도를 갖춘 `case plus = "Plus"` 추가
- **UsageData의 planName**: 기본값 `nil`인 새 `let planName: String?` 필드 — 기존 호출 지점은 모두 변경 없음
- **공급자의 planName 채우기**: Claude/Codex/Cursor는 UserDefaults에서 읽고 Copilot은 `capitalizedPlanName()` 도우미로 API 응답의 `copilot_plan`을 읽음
- **팝오버 플랜 표시**: `ServiceDetailRow`가 서비스 이름 옆에 캡션 크기의 보조 텍스트로 플랜 이름 표시(예: "Claude Code Pro")
- **SoundPackHelpSheet**: "Alert Sounds" DisclosureGroup 레이블의 `questionmark.circle` 버튼이 CESP 디렉터리 구조, manifest JSON 스키마, 지원 오디오 형식(WAV/MP3/AIFF/M4A/CAF), 카테고리 설명이 있는 `.sheet`를 엶
- **추가된 테스트**: `CodexPlan.plus` 한도, `ClaudePlan` 열거형 유효성/왕복 변환, `CopilotUsageProvider.capitalizedPlanName`, Copilot planName 검증
- 테스트 184개 모두 통과


## 개발 기록 47: Z.ai 플랜 자동 감지, Claude Max 5x/20x 분리

- **Z.ai 자동 감지**: 이미 디코딩되지만 사용되지 않던 기존 `ZaiQuotaData.level` 필드를 `capitalizedPlanName()` 도우미를 통해 `UsageData.planName`에 연결 — 이제 API에서 받은 플랜이 팝오버에 자동 표시
- **Claude Max 5x/20x 분리**: 서로 다른 등급을 선택하도록 `ClaudePlan.max`를 `.max5x = "Max 5x"`와 `.max20x = "Max 20x"`로 변경. 저장된 "Max" → "Max 5x" 변환을 위해 `migrateLegacyClaudePlanIfNeeded()` 추가
- **설정 도움말 텍스트**: Copilot("Plan is auto-detected from GitHub API")과 Z.ai("Plan and limits are auto-detected from Z.ai API") 섹션 설명 업데이트
- **자동 감지 요약**: Copilot과 Z.ai는 완전 자동. Claude/Codex/Cursor는 API가 플랜 정보를 노출하지 않아 수동 선택기 유지
- **추가된 테스트**: `testZaiCapitalizedPlanName`, `testClaudePlanLegacyMaxMigratesTo5x`, 5개 사례에 맞게 `testClaudePlanEnumHasExpectedCases` 업데이트
- 테스트 186개 모두 통과


## 개발 기록 48: 구성된 서비스에 planName이 항상 표시되도록 보장

- **수동 공급자의 기본 planName**: 이제 UserDefaults에 저장된 값이 없으면 Claude/Codex/Cursor 공급자가 nil 대신 기본 플랜(`.pro`)으로 대체. 이전에는 설정을 한 번 이상 연 뒤에만 planName이 표시됐음
- **Copilot nil 대체**: API가 `copilot_plan: null`을 반환하면 아무것도 표시하지 않고 "Free"를 기본값으로 사용
- **Gemini 변경 없음**: 플랜 개념이 없어 planName은 nil 유지(레이블 표시 안 함)
- 테스트 186개 모두 통과


## 개발 기록 49: Alert → Notification 용어 변경

- **모델 이름 변경**: `AgentAlertEvent` → `AgentNotifyEvent`, `AgentAlertEventType` → `AgentNotifyEventType`
- **인프라 이름 변경**: `AgentAlertMonitor` → `AgentNotifyMonitor`, `AgentAlertNotificationService` → `AgentNotifyNotificationService`, `AlertSocketListener` → `NotifySocketListener`, `AlertSoundManager` → `NotifySoundManager`
- **감지기 이름 변경**: `AgentAlertEventDetectorProtocol` → `AgentNotifyEventDetectorProtocol`, `CodexAlertEventDetector` → `CodexNotifyEventDetector`, `ClaudeHookAlertEventDetector` → `ClaudeHookNotifyEventDetector`
- **테스트 이름 변경**: 알림 관련 테스트 파일 4개 모두 해당하는 `*Notify*` 이름으로 변경
- **UI 텍스트 업데이트**: "Agent Alerts (Beta)" → "Agent Notifications (Beta)", "Alerts" 탭 → "Notifications" 탭, "Enable alerts" → "Enable notifications", "Alert Sounds" → "Notification Sounds"
- **UserDefaults 키**: 모든 `alert*` 키를 `notification*`로 이름 변경(예: `alertsEnabled` → `notificationsEnabled`, `alertSoundPackPath` → `notificationSoundPackPath`)
- **Notification.Name**: `.alertsSettingsChanged` → `.notificationsSettingsChanged`
- **AppDelegate**: `alertMonitor` → `notifyMonitor`
- 테스트 186개 모두 통과


## 개발 기록 50: 에이전트 소스를 별도 섹션으로 분리, 도움말 시트 추가, Z.ai 캐시 TTL

- **Agent Sources 섹션**: 에이전트별 구성인 Codex 파일 감시자와 Claude 훅 토글을 "Agent Notifications (Beta)"에서 전용 "Agent Sources" 섹션으로 이동
- **도움말 시트**: 알림 UI에서 인라인 설명(소켓 경로, 훅 스크립트 설정, Codex 대체 경로)을 제거하고 전체 문서가 있는 `AgentSourcesHelpSheet`를 여는 `?` 버튼을 Agent Sources 헤더에 추가
- **Z.ai 응답 캐시**: `cachedIfFresh()`/`updateCache()` 정적 메서드로 `ZaiUsageProvider`에 최소 60초 캐시 TTL을 추가하여 새로고침 간격이 60초 미만일 때 과도한 API 요청 방지
- 테스트 186개 모두 통과


## 개발 기록 51: 로그인 시 실행을 기본 활성화

- **기본값 변경**: `launchAtLogin` 기본값을 `false` → `true`로 변경
- **최초 실행 등록**: `AppDelegate`에 `registerLoginItemIfNeeded()` 추가 — 최초 실행 시(UserDefaults 키가 없을 때) 기본값을 쓰고 `LoginItemManager.setEnabled(true)`를 호출하여 로그인 항목을 실제 등록
- 테스트 186개 모두 통과


## 개발 기록 52: 팝오버에서 반복되는 버튼 포커스 링 수정

- **FocusState 제거**: `DetailPopoverView`에서 `@FocusState`, `PopoverButton` 열거형, `.focused()` 수정자 삭제 — 이들이 버튼을 포커스 대상으로 명시 등록하여 버튼 하나가 제거될 때마다 링이 다른 버튼으로 이동했음
- **열 때 첫 응답자 해제**: 팝오버 표시 후 `PopoverController.show()`에서 `makeFirstResponder(nil)`을 호출하여 팝오버가 나타날 때 어떤 요소도 키보드 포커스를 받지 않도록 함
- 테스트 186개 모두 통과


## 개발 기록 53: Z.ai 사용량 공급자 테스트 범위 추가

- **새 테스트 스위트**: Z.ai 할당량 파싱, 플랜 대문자화, Keychain 구성 감지, 캐시 TTL 동작을 다루는 `ZaiUsageProviderTests` 추가
- **인증 재시도 검증**: `401 Unauthorized` 수신 시 Bearer 우선, 이후 원시 키 재시도 흐름에 대한 API 모의 프로토콜 검증 추가
- **오류 경로 범위**: 누락된 API 키(`APIError.unauthorized`)와 한도가 없는 잘못된 할당량 페이로드(`APIError.noData`) 테스트 추가
- **캐시 동작 확인**: `cachedIfFresh` 만료와 네트워크 호출 없이 캐시로 단축되는 `fetchUsage`를 검증하는 테스트 추가
- 테스트 194개 모두 통과


## 개발 기록 54: Z.ai 테스트가 실제 Keychain 데이터를 삭제하는 문제 수정

- **근본 원인**: `ZaiUsageProviderTests`가 setUp/tearDown에서 `KeychainManager.delete(account: "zai")`를 호출하여 사용자의 실제 Z.ai API 키를 Keychain에서 삭제 — 테스트 후 팝오버에서 Z.ai가 사라졌음
- **credentialProvider 주입**: `CopilotUsageProvider`의 패턴에 맞춰 `ZaiUsageProvider.init()`에 `credentialProvider` 클로저 매개변수 추가. 프로덕션 코드는 기본적으로 `KeychainManager`에서 읽고 테스트는 클로저로 모의 자격 증명을 주입
- **테스트 재작성**: `ZaiUsageProviderTests`에서 모든 `KeychainManager.save/delete` 호출 제거. 이제 실제 Keychain을 건드리지 않고 자격 증명을 주입하는 `makeProvider(credential:)` 도우미 사용
- **isConfigured()**: 이제 `KeychainManager.load()`를 직접 호출하지 않고 주입된 `credentialProvider()` 사용
- 테스트 186개 모두 통과


## 개발 기록 55: 에이전트 알림 훅 안정성 + OpenCode 일급 소스

- **실행 시 레거시 설정 마이그레이션**: `AgentNotifySettingsMigrator`를 추가하고 `AppDelegate.applicationDidFinishLaunching`에 `AgentNotifySettingsMigrator.migrateIfNeeded()` 연결. `alert*` 키를 `notification*` 키로 마이그레이션하고 이후 이전 키 제거
- **Codex 훅 구성 감지 강화**: `AgentHookConfigurationChecker`와 설정 상태 UI 추가. 이제 Codex `notify`는 TOML 최상위에서만 검증(테이블 내부 `notify`는 미구성으로 처리)
- **Agent Sources UI 업그레이드**: 훅 상태 행 + 수동 재확인 동작, OpenCode 소스 토글(`notificationOpencodeHookEventsEnabled`), OpenCode + 안전한 설치 프로그램 사용법 도움말 섹션 추가
- **소켓/모니터 관측성**: 폐기 사유, 수명 주기, 게시, 인증 확인에 대해 `NotifySocketListener`, `AgentNotifyMonitor`, `AgentNotifyNotificationService` 전반에 구조화된 `os.log` 진단 추가
- **중복 제거 견고성**: 이제 `AgentNotifyEvent.dedupeKey`는 정규화된 `sessionID`를 우선하고, 없으면 정규화된 메시지 해시, 둘 다 없으면 타임스탬프 버킷으로 대체
- **OpenCode 일급 서비스 유형**: `ServiceType.opencode`(이름/색상/shortName/Keychain 계정) 추가, 소켓 매핑을 Cursor 별칭에서 전용 OpenCode 서비스로 전환, 순서(`UsageViewModel`, `StatusBarDisplayPlanner`)에 OpenCode 포함
- **신규/업데이트된 훅 스크립트**:
- `scripts/agentbar-gemini-hook.sh`: 이벤트 정규화 개선(`AfterAgent`/`SessionEnd`, `Notification + ToolPermission`, `prompt_response` 지원)
- `scripts/agentbar-opencode-hook.sh`: 새 OpenCode JSON 훅 어댑터(`session.idle`/`session.completed`/`permission.asked`/`question.asked`/`session.error`)
- `scripts/install-agent-hooks.sh`: 쓰기 전 `~/.agentbar/backups/<UTC timestamp>/` 백업, 병합 기반 업데이트, OpenCode 플러그인 생성을 갖춘 Codex/Claude/Gemini/OpenCode용 새 안전 설치 프로그램
- **OpenCode 플러그인 이벤트 범위**: 이제 설치 프로그램이 생성한 플러그인이 idle/permission/question/error 이벤트 외에 `session.completed`도 전달
- **테스트**: `AgentHookConfigurationCheckerTests` + `AgentNotifySettingsMigratorTests` 추가. `AgentNotifyEventTests`(중복 제거 대체 경로)와 `NotifySocketListenerTests`(OpenCode 매핑 + 소스 토글 동작) 확장
- **검증**: 대상 스위트 실행 통과(`AgentHookConfigurationCheckerTests`, `AgentNotifySettingsMigratorTests`, `AgentNotifyEventTests`, `NotifySocketListenerTests`, `StatusBarDisplayPlannerTests`) — 테스트 32개, 실패 0개

## 개발 기록 56: 서명 비밀정보 OSS 강화 + 기록 정리

- **Team ID 하드코딩 제거**: `project.yml`과 `AgentBar.xcodeproj/project.pbxproj`에서 하드코딩된 `DEVELOPMENT_TEAM` 제거. 이제 릴리스 서명 스크립트는 추적 파일에 값을 넣는 대신 환경 변수로 `DEVELOPMENT_TEAM`을 요구
- **릴리스 스크립트 보호 장치**: `DEVELOPMENT_TEAM`이 없으면 명확한 메시지와 함께 즉시 실패하도록 `scripts/verify-release-signing.sh`와 `scripts/release.sh` 업데이트. `scripts/test-verify-release-signing.sh`에 파서 범위 추가
- **CI 비밀정보 스캔**: PR과 `main` 푸시에서 전체 git 기록을 대상으로 `gitleaks`를 실행하는 `.github/workflows/secret-scan.yml` 추가
- **문서화**: `CLAUDE.md` 릴리스 서명 명령에 `DEVELOPMENT_TEAM=YOUR_TEAM_ID`를 포함하고 이 강화 단계를 DEVLOG에 기록
- **기록 재작성**: blob과 커밋/태그 메시지에서 민감한 식별자(team ID 리터럴과 개인 별칭)를 제거하도록 `git filter-repo`로 저장소 기록 재작성
- 테스트 203개 모두 통과

## 개발 기록 57: 에이전트 알림 설정 단순화 + 소스 인식 미리보기

- **알림 이벤트 토글 단순화**: 이제 설정에는 `Task completed`와 `Input required` 두 이벤트 토글만 노출. `permissionRequired`와 `decisionRequired`는 내부적으로 별도 이벤트 유형을 유지하지만 제목과 설정 키 하나를 공유
- **설정 키 마이그레이션 통합**: 레거시 입력 토글(`notificationPermissionRequiredEnabled`, `notificationDecisionRequiredEnabled`, `alertPermissionRequiredEnabled`, `alertDecisionRequiredEnabled`)을 `notificationInputRequiredEnabled`로 매핑한 뒤 이전 키를 삭제하는 마이그레이션 추가
- **메시지 소스 식별 개선**: 이제 알림 본문 접두사가 에이전트와 선택적 세션 맥락이 있는 소스 태그를 사용(예: `[OpenAI Codex | session-1]`). 긴 세션 ID는 가독성을 위해 축약
- **설정 UX 정렬**: 이제 Notifications 섹션은 `Enable notifications`, `Task completed`, `Input required`, `Show message preview`에 집중하고 `Agent Sources`와 `Notification Sounds` 섹션은 소스/소리별 구성 유지
- **테스트**: 소스 태그를 사용하도록 알림 본문 검증 업데이트, alert 시절 입력 키의 마이그레이션 범위 추가
- 테스트 208개 모두 통과

## 개발 기록 58: 에이전트 알림의 OpenCode 플러그인 안정성 수정

- **문제 영역**: OpenCode 알림은 플러그인 런타임에서 `agentbar-opencode-hook.sh`를 생성하는 데 의존했으며 프로세스 생성/런타임 환경이 조용히 실패하면 다른 에이전트는 작동해도 OpenCode 이벤트가 폐기됐음
- **플러그인 전송 재작성**: 이제 설치 프로그램이 이벤트마다 셸을 호출하는 대신 `node:net`을 통해 정규화된 이벤트를 `~/.agentbar/events.sock`에 직접 쓰는 `~/.config/opencode/plugins/agentbar-notify.js`를 생성
- **이벤트 정규화 강화**: `session.idle/session.completed`, `permission.asked`, 입력/오류 변형에 대한 견고한 매핑과 필드 추출 추가. `input.event`와 직접 이벤트 형태 페이로드 모두 지원
- **안전한 설치 동작 유지**: `scripts/install-agent-hooks.sh` 재실행 시에도 플러그인 파일 수정 전 타임스탬프 백업 생성
- **검증**: `bash -n scripts/install-agent-hooks.sh` 통과, 설치 프로그램이 백업과 함께 플러그인 업데이트, 로컬 dry-run에서 플러그인이 Unix 소켓으로 정규화된 OpenCode 페이로드를 내보냄을 확인

## 개발 기록 59: OpenCode 이벤트 모델을 두 카테고리 알림에 맞춤

- **두 카테고리 정렬**: 이제 OpenCode 권한 프롬프트를 별도 `permission` 카테고리가 아닌 `decision`(입력 필요)으로 정규화하여 앱의 단순화된 알림 모델(`task completed` 대 `input required`)과 일치
- **훅 스크립트 업데이트**: 이제 `scripts/agentbar-opencode-hook.sh`가 `permission.asked`/`permission`/`required_permission`을 `decision`으로 매핑
- **설치 프로그램 플러그인 업데이트**: 이제 `scripts/install-agent-hooks.sh`가 생성하는 OpenCode 플러그인에도 같은 매핑을 적용하여 런타임 동작과 훅 스크립트 동작 일치
- **회귀 테스트**: python3 의존성 없이 OpenCode 페이로드 정규화를 검증하는 `HookScriptFallbackTests.testOpenCodeHookMapsPermissionAskedToDecisionWithoutPython3` 추가

## 개발 기록 60: 팝오버 바닥글에 빌드 버전 식별자 추가

- **Run Script 빌드 단계**: PlistBuddy를 통해 빌드 제품의 Info.plist에 `GitCommitHash`(있으면 `GitVersionTag`도)를 주입하는 "Embed Git Version Info" 단계 추가
- **바닥글 버전 표시**: 이제 `DetailPopoverView`가 "Last updated" 아래에 버전 식별자를 표시 — 사용 가능하면 git 태그, 아니면 짧은 커밋 해시를 `.caption2` `.tertiary` 스타일로 표시
- **정적 계산**: 런타임 비용이 없도록 `Bundle.main.infoDictionary`에서 `static let`으로 버전 문자열을 한 번만 계산
- 테스트 209개 모두 통과


## 개발 기록 61: 팝오버에 Buy Me a Coffee 버튼 추가

- **BMC 후원 버튼**: `DetailPopoverView`의 사용량 섹션과 바닥글 사이에 가운데 정렬된 "Buy Me a Coffee" 버튼 추가. 클릭 시 기본 브라우저에서 `https://buymeacoffee.com/_scari` 열기
- **스타일**: 커피잔 아이콘이 있는 주황색 `.bordered` 버튼, 팝오버 너비 중앙 정렬
- 테스트 209개 모두 통과

## 개발 기록 62: BMC 동작 테스트 용이성과 범위 강화

- **주입 가능한 URL 열기 함수**: 브라우저를 실행하지 않고 외부 링크 동작을 테스트하도록 이제 `DetailPopoverView`가 `openExternalURL` 클로저(기본값 `NSWorkspace.shared.open`)를 받음
- **결정론적 동작 검증**: 단위 테스트에서 동일한 BMC 동작 경로를 실행하도록 `#if DEBUG` 아래에 `triggerBMCForTesting()` 추가
- **새 회귀 테스트**: BMC 동작이 `https://buymeacoffee.com/_scari`를 여는지 검증하는 `DetailPopoverViewTests.testBuyMeACoffeeActionOpensExpectedURL` 추가
- 테스트 210개 모두 통과

## 개발 기록 63: 소비량 기반 팝오버 사용량 순위 + 릴리스 중심 테스트

- **팝오버 순서 수정**: 이제 `DetailPopoverView`가 고정 서비스 순서 대신 소비량 기반 순위(`DetailPopoverView.sortedForDisplay`)로 사용량 행을 렌더링하여 사용량이 가장 많은 에이전트를 먼저 표시
- **순위 일관성**: 팝오버 순위는 상태 막대와 같은 점수/동률 결정 정책(`max(5h, weekly)` 후 서비스 순서)을 사용하면서 사용할 수 없는 행도 팝오버에 유지
- **추가된 범위**: `DetailPopoverViewTests.testSortedForDisplayOrdersByHighestUsageDescending`, `DetailPopoverViewTests.testSortedForDisplayUsesServiceOrderAsTieBreaker`, `DetailPopoverViewTests.testSortedForDisplayKeepsUnavailableRows` 추가
- 테스트 213개 모두 통과

## 개발 기록 64: README/DMG 패키징용 SVG 아이콘 자동화

- **아이콘 파이프라인 스크립트**: `docs/assets/agentbar-icon.svg`에서 앱 아이콘 자산을 생성하는 `scripts/generate-icons.sh` 추가
- **출력 형식**: 스크립트가 `build/icons/` 아래에 `1024` 마스터 PNG, 크기 조정된 PNG 세트(`16`부터 `1024`), `.iconset`, `.icns` 생성
- **렌더러 대체**: SVG 렌더링은 사용 가능한 도구(`rsvg-convert`, `inkscape`, `magick`, `sips`, `qlmanage`) 사이에서 자동 대체
- **ICNS 대체**: 가능하면 `iconutil`을 사용하고 로컬 환경에서 `iconutil`이 iconset 변환을 거부하면 `python3 + Pillow`로 대체
- **README 문서**: 간결한 아이콘 생성 사용법과 출력 경로 추가

## 개발 기록 65: CESP 사운드 팩 레지스트리 통합

- **빌드 플래그**: 모든 알림 소리 기능을 제어하는 `AGENTBAR_NOTIFICATION_SOUNDS` 컴파일 조건(Debug에서 ON, Release에서 OFF) 추가. `NotifySoundManager`, `AgentNotifyNotificationService` 소리 호출, `SettingsView` 소리 섹션, `NotifySoundManagerTests`를 `#if` 가드로 감쌈
- **CESPManifest 이중 형식**: 실제 CESP 형식(`categories.*.sounds[].{file, label}`)과 레거시 형식(`sounds: [String: [String]]`)을 모두 지원하도록 `CESPManifest` 업데이트, `soundFiles(for:)` 도우미 메서드 제공
- **CESPRegistryPack 모델**: 계산 프로퍼티 `formattedSize`, `baseContentURL`, `manifestURL`을 갖춘 새 `CESPRegistryPack`(Decodable, Sendable, Identifiable), `CESPRegistryIndex` 래퍼
- **CESPRegistryService**: `peonping.github.io/registry/index.json`에서 가져오는 1시간 캐시의 actor 기반 레지스트리 조회기
- **CESPPackDownloadService**: 팩을 `~/.openpeon/packs/{name}/`에 저장하는 actor 기반 다운로드 서비스. manifest와 각 소리 파일을 진행 콜백과 함께 다운로드하며 실패 시 부분 다운로드 정리
- **SoundPackViewModel**: 레지스트리 불러오기, 팩 선택, 다운로드 진행, `NotifySoundManager`를 통한 활성화를 관리하는 `@MainActor ObservableObject`
- **설정 UI 리팩터링**: NSOpenPanel 파일 탐색기를 CESP 레지스트리의 Picker 드롭다운으로 교체. 다운로드 진행 막대, 오류 표시, 새로고침 버튼 추가. `chooseSoundPackDirectory()` 메서드 제거
- **새 테스트**: `CESPRegistryPackTests`(테스트 8개), `CESPPackDownloadServiceTests`(`MockURLProtocol`을 사용한 테스트 4개), 실제 CESP 형식·표시 이름·대체 동작에 대한 새 `NotifySoundManagerTests` 5개
- 테스트 231개 모두 통과

## 개발 기록 66: 사운드 팩 설정 UI 개선

- **언어 필터**: `SoundPackViewModel`에 `selectedLanguage`와 `filteredPacks` 추가. 팩 목록에서 `availableLanguages` 계산. 설정의 Language Picker가 팩 드롭다운 필터링
- **에이전트 소리 재정의**: 에이전트별(Claude, Codex, OpenCode) Default/None/팩 옵션 사운드 팩 선택. UserDefaults에 `notificationSoundPackName_{keychainAccount}`와 `notificationSoundPackPath_{keychainAccount}`로 저장
- **NotifySoundManager 리팩터링**: `play(for:service:)`가 전역 대체 전 에이전트별 팩 경로를 결정. `resolvePackPath(for:)`와 manifest 캐시(`resolveManifest(at:)`) 추가. 카테고리 토글이 알림 수준 토글과 중복되어 `isCategoryEnabled()` 제거
- **AgentNotifyNotificationService**: 에이전트별 소리 라우팅을 위해 `event.service`를 `NotifySoundManager.play(for:service:)`에 전달
- **SettingsView 정리**: `notificationSoundTaskCompleteEnabled`/`notificationSoundInputRequiredEnabled` 토글 제거. Language 선택기와 Agent Sound Overrides DisclosureGroup 추가. Volume 슬라이더를 섹션 아래로 이동. Test 버튼 유지
- **테스트**: 에이전트 재정의 테스트(`testPlayReturnsFalseWhenAgentSetToNone`, `testPlayUsesGlobalPackWhenNoAgentOverride`, `testPlayReturnsFalseWhenNoPackConfiguredWithService`) 추가. CESPRegistryPackTests에 언어 필터 테스트(`testLanguageFieldDecodes`, `testLanguageFilteringOnPacks`, `testAvailableLanguagesFromPacks`) 추가
- 테스트 236개 모두 통과

## 개발 기록 67: 소리 설정 다듬기 — 언어 표시, 다중 언어, 스타일, 테스트 버튼

- **언어 표시**: Language 선택기가 원래 코드(예: "en", "zh-CN")를 그대로 표시
- **다중 언어 팩**: 이제 `availableLanguages`와 `filteredPacks`가 쉼표 구분 언어 필드(예: "en,ru")를 분리. silicon_valley 팩이 en과 ru 필터 모두에 표시
- **섹션 스타일 일관성**: Notification Sounds 섹션을 `Section` 안의 `DisclosureGroup` 래퍼에서 Agent Sources 섹션과 같은 `Section { ... } header: { ... }` 패턴으로 전환
- **에이전트 재정의 적용 테스트 버튼**: 이제 `playTest(category:service:)`가 일관된 경로 결정을 위해 `resolvePackPath(for:)` + `resolveManifest(at:)` 사용. Agent Sound Overrides 행에 에이전트별 재생 버튼(play.circle 아이콘) 추가. 전역 Test 버튼은 전역 팩을 테스트
- **테스트**: `testMultiLanguageFilteringIncludesCommaDelimited`, `testAvailableLanguagesSplitsCommaDelimited` 추가
- 테스트 239개 모두 통과

## 개발 기록 68: 알림 카드 가독성 개선

- **제목 재설계**: 이제 알림 제목에 일반 이벤트 제목 대신 에이전트/서비스 이름(예: `OpenAI Codex`, `Claude Code`) 표시
- **본문 재설계**: 이제 알림 본문이 명시적 상태(`Task completed` 또는 `Input required`)로 시작하고 상세 텍스트를 덧붙임
- **세션 태그 제거**: 카드의 길고 정보량이 적은 식별자를 피하도록 알림 본문에서 `[service | session]` 접두사 제거
- **미리보기 문구 업데이트**: 이제 미리보기 모드가 알림 본문에 에이전트 출력 텍스트를 표시한다는 점을 설정 문구에 명확히 설명
- **범위 업데이트**: `AgentNotifyNotificationServiceTests`에 제목과 본문 형식 모두에 대한 콘텐츠 수준 검증 추가
- 테스트 240개 모두 통과

## 개발 기록 69: Agent Sound Overrides를 테스트 버튼 아래로 이동

- **레이아웃 순서 변경**: 더 나은 시각적 흐름을 위해 Notification Sounds 섹션에서 Agent Sound Overrides DisclosureGroup을 Test 버튼 행 아래로 이동(Language → Pack → Progress/Error → Test → Overrides → Volume)
- 테스트 239개 모두 통과


## 개발 기록 70: 더 빠른 실행을 위한 테스트 스위트 통합

- **모의 API 검증 테스트 제거**(테스트 4개): `testMockKeychainSecurityAPIRejectsMalformedCopyQuery`, `testMockKeychainSecurityAPIRejectsMalformedAddQuery`, `testMockKeychainSecurityAPIRejectsMalformedUpdateQuery`, `testMockKeychainSecurityAPIRejectsMalformedDeleteQuery` — 프로덕션 코드가 아닌 모의 객체 자체를 테스트했음
- **Keychain 불러오기 테스트 통합**(4 → 1): `testKeychainLoadDoesNotFallbackToLegacyOnUnexpectedDataProtectionFailure`, `testKeychainLoadFallsBackToLegacyOnMissingEntitlementAndKeepsLegacyWhenMigrationFails`, `testKeychainLoadMigratesLegacyItemWhenDataProtectionSaveSucceeds`, `testKeychainLoadKeepsLegacyItemWhenMigrationSaveFails`를 단일 `testKeychainLoadMigrationBehavior`로 병합
- **Plan 열거형 테스트 통합**(5 → 1): `testCodexPlanPlusLimits`, `testCodexPlanAllCasesIncludesPlus`, `testClaudePlanEnumHasExpectedCases`, `testClaudePlanRoundTrips`, `testClaudePlanLegacyMaxMigratesTo5x`를 단일 `testPlanEnumsRoundTripAndHaveExpectedCases`로 병합
- **테스트 수**: 236 → 225(통합으로 테스트 11개 제거)
- 테스트 225개 모두 통과

## 개발 기록 71: 에이전트 알림에 명시적 음소거 모드 추가

- **알림 소리 모드 설정**: `notificationSoundMode`(`system` / `mute`)를 추가하고 Settings > Notifications > Agent Notifications에 `Mute` 옵션이 있는 전용 `Notification sound` 선택기로 노출
- **소리 없이 표시되는 알림**: 이제 `AgentNotifyNotificationService`가 게시마다 `NotificationSoundMode`를 결정하고 모드가 `mute`이면 `content.sound = nil`로 설정하여 알림은 게시하면서 사용자 지정 사운드 팩과 macOS 기본 알림 소리를 모두 차단
- **설정 데이터 위생**: 알 수 없는 저장 소리 모드 값을 `system`으로 대체하도록 `SettingsView.onAppear`에 유효하지 않은 값 정리 추가
- **동작 테스트 범위**: 음소거 모드가 소리 페이로드를 억제하는지 검증하도록 `AgentNotifyNotificationServiceBehaviorTests`에 `testPostMutesSoundWhenSoundModeIsMute` 추가
- 테스트 253개 모두 통과

## 개발 기록 72: 알림 설정 섹션 순서 변경

- **Notification Sounds 배치**: 작업 흐름에서 소리 컨트롤이 먼저 나타나도록 Notifications 탭(`SettingsView.notificationsTab`)에서 `Notification Sounds` 섹션을 `Agent Sources` 위로 이동
- **동작 변경 없음**: 기존 소리/소스 토글과 핸들러를 변경 없이 유지. 표시 순서만 업데이트
- 테스트 253개 모두 통과

## 개발 기록 73: Usage Settings에 BMC 숨기기 설정 추가

- **Usage 탭 설정 추가**: `hideBuyMeACoffeeButton`이 뒷받침하는 `Hide Buy Me a Coffee button` 토글을 Usage Settings 아래쪽(`Support` 섹션)에 추가
- **사용자 안내 문구**: 후원자를 위한 설명 추가: "If you've already donated and the BMC button feels distracting, you can hide it."
- **팝오버 동작 연결**: 이제 `DetailPopoverView`가 같은 설정을 읽고 나머지 바닥글/레이아웃은 그대로 유지하면서 `Buy Me a Coffee` CTA를 조건부로 숨김
- **회귀 범위**: 디버그 도우미를 통해 숨김/표시 상태에 대한 `DetailPopoverViewTests` 범위 추가
- 테스트 255개 모두 통과

## 개발 기록 74: 태그가 없을 때 팝오버 버전을 커밋 해시로 대체하도록 수정

- **빌드 파이프라인 수정**: `Embed Git Version Info` 빌드 후 스크립트가 프로젝트에 실제 존재하고 빌드마다 실행되도록 `project.yml`에서 `AgentBar.xcodeproj` 재생성
- **Info.plist 주입 검증**: 이제 Debug 빌드 출력이 태그 없는 커밋에 `GitCommitHash`를 쓰고 정확한 태그가 없을 때 `GitVersionTag`를 없는 상태로 유지하여 의도치 않은 `CFBundleShortVersionString`(`1.0`) 대체 방지
- **버전 결정 강화**: `DetailPopoverView` 버전 로직을 공백에 안전한 정규화와 명시적 대체 순서(tag → commit hash → short version → `unknown`)를 갖춘 `resolvedVersionString(from:)`로 리팩터링
- **새 테스트**: 버전 우선순위 규칙과 누락 값 대체 동작에 대한 `DetailPopoverViewTests` 범위 추가

## 개발 기록 75: 일간 히트맵 타일과 추세 차트 상자의 세로 정렬

- **공유 크기 상수**: `UsageHistoryTabView`에 공유 타일/간격 상수를 도입하고 해당 값에서 `heatmapGridHeight` 도출
- **상단 가장자리 정렬 수정**: 선 차트 위의 독립 제목 행을 제거하여 차트 상자가 일간 히트맵 그리드와 같은 세로 시작점에서 시작
- **높이 정렬 수정**: 추세 차트 상자 높이를 계산된 히트맵 그리드 높이에 맞춰 두 시각 상자가 세로로 정렬되도록 보장
- **미래 대비**: 향후 타일 크기 변경이 오정렬을 다시 유발하지 않도록 하드코딩된 히트맵 간격 값을 공유 상수로 교체

## 개발 기록 76: 보조 창 히트맵에서 요일 y축 숨기기

- **보조 맥락 명확성**: 이제 `UsageHistoryTabView`에서 히트맵 요일 y축(Sun/Tue/Thu/Sat)은 기본 창 패널에만 표시
- **요청된 UX 동작**: 보조 창 패널은 더 이상 요일 y축 레이블을 렌더링하지 않아 사용자가 재설정 주기 맥락에서 보조 데이터를 해석할 때 의미 불일치를 줄임
- **회귀 범위**: 축 가시성 규칙(`primary`는 축 표시, `secondary`는 축 숨김)을 고정하도록 `UsageHistoryTabViewTests.testShowsWeekdayAxisOnlyForPrimaryWindow` 추가
