# AgentBar 개발 기록

> 개발 기록 1–69는 [DEVLOG-archive.md](DEVLOG-archive.md)에 보관되어 있습니다.

## 개발 기록 99: 전체 Markdown 한국어화 및 최신 스크린샷 반영

- **문서 한국어화**: README, 개발 지침, 개발 기록과 보관 기록, 알림 로드맵, 사용량 기록 설계, 빌드 명령 안내를 한국어로 옮겼습니다. 과거 기록의 번호와 사실, 코드 예제, 실행 명령, 링크는 유지했습니다.
- **최신 실행 화면**: 사용자가 제공한 Claude 초기화 시각과 Codex 실제 사용량·초기화권 화면으로 README 이미지를 교체했습니다. 이미지는 편집하지 않았으며, 주요 영문 UI 표시의 뜻을 한국어로 설명했습니다.
- **변경 범위 검증**: 소스 코드, 테스트 코드, 프로젝트 설정, 빌드 스크립트에는 변경이 없습니다. 설치 명령의 셸 문법과 원본 이미지 일치 여부를 확인했습니다.
- **테스트 결과**: 실행 로그에서 286개 중 285개 통과, 1개 건너뜀, 실패 0개를 확인했습니다. 별도로 Xcode 결과 묶음 저장 과정에서 `mkstemp: No such file or directory` 오류가 발생했으며, 이 문서 변경에서는 관련 코드를 수정하지 않았습니다.

## 개발 기록 98: 포크 변경 사항을 main에 공개

- **기본 브랜치**: 기존 기록을 보존하면서 개인 저장소의 `main`에 빨리 감기 방식으로 통합할 수 있도록 기존 포크 변경 사항을 준비했습니다.
- **설치 안내**: 저장소 링크, 복제 및 업데이트 명령, 문제 해결 안내가 `main`을 사용하도록 수정했습니다. 이전 브랜치 사용자가 로컬 변경을 버리지 않고 최신 main을 새로 복제하는 방법도 문서화했습니다.
- 전체 285개 테스트 통과(1개 건너뜀)

## 개발 기록 97: 개인 포크의 독립 설치 방법 문서화

- **포크 전용 설정**: 원본 저장소의 DMG 설치 안내를 개인 브랜치의 정확한 복제 방법, Xcode 사전 요구 사항, 임시 서명 방식의 Debug 빌드, 사용자별 Applications 설치, 백업 및 업데이트 명령으로 교체했습니다.
- **계정 설정 및 문제 해결**: Codex CLI 설치와 ChatGPT 로그인, Claude 키체인 접근, 서버 할당량 및 초기화권 동작, 오래된 데이터, CLI 탐색, 이전 앱 복사본에 관해 문서화했습니다.
- **명확한 출처 표기**: 포크 변경 사항 요약을 추가하고 원본 저장소의 스크린샷과 지원 링크를 명시했으며, 이 로컬 빌드를 설명하지 않는 배지를 제거했습니다.
- **검증**: Xcode 16.3 및 macOS 15.7.4에서 문서에 적힌 서명 덮어쓰기를 적용해 새 복제본을 빌드하고, 앱을 임시 설치 디렉터리로 복사한 뒤 임시 서명을 검증했으며 README 셸 블록의 문법을 검사했습니다. 데스크톱 입력 자동화는 사용하지 않았습니다.
- 전체 285개 테스트 통과(1개 건너뜀)

## 개발 기록 96: 실시간 Codex 사용량과 초기화권 조회

