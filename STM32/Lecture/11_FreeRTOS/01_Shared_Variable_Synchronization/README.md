# FreeRTOS Shared Variable Synchronization

동일 우선순위의 두 태스크가 전역변수 `shared_var`를 각각 `+1`, `+10` 갱신하는 실습입니다. 보호가 없는 상태와 Mutex·Semaphore를 적용한 상태를 비교하여, 태스크 스케줄링과 임계영역 보호의 필요성을 학습합니다.

## 실습 환경

- Board: NUCLEO-F411RE
- MCU: STM32F411RETx
- IDE/Generator: STM32CubeIDE / STM32CubeMX
- STM32Cube FW_F4: V1.28.3
- FreeRTOS: 10.3.1
- API: CMSIS-RTOS V2
- 출력: USART2, 115200 bps, 8-N-1
- Kernel Tick: 1 kHz
- Preemption: Enabled
- Heap: `heap_4`, 15,360 bytes

## 폴더 구성

| 경로 | 내용 | 상태 |
|---|---|---|
| `00_Original_Drive_Source` | Drive에 보관된 실제 제출 `main.c`, `freertos.c` | 원문 보존 |
| `01_No_Protection` | 동기화 객체 없이 공유변수 접근 | CubeMX 생성본 기반 복원 |
| `02_Mutex` | `osMutexAcquire/Release` 적용 | CubeMX 생성본 기반 복원 |
| `03_Semaphore_Count1` | `osSemaphoreAcquire/Release` 적용 | CubeMX 생성본 기반 복원 |
| `04_Improved_Lock_Scope` | 공유변수 갱신만 보호하고 출력·지연은 임계영역 밖으로 이동 | 개선 참고본 |
| `settings` | CubeMX·FreeRTOS 설정과 버전 차이 | 문서화 |

실행 화면 캡처와 CubeMX 설정 캡처는 GitHub에 중복 저장하지 않고 Notion 학습 페이지에서 관리합니다.

## 실험 로직

- Task02: `shared_var++`
- Task03: `shared_var += 10`
- 두 태스크는 각 버전 안에서 같은 우선순위를 사용합니다.
- `printf()`는 USART2 Polling 전송으로 리타겟팅합니다.

보호가 없으면 두 태스크의 Read-Modify-Write와 출력 순서를 보장할 수 없습니다. Mutex나 Semaphore로 임계영역을 보호하면 한 태스크만 공유변수에 접근하도록 직렬화할 수 있습니다.

## Semaphore 설정 해석

CubeMX에서는 Counting Semaphore 객체로 생성했지만 `osSemaphoreNew(1, 1, ...)`처럼 최대 카운트와 초기 카운트를 모두 1로 설정했습니다. 따라서 본 실습에서는 Binary Semaphore와 같은 상호배제 방식으로 동작합니다.

Mutex는 소유권 개념과 우선순위 역전 완화를 위한 Priority Inheritance를 제공하므로, 하나의 공유자원을 보호하는 목적에는 보통 Mutex가 더 적합합니다. Semaphore는 자원 개수나 이벤트 신호 전달을 표현할 때 더 일반적으로 사용합니다.

## 원본과 복원본의 차이

실제 Drive 원본은 세 태스크가 모두 `osPriorityNormal`이고 HSI PLL 84 MHz를 사용하며, 현재 실습과 무관한 TIM2 시작 및 USART2 수신 인터럽트 코드가 남아 있습니다. 이 파일은 당시 학습 이력으로 수정하지 않았습니다.

사용자가 제공한 CubeMX 설정 PDF와 생성 `freertos.c`는 Task02·Task03가 모두 `osPriorityLow`, HSE Bypass 기반 100 MHz이며 TIM2를 포함하지 않습니다. 세 비교 버전은 이 생성본을 기반으로 복원했습니다. 우선순위의 구체적인 값은 다르지만 Task02와 Task03가 서로 같은 우선순위라는 실험 조건은 동일합니다.

## 임계영역 개선

실습 원본은 Lock을 획득한 상태에서 `printf()`와 `osDelay(1000)`까지 수행합니다. 동작 비교에는 유효하지만 다른 태스크가 약 1초 동안 같은 자원에 접근하지 못합니다.

개선본은 다음 순서로 Lock 보유 시간을 줄입니다.

1. Lock 획득
2. 공유변수 갱신
3. 출력용 Snapshot 저장
4. Lock 해제
5. UART 출력과 지연 수행

## 핵심 학습 포인트

- `volatile`은 Compiler 최적화를 제한할 뿐 원자성이나 태스크 동기화를 보장하지 않습니다.
- `shared_var++`와 `shared_var += 10`은 Read-Modify-Write 연산이므로 선점 시 갱신 유실 가능성이 있습니다.
- 같은 우선순위의 태스크도 Tick과 Blocking API에 따라 실행이 교대되며 접근 순서는 보장되지 않습니다.
- 공유자원 보호 범위는 필요한 연산으로 최소화해야 응답성과 동시성이 좋아집니다.
- Mutex와 Semaphore는 API 모양이 비슷하지만 소유권, Priority Inheritance, 자원·이벤트 표현 목적이 다릅니다.
- UART `printf()` 자체도 공유 출력 자원이므로 여러 태스크가 동시에 사용한다면 별도의 직렬화 전략이 필요합니다.

## 검증 범위

- Drive 원본 Semaphore 버전: 제공된 Tera Term 실행 캡처로 출력 이력 확인
- 복원본·개선본: 원본과 CubeMX 생성 파일을 대조한 정적 검토
- 미수행: 현재 환경의 CubeIDE 전체 재빌드 및 실물 보드 재시험
