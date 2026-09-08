# AgentBar Development Log

> Iterations 1–69 archived in [DEVLOG-archive.md](DEVLOG-archive.md).

## Iteration 95: Tune popover width
- **Popover width**: Reduced the reset-timestamp layout from 416pt to 350pt for a more compact menu bar popover.
- All 287 tests passing

## Iteration 94: Correct Codex window mapping and simplify the popover
- **Codex rate-window mapping**: Classifies local Codex `rate_limits` by `window_minutes`; a 10,080-minute primary window now displays as the sole 7-day row instead of an incorrect 5-hour row plus stale cached data.
- **Popover layout**: Increased the popover width from 320pt to 416pt so reset timestamps remain on one line, and removed the Buy Me a Coffee button and its Settings toggle.
- **Regression tests**: Added coverage for a Codex primary-only 7-day window, removed-support-button state, and popover width.
- All 287 tests passing

## Iteration 93: Show the exact 5-hour reset time
- **5-hour reset timestamp**: `MetricRow` now shows the local reset time as `MM/dd HH:mm` immediately before the remaining duration, so the Claude 5-hour session can be read without calculating from the countdown.
- **Focused display**: The timestamp is enabled only for rows labeled `5h`; weekly and other service windows retain their current layout.
- **Regression test**: Added coverage for the timestamp format with an explicit time zone.
- All 287 tests passing

## Iteration 92: Align notification delivery and custom sound playback
- **Notification ordering refactor**: `AgentNotifyNotificationService` now posts `UNNotificationRequest` first, then plays custom sound. This reduces timing skew between Notification Center card creation and audible feedback.
- **Custom sound preflight**: Added `NotifySoundManager.canPlay(for:service:)` so notification content can choose between custom path (`sound=nil`) and system default (`.default`) before posting.
- **Playback failure hardening**: `NotifySoundManager.play()` / `playTest()` now verify `AVAudioPlayer.play()` success instead of assuming playback started; failed starts no longer report success.
- **Fallback behavior**: When custom sound is selected but fails to start after notification delivery, service now plays a fallback alert tone to avoid silent notifications.
- **Tests added**:
  - `AgentNotifyNotificationServiceBehaviorTests.testPostPlaysCustomSoundAfterNotificationRequestAdded`
  - `AgentNotifyNotificationServiceBehaviorTests.testPostTriggersFallbackSoundWhenCustomPlaybackFails`
  - `NotifySoundManagerTests.testCanPlayReturnsTrueWhenCategoryHasExistingFile`
  - `NotifySoundManagerTests.testCanPlayReturnsFalseWhenCategoryFilesAreMissing`
  - `NotifySoundManagerTests.testPlayReturnsFalseWhenAudioFileCannotBeDecoded`
- `./scripts/test.sh` 통과

## Iteration 91: Archive old DEVLOG iterations
- **DEVLOG split**: Moved iterations 1–69 (plus superseded 70–76) to `DEVLOG-archive.md`. DEVLOG.md reduced from 811 to ~190 lines, keeping only iterations 70–91 which reflect the current codebase state.
- All 279 tests passing

## Iteration 90: Cache usage metrics for Cursor, Copilot, Gemini
- **Cursor/Copilot (`cachedOrThrow`)**: On API failure (network error, 401, etc.), returns last cached UsageMetric from UserDefaults if reset time hasn't passed. Previously, any API error immediately threw and ViewModel showed zero.
- **Gemini (`resolveMetric`)**: When no log events found in current daily window, prefers cached non-zero value until daily reset passes. Same pattern as Codex (Iteration 89).
- **Test isolation**: All three test suites now use per-test `UserDefaults(suiteName:)` to prevent cross-test cache pollution.
- All 279 tests passing

## Iteration 89: Cache Codex usage across idle sessions
- **Idle-session cache**: `CodexUsageProvider` now caches last non-zero usage metrics in UserDefaults (`codexUsageCache.fiveHour`, `codexUsageCache.weekly`). When rate_limits window becomes stale (no active session), cached values are preserved until reset time passes — matching Claude provider's existing pattern (Iteration 35-36)
- **resolveMetric()**: New method wraps window resolution with cache logic: save non-zero results, prefer cached over zero when cache reset time is still in the future
- **Test isolation**: `CodexUsageProviderTests` now uses per-test `UserDefaults(suiteName:)` to prevent cross-test cache pollution
- **New tests**: `testPrefersCachedUsageWhenWindowBecomesStale`, `testCacheExpiredWhenResetTimePasses`
- All 279 tests passing