- **실시간 할당량**: 세션 로그 탐색과 예상 토큰 합계를 인증된 Codex App Server의 `account/rateLimits/read` 메서드로 교체했습니다. 각 새로고침은 모델 턴을 시작하지 않고 서버 비율, 기간 길이, 초기화 시각, 계정 요금제를 읽습니다.
- **초기화권**: 사용 가능한 초기화 횟수와 반환된 만료일을 표시합니다. 이 연동은 초기화권을 읽기만 하며 절대 사용하지 않습니다.
- **실패 처리**: 마지막으로 성공한 관측값을 오래된 데이터 경고 및 시각과 함께 보존하고, 오래된 결과는 사용 기록에서 제외하며, 첫 요청이 실패하면 사용량을 확인할 수 없다고 표시합니다.
- **프로세스 수명 주기**: 제한 시간이 있는 표준 입출력 초기화와 응답 읽기, 파일 끝 및 오류 처리, 프로세스 정리, nvm 설치를 포함한 그래픽 사용자 환경의 CLI 탐색을 추가했습니다.
- **검증**: 전송 계층 고정 데이터로 초기화, 조각난 응답, 알림, 시간 초과, 서버 오류를 다룹니다. 운영 Swift 클라이언트를 사용한 읽기 전용 확인에서 최소 PATH 환경을 포함해 주간 사용량 50%와 초기화권 2개가 반환되었습니다.
- 전체 285개 테스트 통과(1개 건너뜀)

## 개발 기록 95: 상세 팝업 너비 조정

- **상세 팝업 너비**: 더 간결한 메뉴 막대 상세 팝업을 위해 초기화 시각 레이아웃을 416pt에서 350pt로 줄였습니다.
- 전체 287개 테스트 통과

## 개발 기록 94: Codex 기간 매핑 수정 및 상세 팝업 단순화

- **Codex 사용량 기간 매핑**: 로컬 Codex `rate_limits`를 `window_minutes`에 따라 분류합니다. 이제 10,080분짜리 기본 기간은 잘못된 5시간 행과 오래된 캐시 데이터로 표시되지 않고, 단일 7일 행으로 표시됩니다.
- **상세 팝업 레이아웃**: 초기화 시각이 한 줄에 유지되도록 상세 팝업 너비를 320pt에서 416pt로 늘리고, Buy Me a Coffee 버튼과 해당 설정 스위치를 제거했습니다.
- **회귀 테스트**: Codex의 기본 7일 기간만 있는 경우, 제거된 후원 버튼 상태, 상세 팝업 너비를 검증하는 범위를 추가했습니다.
- 전체 287개 테스트 통과

## 개발 기록 93: 정확한 5시간 초기화 시각 표시

- **5시간 초기화 시각**: 이제 `MetricRow`가 남은 시간 바로 앞에 현지 초기화 시각을 `MM/dd HH:mm` 형식으로 표시하므로, 남은 시간을 계산하지 않고도 Claude 5시간 세션을 확인할 수 있습니다.
- **선별 표시**: 시각은 `5h`로 표시된 행에서만 활성화되며, 주간 및 다른 서비스 기간은 기존 레이아웃을 유지합니다.
- **회귀 테스트**: 명시적인 시간대를 사용한 시각 형식 검증을 추가했습니다.
- 전체 287개 테스트 통과

## 개발 기록 92: 알림 전달과 사용자 지정 소리 재생 시점 맞춤

- **알림 순서 재구성**: 이제 `AgentNotifyNotificationService`가 `UNNotificationRequest`를 먼저 게시한 뒤 사용자 지정 소리를 재생합니다. 알림 센터 카드 생성과 소리 알림 사이의 시각 차이를 줄입니다.
- **사용자 지정 소리 사전 확인**: `NotifySoundManager.canPlay(for:service:)`를 추가해 알림 내용을 게시하기 전에 사용자 지정 경로(`sound=nil`)와 시스템 기본값(`.default`) 중 하나를 선택할 수 있게 했습니다.
- **재생 실패 처리 강화**: 이제 `NotifySoundManager.play()` 및 `playTest()`는 재생이 시작되었다고 가정하지 않고 `AVAudioPlayer.play()`의 성공 여부를 확인합니다. 시작에 실패하면 더 이상 성공으로 보고하지 않습니다.
- **대체 동작**: 사용자 지정 소리를 선택했지만 알림 전달 후 재생에 실패하면, 소리 없는 알림을 피하기 위해 서비스가 대체 알림음을 재생합니다.
- **추가한 테스트**:
  - `AgentNotifyNotificationServiceBehaviorTests.testPostPlaysCustomSoundAfterNotificationRequestAdded`
  - `AgentNotifyNotificationServiceBehaviorTests.testPostTriggersFallbackSoundWhenCustomPlaybackFails`
  - `NotifySoundManagerTests.testCanPlayReturnsTrueWhenCategoryHasExistingFile`
  - `NotifySoundManagerTests.testCanPlayReturnsFalseWhenCategoryFilesAreMissing`
  - `NotifySoundManagerTests.testPlayReturnsFalseWhenAudioFileCannotBeDecoded`
