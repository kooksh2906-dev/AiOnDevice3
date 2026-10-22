# 07. 28BYJ-48 Stepper Motor with ULN2003

STM32F411RE의 네 GPIO 출력과 ULN2003 Driver를 사용하여 28BYJ-48 5 V Stepper Motor의 상(코일 권선)을 순서대로 통전하고, 회전 방향·Step 수·각도를 제어한 학습 기록입니다. 실제 수업의 GPIO Polling 반걸음 제어 코드와 강사님 TIM10 Interrupt 참고 코드를 분리해 보존하고, Main Loop를 막지 않는 Module형 개선본을 별도 버전으로 추가했습니다.

## 1. 구동 원리와 회로 역할

28BYJ-48은 4상 5선식 Unipolar Geared Stepper Motor입니다. 고정자의 각 상을 정해진 순서로 통전하면 자계의 방향이 단계적으로 바뀌고, Rotor가 다음 안정 위치로 이동합니다. 따라서 Servo Motor처럼 일정한 PWM Pulse Width를 위치 명령으로 전달하는 방식이 아니라, Controller가 상 여자 순서와 Step 발생 주기를 직접 만들어야 합니다.

| 구성 | 역할 |
|---|---|
| STM32F411RE | IN1~IN4 Logic 신호와 Step 주기를 생성합니다. |
| ULN2003 | Darlington Open-collector 출력으로 선택된 권선 전류를 GND 방향으로 흘리고, 내장 Clamp Diode로 유도성 부하의 역기전력 경로를 제공합니다. |
| 28BYJ-48 | 4개 상의 순차 여자에 따라 회전하고 내부 감속 기어를 통해 출력축 Torque를 높입니다. |
| Motor 5 V 전원 | 권선 전류를 공급합니다. STM32 GPIO에서 Motor를 직접 구동하지 않습니다. |

Motor의 공통선은 5 V에 연결되고 ULN2003이 각 상의 Low-side 전류를 Sink합니다. STM32와 Motor 전원은 GND 기준을 공유해야 하며, ULN2003의 COM/Clamp Diode 연결은 사용하는 Module 회로를 확인하여 Motor 전원에 연결합니다.

## 2. 상 여자 방식

여기서 `상`은 고정자 코일 권선의 전기적 구분입니다. `1상 여자`와 `2상 여자`는 한 Step에서 동시에 통전하는 상의 수를 뜻하며, `1-2상 여자`는 이 두 상태를 번갈아 사용하는 Half-step 방식입니다.

| 여자 방식 | 순방향 시퀀스(IN1 IN2 IN3 IN4) | 상태 수 | 수업 기준 출력축 해상도 | 특성 |
|---|---|---:|---:|---|
| 1상 여자, Wave-step | `1000 → 0100 → 0010 → 0001` | 4 | 약 2048 step/rev | 한 번에 한 상만 통전하여 소비 전류와 발열이 작지만, 2상 여자보다 Holding/구동 Torque가 낮습니다. |
| 2상 여자, Full-step | `1100 → 0110 → 0011 → 1001` | 4 | 약 2048 step/rev | 인접한 두 상을 함께 통전하여 Torque가 커지는 대신 소비 전류와 발열이 증가합니다. |
| 1-2상 여자, Half-step | `1000 → 1100 → 0100 → 0110 → 0010 → 0011 → 0001 → 1001` | 8 | 약 4096 half-step/rev | 1상과 2상 상태를 교대로 삽입하여 Step 각을 절반으로 줄이고 더 세밀하게 회전합니다. 전류 보상이 없으면 상태별 Torque 차이와 미세한 진동이 생길 수 있습니다. |

역방향 회전은 같은 시퀀스를 반대 순서로 진행합니다. 이번 실제 GPIO Polling 코드와 TIM10 참고 코드는 모두 1-2상 여자 시퀀스를 사용합니다.

## 3. Step 수와 각도 계산

