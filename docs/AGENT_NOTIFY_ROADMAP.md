# 에이전트 알림 로드맵(1~3단계)

## 1. 제품 목표

현재 AgentBar는 사용량 할당량을 시각화합니다. 이 로드맵은 에이전트 실행에 사용자의 주의가 필요할 때 알려 주는 "에이전트 주의 알림 도구"로 앱을 확장합니다.

주요 결과:

- 에이전트 완료 후 유휴 시간 단축
- 막힌 실행을 빠르게 표시(권한 또는 결정 대기)
- 이후 단계에서 선택형 모바일 전달 지원

## 2. 범위와 원칙

### 범위

- 1단계: 로컬 macOS 알림 센터 알림(Codex 우선 연동)
- 1.5단계: Claude Code 훅 수집(이벤트 기반 소스 및 대체 폴링)
- 2단계: 외부 또는 모바일 채널을 통한 iPhone 푸시 전달
- 3단계: 양방향 원격 프롬프트 제출

### 원칙

- Codex를 우선하되 제공자에 종속되지 않는 구조(나중에 새 감지기 추가 가능)
- 사용자 모르게 데이터를 외부로 보내지 않으며, 외부 채널은 사용자가 명시적으로 동의해야 함
- 중복 억제와 대기 시간 적용은 필수
- 가능하면 확정적인 이벤트 매핑을 사용하고, 꼭 필요할 때만 추론 방식 매핑 사용

## 3. 1단계(로컬 알림 센터 최소 기능 제품)

### 3.1 사용자 이야기

- 사용자는 Codex 작업이 완료되면 로컬 알림을 받습니다.
- 사용자는 Codex가 높은 권한을 요청하면 로컬 알림을 받습니다.
- 사용자는 Codex가 결정이나 입력을 요청하면 로컬 알림을 받습니다.
- 사용자는 설정에서 각 알림 유형을 켜거나 끌 수 있습니다.

### 3.2 기능 요구 사항

- 이벤트 소스: `~/.codex/sessions/**/*.jsonl`
- 이벤트 유형:
  - `taskCompleted`
  - `permissionRequired`
  - `decisionRequired`
- 기본 폴링 간격: 5초
- 중복 억제:
  - 저장된 워터마크보다 오래된 이벤트 무시
  - `(service, eventType, sessionID)` 키별 대기 시간 적용(기본값 90초)
- `UNUserNotificationCenter`를 통한 로컬 알림 전달
- 설정 스위치:
  - 전체 켜기 및 끄기
  - 이벤트별 켜기 및 끄기
- 설정의 알림 권한 요청 버튼

### 3.3 비기능 요구 사항

- 가벼운 탐색(최근 파일과 늘어난 워터마크만 확인)
- 안전한 실패 동작(구문 분석 오류로 앱이 종료되면 안 됨)
- 개인정보 보호: 1단계에서는 네트워크 전송 없음
- 테스트 가능성: 감지기 로직과 감시기의 걸러내기 동작을 단위 테스트할 수 있어야 함

### 3.4 이벤트 매핑(Codex JSONL)

| JSONL 신호 | 매핑된 이벤트 | 신뢰도 |
|---|---|---|
| `event_msg.payload.type == task_complete` | `taskCompleted` | 높음 |
| `response_item.payload.type == function_call`이며 인자에 `sandbox_permissions=require_escalated`가 있음 | `permissionRequired` | 높음 |
| 사용자에게 결정이나 질문을 요청하는 것으로 보이는 텍스트가 있는 `event_msg.payload.type == agent_message` | `decisionRequired` | 중간(추론 방식) |

추론 방식 참고 사항:

- 1단계의 결정 요청 감지는 텍스트 기반입니다. 가능한 경우 이후 단계에서 명시적인 프로토콜 신호를 사용하도록 개선해야 합니다.

### 3.5 구조

구성 요소:

- `AgentAlertEvent`: 표준화된 이벤트 모델(서비스, 유형, 메시지, 시각, 중복 제거 키)
- `AgentAlertEventDetectorProtocol`: 교체 가능한 감지기 인터페이스
- `CodexAlertEventDetector`: Codex JSONL 구문 분석기 및 매퍼
- `AgentAlertMonitor`: 폴링 조정, 워터마크 및 대기 시간, 설정 필터
- `AgentAlertNotificationService`: 로컬 알림 전달