- `./scripts/test.sh` 통과

## 개발 기록 91: 이전 개발 기록 보관

- **DEVLOG 분리**: 개발 기록 1–69와 대체된 개발 기록 70–76을 `DEVLOG-archive.md`로 옮겼습니다. 현재 코드베이스 상태를 반영하는 개발 기록 70–91만 남겨 DEVLOG.md를 811줄에서 약 190줄로 줄였습니다.
- 전체 279개 테스트 통과

## 개발 기록 90: Cursor, Copilot, Gemini 사용량 지표 캐시

- **Cursor/Copilot (`cachedOrThrow`)**: API 실패(네트워크 오류, 401 등) 시 초기화 시각이 지나지 않았다면 UserDefaults에서 마지막으로 캐시한 UsageMetric을 반환합니다. 이전에는 모든 API 오류가 즉시 예외를 발생시켜 ViewModel이 0을 표시했습니다.
- **Gemini (`resolveMetric`)**: 현재 일일 기간에 로그 이벤트가 없으면 일일 초기화 시각까지 캐시된 0이 아닌 값을 우선합니다. Codex와 같은 방식입니다(개발 기록 89).
- **테스트 격리**: 이제 세 테스트 모음 모두 테스트별 `UserDefaults(suiteName:)`를 사용해 테스트 간 캐시 오염을 방지합니다.
- 전체 279개 테스트 통과

## 개발 기록 89: 유휴 세션에서도 Codex 사용량 캐시 유지

- **유휴 세션 캐시**: 이제 `CodexUsageProvider`는 마지막 0이 아닌 사용량 지표를 UserDefaults(`codexUsageCache.fiveHour`, `codexUsageCache.weekly`)에 캐시합니다. rate_limits 기간이 오래된 상태가 되면(활성 세션 없음), 초기화 시각이 지날 때까지 캐시 값을 보존합니다. 이는 Claude 제공자의 기존 방식과 같습니다(개발 기록 35–36).
- **resolveMetric()**: 기간 해석을 캐시 로직으로 감싸는 새 메서드입니다. 0이 아닌 결과를 저장하고, 캐시 초기화 시각이 아직 미래라면 0보다 캐시 값을 우선합니다.
- **테스트 격리**: 이제 `CodexUsageProviderTests`는 테스트별 `UserDefaults(suiteName:)`를 사용해 테스트 간 캐시 오염을 방지합니다.
- **새 테스트**: `testPrefersCachedUsageWhenWindowBecomesStale`, `testCacheExpiredWhenResetTimePasses`
- 전체 279개 테스트 통과

## 개발 기록 88: 앱 여러 개 실행 방지

- **단일 인스턴스 보호**: `AppDelegate.terminateIfAlreadyRunning()`이 같은 번들 식별자를 가진 다른 프로세스를 `NSRunningApplication`에서 확인하고, 발견하면 `NSApp.terminate(nil)`을 호출합니다.
- **안전한 테스트 동작**: `XCTestConfigurationFilePath` 환경 변수가 있으면 검사를 건너뜁니다. 테스트 호스트가 번들 식별자를 공유하기 때문입니다.
- 전체 277개 테스트 통과

## 개발 기록 87: DMG 배경에 실행 안내 추가

- **두 단계 안내**: DMG 배경의 단일 "Drag to Applications" 문구를 번호가 있는 "1. Drag AgentBar to Applications"와 "2. Open AgentBar to get started" 두 단계로 바꿨습니다.
- **스크립트 재구성**: `load_font()`와 `draw_centered_text()` 도우미를 분리했습니다. 시각적 위계를 위해 2단계는 약간 더 작은 글꼴과 더 흐린 알파 값을 사용합니다.
- 전체 277개 테스트 통과