## Iteration 88: Prevent multiple app instances
- **Single-instance guard**: `AppDelegate.terminateIfAlreadyRunning()` checks `NSRunningApplication` for other processes with the same bundle ID and calls `NSApp.terminate(nil)` if found
- **Test-safe**: Skips the check when `XCTestConfigurationFilePath` environment variable is present (test host shares bundle ID)
- All 277 tests passing

## Iteration 87: Add launch nudge to DMG background
- **Two-step guide**: Updated DMG background from single "Drag to Applications" to numbered steps: "1. Drag AgentBar to Applications" + "2. Open AgentBar to get started"
- **Script refactored**: Extracted `load_font()` and `draw_centered_text()` helpers; step 2 uses slightly smaller font and dimmer alpha for visual hierarchy
- All 277 tests passing

## Iteration 86: Styled DMG installer with create-dmg
- **`scripts/generate-dmg-background.py`**: Python3+Pillow script generating 1200x800 Retina background with slate gradient, chevron arrow, and "Drag to Applications" hint text
- **`docs/assets/dmg-background@2x.png`**: Pre-generated background image committed for reuse across releases
- **`scripts/create-styled-dmg.sh`**: `create-dmg` wrapper with 600x400 window, app icon at (150,200), Applications drop link at (450,200), volume icon, and hidden `.app` extension
- **`scripts/release.sh`**: Replaced bare `hdiutil create` with `create-styled-dmg.sh` call; added `create-dmg` prerequisite check
- All 277 tests passing

## Iteration 85: Post-v0.5 reliability refactor (history + keychain)
- **UsageHistoryStore**: snapshot + append-log(`usage-history.events.jsonl`) 구조로 전환
  - 기록 시 전체 snapshot rewrite 대신 log append
  - load 시 log replay
  - 이벤트 수/파일 크기 임계치 기반 compact(정렬 + snapshot 저장 + log 제거)
  - day/secondary upsert를 index map 기반으로 최적화
- **UsageHistoryDayRecord**: `secondarySampleCount` 필드 추가
  - secondary 평균 계산 분모를 `sampleCount`에서 분리해 희석 오류 방지
  - 구버전 데이터 디코딩 하위호환 유지
- **UsageHistoryViewModel**: `refreshGeneration` + 취소 가능한 단일 `refreshTask` 도입
  - 겹치는 refresh 요청에서 stale 결과 반영 차단
  - secondary 히트맵의 sample count는 `secondarySampleCount` 사용
- **KeychainManager**: load 결과를 `LoadOutcome(value, shouldCache)`로 분리
  - transient Keychain 오류(`errSecInteractionNotAllowed` 등)는 캐시하지 않음
  - 안정 상태(`errSecItemNotFound` 등)만 캐시
- **테스트 추가**
  - `UsageHistoryStoreTests`: secondary 평균 분모 분리 검증
  - `UsageHistoryViewModelTests`: refresh overlap 시 최신 generation 우선 반영 검증
  - `UsageViewModelTests`: Keychain in-process cache의 안정/일시 오류 캐시 정책 검증
- `./scripts/test.sh` 통과

## Iteration 84: Show plan name in zero-usage fallback
- **UsageViewModel.storedPlanName(for:)**: Read plan name from UserDefaults for Claude/Codex/Cursor when fetchUsage() fails, so the plan label still appears next to the service name
- All 273 tests passing

## Iteration 83: Change Codex color from emerald to gray
- **ServiceType darkColor/lightColor**: Codex changed from emerald-500/300 to gray-500/300 (`0.42, 0.45, 0.49` / `0.71, 0.73, 0.76`)
- Test updated: `testCodexDarkColorIsGray500`
- All 273 tests passing

