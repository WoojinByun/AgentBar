# 사용량 기록 구현 계획(7일 주기별 소진율 포함)

## 1. 목적

설정의 `History`(사용량 기록) 탭에서 다음을 동시에 제공한다.

1. 일별 사용 강도 시각화(`Daily Heatmap`, 일별 히트맵)
2. 7일 한도를 매 주기 얼마나 꾸준히 소진하는지 표시(`7d Cycle Consistency`, 7일 주기별 소진율)

핵심 판단 질문:

- 최근 기간 동안 매일 얼마나 사용했는가
- 7일 한도를 각 주기마다 얼마나 꾸준히 소진했는가

## 2. 범위

포함:

- 일 단위 히트맵 (기존 방향 유지)
- 7일 주기를 나열한 타일과 지표(새로운 핵심 기능)
- 사용량 기록 저장소(일별 집계 + `secondary` 샘플)
- 서비스·한도 구간·조회 기간 선택 UI
- 단위 테스트 + 기존 테스트 보강

제외:

- 과거 로그로 누락된 기록 채우기
- CSV 내보내기
- 메뉴 막대 및 상세 팝업에 사용량 기록 표시

## 3. 한도 구간 규칙

사용량 기록은 `UsageData`의 공통 구조를 기준으로 동작한다.

- `primary`: `UsageData.fiveHourUsage`
- `secondary`: `UsageData.weeklyUsage` (없으면 미지원)

7일 주기별 소진율 패널은 아래 조건에서만 활성화한다.

- 선택한 한도 구간이 `secondary`
- 선택 서비스의 `weeklyLabel == "7d"`

즉, Claude/Codex에서만 7일 주기 패널을 표시한다.

## 4. 데이터 모델

신규 파일: `AgentBar/Models/UsageHistory.swift`

```swift
import Foundation

struct UsageHistoryDayRecord: Codable, Sendable, Equatable {
    let service: ServiceType
    let dayStart: Date
    var primaryPeakRatio: Double
    var primaryAverageRatio: Double
    var secondaryPeakRatio: Double?
    var secondaryAverageRatio: Double?
    var sampleCount: Int
    var lastSampleAt: Date
}

// 7d 사이클 분석용 secondary 시계열 샘플
struct UsageHistorySecondarySample: Codable, Sendable, Equatable {
    let service: ServiceType
    let sampledAt: Date
    let ratio: Double        // 0...1
    let resetAt: Date        // secondary resetTime
}

struct UsageHistoryStoreFile: Codable, Sendable {
    var schemaVersion: Int
    var dayRecords: [UsageHistoryDayRecord]
    var secondarySamples: [UsageHistorySecondarySample]
}

enum UsageHistoryWindow: String, CaseIterable, Sendable {
    case primary
    case secondary
}
```

정규화 규칙:

- `ratio`는 항상 `0...1` 범위로 제한한다.
- `resetAt`은 초 단위 오차를 없애기 위해 분 단위 미만을 버린 뒤 저장한다.

## 5. 저장소 설계

신규 파일: `AgentBar/Infrastructure/UsageHistoryStore.swift`

타입:

- `protocol UsageHistoryStoreProtocol: Sendable`
- `actor UsageHistoryStore: UsageHistoryStoreProtocol`

필수 API:

```swift
protocol UsageHistoryStoreProtocol: Sendable {
    func record(samples: [UsageData], recordedAt: Date) async
    func dayRecords(for service: ServiceType, since: Date, until: Date) async -> [UsageHistoryDayRecord]
    func secondarySamples(for service: ServiceType, since: Date, until: Date) async -> [UsageHistorySecondarySample]
    func availableServices(since: Date, until: Date) async -> [ServiceType]
}
```

저장 경로:

- `~/Library/Application Support/AgentBar/usage-history.json`

내부 정책:

- `schemaVersion = 2`
- `dayRecords` 보관 기간: 365일
- `secondarySamples` 보관 기간: 120일
- 저장은 `.atomic` 옵션으로 원자적으로 수행한다.
- 디코딩 실패 시 기존 파일을 `usage-history.corrupt-<unix>.json`으로 옮기고 빈 저장소로 초기화한다.

샘플 기록 정책 (`record(samples:recordedAt:)`):

1. 일 집계(`UsageHistoryDayRecord`) 갱신
2. `weeklyUsage?.resetTime`이 있는 샘플만 `UsageHistorySecondarySample` 저장
3. `secondary` 샘플은 5분 단위 묶음에 추가하거나 기존 항목을 갱신해 저장 크기를 제한한다.
   - 버킷 키: `(service, floor(sampledAt to 5min), resetAt)`
   - 동일 버킷 충돌 시 `ratio`가 큰 샘플 유지