## 개발 기록 86: create-dmg를 사용한 꾸며진 DMG 설치 프로그램

- **`scripts/generate-dmg-background.py`**: 청회색 그라데이션, 갈매기표 화살표, "Drag to Applications" 안내 문구가 있는 1200x800 레티나 배경을 생성하는 Python3 및 Pillow 스크립트입니다.
- **`docs/assets/dmg-background@2x.png`**: 여러 릴리스에서 재사용할 수 있도록 미리 생성해 커밋한 배경 이미지입니다.
- **`scripts/create-styled-dmg.sh`**: `create-dmg` 래퍼로 600x400 창, (150,200)의 앱 아이콘, (450,200)의 Applications 끌어놓기 링크, 볼륨 아이콘, 숨겨진 `.app` 확장자를 구성합니다.
- **`scripts/release.sh`**: 단순한 `hdiutil create` 호출을 `create-styled-dmg.sh` 호출로 교체하고 `create-dmg` 사전 요구 사항 검사를 추가했습니다.
- 전체 277개 테스트 통과

## 개발 기록 85: v0.5 이후 안정성 재구성(기록 및 키체인)

- **UsageHistoryStore**: 스냅숏과 추가 전용 로그(`usage-history.events.jsonl`) 구조로 전환
  - 기록할 때 전체 스냅숏을 다시 쓰는 대신 로그 추가
  - 불러올 때 로그 재생
  - 이벤트 수 및 파일 크기 임곗값을 기준으로 압축(정렬, 스냅숏 저장, 로그 제거)
  - 날짜 및 보조 자료 갱신 또는 삽입을 인덱스 맵 기반으로 최적화
- **UsageHistoryDayRecord**: `secondarySampleCount` 필드 추가
  - 보조 자료 평균 계산의 분모를 `sampleCount`에서 분리해 희석 오류 방지
  - 이전 버전 데이터 디코딩과의 호환성 유지
- **UsageHistoryViewModel**: `refreshGeneration`과 취소 가능한 단일 `refreshTask` 도입
  - 겹치는 새로고침 요청에서 오래된 결과 반영 차단
  - 보조 자료 히트맵의 표본 수에 `secondarySampleCount` 사용
- **KeychainManager**: 불러오기 결과를 `LoadOutcome(value, shouldCache)`로 분리
  - 일시적인 키체인 오류(`errSecInteractionNotAllowed` 등)는 캐시하지 않음
  - 안정된 상태(`errSecItemNotFound` 등)만 캐시
- **추가한 테스트**
  - `UsageHistoryStoreTests`: 보조 자료 평균의 분모 분리 검증
  - `UsageHistoryViewModelTests`: 새로고침이 겹칠 때 최신 세대 결과를 우선하는지 검증
  - `UsageViewModelTests`: 키체인 프로세스 내부 캐시의 안정 상태 및 일시 오류 캐시 정책 검증
- `./scripts/test.sh` 통과

## 개발 기록 84: 사용량이 0인 대체 표시에도 요금제 이름 표시

- **UsageViewModel.storedPlanName(for:)**: fetchUsage()가 실패해도 서비스 이름 옆에 요금제 표시가 계속 나타나도록 Claude, Codex, Cursor의 요금제 이름을 UserDefaults에서 읽습니다.
- 전체 273개 테스트 통과

## 개발 기록 83: Codex 색상을 에메랄드에서 회색으로 변경

- **ServiceType darkColor/lightColor**: Codex 색상을 emerald-500/300에서 gray-500/300(`0.42, 0.45, 0.49` / `0.71, 0.73, 0.76`)으로 변경했습니다.
- 수정한 테스트: `testCodexDarkColorIsGray500`
- 전체 273개 테스트 통과

## 개발 기록 82: 기록 탭의 보조 자료 보기에서 5h/7d 구조가 아닌 서비스 숨김