데이터 흐름:

1. 감시기 주기 실행
2. 감지기가 워터마크 이후의 새 표준 이벤트 반환
3. 감시기가 설정과 대기 시간 적용
4. 알림 서비스가 로컬 알림 게시
5. 워터마크 갱신

### 3.6 설정과 저장

UserDefaults 키:

- `alertsEnabled` (Bool)
- `alertTaskCompletedEnabled` (Bool)
- `alertPermissionRequiredEnabled` (Bool)
- `alertDecisionRequiredEnabled` (Bool)
- `alertPollingSeconds` (Double, 기본값 5)
- `alertLastSeenCodexTimestamp` (epoch 이후 초를 나타내는 Double)

### 3.7 안정성과 오류 처리

- 파일의 한 줄에서 구문 분석 오류가 발생하면 해당 줄을 건너뛰고 주기 실행은 계속해야 합니다.
- 파일 접근 오류는 기록하고 해당 주기에서 무시해야 합니다.
- 알림 게시 실패가 이미 처리한 이벤트의 워터마크 갱신을 막아서는 안 됩니다.

### 3.8 테스트 계획

단위 테스트:

- 감지기가 작업 완료 이벤트를 올바르게 매핑하는지 확인
- 감지기가 권한 요청 함수 호출을 올바르게 매핑하는지 확인
- 감지기가 결정 요청 메시지를 올바르게 매핑하는지 확인
- 감시기가 대기 시간 및 워터마크를 사용해 중복을 억제하는지 확인
- 설정 필터가 비활성화된 이벤트 유형을 막는지 확인

수동 확인:

- 알림을 활성화하고 Codex 예제 작업을 실행한 뒤 알림이 나타나는지 확인
- 높은 권한이 필요한 명령을 실행하고 권한 알림 확인
- 같은 이벤트에 알림이 반복해서 쏟아지지 않는지 확인

### 3.9 1.5단계 부록(Claude 훅)

목표:

- 로컬 연결 파일에 기록된 Claude Code 훅 이벤트를 수집해 폴링을 보완합니다.

추가 사항:

- 새 감지기: `ClaudeHookAlertEventDetector`
- 훅 연결 경로: `~/.claude/agentbar/hook-events.jsonl`
- 설정의 소스 스위치:
  - Codex 세션 폴링 소스(`alertCodexEventsEnabled`)
  - Claude 훅 소스(`alertClaudeHookEventsEnabled`)

연결 형식:

- 훅 호출마다 JSONL 한 줄:
  - `captured_at`: ISO8601 UTC 타임스탬프(연결 도구에서 생성)
  - `payload_base64`: base64로 인코딩한 Claude 훅 원본 JSON 내용

Claude 이벤트 매핑:

- `hook_event_name in {Stop, SubagentStop}` -> `taskCompleted`(높은 신뢰도)
- `hook_event_name == Notification` + 권한 요청으로 보이는 텍스트 -> `permissionRequired`(중간 신뢰도)
- `hook_event_name == Notification` + 결정 또는 입력 요청으로 보이는 텍스트 -> `decisionRequired`(중간 신뢰도)

운영 참고 사항:

- 이벤트 소스는 Claude 훅 실행 시점에 이벤트 기반으로 동작합니다. 감시기의 폴링은 복원력이 있는 로컬 수집 반복 과정으로 유지됩니다.
- 훅을 설정하지 않아도 Codex 폴링 알림은 변경 없이 계속 작동합니다.

## 3.10 1.7단계 부록(소켓 및 사용자 지정 소리)

목표:

- 푸시 기반 이벤트 전달을 위해 폴링을 유닉스 도메인 소켓 수신기로 교체
- CESP 호환 소리 묶음을 지원하는 사용자 지정 소리 재생 추가

구조 변경:

