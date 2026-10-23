# CubeMX / FreeRTOS Settings

## 1. 공통 프로젝트 설정

| 항목 | 설정 |
|---|---|
| Board / MCU | NUCLEO-F411RE / STM32F411RETx |
| Toolchain | STM32CubeIDE |
| Firmware package | STM32Cube FW_F4 V1.28.3 |
| FreeRTOS | 10.3.1 |
| Interface | CMSIS-RTOS V2 |
| Preemption | Enabled |
| Kernel Tick | 1,000 Hz |
| Minimal Stack | 128 words |
| Total Heap | 15,360 bytes, `heap_4` |
| Newlib reentrancy | Enabled |
| SYS Timebase | TIM11 |
| Clock source | HSE Bypass, SYSCLK 100 MHz |
| UART | USART2 Asynchronous, PA2/PA3, 115200-8-N-1 |

## 2. 공통 태스크 구성

| 태스크 | Stack | 생성본 우선순위 | 역할 |
|---|---:|---|---|
| `defaultTask` | 128 × 4 bytes | Normal | 유휴 반복과 `osDelay(1)` |
| `myTask02` | 128 × 4 bytes | Low | 공유변수에 1을 더하고 출력 |
| `myTask03` | 128 × 4 bytes | Low | 공유변수에 10을 더하고 출력 |

Task02와 Task03의 우선순위를 같게 설정하여, 어느 한쪽의 고정된 우선순위 우위가 아니라 스케줄링 중 공유변수 접근과 동기화 방식의 차이를 확인합니다.

## 3. 버전별 RTOS 객체

| 버전 | CubeMX 객체 | 생성 코드 | 동기화 의미 |
|---|---|---|---|
| No Protection | 없음 | 없음 | 접근 순서와 갱신 원자성 미보장 |
| Mutex | `myMutex01` | `osMutexNew(...)` | 소유권 기반 상호배제 |
| Semaphore | `myCountingSem01` | `osSemaphoreNew(1, 1, ...)` | 카운트 1이므로 Binary Semaphore와 같은 동작 |

## 4. UART 출력

`printf()`의 한 문자를 USART2 Polling 전송으로 연결합니다.

```c
HAL_UART_Transmit(&huart2, (uint8_t *)&ch, 1U, 0xFFFFU);
```

이 전송은 완료될 때까지 호출 태스크를 기다리게 합니다. 원본처럼 Lock 안에서 출력하면 공유변수뿐 아니라 UART 출력과 1초 지연까지 전체 임계영역에 포함됩니다.

## 5. CubeMX 생성본과 실제 Drive 원본 비교

| 항목 | 제공된 설정 PDF·빈 생성본 | 실제 Drive 제출 원본 |
|---|---|---|
| Task02 / Task03 | 둘 다 Low | 둘 다 Normal |
| System Clock | HSE Bypass PLL 100 MHz | HSI PLL 84 MHz |
| TIM2 | 없음 | 초기화 및 Interrupt Start 잔존 |
| USART2 RX Interrupt | 없음 | 수신 시작 코드 잔존 |
| Semaphore | Count 1 / Initial 1 | Count 1 / Initial 1 |

TIM2와 USART2 RX Interrupt는 공유변수 동기화 실험의 핵심 기능이 아니므로 복원본에는 포함하지 않았습니다. 실제 Drive 파일은 당시 상태를 보여 주는 자료로 그대로 보존합니다.

## 6. Code Generation 범위

CubeMX 설정 문서에서 생성되는 핵심 초기화 함수는 다음과 같습니다.

- `SystemClock_Config()`
- `MX_GPIO_Init()`
- `MX_USART2_UART_Init()`
- `MX_FREERTOS_Init()`

`freertos.c`의 사용자 로직과 USART2 리타겟팅은 `USER CODE BEGIN/END` 영역에 배치하여 CubeMX 재생성 시 보존되도록 구성했습니다.