- **ServiceType.hasFiveHourSevenDayStructure**: `fiveHourLabel == "5h" && weeklyLabel == "7d"`인지 확인하는 계산 속성입니다. Claude와 Codex만 해당하며, MCP 월간 기간은 7일 주기와 비교할 수 없으므로 Z.ai(MCP)는 제외됩니다.
- **UsageHistoryViewModel**: `hasFiveHourSevenDayStructure`에 따라 서비스를 걸러내며, `selectedWindow == .secondary`일 때 적용합니다.
- **수정한 테스트**: `testNon5h7dServiceIsExcludedFromSecondaryWindow`에서 보조 자료 보기에 Z.ai 패널이 없는지 검증합니다.
- 전체 273개 테스트 통과

## 개발 기록 81: 영구 불러오기 캐시로 키체인 권한 대화 상자 제거

- **KeychainManager 불러오기 캐시**: 프로세스 내부 `[String: CachedValue]` 캐시를 `load(account:)`에 추가했습니다. 첫 호출만 Security 프레임워크를 사용하며 이후 모든 호출은 SecItemCopyMatching 호출 없이 캐시 결과를 반환합니다. `save()` 또는 `delete()`를 호출할 때만 무효화됩니다.
- **KeychainManager dataProtection 건너뛰기**: 임시 서명에서 `errSecMissingEntitlement`가 감지되면 이후 호출은 dataProtection 저장소 질의를 완전히 건너뜁니다.
- 전체 273개 테스트 통과

## 개발 기록 80: 기록 가독성 개선 및 일일 추세선 추가

- 저장된 일일 최고 사용량 값을 이용하는 서비스별 `Daily Usage Trend` 꺾은선 차트를 히트맵 오른쪽에 추가했습니다.
- 날짜별 기록 저장을 확장해 최고 및 평균 `used` 값과 관련 단위 메타데이터를 보존합니다.
- 기록 탭 상단에 타일의 의미를 설명하는 안내 문구를 추가했습니다.
  - Daily Heatmap: `1 tile = 1 day`(왼쪽에 요일 눈금 표시)
  - 7d Cycle Consistency: `1 tile = 1 reset cycle`
- 주기 영역 제목에 타일의 의미를 명시했습니다.
- 계획 문서에 안내 문구 요구 사항을 추가했습니다.
- 빌드 및 테스트 통과

## 개발 기록 79: 기록 탭 개선 - 모든 서비스 보기 및 정렬

- 설정에서 `History` 탭을 가장 오른쪽으로 옮겼습니다(`Usage` -> `Notifications` -> `History`).
- `UsageHistoryViewModel`을 단일 서비스 상태에서 모든 서비스 패널을 관리하는 구조로 재구성했습니다.
  - `UsageHistoryServicePanel` 추가
  - 한 번의 새로고침으로 이용 가능한 모든 서비스의 패널 데이터 계산
  - 사용 빈도(활성 날짜)를 기준으로 패널 내림차순 정렬
  - 동률이면 일일 평균 최고 사용량, 안정적인 서비스 순서 차례로 비교
- `UsageHistoryTabView` 수정
  - 서비스 드롭다운 제거
  - 모든 서비스를 한 화면에 표시(서비스 영역을 세로로 쌓음)
  - 전체 기간 및 범위 조작 요소 유지
  - 서비스별 일일 히트맵 요약과 조건부 7일 주기 일관성 블록 유지
- `UsageHistoryViewModelTests`를 새 다중 패널 API에 맞게 수정하고 빈도 정렬 테스트를 추가했습니다.
- `docs/USAGE_HISTORY_IMPLEMENTATION_PLAN.md`를 사용자 화면 동작에 맞게 수정했습니다(모든 서비스, 빈도순, 가장 오른쪽의 History 탭).
- 빌드 및 테스트 통과

## 개발 기록 78: xctestplan을 사용한 테스트 실행 최적화