- 새로 추가: `AlertSocketListener`(`~/.agentbar/events.sock`의 NWListener)
- 새로 추가: `AlertSoundManager`(CESP 매니페스트 구문 분석기 및 AVAudioPlayer)
- 수정: `AgentAlertMonitor` — 소켓 우선, Codex 파일 감시기는 대체 수단으로만 사용
- 수정: `AgentAlertNotificationService` — 사용자 지정 소리 연동
- 새 훅 스크립트: `agentbar-hook.sh`(Claude), `agentbar-codex-hook.sh`(Codex)

소켓 프로토콜:

- 유닉스 도메인 소켓을 통해 줄바꿈으로 구분한 JSON 전송
- 형식: `{"agent":"claude","event":"stop","session_id":"...","message":"...","timestamp":"..."}`
- 이벤트 매핑: `stop`/`subagent_stop` -> taskCompleted, `permission` -> permissionRequired, `decision` -> decisionRequired

소리 묶음 형식(CESP):

- `openpeon.json` 매니페스트가 있는 디렉터리
- 범주: `task.complete`, `input.required`
- 범주별 켜기 및 끄기, 음량 조절, 반복 없는 선택

상태: **완료**(개발 기록 40)

## 4. 2단계(iPhone 전달)

### 4.1 목표

짧은 지연 시간과 명확한 작업 맥락으로 같은 주의 알림 이벤트를 iPhone에 전달합니다.

### 4.2 채널 전략

- 기본: APNs 기반 동반 앱을 통한 푸시(권장)
- 대안: 사용자가 설정한 웹훅 중계(Slack, Telegram, Pushover 등)

### 4.3 구조 추가 사항

- `RemoteAlertDispatcher` 인터페이스
- 재시도 및 대기 시간 증가가 있는 외부 전송 이벤트 대기열
- 기기별 토큰으로 서명한 내용
- 전달 상태 계측(성공 및 실패 횟수)

### 4.4 보안

- 설정에서 명시적인 동의 및 토큰 설정
- 저장된 민감한 내용 필드를 키체인에서 암호화
- 기본적으로 최소한의 내용만 사용(서비스, 유형, 요약, 시각)

### 4.5 운영 요구 사항

- 일시적인 실패에 대한 지수 대기 및 시간 분산
- 반복되는 실패에 대한 회로 차단 동작
- 설정의 "Send test push" 동작

## 5. 3단계(양방향 원격 프롬프트)

### 5.1 목표

원격 답장을 통해 새 프롬프트 지시를 Mac에서 실행되는 에이전트 작업 흐름으로 돌려보냅니다.

### 5.2 권장 접근 방식

- iOS 동반 앱의 빠른 답장 동작을 구조화된 명령에 매핑
- Mac 쪽 로컬 수신기가 인증 및 세션을 검증하고 선택한 에이전트 경로로 프롬프트 전달

### 5.3 명령 모델

- `reply_text`
- `approve_permission`
- `defer`
- `run_followup_prompt`

각 명령에 포함되는 정보:

- 기기 식별 정보
- 서명된 일회용 값 및 타임스탬프
- 대상 서비스 및 세션 맥락

### 5.4 안전 조절 장치

- iPhone과 Mac을 명시적으로 연결해야 함
- 일회용 값 캐시를 통한 재전송 공격 방지
- 위험한 명령을 위한 선택형 "실행 전 확인" 방식

### 5.5 iMessage를 기본 양방향 채널로 사용하지 않는 이유

- macOS 메시지 스크립트는 보내기를 지원하지만, 들어오는 내용을 안정적으로 구조화해 읽는 기능은 제한적이고 취약함
- 데이터베이스 탐색(`chat.db`)에는 많은 권한이 필요하고 운영 체제 변경에 쉽게 깨짐
- 안정적인 주요 제품 경로로 적합하지 않음

## 6. 단계별 목표와 종료 조건

1단계 종료:

- 이벤트 감지, 로컬 알림, 설정 스위치 구현 및 테스트 통과

1.5단계 종료:

- Claude 훅 연결 수집, 소스 스위치 구현 및 테스트 통과

2단계 종료:

- 재시도와 관측 기능을 갖춘 iPhone 채널을 하나 이상 운영 환경에 적용

3단계 종료:

- 명령 검증 및 감사 기록이 포함된 안전한 원격 답장 흐름 검증
