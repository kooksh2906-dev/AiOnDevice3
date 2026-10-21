# GPIO LED - Blocking / Non-Blocking

## 1. 학습 개요

STM32F411RE의 GPIO 출력으로 LED를 점멸하고, 같은 동작을 Blocking 방식과 Non-Blocking 방식으로 비교합니다.

- Blocking 방식은 `HAL_Delay()`가 끝날 때까지 `while` 루프의 다음 작업이 진행되지 않습니다.
- Non-Blocking 방식은 `HAL_GetTick()`으로 경과 시간을 검사하고, 대기하지 않은 채 다른 작업을 계속 실행할 수 있습니다.
- 원본 Non-Blocking 실습에는 `lastTick`을 갱신하지 않은 오류 버전과 이를 정정한 버전이 모두 남아 있어 문제 원인과 수정 과정을 함께 보존했습니다.

## 2. 버전 구성

| 버전 | 성격 | 주요 내용 |
|---|---|---|
| `VER1_Reconstructed_Blocking_HAL_Delay` | 복원 기준본 | PA5 LED를 `HAL_GPIO_TogglePin()`과 `HAL_Delay()`로 점멸합니다. 수업 당시 Blocking 원본 파일은 확인되지 않아 이후 실습에 남아 있는 패턴을 기반으로 복원했습니다. |
| `VER2_Original_NonBlocking_Bug` | 원본 오류 보존 | `lastTick`을 갱신하지 않아 최초 주기 경과 후 LED 상태가 루프마다 계속 변경되는 문제를 보존했습니다. |
| `VER3_Original_NonBlocking_Fixed` | 원본 정정본 | LED 상태를 변경한 뒤 `lastTick`을 현재 Tick으로 갱신합니다. |
| `VER4_Improved_NonBlocking_LED_Module` | 개선·모듈화 | LED 상태와 시간 정보를 구조체로 관리하고, 초기화·주기 변경·상태 갱신 함수를 소스와 헤더로 분리했습니다. |

## 3. HAL과 레지스터의 관계

| 학습 코드 | HAL/초기화 동작 | 관련 하드웨어 동작 |
|---|---|---|
| `MX_GPIO_Init()` | GPIO Clock 활성화 및 `HAL_GPIO_Init()` 호출 | `GPIOx_MODER`, `GPIOx_OTYPER`, `GPIOx_OSPEEDR`, `GPIOx_PUPDR` 설정 |
| `HAL_GPIO_WritePin()` | 출력 Pin을 Set 또는 Reset | `GPIOx_BSRR`를 통한 원자적 Bit Set/Reset |
| `HAL_GPIO_TogglePin()` | 현재 출력 상태를 반전 | 출력 상태 확인 후 대상 Pin 반전 |
| `HAL_GetTick()` | HAL Time Base의 현재 Tick 반환 | 기본 설정에서는 1 ms마다 증가하는 SysTick 기반 값 사용 |
| `HAL_Delay()` | 지정한 ms 동안 대기 | Tick이 경과할 때까지 현재 실행 흐름을 점유 |

GPIO 출력 모드에서는 `MODER=01`, Push-Pull 출력에서는 `OTYPER=0`이 사용됩니다. 출력 상태를 명시적으로 기록하는 개선 버전은 `HAL_GPIO_WritePin()`을 사용하여 구조체의 상태와 실제 출력 의도를 함께 관리합니다.

## 4. 오류 분석

오류 버전에서는 다음 조건이 한 번 참이 된 뒤에도 `lastTick`이 계속 0으로 남습니다.

```c
if (currTick - led->lastTick >= led->interval)
{
    /* lastTick 갱신이 없음 */
}
```

따라서 500 ms가 지난 뒤 `led1`은 `updateLed()`가 호출될 때마다 상태가 바뀌며, 의도한 500 ms 간격을 유지하지 못합니다. 정정본은 상태 변경 시점에 `lastTick = currTick`을 저장하여 다음 주기를 새로 측정합니다.

개선 버전은 `uint32_t`의 뺄셈 결과로 경과 시간을 비교합니다. 이 방식은 Tick 값이 최댓값을 지나 0으로 순환하는 경우에도 모듈러 연산 특성을 이용하여 일반적인 주기 비교를 유지합니다.

## 5. 핵심 학습 포인트

- GPIO Clock 활성화와 출력 Pin 초기화가 선행되어야 HAL GPIO 함수가 의도대로 동작합니다.
- `HAL_Delay()`는 간단하지만 대기 중 다른 주기 작업을 함께 처리하기 어렵습니다.
- `HAL_GetTick()` 기반 상태 갱신은 여러 작업을 하나의 Super Loop에서 독립적인 주기로 실행하는 기초가 됩니다.
- Non-Blocking 로직은 현재 시간뿐 아니라 이전 실행 시점을 반드시 저장해야 합니다.
- 구조체를 사용하면 Port, Pin, 주기, 상태 및 마지막 실행 시점을 LED별로 독립 관리할 수 있습니다.
- 원본 오류와 정정본을 함께 비교하면 시간 상태를 갱신하는 위치가 동작에 미치는 영향을 확인할 수 있습니다.

## 6. 검증 상태

- 공식 Reference Manual과 HAL/LL User Manual을 바탕으로 GPIO 및 Time Base 동작을 정적 검토했습니다.
- 네 버전의 CubeIDE 형식 `main.c`와 개선 모듈은 HAL Stub을 사용한 C 문법 및 경고 검사를 수행할 수 있도록 구성했습니다.
- 원본 `.ioc`와 전체 CubeIDE 프로젝트는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서는 CubeIDE 재빌드와 STM32F411RE 실물 보드 재시험을 수행하지 않았습니다.