- **AgentBar.xctestplan(Fast)**: 느린 통합 테스트 클래스 3개(NotifySocketListenerLifecycleTests, HookScriptFallbackTests, AgentNotifyMonitorSocketReceiveTests)를 제외합니다. 병렬 실행을 활성화했습니다. 테스트 249개, 약 15초입니다.
- **AgentBarFull.xctestplan(Full)**: 전체 267개 테스트를 병렬로 실행합니다. 약 22초이며 커밋 전 검증용입니다.
- **공유 xcscheme**: Fast 계획을 기본값으로, Full 계획을 대안으로 연결하는 AgentBar.xcscheme을 만들었습니다.
- **CLAUDE.md 수정**: Build & Run 영역에 빠른, 전체, 단일 클래스 테스트 명령을 추가했습니다.
- **TEST_HOST 유지**: 테스트가 `@testable import AgentBar`를 사용하므로 TEST_HOST/BUNDLE_LOADER를 제거하면 링커 오류가 발생했습니다. 앱이 호스트하는 테스트 방식을 유지했으며, 속도 개선은 병렬화와 느린 테스트 제외에서 얻었습니다.
- 전체 267개 테스트 통과

## 개발 기록 77: 사용 기록 6단계 - 빌드 및 실행 인계

- `xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet` 명령으로 디버그 앱을 다시 빌드했습니다.
- 실행 인계를 시도했습니다.
  - 기존 AgentBar 프로세스 종료(`pkill -x AgentBar`)
  - 앱 번들 다시 실행 시도(`open build/Build/Products/Debug/AgentBar.app`)
- 이 실행 환경에서는 `open`이 LaunchServices 오류 `-600`을 반환하고 바이너리 직접 실행도 즉시 종료되었으므로, 에이전트 쪽에서 사용자 화면의 지속 실행을 검증할 수 없었습니다.
- 로컬 검증용 빌드 결과물 경로를 전달했습니다: `build/Build/Products/Debug/AgentBar.app`

## 개발 기록 76: 사용 기록 5단계 - 테스트 범위

- `UsageHistoryStoreTests` 추가:
  - 날짜 기록의 최고 및 평균 집계
  - 보조 자료의 5분 구간 갱신 또는 삽입 동작
  - 보존 기간에 따른 정리(날짜 및 표본 기간)
  - 저장 후 불러오기 왕복
  - 손상된 저장소 백업 및 초기화
- `UsageHistoryViewModelTests` 추가:
  - 히트맵 셀 수와 단계 매핑
  - 일일 요약 계산
  - 7일 주기 묶기 및 요약 지표
  - 7일 주기가 아닌 패널의 비활성화 동작
- `UsageViewModelTests` 수정:
  - 성공한 제공자 결과만 기록에 저장하는지 검증
  - 모든 제공자가 실패했을 때 기록을 쓰지 않는지 검증
- `SettingsViewBehaviorTests`에 `SettingsTab.history` 검증 범위를 추가했습니다.
- `./scripts/test.sh`를 통해 테스트 모음 통과

## 개발 기록 75: 사용 기록 4단계 - 설정의 History 탭과 사용자 화면

- `UsageHistoryTabView`를 `AgentBar/Views/Settings/UsageHistoryTabView.swift`에 추가했습니다.
- `History` 탭을 `SettingsView`에 추가하고 서비스, 기간, 범위 조작 요소를 배치했습니다.
- 도구 설명, 범례, 요약 카드가 있는 기여도 형태의 `Daily Heatmap` 격자를 구현했습니다.
- 주기 막대와 요약 지표가 있는 조건부 `7d Cycle Consistency` 영역을 구현했습니다.
- 기록이 없거나 7일 주기 데이터가 충분하지 않을 때의 빈 상태를 추가했습니다.
- 빌드 통과

## 개발 기록 74: 사용 기록 3단계 - 기록 뷰 모델과 주기 분석

- `UsageHistoryViewModel`을 `AgentBar/ViewModels/UsageHistoryViewModel.swift`에 추가했습니다.
- 일일 히트맵 데이터 생성(`7 x weeks`)과 일일 요약 지표를 구현했습니다.
- 7일 일관성 분석을 위해 보조 표본 주기를 `resetAt` 기준으로 묶도록 구현했습니다.
- 주기 지표를 추가했습니다.
  - 완료율
  - 80% 및 100%에 도달하는 데 걸린 날짜 수
  - 높은 사용률 구간 시간(`>=80%`, 구간 상한 적용)
  - 현재 연속 완료 횟수
- 기록 새로고침을 `Notification.Name.usageHistoryChanged`에 연결했습니다.
- 빌드 통과

