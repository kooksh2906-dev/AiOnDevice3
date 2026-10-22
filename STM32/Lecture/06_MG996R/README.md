# 06. MG996R Servo Motor PWM Control

STM32F411RE의 TIM3 Channel 1 PWM으로 MG996R Servo Motor의 위치를 제어하고, USART2 Interrupt 수신 명령으로 세 위치를 선택한 실습입니다. 수업 자료의 CubeMX 화면과 코드 캡처를 기준으로 전체 CubeIDE 형식 `main.c`를 복원했으며, 원본 전체 Project가 남아 있지 않으므로 두 실습 버전은 `Reconstructed`로 구분했습니다.

## 1. 실제 실습 구성

| 구분 | 설정·연결 | 역할 |
|---|---|---|
| Board | NUCLEO-F411RE | STM32F411RE 실행 보드 |
| Servo Signal | PA6, AF2 TIM3_CH1 | 50 Hz PWM Pulse 출력 |
| Servo VCC | Red, 수업 기준 5 V | Motor 전원 |
| Servo GND | Brown | 외부 전원과 STM32의 공통 GND |
| Servo PWM | Orange | TIM3_CH1 Signal |
| USART2 | ST-LINK Virtual COM Port | `a`, `b`, `c` 위치 명령 수신 및 Echo |

MG996R 제조사 사양은 동작 전압 4.8~6.6 V, 무부하 동작 전류 170 mA, Stall 전류 1.4 A를 제시합니다. 따라서 Board의 5 V Pin이나 USB 전원이 Motor 부하 전류를 항상 감당한다고 가정하지 않고, 충분한 전류 용량의 외부 5~6 V 전원을 사용하며 외부 전원 GND와 STM32 GND를 반드시 공통으로 연결하는 구성이 안전합니다.

## 2. Timer 설정과 50 Hz PWM 계산

수업 Clock Tree에서 TIM3 입력 Clock은 100 MHz이고 CubeMX 설정은 다음과 같습니다.

```text
TIM3CLK = 100,000,000 Hz
PSC     = 999
ARR     = 1999

f_CNT = TIM3CLK / (PSC + 1)
      = 100,000,000 / 1000
      = 100,000 Hz

1 Count = 10 us

T_PWM = (ARR + 1) x 10 us
      = 2000 x 10 us
      = 20 ms

f_PWM = 1 / 20 ms = 50 Hz
```

PWM Mode 1의 Up-counting에서는 CNT가 CCR1보다 작은 구간이 Active High입니다. 따라서 Pulse Width는 다음과 같이 계산합니다.

```text
Pulse Width = CCR1 x 10 us
Duty        = CCR1 / (ARR + 1) x 100 %
```

| CCR1 | Pulse Width | Duty | 수업 UART 코드의 위치 표기 |
|---:|---:|---:|---|
| 50 | 0.5 ms | 2.5 % | -90 degree |
| 150 | 1.5 ms | 7.5 % | 0 degree |
| 250 | 2.5 ms | 12.5 % | +90 degree |

각도 표기는 수업 당시 Motor와 Horn을 기준으로 한 제어값입니다. TowerPro는 일반 MG996R과 별도의 180-degree 주문형 Variant를 구분하고 있으므로, `0.5~2.5 ms = 정확한 180 degree`를 모든 MG996R 호환품에 일반화하지 않습니다. 실제 장치에서는 기계적 Stop, Horn 조립 위치 및 개체 편차를 확인하며 최소·중앙·최대 Pulse를 보정해야 합니다.

## 3. 실습 진행 흐름

### 3.1 고정 위치 순차 제어

수업 첫 단계는 TIM3 PWM을 시작한 뒤 CCR1에 50, 100, 200을 순서대로 기록하고 각 위치 사이에서 100 ms 대기합니다.

```c
HAL_TIM_PWM_Start(&htim3, TIM_CHANNEL_1);

TIM3->CCR1 = 50U;
HAL_Delay(100U);
TIM3->CCR1 = 100U;
HAL_Delay(100U);
TIM3->CCR1 = 200U;
HAL_Delay(100U);
```