수업에 사용한 28BYJ-48 자료에는 정격 5 V, 4상, 감속비 `1/64`, Stride angle `5.625°/64`가 제시되어 있습니다. 수업에서는 다음의 명목값으로 계산했습니다.

```text
1상 또는 2상 여자: 64 rotor steps/rev × 64 gear ratio ÷ 2 = 2048 steps/rev
1-2상 여자:        64 rotor half-steps/rev × 64 gear ratio = 4096 half-steps/rev

steps = degrees × steps_per_revolution / 360
```

따라서 Half-step 기준 180°는 `180 × 4096 / 360 = 2048 step`입니다. 다만 시판 28BYJ-48은 제조사·Lot별 실제 기어비와 기계 오차가 명목값과 다를 수 있으므로, 정밀한 각도가 필요할 때는 출력축 1회전의 실제 Step 수를 측정하여 `steps_per_revolution`을 보정해야 합니다. 개선본은 이 값을 초기화 인자로 받습니다.

## 4. 실제 Pin 연결

| ULN2003 입력 | STM32 Pin | GPIO 설정 | Half-step Sequence Index |
|---|---|---|---:|
| IN1 | PB1 | Output Push-Pull | 0 |
| IN2 | PB15 | Output Push-Pull | 1 |
| IN3 | PB14 | Output Push-Pull | 2 |
| IN4 | PB13 | Output Push-Pull | 3 |

수업 코드의 배열 열 순서는 IN1, IN2, IN3, IN4입니다. 실제 Motor가 예상과 반대로 회전하면 무조건 배선을 바꾸기보다 먼저 시퀀스 진행 방향과 `DIR_CW`/`DIR_CCW`의 기구 기준을 확인합니다.

## 5. GPIO Polling 제어

`VER1_Reconstructed_Lecture_Half_Step`은 메일에 보관된 `stepper.h/.c` 화면을 기준으로 복원했습니다. `rotateSteps()`가 8개 Half-step 상태를 순서대로 출력하고 매 Step마다 `HAL_Delay(1)`을 호출합니다.

```c
for (uint16_t i = 0U; i < steps; i++)
{
  step = (direction == DIR_CW) ? (i % 8U) : (7U - (i % 8U));
  stepMotor(step);
  HAL_Delay(1U);
}
```

구조가 단순하여 여자 시퀀스와 방향 전환을 확인하기 좋지만, 회전이 끝날 때까지 Main Context가 Blocking됩니다. 또한 `HAL_Delay(1)`의 실제 Scheduling 단위와 Motor의 기동 Torque에 따라 높은 속도에서 Step 손실이 생길 수 있습니다.

## 6. TIM10 Interrupt 제어

`VER2_Reconstructed_Instructor_Reference`는 강사님 참고 코드의 구조를 보존했습니다. TIM10 Update Interrupt마다 다음 Half-step 상태를 출력하고 `remainingSteps`를 감소시키므로, Main Loop가 Motor의 모든 Step을 직접 기다리지 않아도 됩니다.

### 6.1 1 MHz Timer Tick과 Step 주기

수업 Clock 기준 TIM10 입력 Clock은 100 MHz이며, 참고 코드는 PSC를 99로 설정하여 1 MHz Counter Clock을 만듭니다.

```text
f_CNT = 100 MHz / (PSC + 1)
      = 100 MHz / 100
      = 1 MHz

ARR = (1,000,000 / step_frequency) - 1
```

| Speed Level | Step Frequency | ARR | 실제 주기 |
|---:|---:|---:|---:|
| 0 | 1000 Hz | 999 | 1.000 ms |
| 1 | 800 Hz | 1249 | 1.250 ms |
| 2 | 600 Hz | 1665 | 약 1.666 ms |
| 3 | 400 Hz | 2499 | 2.500 ms |
| 4 | 200 Hz | 4999 | 5.000 ms |