## Iteration 82: Hide non-5h/7d services from Secondary in History tab
- **ServiceType.hasFiveHourSevenDayStructure**: Computed property checking `fiveHourLabel == "5h" && weeklyLabel == "7d"` — only Claude and Codex qualify; Z.ai (MCP) is excluded because MCP monthly is not comparable to 7d cycles
- **UsageHistoryViewModel**: Filter services by `hasFiveHourSevenDayStructure` when `selectedWindow == .secondary`
- **Test updated**: `testNon5h7dServiceIsExcludedFromSecondaryWindow` verifies Z.ai panel is absent in secondary view
- All 273 tests passing

## Iteration 81: Eliminate Keychain permission dialogs via permanent load cache
- **KeychainManager load cache**: Added in-process `[String: CachedValue]` cache to `load(account:)` — first call hits Security framework, all subsequent calls return cached result with zero SecItemCopyMatching calls. Invalidated by `save()`/`delete()` only
- **KeychainManager dataProtection skip**: When `errSecMissingEntitlement` is detected (ad-hoc signing), subsequent calls skip the dataProtection store query entirely
- All 273 tests passing

## Iteration 80: History readability update + daily trend line
- Added per-service `Daily Usage Trend` line chart to the right side of the heatmap using stored daily peak usage values
- Extended day history persistence to keep peak/average `used` values and corresponding unit metadata
- Added top guide text in History tab clarifying tile semantics:
  - Daily Heatmap: `1 tile = 1 day` (weekday ticks on the left)
  - 7d Cycle Consistency: `1 tile = 1 reset cycle`
- Updated cycle section title to explicitly include tile meaning
- Updated plan document to include guide text requirement
- Build and tests pass

## Iteration 79: History tab refinement - all services view and ordering
- Moved `History` tab to the rightmost position in Settings (`Usage` -> `Notifications` -> `History`)
- Reworked `UsageHistoryViewModel` from single-service state to all-service panels
  - added `UsageHistoryServicePanel`
  - computes panel data for every available service in one refresh
  - sorts panels by usage frequency (active days) descending
  - tie-breakers: average daily peak, then stable service order
- Updated `UsageHistoryTabView`
  - removed service dropdown
  - renders all services in one screen (service sections stacked vertically)
  - keeps global window/range controls
  - keeps per-service daily heatmap summary and conditional 7d cycle consistency block
- Updated `UsageHistoryViewModelTests` to new multi-panel API and added frequency ordering test
- Updated `docs/USAGE_HISTORY_IMPLEMENTATION_PLAN.md` to match UI behavior (all services + frequency order + rightmost History tab)
- Build and tests pass

## Iteration 78: Test execution optimization with xctestplan
- **AgentBar.xctestplan (Fast)**: Excludes 3 slow integration test classes (NotifySocketListenerLifecycleTests, HookScriptFallbackTests, AgentNotifyMonitorSocketReceiveTests). Parallel execution enabled. 249 tests, ~15s.
- **AgentBarFull.xctestplan (Full)**: All 267 tests with parallel execution. ~22s. For pre-commit validation.
- **Shared xcscheme**: Created AgentBar.xcscheme linking Fast plan as default, Full plan as alternate.
- **CLAUDE.md updated**: Added fast/full/single-class test commands to Build & Run section.
- **TEST_HOST kept**: Removing TEST_HOST/BUNDLE_LOADER caused linker errors since tests use `@testable import AgentBar`. Kept app-hosted testing; speedup comes from parallelism and slow test exclusion.
- All 267 tests passing

## Iteration 77: Usage History Step 6 - build and runtime handoff
- Rebuilt debug app with `xcodebuild build -project AgentBar.xcodeproj -scheme AgentBar -configuration Debug -derivedDataPath build -quiet`
- Attempted runtime handoff:
  - terminated existing AgentBar process (`pkill -x AgentBar`)
  - attempted to relaunch app bundle (`open build/Build/Products/Debug/AgentBar.app`)
- In this execution environment, `open` returned LaunchServices error `-600` and direct binary launch exited immediately, so persistent UI runtime verification could not be completed from the agent side
- Delivered build artifact path for local verification: `build/Build/Products/Debug/AgentBar.app`

## Iteration 76: Usage History Step 5 - test coverage
- Added `UsageHistoryStoreTests`:
  - day record peak/average aggregation
  - secondary 5-minute bucket upsert behavior
  - retention pruning (day + sample windows)
  - persistence round-trip
  - corrupt store backup and reset