## 개발 기록 73: 사용 기록 2단계 - 조회 흐름 연동

- 이제 `UsageViewModel`이 의존성 주입을 위한 `historyStore: UsageHistoryStoreProtocol`을 받습니다.
- 이제 `fetchAllUsage()`가 제공자의 성공 및 실패 결과를 별도로 추적합니다.
- 성공한 조회 결과만 `historyStore.record(samples:recordedAt:)`를 통해 기록에 저장합니다.
- 실패 시 대신 표시하는 행(`zeroUsageData`)은 사용자 화면에 계속 보이지만 기록에는 저장하지 않습니다.
- 기록을 성공적으로 쓴 뒤 `Notification.Name.usageHistoryChanged` 알림을 보내도록 추가했습니다.
- 새로 추가한 기록 소스 파일을 빌드에 포함하도록 `xcodegen generate`로 Xcode 프로젝트를 다시 생성했습니다.
- 빌드 통과

## 개발 기록 72: 사용 기록 1단계 - 모델과 영구 저장소

- `UsageHistory` 모델을 `AgentBar/Models/UsageHistory.swift`에 추가:
  - `UsageHistoryDayRecord`
  - `UsageHistorySecondarySample`
  - `UsageHistoryStoreFile`(schema v2)
  - `UsageHistoryWindow`
- `UsageHistoryStore` 액터를 `AgentBar/Infrastructure/UsageHistoryStore.swift`에 추가하고 `UsageHistoryStoreProtocol`을 따르게 했습니다.
- `~/Library/Application Support/AgentBar/usage-history.json`에 영구 기록 저장소를 구현했습니다.
- 날짜 단위 집계, 보조 표본 수집, 보존 기간에 따른 정리, 원자적 JSON 쓰기를 구현했습니다.
- 손상된 파일 복구와 이전 schema v1에서 옮기는 경로를 추가했습니다.
- 빌드 통과

## 개발 기록 71: 유효한 캐시가 있어도 API 실패 시 Claude 7d 행이 사라지는 문제 수정

- **원인**: `fetchUsage()`가 예외를 발생시키면(예: 밤사이 OAuth 토큰 만료) `UsageViewModel.zeroUsageData()`가 `weeklyUsage: nil`을 반환했습니다. 이 때문에 캐시된 7일 데이터가 아직 유효해도(초기화 시각이 지나지 않음) 7d 행 전체가 숨겨졌습니다.
- **API 실패 시 캐시로 대체**: `cachedOrThrow(_:)`를 `ClaudeUsageProvider`에 추가했습니다. 모든 API 오류(401, 네트워크 등)에서 예외를 발생시키기 전에 UserDefaults 캐시를 확인합니다. 캐시된 기간 중 하나 이상(5h 또는 7d)의 유효한 초기화 시각이 아직 미래라면 예외 대신 캐시 값을 반환합니다.
- **동작**: 잠자기 이후 5h가 초기화되면 0%를 표시합니다. 7d가 여전히 유효하면 캐시된 비율을 표시합니다. 두 기간이 모두 만료되고 API도 실패하면 이전처럼 예외를 발생시킵니다.
- **추가한 테스트**: `testFallsBackToCacheOnAPIFailureWhenSevenDayCacheValid`(유효한 7d 캐시가 있는 401), `testFallsBackToCacheOnMissingCredentials`(유효한 7d 캐시가 있는 nil 토큰)
- 전체 227개 테스트 통과

## 개발 기록 70: 자산 카탈로그에 앱 아이콘 추가 및 README 수정

- **AppIcon 자산 카탈로그**: 모든 macOS 아이콘 크기(16–512@2x)가 있는 `Assets.xcassets/AppIcon.appiconset`을 만들고, 앱 번들에 아이콘이 포함되도록 Xcode 프로젝트에 PBXResourcesBuildPhase를 추가했습니다.
- **README.md**: 더 깔끔한 서비스 표, 기능 목록, 설치 및 빌드 영역으로 v0.4 기능 구성에 맞게 단순화했습니다.
- 전체 225개 테스트 통과