`600 Hz`는 정수 ARR 때문에 실제 값이 약 600.24 Hz가 됩니다. TIM10은 APB2 Timer이며 STM32F411에서는 Update Interrupt가 `TIM1_UP_TIM10_IRQn` Vector를 공유하므로 CubeMX NVIC에서 해당 Interrupt를 활성화해야 합니다.

### 6.2 참고 코드에서 확인할 점

- `main.c`에서 `HAL_TIM_Base_Start_IT()`를 호출한 뒤 `rotateDegrees()` 내부에서 다시 Start하는 중복 흐름을 원형 보존했습니다.
- Callback이 `stepper.c`에 정의되어 있어 다른 Timer Module도 같은 HAL Callback을 구현하면 Symbol 충돌이 발생할 수 있습니다.
- Header의 `static const` 시퀀스는 Header를 Include하는 Translation Unit마다 사본을 만들 수 있습니다.
- `currentStep`을 먼저 증가시킨 뒤 출력하므로 최초 상태가 Sequence Index 1에서 시작합니다.
- 마지막 Step을 출력한 다음 Interrupt에서 Timer를 정지하므로 종료 판단이 한 주기 늦습니다.
- 구동 중 새 회전 명령을 넣을 때 Busy/동시성 검사가 없습니다.

이 항목들은 학습 과정의 비교 근거로 남기고, `VER3`에서 별도로 정리했습니다.

## 7. 개선본의 설계 의도

`VER3_Improved_NonBlocking_Stepper_Module`은 세 여자 방식을 하나의 Module에서 선택할 수 있게 구성했습니다.

- 여자 시퀀스는 `stepper.c` 내부에 두어 구현 세부사항을 감췄습니다.
- `StepperDriveMode`, `StepperDirection`, `Stepper_HandleTypeDef`으로 설정과 실행 상태를 묶었습니다.
- HAL Callback은 사용자의 코딩 기준에 맞게 `main.c`의 `USER CODE BEGIN 4`에 두고, TIM10을 확인한 뒤 Module 함수로 전달합니다.
- Timer Start는 `Stepper_RotateSteps()` 한곳에서만 수행합니다.
- Degree를 Step으로 바꿀 때 반올림하고, 1회전 Step 수를 보정 가능한 초기화 값으로 받습니다.
- Busy 상태에서는 새 명령을 거부하여 진행 중인 회전값이 덮어써지는 것을 방지합니다.
- 목표 Step이 끝나면 마지막 상을 유지하여 Holding Torque를 남깁니다. Torque가 필요 없으면 `Stepper_Release()`로 네 출력을 Low로 만들어 발열과 소비 전류를 줄일 수 있습니다.

```c
void HAL_TIM_PeriodElapsedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM10)
  {
    Stepper_OnTimerElapsed(&stepper, htim);
  }
}
```

## 8. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `VER1_Reconstructed_Lecture_Half_Step` | 실제 수업 화면 기반 복원본 | `HAL_GPIO_WritePin()`과 `HAL_Delay(1)`로 8상태 Half-step을 Blocking 출력합니다. |
| `VER2_Reconstructed_Instructor_Reference` | 강사님 참고 코드 복원본 | TIM10 Update Callback, 5단계 주파수 표, 4096 half-step/rev 각도 계산을 보존합니다. |
| `VER3_Improved_NonBlocking_Stepper_Module` | 별도 개선본 | 1상·2상·1-2상 선택, 비차단 상태 관리, 반올림 각도 변환, Busy 검사 및 Coil Release API를 추가했습니다. |

각 버전의 진입점은 STM32CubeMX/CubeIDE 생성 형식의 전체 `main.c`입니다. 사용자 Header 참조는 `USER CODE Includes`, 초기 회전 명령은 `USER CODE 2`, Main Loop 처리는 `USER CODE 3`, 개선본 Callback은 `USER CODE 4`에 배치했습니다.