이 단계에서는 50 Hz Frame은 유지하고 CCR1만 바꾸어 High Pulse Width가 Servo 위치 명령이 된다는 점을 확인합니다.

### 3.2 UART Interrupt 위치 선택

다음 단계에서는 USART2가 1 Byte를 Interrupt로 수신하고 `HAL_UART_RxCpltCallback()`에서 입력 문자를 위치값으로 변환합니다.

```c
'a' -> CCR1  50 -> 수업 표기 -90 degree
'b' -> CCR1 250 -> 수업 표기 +90 degree
'c' -> CCR1 150 -> 수업 표기   0 degree
```

수업 화면에는 각 `if` 내부의 수신 재등록과 Callback 마지막의 공통 재등록이 함께 보입니다. 이 구조는 같은 완료 Callback에서 `HAL_UART_Receive_IT()`를 중복 호출할 수 있고, ISR 안에서 Blocking `HAL_UART_Transmit()`도 실행합니다. 학습 흔적을 보존하기 위해 복원본에는 그대로 남기고, 개선본에서 한 번의 재등록과 Main Context의 송신으로 분리했습니다.

## 4. 버전 구성

| 버전 | 성격 | 내용 |
|---|---|---|
| `VER1_Reconstructed_Lecture_Fixed_Position` | 수업 화면 기반 복원본 | `CCR1=50/100/200`, 각 100 ms Delay의 고정 위치 순차 제어를 보존했습니다. |
| `VER2_Reconstructed_Lecture_UART_Control` | 수업 화면 기반 복원본 | USART2 Callback의 `a/b/c` 명령, Echo, 수업 각도 주석 및 수신 재등록 흐름을 보존했습니다. |
| `VER3_Improved_Calibrated_UART_Control` | 별도 개선본 | `servo.c/.h`, Pulse Width 단위 API, -90~+90 Clamp, 최소·중앙·최대 Calibration 값, 한 번의 UART 재등록 및 ISR/Foreground 역할 분리를 추가했습니다. |

모든 버전의 진입점은 CubeMX/CubeIDE 생성 형식을 유지한 전체 `main.c`입니다. PWM 및 UART 최초 시작은 `USER CODE BEGIN 2`, Main Loop 동작은 `USER CODE BEGIN 3`, UART Callback은 `USER CODE BEGIN 4`에 배치했습니다.

## 5. 개선본의 설계 의도

### 5.1 Register 직접 기록을 HAL Macro로 분리

수업 코드의 `TIM3->CCR1` 직접 기록은 CCR과 Pulse Width의 관계를 확인하기에 명확합니다. 개선본은 장치 제어 Module에서 `__HAL_TIM_SET_COMPARE()`를 사용하여 Timer Handle과 Channel을 인자로 받도록 분리했습니다.

```c
compare = pulseUs / timerTickUs;
__HAL_TIM_SET_COMPARE(servo->timer, servo->channel, compare);
```

### 5.2 Pulse Calibration과 범위 제한

개선본의 기본값은 수업 코드와 동일한 500/1500/2500 us입니다. 입력 각도는 -90~+90으로 제한한 뒤 중앙을 기준으로 양쪽 Pulse Range에 선형 대응합니다. 이 상수는 실제 Motor의 기계적 한계 안에서 보정할 수 있도록 한곳에 모았습니다.

### 5.3 Interrupt Callback 최소화

Callback에서는 명령 해석, 요청 저장 및 다음 수신 등록만 수행합니다. 실제 CCR 갱신과 Blocking UART Echo는 Main Loop가 처리하여 ISR 체류 시간을 줄입니다.

## 6. CubeMX·HAL·Register 연결