4. 보관 기간이 지난 데이터를 정리한 뒤 파일을 저장한다.

## 6. 수집 파이프라인 변경

수정 파일: `AgentBar/ViewModels/UsageViewModel.swift`

변경 사항:

1. 초기화 메서드에 `historyStore: UsageHistoryStoreProtocol`을 주입한다.
2. 제공자의 조회 결과를 `success`와 `failure`로 나누어 추적한다.
3. `success` 결과만 사용량 기록에 저장한다.
4. `failure`는 기존처럼 사용량 0인 대체 행을 표시하되 사용량 기록에는 저장하지 않는다.
5. 기록 완료 후 `Notification.Name.usageHistoryChanged` 발행

신규 알림:

- `AgentBar/Views/Settings/SettingsView.swift`의 `Notification.Name` 확장에 추가한다.
- `static let usageHistoryChanged = Notification.Name("AgentBarUsageHistoryChanged")`

## 7. 뷰 모델 설계

신규 파일: `AgentBar/ViewModels/UsageHistoryViewModel.swift`

### 7.1 상태

- `@Published var selectedService: ServiceType?`
- `@Published var selectedWindow: UsageHistoryWindow = .primary`
- `@Published var selectedRangeWeeks: Int = 8` (`4`, `8`, `12`)
- `@Published var heatmapCells: [UsageHistoryHeatmapCell]`
- `@Published var dailySummary: UsageHistorySummary`
- `@Published var cycleSummary: UsageHistoryCycleSummary`
- `@Published var cycleCells: [UsageHistoryCycleCell]`
- `@Published var isSevenDayCycleAvailable: Bool`

### 7.2 보조 모델

```swift
struct UsageHistoryHeatmapCell: Identifiable, Sendable {
    let id: String
    let date: Date
    let ratio: Double
    let level: Int      // 0...4
    let sampleCount: Int
    let peakRatio: Double
    let averageRatio: Double
}

struct UsageHistorySummary: Sendable, Equatable {
    let limitHitDays: Int
    let nearLimitDays: Int
    let averageDailyPeakRatio: Double
    let lastHitDate: Date?
}

struct UsageHistoryCycleCell: Identifiable, Sendable {
    let id: String
    let cycleStart: Date
    let cycleEnd: Date
    let peakRatio: Double
    let level: Int      // 0...4
    let reached80: Bool
    let reached100: Bool
    let daysTo80: Int?
    let daysTo100: Int?
    let highBandHours: Double
}

struct UsageHistoryCycleSummary: Sendable, Equatable {
    let completedCycles: Int
    let totalClosedCycles: Int
    let completionRate: Double       // 0...1
    let averageDaysTo80: Double?
    let averageDaysTo100: Double?
    let averageHighBandHours: Double
    let currentCompletionStreak: Int
}
```

### 7.3 일별 히트맵 계산

- 7행(일~토), N열(선택 주수)
- 현재 날짜 포함 최근 N주 고정 길이
- 데이터가 없는 날짜는 `ratio=0`으로 처리한다.
- 레벨 매핑:
  - `0`: `ratio == 0`
  - `1`: `0 < ratio <= 0.25`
  - `2`: `0.25 < ratio <= 0.5`
  - `3`: `0.5 < ratio <= 0.75`
  - `4`: `0.75 < ratio <= 1.0`

### 7.4 7일 주기 계산

입력:

- `secondarySamples`(서비스 패널 단위)

사이클 그룹 키:

- `resetAt`(분 단위 미만을 버린 값)

사이클 정의:

- 같은 `resetAt`을 가진 샘플 집합 = 하나의 사이클
- `cycleEnd = resetAt`
- `cycleStart = 이전 cycleEnd` (첫 사이클은 `min(sampledAt)` 사용)
- 종료된 주기(`closed cycle`): `cycleEnd <= now`

사이클 지표:

- `peakRatio = max(ratio)`
- `reached80 = peakRatio >= 0.8`
- `reached100 = peakRatio >= 1.0`
- `daysTo80`: `ratio >= 0.8`인 첫 샘플이 `cycleStart`로부터 며칠 뒤에 기록되었는지
- `daysTo100`: `ratio >= 1.0`인 첫 샘플이 `cycleStart`로부터 며칠 뒤에 기록되었는지
- `highBandHours`:
  - 샘플 정렬 후 인접 샘플 간 구간 합
  - 이전 샘플의 `ratio`가 `>=0.8`인 구간만 합산
  - 과대 추정을 막기 위해 한 구간은 최대 30분까지만 반영