## 9. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register·Bit | 의미 |
|---|---|---|
| PB1/PB13/PB14/PB15 GPIO Output | `GPIOB_MODER`, `OTYPER`, `PUPDR`, `OSPEEDR` | ULN2003 IN1~IN4 Logic 출력 설정 |
| `HAL_GPIO_WritePin()` | `GPIOB_BSRR` | 각 상의 Set/Reset을 Atomic하게 출력 |
| TIM10 Prescaler 99 | `TIM10_PSC` | 100 MHz Timer Clock을 1 MHz Counter Clock으로 분주 |
| TIM10 Period | `TIM10_ARR` | Step Interrupt 주기 설정 |
| `HAL_TIM_Base_Start_IT()` | `DIER.UIE`, `CR1.CEN` | Update Interrupt와 Counter 시작 |
| `HAL_TIM_Base_Stop_IT()` | `DIER.UIE`, `CR1.CEN` | Step 완료 시 Interrupt와 Counter 정지 |
| TIM10 NVIC Enable | `TIM1_UP_TIM10_IRQn` | TIM10 Update Event를 CPU Interrupt로 전달 |

## 10. 핵심 학습 포인트

- Stepper Motor는 상의 여자 순서가 위치 변화의 기본 단위이며, 시퀀스 순서를 뒤집으면 회전 방향이 반전됩니다.
- 1상 여자, 2상 여자, 1-2상 여자는 해상도·Torque·전류·진동 특성이 다릅니다.
- 28BYJ-48의 GPIO 신호는 ULN2003의 Logic 입력일 뿐이며, 실제 권선 전류는 Driver와 별도 Motor 전원이 담당합니다.
- 원하는 회전각은 `steps_per_revolution`과 정수 계산으로 변환되므로 기어비 오차, 반올림 및 Backlash를 고려해야 합니다.
- Polling+Delay 방식은 원리 확인에 단순하지만 CPU를 점유하고, Timer Interrupt 방식은 Step Timing과 Main Application을 분리할 수 있습니다.
- Step 주파수는 Timer 입력 Clock, PSC, ARR의 관계로 결정되며 너무 빠른 기동은 Torque 부족과 Step 손실을 일으킬 수 있습니다.
- HAL Callback은 공유 진입점이므로 Timer Instance를 확인하고, Module별 처리는 짧은 함수로 위임하는 편이 확장에 유리합니다.
- 정지 후 상을 계속 통전하면 Holding Torque를 얻지만 전류와 발열이 유지되며, 출력을 해제하면 소비 전류는 줄지만 Holding Torque를 잃습니다.

## 11. 검증 범위

- 메일에 보관된 28BYJ-48 사양표, Step 수 계산 메모, CubeMX Pinout, `stepper.h/.c` 화면을 서로 대조했습니다.
- 수업용 28BYJ-48-5V 자료의 정격 전압, 상 수, 감속비 및 Stride angle을 계산 근거로 사용했습니다.
- STM32F411RE RM0383, UM1725 및 Timer Application Note를 기준으로 GPIO BSRR, TIM10 PSC/ARR, Update Interrupt와 HAL Base Timer 흐름을 정적 검토했습니다.
- ULN2003 제조사 자료를 기준으로 Darlington Open-collector 출력과 Clamp Diode의 역할을 확인했습니다.
- GitHub에는 코드와 설정 문서만 보존하고, 실제 수업 화면은 Notion에 배치합니다.
- 세 버전의 `main.c`와 `stepper.c`는 HAL Stub을 이용한 C 문법·경고 검사를 수행합니다.
- 원본 `.ioc`, 생성된 `tim.c/.h`, `gpio.c/.h`, `usart.c/.h`, Interrupt Handler 및 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서 CubeIDE 전체 재빌드와 실물 Board 재시험은 수행하지 않았습니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8
- STMicroelectronics, *AN4013: Introduction to Timers for STM32 MCUs*
- STMicroelectronics, *ULN2001A–ULN2004A Seven Darlington Arrays*
- 수업 자료, *28BYJ-48-5V.pdf*
- 메일 보관 자료, *[STM32 학습 기록] FW: LAP_STEPMOTOR*