| CubeMX/HAL | 주요 Register·Bit | 의미 |
|---|---|---|
| TIM3 PWM Generation CH1 | `TIM3_CCMR1.CC1S=00`, `OC1M=110` | Channel 1을 PWM Mode 1 Output으로 설정 |
| PSC 999 | `TIM3_PSC` | 100 MHz를 100 kHz Counter Clock으로 분주 |
| Period 1999 | `TIM3_ARR` | 2000 Count, 20 ms Frame 설정 |
| Pulse 100 | `TIM3_CCR1` | 초기 1.0 ms High Pulse 설정 |
| Output Compare Preload Enable | `TIM3_CCMR1.OC1PE` | CCR1 갱신을 Update Event에 맞추어 반영 |
| CH Polarity High | `TIM3_CCER.CC1P=0` | Active High PWM 출력 |
| `HAL_TIM_PWM_Start()` | `CC1E`, `CEN` | CH1 Output과 Counter 시작 |
| `__HAL_TIM_SET_COMPARE()` | `CCR1` Write | Servo 위치를 나타내는 Pulse Width 변경 |
| `HAL_UART_Receive_IT()` | USART RXNE Interrupt 흐름 | 1 Byte 수신을 예약하고 완료 시 Callback 호출 |

## 7. 핵심 학습 포인트

- Servo Motor 위치 제어에서는 일반적인 LED 밝기 제어처럼 Duty 비율만 보는 것이 아니라, 일정한 Frame 안의 High Pulse Width를 위치 명령으로 해석해야 합니다.
- STM32 Timer의 실제 입력 Clock, PSC, ARR을 먼저 계산해야 원하는 50 Hz Frame과 Pulse 해상도를 만들 수 있습니다.
- 10 us/Count 설정에서는 1.5 ms 중심 Pulse가 CCR1 150으로 직접 대응합니다.
- PWM을 시작하는 `HAL_TIM_PWM_Start()`와 위치를 바꾸는 CCR 갱신은 서로 다른 단계입니다.
- UART Interrupt를 결합하면 Blocking 수신 없이 외부 명령으로 위치를 선택할 수 있습니다.
- ISR 안에서는 긴 Blocking 송신이나 중복 수신 등록을 피하고, 짧은 Event 전달 후 Main Context에서 응용 동작을 수행하는 편이 좋습니다.
- 전원선과 Signal 선의 역할을 분리해서 이해해야 하며, 고Torque Servo의 전류 요구량과 공통 GND를 반드시 고려해야 합니다.
- 수업의 Pulse Endpoint와 각도 표기는 실제 사용 Motor에서 검증·보정해야 하며 제조사 Variant나 호환품에 그대로 일반화하지 않습니다.

## 8. 검증 범위

- `STM_PWM.pdf`의 TIM3 CubeMX 설정, 고정 위치 코드, USART2 Callback, Pulse 계산 메모 및 배선 그림을 서로 대조했습니다.
- STM32F411RE RM0383과 UM1725를 기준으로 TIM3 PWM Mode 1, PSC/ARR/CCR 및 HAL PWM/UART Interrupt 흐름을 정적 검토했습니다.
- TowerPro 공식 MG996R 사양에서 동작 전압, 전류, 각도 Variant 차이를 확인하여 전원 주의사항과 Calibration 범위를 보완했습니다.
- GitHub에는 코드와 설정 문서만 보존하고, 실제 수업 화면은 Notion에 배치합니다.
- 세 버전의 `main.c`와 개선본 `servo.c`는 HAL Stub을 이용한 C 문법·경고 검사를 수행합니다.
- 원본 `.ioc`, 생성된 `tim.c/.h`, `gpio.c/.h`, `usart.c/.h`, Interrupt Handler 및 전체 CubeIDE Project는 현재 보관본에 포함되지 않았습니다.
- 이번 정리 과정에서 CubeIDE 전체 재빌드와 실물 Board 재시험은 수행하지 않았습니다.

## 참고 문서

- STMicroelectronics, *RM0383: STM32F411xC/E Reference Manual*, Rev 3
- STMicroelectronics, *UM1725: Description of STM32F4 HAL and Low-layer Drivers*, Rev 8
- STMicroelectronics, *AN4013: Introduction to Timers for STM32 MCUs*
- TowerPro, *MG996R Product Specification*
- 수업 자료, *STM_PWM.pdf*