- Added `UsageHistoryViewModelTests`:
  - heatmap cell count and level mapping
  - daily summary calculation
  - 7d cycle grouping and summary metrics
  - non-7d cycle panel disable behavior
- Updated `UsageViewModelTests`:
  - verifies history records only successful provider results
  - verifies no history write when all providers fail
- Updated `SettingsViewBehaviorTests` with `SettingsTab.history` coverage
- Test suite passes via `./scripts/test.sh`

## Iteration 75: Usage History Step 4 - Settings History tab and UI
- Added `UsageHistoryTabView` in `AgentBar/Views/Settings/UsageHistoryTabView.swift`
- Added `History` tab in `SettingsView` with service/window/range controls
- Implemented `Daily Heatmap` contribution-style grid with tooltip + legend + summary cards
- Implemented conditional `7d Cycle Consistency` section with cycle strip and summary metrics
- Added empty states for no history and insufficient 7d cycle data
- Build passes

## Iteration 74: Usage History Step 3 - History view model and cycle analytics
- Added `UsageHistoryViewModel` in `AgentBar/ViewModels/UsageHistoryViewModel.swift`
- Implemented daily heatmap data generation (`7 x weeks`) and daily summary metrics
- Implemented secondary sample cycle grouping by `resetAt` for 7d consistency analysis
- Added cycle metrics:
  - completion rate
  - days to 80% / 100%
  - high-band hours (`>=80%`, capped segment)
  - current completion streak
- Wired history refresh to `Notification.Name.usageHistoryChanged`
- Build passes

## Iteration 73: Usage History Step 2 - fetch pipeline integration
- `UsageViewModel` now accepts `historyStore: UsageHistoryStoreProtocol` for dependency injection
- `fetchAllUsage()` now tracks provider outcomes as success/failure separately
- Only successful fetch results are recorded to history via `historyStore.record(samples:recordedAt:)`
- Failure fallback rows (`zeroUsageData`) remain visible in UI but are excluded from history recording
- Added `Notification.Name.usageHistoryChanged` broadcast after successful history writes
- Regenerated Xcode project with `xcodegen generate` to include newly added history source files in build
- Build passes

## Iteration 72: Usage History Step 1 - Models and persistent store
- Added `UsageHistory` models in `AgentBar/Models/UsageHistory.swift`:
  - `UsageHistoryDayRecord`
  - `UsageHistorySecondarySample`
  - `UsageHistoryStoreFile` (schema v2)
  - `UsageHistoryWindow`
- Added `UsageHistoryStore` actor in `AgentBar/Infrastructure/UsageHistoryStore.swift` with `UsageHistoryStoreProtocol`
- Implemented persisted history storage at `~/Library/Application Support/AgentBar/usage-history.json`
- Implemented day-level aggregation, secondary sample collection, retention pruning, and atomic JSON writes
- Added corrupt file recovery and legacy schema v1 migration path
- Build passes

## Iteration 71: Fix Claude 7d row disappearing on API failure with valid cache
- **Root cause**: When `fetchUsage()` threw (e.g. OAuth token expired overnight), `UsageViewModel.zeroUsageData()` returned `weeklyUsage: nil`, hiding the 7d row entirely even though cached 7d data was still valid (reset time not yet passed)
- **Cache fallback on API failure**: Added `cachedOrThrow(_:)` to `ClaudeUsageProvider` — on any API error (401, network, etc.), checks UserDefaults cache before throwing. If at least one cached window (5h or 7d) has a valid reset time still in the future, returns cached values instead of throwing
- **Behavior**: 5h resets after sleep → shows 0%. 7d still valid → shows cached %. Both windows expired + API failing → throws as before
- **Tests added**: `testFallsBackToCacheOnAPIFailureWhenSevenDayCacheValid` (401 with valid 7d cache), `testFallsBackToCacheOnMissingCredentials` (nil token with valid 7d cache)
- All 227 tests passing

## Iteration 70: Add app icon to Asset Catalog + update README
- **AppIcon asset catalog**: Created `Assets.xcassets/AppIcon.appiconset` with all macOS icon sizes (16–512@2x), added PBXResourcesBuildPhase to Xcode project so the icon is included in the app bundle
- **README.md**: Simplified to match v0.4 feature set — cleaner service table, feature list, install/build sections
- All 225 tests passing