사이클 요약:

- `completedCycles`: 종료된 주기 중 `reached100`을 달성한 개수
- `completionRate = completedCycles / totalClosedCycles`
- `averageDaysTo80`, `averageDaysTo100`: 값이 있는 주기들의 평균
- `averageHighBandHours`: 종료된 주기들의 평균
- `currentCompletionStreak`: 가장 최근에 종료된 주기부터 연속으로 `reached100`을 달성한 개수

표시 개수:

- 최근 종료된 12개 주기를 `cycleCells`로 표시

## 8. UI 설계

신규 파일: `AgentBar/Views/Settings/UsageHistoryTabView.swift`

구성:

1. 상단 컨트롤
- 한도 구간 선택기(`primary`/`secondary`)
- 조회 기간 선택기(`4w`/`8w`/`12w`)
- 짧은 가이드 텍스트:
  - 일별 히트맵: `1 tile = 1 day`(타일 하나는 하루)
  - 7일 주기별 소진율: `1 tile = 1 reset cycle`(타일 하나는 초기화 주기 하나)

2. 서비스 패널 목록
- 선택 가능한 모든 서비스를 한 화면에 동시 표시
- 정렬 기준:
  - 1순위: 사용 빈도(활성 일수) 내림차순
  - 2순위: 평균 일별 피크 내림차순
  - 3순위: 기존 서비스 우선순위

3. 일별 히트맵 섹션(서비스별)
- GitHub 기여도 그래프처럼 색 농도로 사용량을 보여주는 타일
- 요약 4개:
  - `Limit Hit Days`: 한도에 도달한 날짜 수
  - `Near Limit Days`: 한도에 근접한 날짜 수
  - `Avg Daily Peak`: 일별 최고 사용량의 평균
  - `Last Hit Date`: 마지막 한도 도달 날짜

4. 7일 주기별 소진율 섹션(서비스별 조건부 표시)
- 조건: `isSevenDayCycleAvailable == true`
- `UsageHistoryCycleStripView` (신규 내부 컴포넌트)
  - 최근 12사이클 타일/스트립
  - 색상은 `peakRatio` 레벨
- 요약 5개:
  - `Cycle Completion Rate`: 한도를 모두 소진한 주기의 비율
  - `Completed Cycles`(`X / Y`): 한도를 모두 소진한 주기 수 / 전체 종료 주기 수
  - `Avg Days to 80%`: 80% 사용까지 걸린 평균 일수
  - `Avg Days to 100%`: 100% 사용까지 걸린 평균 일수
  - `Current Completion Streak`: 최근 연속으로 한도를 모두 소진한 주기 수
- 보조 지표:
  - `Avg High-Band Hours (>=80%)`: 사용률 80% 이상을 유지한 평균 시간

5. 빈 상태
- 데이터 없음: `"No history yet. Keep AgentBar running to collect usage."`(아직 기록이 없습니다. 사용량을 수집하려면 AgentBar를 계속 실행해 주세요.)
- 사이클 없음: `"Not enough 7d cycle data yet."`(7일 주기 데이터가 아직 충분하지 않습니다.)

색상:

- 레벨 0: `Color.gray.opacity(0.15)`
- 레벨 1~4: `service.darkColor.opacity(0.25/0.45/0.7/1.0)`

툴팁:

- 일별 타일: 날짜, 최고 사용률, 평균 사용률, 샘플 수
- 사이클 타일: 주기 범위, 최고 사용률, 80%/100% 도달 여부, 도달까지 걸린 일수, 사용률 80% 이상 유지 시간

## 9. 설정 화면 통합

수정 파일: `AgentBar/Views/Settings/SettingsView.swift`

- `SettingsTab`에 `.history` 추가
- `TabView`에 `History` 탭 추가 (가장 오른쪽)
- `historyTab`에서 `UsageHistoryTabView` 렌더링

## 10. 변경 파일 목록

신규:

- `AgentBar/Models/UsageHistory.swift`
- `AgentBar/Infrastructure/UsageHistoryStore.swift`
- `AgentBar/ViewModels/UsageHistoryViewModel.swift`
- `AgentBar/Views/Settings/UsageHistoryTabView.swift`
- `AgentBarTests/UsageHistoryStoreTests.swift`
- `AgentBarTests/UsageHistoryViewModelTests.swift`

수정:

- `AgentBar/ViewModels/UsageViewModel.swift`
- `AgentBar/Views/Settings/SettingsView.swift`
- `AgentBarTests/UsageViewModelTests.swift`
- `AgentBarTests/SettingsViewBehaviorTests.swift`

## 11. 테스트 계획

### 11.1 UsageHistoryStoreTests

필수:

1. 일별 기록의 최댓값·평균·샘플 수 갱신
2. `secondary` 샘플을 5분 단위 묶음으로 추가·갱신
3. 보관 기간이 지난 데이터 정리(일별 기록 365일, 샘플 120일)
4. 저장 후 다시 읽었을 때 데이터 일치 여부
5. 손상 파일 복구(손상 표시가 있는 이름으로 바꾼 뒤 초기화)

### 11.2 UsageHistoryViewModelTests

필수:

1. 히트맵 셀 수(`7 * weeks`) 및 레벨 매핑 경계값
2. 일별 요약 계산 정확성
3. 주기별 그룹화(`resetAt` 기준) 정확성
4. 주기별 요약 계산 정확성
   - 한도 소진 주기 비율
   - `daysTo80/100`: 80%/100% 도달까지 걸린 일수
   - 연속 소진 주기 수
   - `highBandHours`: 80% 이상 유지 시간(구간별 상한 반영)
5. `secondary` 미지원 또는 7일 한도가 아닌 서비스에서 주기 패널 비활성화

### 11.3 기존 테스트 보강

- `UsageViewModelTests`
  - 조회에 성공한 결과만 사용량 기록에 저장
  - 조회 실패 시 표시하는 사용량 0인 대체 값은 기록하지 않음

- `SettingsViewBehaviorTests`
  - `History` 탭이 포함된 뷰의 `body` 빌드 안정성

## 12. 구현 순서

1. `UsageHistory.swift` 추가(스키마 v2)
2. `UsageHistoryStore.swift` 구현 및 저장소 테스트
3. `UsageViewModel`에 기록 저장소 주입·기록 호출 연결 및 테스트 보강
4. `UsageHistoryViewModel.swift` 구현(일별 및 주기별 분석) 및 테스트
5. `UsageHistoryTabView.swift` 구현(히트맵 및 주기별 타일)
6. `SettingsView.swift` 탭 통합
7. 전체 테스트 실행 후 보정

## 13. 완료 기준

- 설정의 `History` 탭에서 일별 타일 히트맵이 정상 표시된다.
- Claude/Codex `secondary(7d)` 선택 시 `7d Cycle Consistency` 섹션이 표시된다.
- 한도 소진 주기 비율, 연속 소진 주기 수, 목표 사용률 도달 일수, 높은 사용률 유지 시간 지표가 계산된다.
- 조회 실패 시 표시하는 사용량 0인 대체 값은 사용량 기록에 저장되지 않는다.
- 신규/기존 테스트가 모두 통과한다.

## 14. v0.5 이후 리팩토링 메모 (2026-02-20)

### 14.1 저장소 쓰기 작업 경량화

- `UsageHistoryStore`는 전체 상태 파일(스냅샷, `usage-history.json`)과 추가 기록 로그(`usage-history.events.jsonl`)로 동작한다.
- 신규 샘플 기록 시:
  1. 메모리 상태에 반영
  2. 이벤트를 추가 기록 로그에 덧붙임
  3. 로그가 이벤트 수 또는 파일 크기 임계치에 도달하면 압축 정리(정렬, 스냅샷 저장, 로그 제거)
- 효과:
  - 샘플마다 전체 JSON 파일을 다시 쓰지 않음
  - 비정상 종료 후에도 로그를 재적용해 복구 가능

### 14.2 secondary 평균 계산의 분모 분리

- `UsageHistoryDayRecord.secondarySampleCount` 추가.
- secondary 평균(`secondaryAverageRatio`, `secondaryAverageUsed`)은 전체 `sampleCount`가 아니라 `secondarySampleCount` 기준으로 계산.
- secondary가 없는 샘플이 섞여도 평균이 희석되지 않는다.

### 14.3 사용량 기록 새로고침의 경쟁 상태 방지

- `UsageHistoryViewModel`에 `refreshGeneration` + `refreshTask` 도입.
- 새로고침 요청이 오면 이전 작업을 취소하고 요청 세대 번호가 맞지 않는 결과를 버린다.
- 늦게 끝난 이전 새로고침이 최신 UI 상태를 덮어쓰는 문제를 방지한다.

### 14.4 키체인 읽기 캐시 안정화

- `KeychainManager.load`는 읽기 결과를 `LoadOutcome(value, shouldCache)`로 처리한다.
- `errSecInteractionNotAllowed` 등 일시적 실패는 캐시하지 않는다.
- `errSecItemNotFound` 등 안정 상태만 캐시하여, 일시 실패 후 복구 시 재시도가 가능하다.
